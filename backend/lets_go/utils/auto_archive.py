from __future__ import annotations

from datetime import timedelta

from django.db import transaction
from django.db.models import Max
from django.db.models import Avg
from django.utils import timezone

from lets_go.models import (
    Booking,
    BookingHistorySnapshot,
    RideAuditEvent,
    SosIncident,
    ResolvedSosAuditSnapshot,
    Trip,
    TripStopBreakdown,
    TripActualPathSummary,
    TripActualPathPoint,
    TripChatGroup,
    TripHistorySnapshot,
    TripLiveLocationUpdate,
)

from lets_go.models.models_payment import TripPayment


def _archive_trip(trip: Trip) -> bool:
    """Archive one eligible trip.

    Returns True if archived (snapshotted + purged), False if skipped.
    """

    now = timezone.now()
    cutoff = now - timedelta(hours=24)

    base_final_dt = trip.completed_at or trip.cancelled_at or trip.updated_at
    last_action_dt = None
    try:
        b_agg = Booking.objects.filter(trip=trip).aggregate(
            max_dropoff=Max('dropoff_at'),
            max_booking_updated=Max('updated_at'),
            max_booking_completed=Max('completed_at'),
        )
        p_agg = TripPayment.objects.filter(booking__trip=trip, payment_status='COMPLETED').aggregate(
            max_payment_completed=Max('completed_at'),
        )
        candidates = [
            base_final_dt,
            b_agg.get('max_dropoff'),
            b_agg.get('max_booking_updated'),
            b_agg.get('max_booking_completed'),
            p_agg.get('max_payment_completed'),
        ]
        last_action_dt = max([c for c in candidates if c is not None], default=None)
    except Exception:
        last_action_dt = base_final_dt

    final_dt = last_action_dt
    if final_dt is None or final_dt > cutoff:
        return False

    # Completed trips must have no pending payments.
    if trip.trip_status == 'COMPLETED':
        pending = (
            Booking.objects.filter(trip=trip, booking_status__in=['CONFIRMED', 'COMPLETED'])
            .exclude(payment_status='COMPLETED')
            .exists()
        )
        if pending:
            return False

    has_sos = SosIncident.objects.filter(trip=trip).exists()
    can_purge_sos = False
    if has_sos:
        try:
            any_open = SosIncident.objects.filter(trip=trip, status=SosIncident.STATUS_OPEN).exists()
            has_resolved_snapshot = ResolvedSosAuditSnapshot.objects.filter(trip_id=trip.trip_id).exists()
            can_purge_sos = (not any_open) and has_resolved_snapshot
        except Exception:
            can_purge_sos = False

    from lets_go.management.commands.cleanup_archived_trips import _compute_stats, _thin_points

    with transaction.atomic():
        # 1) Trip snapshot
        snap, _ = TripHistorySnapshot.objects.get_or_create(
            trip_id=trip.trip_id,
            defaults={'trip_status': trip.trip_status, 'driver_id': trip.driver_id},
        )

        planned_stops = []
        try:
            route = getattr(trip, 'route', None)
            if route is not None:
                rs = route.route_stops.all().order_by('stop_order')
                for s in rs:
                    planned_stops.append(
                        {
                            'name': s.stop_name,
                            'order': s.stop_order,
                            'latitude': float(s.latitude) if s.latitude is not None else None,
                            'longitude': float(s.longitude) if s.longitude is not None else None,
                            'address': s.address,
                        }
                    )
        except Exception:
            planned_stops = []

        route_names = []
        try:
            fc = trip.fare_calculation or {}
            if isinstance(fc, dict):
                sb = fc.get('stop_breakdown') or []
                if isinstance(sb, list) and sb:
                    first = sb[0]
                    last = sb[-1]
                    route_names = [
                        str(first.get('from_stop_name') or 'From'),
                        str(last.get('to_stop_name') or 'To'),
                    ]
        except Exception:
            route_names = []

        vehicle_data = {}
        try:
            v = getattr(trip, 'vehicle', None)
            if v is not None:
                vehicle_data = {
                    'id': v.id,
                    'model_number': v.model_number,
                    'company_name': v.company_name,
                    'plate_number': v.plate_number,
                    'vehicle_type': v.vehicle_type,
                    'color': v.color,
                    'seats': v.seats,
                    'fuel_type': v.fuel_type,
                }
        except Exception:
            vehicle_data = {}

        snap.trip_obj = trip
        snap.trip_status = trip.trip_status
        snap.driver_id = trip.driver_id
        snap.trip_date = trip.trip_date
        snap.departure_time = trip.departure_time
        snap.route_id = getattr(getattr(trip, 'route', None), 'route_id', None)
        snap.route_name = getattr(getattr(trip, 'route', None), 'route_name', None)
        snap.route_names = route_names
        snap.planned_stops = planned_stops
        snap.vehicle_data = vehicle_data
        snap.total_seats = trip.total_seats
        snap.base_fare = int(trip.base_fare) if trip.base_fare is not None else None
        snap.gender_preference = trip.gender_preference
        snap.notes = trip.notes
        snap.is_negotiable = bool(getattr(trip, 'is_negotiable', True))
        snap.fare_calculation = trip.fare_calculation or {}
        breakdown = []
        try:
            for sb in TripStopBreakdown.objects.filter(trip=trip).order_by('from_stop_order', 'to_stop_order'):
                breakdown.append({
                    'from_stop_order': sb.from_stop_order,
                    'to_stop_order': sb.to_stop_order,
                    'from_stop_name': sb.from_stop_name,
                    'to_stop_name': sb.to_stop_name,
                    'distance_km': float(sb.distance_km) if sb.distance_km is not None else None,
                    'duration_minutes': int(sb.duration_minutes) if sb.duration_minutes is not None else None,
                    'price': int(sb.price) if sb.price is not None else None,
                    'from_coordinates': {
                        'lat': float(sb.from_latitude) if sb.from_latitude is not None else None,
                        'lng': float(sb.from_longitude) if sb.from_longitude is not None else None,
                    },
                    'to_coordinates': {
                        'lat': float(sb.to_latitude) if sb.to_latitude is not None else None,
                        'lng': float(sb.to_longitude) if sb.to_longitude is not None else None,
                    },
                    'price_breakdown': sb.price_breakdown or {},
                })
        except Exception:
            breakdown = []
        snap.stop_breakdown = breakdown
        snap.started_at = trip.started_at
        snap.completed_at = trip.completed_at
        snap.cancelled_at = trip.cancelled_at
        snap.finalized_at = final_dt
        snap.save()

        # 2) Booking snapshots
        for b in Booking.objects.filter(trip=trip).select_related('from_stop', 'to_stop', 'passenger'):
            bs, _ = BookingHistorySnapshot.objects.get_or_create(
                booking_id=b.booking_id,
                defaults={
                    'trip_id': trip.trip_id,
                    'passenger_id': b.passenger_id,
                    'booking_status': b.booking_status,
                    'ride_status': getattr(b, 'ride_status', 'UNKNOWN'),
                    'payment_status': getattr(b, 'payment_status', 'UNKNOWN'),
                },
            )
            bs.booking_obj = b
            bs.trip_obj = trip
            bs.trip_id = trip.trip_id
            bs.passenger_id = b.passenger_id
            bs.booking_status = b.booking_status
            bs.ride_status = getattr(b, 'ride_status', 'UNKNOWN')
            bs.payment_status = getattr(b, 'payment_status', 'UNKNOWN')
            bs.from_stop_name = getattr(getattr(b, 'from_stop', None), 'stop_name', None)
            bs.to_stop_name = getattr(getattr(b, 'to_stop', None), 'stop_name', None)
            bs.from_stop_order = getattr(getattr(b, 'from_stop', None), 'stop_order', None)
            bs.to_stop_order = getattr(getattr(b, 'to_stop', None), 'stop_order', None)
            bs.number_of_seats = b.number_of_seats
            try:
                bs.total_fare = int(b.total_fare) if b.total_fare is not None else None
            except Exception:
                bs.total_fare = None
            bs.booked_at = b.booked_at
            bs.pickup_verified_at = getattr(b, 'pickup_verified_at', None)
            bs.dropoff_at = getattr(b, 'dropoff_at', None)
            bs.completed_at = getattr(b, 'completed_at', None)
            bs.finalized_at = getattr(b, 'dropoff_at', None) or getattr(b, 'completed_at', None) or getattr(b, 'updated_at', None)
            bs.save()

        # 2b) Ratings update (driver/passengers)
        # Ratings are stored on Booking rows (driver_rating/passenger_rating).
        # Since we are about to purge operational Trip + Booking rows, recompute
        # aggregate ratings now so UsersData reflects the latest truth.
        try:
            if trip.trip_status == 'COMPLETED':
                # Update driver's average rating across all completed trips.
                driver_avg = (
                    Booking.objects
                    .filter(trip__driver_id=trip.driver_id, trip__trip_status='COMPLETED')
                    .exclude(driver_rating__isnull=True)
                    .aggregate(avg=Avg('driver_rating'))
                    .get('avg')
                )
                if driver_avg is not None:
                    try:
                        trip.driver.driver_rating = float(driver_avg)
                        trip.driver.save(update_fields=['driver_rating'])
                    except Exception:
                        pass

                # Update each passenger's average rating based on completed bookings.
                passenger_ids = list(
                    Booking.objects.filter(trip=trip).values_list('passenger_id', flat=True).distinct()
                )
                for pid in passenger_ids:
                    passenger_avg = (
                        Booking.objects
                        .filter(passenger_id=pid, booking_status='COMPLETED')
                        .exclude(passenger_rating__isnull=True)
                        .aggregate(avg=Avg('passenger_rating'))
                        .get('avg')
                    )
                    if passenger_avg is None:
                        continue
                    try:
                        from lets_go.models import UsersData
                        UsersData.objects.filter(id=pid).update(passenger_rating=float(passenger_avg))
                    except Exception:
                        pass
        except Exception:
            # Rating update must never block archiving.
            pass

        # 3) Actual path summary
        raw_points = []
        for u in TripLiveLocationUpdate.objects.filter(trip=trip, role='DRIVER').order_by('recorded_at'):
            raw_points.append(
                {
                    'lat': float(u.latitude),
                    'lng': float(u.longitude),
                    'speed': u.speed_mps,
                    'timestamp': u.recorded_at.isoformat(),
                }
            )

        simplified = _thin_points(raw_points)
        stats = _compute_stats(simplified)

        # Persist into the trip history snapshot so we can safely purge the operational rows.
        # Keep the same {lat,lng,speed,timestamp} structure used by live tracking.
        snap_has_actual_path = False
        try:
            snap.actual_path = simplified if isinstance(simplified, list) else []
            snap.save(update_fields=['actual_path'])
            snap_has_actual_path = isinstance(snap.actual_path, list) and len(snap.actual_path) >= 2
        except Exception:
            pass

        path, _ = TripActualPathSummary.objects.get_or_create(
            trip_obj=trip,
            defaults={'source': 'TripLiveLocationUpdate', 'trip_id': trip.trip_id},
        )
        path.trip_obj = trip
        path.trip_id = trip.trip_id
        path.source = 'TripLiveLocationUpdate'
        path.point_count = stats.point_count
        path.started_at = stats.started_at
        path.ended_at = stats.ended_at
        path.distance_km = stats.distance_km
        path.duration_seconds = stats.duration_seconds
        path.bbox = stats.bbox
        path.simplified_points = simplified
        path.generated_at = timezone.now()
        path.save()

        try:
            TripActualPathPoint.objects.filter(summary=path).delete()
            bulk = []
            if isinstance(simplified, list):
                for idx, p in enumerate(simplified):
                    if not isinstance(p, dict):
                        continue
                    lat = p.get('lat')
                    lng = p.get('lng')
                    if lat is None or lng is None:
                        continue
                    bulk.append(
                        TripActualPathPoint(
                            summary=path,
                            point_index=idx,
                            latitude=float(lat),
                            longitude=float(lng),
                            speed_mps=p.get('speed'),
                            recorded_at=None,
                        )
                    )
            if bulk:
                TripActualPathPoint.objects.bulk_create(bulk, batch_size=2000)
        except Exception:
            pass

        if (not has_sos) or can_purge_sos:
            TripLiveLocationUpdate.objects.filter(trip=trip).delete()
            RideAuditEvent.objects.filter(trip=trip).delete()
            TripChatGroup.objects.filter(trip=trip).delete()

            # The actual path has been stored in TripHistorySnapshot.actual_path.
            # Clean up path tables so they don't grow forever.
            if snap_has_actual_path:
                try:
                    TripActualPathPoint.objects.filter(summary=path).delete()
                except Exception:
                    pass
                try:
                    TripActualPathSummary.objects.filter(id=path.id).delete()
                except Exception:
                    pass

            trip.delete()

    return True


def auto_archive_for_driver(*, driver_id: int, limit: int = 5) -> int:
    """Archive eligible trips for one driver. Safe to call inside normal request paths."""

    if driver_id <= 0:
        return 0

    processed = 0
    qs = (
        Trip.objects.filter(driver_id=driver_id, trip_status__in=['COMPLETED', 'CANCELLED'])
        .select_related('route', 'vehicle')
        .order_by('updated_at')
    )

    for trip in qs.iterator():
        if processed >= limit:
            break
        try:
            if _archive_trip(trip):
                processed += 1
        except Exception:
            # Never fail the caller (UI load). This is best-effort archiving.
            continue

    return processed


def auto_archive_global(*, limit: int = 10) -> int:
    """Archive eligible trips across the system. Intended for admin dashboards."""

    processed = 0
    qs = (
        Trip.objects.filter(trip_status__in=['COMPLETED', 'CANCELLED'])
        .select_related('route', 'vehicle')
        .order_by('updated_at')
    )

    for trip in qs.iterator():
        if processed >= limit:
            break
        try:
            if _archive_trip(trip):
                processed += 1
        except Exception:
            continue

    return processed

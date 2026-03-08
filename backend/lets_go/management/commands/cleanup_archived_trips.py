from __future__ import annotations

from dataclasses import dataclass
from datetime import timedelta
from math import asin, cos, radians, sin, sqrt
from typing import Any

from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models import Max
from django.utils import timezone

from lets_go.models import (
    Booking,
    BookingHistorySnapshot,
    RideAuditEvent,
    SosIncident,
    ResolvedSosAuditSnapshot,
    Trip,
    TripActualPathSummary,
    TripActualPathPoint,
    TripChatGroup,
    TripHistorySnapshot,
    TripLiveLocationUpdate,
)

from lets_go.models.models_payment import TripPayment


def _haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    r = 6371000.0
    dlat = radians(lat2 - lat1)
    dlng = radians(lng2 - lng1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlng / 2) ** 2
    return 2 * r * asin(sqrt(a))


@dataclass
class _Stats:
    point_count: int
    bbox: dict[str, float]
    distance_km: float | None
    duration_seconds: int | None
    started_at: timezone.datetime | None
    ended_at: timezone.datetime | None


def _build_bbox(points: list[dict[str, Any]]) -> dict[str, float]:
    lats = [float(p['lat']) for p in points]
    lngs = [float(p['lng']) for p in points]
    return {
        'min_lat': min(lats),
        'max_lat': max(lats),
        'min_lng': min(lngs),
        'max_lng': max(lngs),
    }


def _thin_points(points: list[dict[str, Any]], min_dist_m: float = 12.0, max_points: int = 600) -> list[dict[str, Any]]:
    if len(points) <= 2:
        return points

    thinned = [points[0]]
    last = points[0]
    for p in points[1:-1]:
        try:
            d = _haversine_m(float(last['lat']), float(last['lng']), float(p['lat']), float(p['lng']))
        except Exception:
            continue
        if d >= min_dist_m:
            thinned.append(p)
            last = p
        if len(thinned) >= max_points - 1:
            break

    thinned.append(points[-1])
    return thinned


def _compute_stats(points: list[dict[str, Any]]) -> _Stats:
    if not points:
        return _Stats(point_count=0, bbox={}, distance_km=None, duration_seconds=None, started_at=None, ended_at=None)

    bbox = _build_bbox(points)

    dist_m = 0.0
    for a, b in zip(points, points[1:]):
        try:
            dist_m += _haversine_m(float(a['lat']), float(a['lng']), float(b['lat']), float(b['lng']))
        except Exception:
            continue

    # Duration: use timestamp if present (isoformat), otherwise None
    duration_seconds: int | None = None
    started_at = None
    ended_at = None
    try:
        t0 = points[0].get('timestamp')
        t1 = points[-1].get('timestamp')
        if isinstance(t0, str) and isinstance(t1, str):
            dt0 = timezone.datetime.fromisoformat(t0.replace('Z', '+00:00'))
            dt1 = timezone.datetime.fromisoformat(t1.replace('Z', '+00:00'))
            duration_seconds = int((dt1 - dt0).total_seconds())
            started_at = dt0
            ended_at = dt1
    except Exception:
        duration_seconds = None
        started_at = None
        ended_at = None

    return _Stats(
        point_count=len(points),
        bbox=bbox,
        distance_km=dist_m / 1000.0 if dist_m > 0 else None,
        duration_seconds=duration_seconds,
        started_at=started_at,
        ended_at=ended_at,
    )


class Command(BaseCommand):
    help = 'Purge operational data for archived trips. Skips any trip with SOS incidents (open or resolved).'

    def add_arguments(self, parser):
        parser.add_argument('--dry-run', action='store_true', help='Do not delete; only print what would happen')
        parser.add_argument('--limit', type=int, default=50, help='Max trips to process per run')

    def handle(self, *args, **options):
        dry_run: bool = options['dry_run']
        limit: int = options['limit']

        now = timezone.now()
        cutoff = now - timedelta(hours=24)

        qs = (
            Trip.objects.filter(trip_status__in=['COMPLETED', 'CANCELLED'])
            .select_related('route', 'vehicle', 'driver')
            .order_by('updated_at')
        )

        processed = 0
        deleted = 0
        skipped_sos = 0
        skipped_not_ready = 0

        for trip in qs.iterator():
            if processed >= limit:
                break
            processed += 1

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
                skipped_not_ready += 1
                continue

            # Match "history eligibility" behavior: completed trips must have no pending payments.
            if trip.trip_status == 'COMPLETED':
                pending = (
                    Booking.objects.filter(trip=trip, booking_status__in=['CONFIRMED', 'COMPLETED'])
                    .exclude(payment_status='COMPLETED')
                    .exists()
                )
                if pending:
                    skipped_not_ready += 1
                    continue

            # SOS retention: if ANY SOS incident exists for this trip (open or resolved), skip cleanup.
            has_sos = SosIncident.objects.filter(trip=trip).exists()
            can_purge_sos = False
            if has_sos:
                try:
                    any_open = SosIncident.objects.filter(trip=trip, status=SosIncident.STATUS_OPEN).exists()
                    has_resolved_snapshot = ResolvedSosAuditSnapshot.objects.filter(trip_id=trip.trip_id).exists()
                    can_purge_sos = (not any_open) and has_resolved_snapshot
                except Exception:
                    can_purge_sos = False

            trip_id_str = getattr(trip, 'trip_id', None) or str(trip.pk)

            if dry_run:
                self.stdout.write(f'[DRY_RUN] would purge trip={trip_id_str}')
                continue

            with transaction.atomic():
                # 1) Ensure snapshots exist (idempotent)
                snap, _ = TripHistorySnapshot.objects.get_or_create(
                    trip_id=trip.trip_id,
                    defaults={'trip_status': trip.trip_status, 'driver_id': trip.driver_id},
                )

                planned_stops = []
                try:
                    rs = trip.route.route_stops.all().order_by('stop_order')
                    for s in rs:
                        planned_stops.append({
                            'name': s.stop_name,
                            'order': s.stop_order,
                            'latitude': float(s.latitude) if s.latitude is not None else None,
                            'longitude': float(s.longitude) if s.longitude is not None else None,
                            'address': s.address,
                        })
                except Exception:
                    planned_stops = []

                route_names = []
                try:
                    if trip.fare_calculation and isinstance(trip.fare_calculation, dict):
                        sb = trip.fare_calculation.get('stop_breakdown') or []
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
                    v = trip.vehicle
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
                snap.route_id = getattr(trip.route, 'route_id', None)
                snap.route_name = getattr(trip.route, 'route_name', None)
                snap.route_names = route_names
                snap.planned_stops = planned_stops
                snap.vehicle_data = vehicle_data
                snap.total_seats = trip.total_seats
                snap.base_fare = int(trip.base_fare) if trip.base_fare is not None else None
                snap.gender_preference = trip.gender_preference
                snap.notes = trip.notes
                snap.is_negotiable = bool(getattr(trip, 'is_negotiable', True))
                snap.fare_calculation = trip.fare_calculation or {}
                snap.stop_breakdown = []
                snap.started_at = trip.started_at
                snap.completed_at = trip.completed_at
                snap.cancelled_at = trip.cancelled_at
                snap.finalized_at = final_dt
                snap.save()

                # Booking snapshots
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

                # 2) Actual path summary from TripLiveLocationUpdate (driver)
                raw_points: list[dict[str, Any]] = []
                for u in TripLiveLocationUpdate.objects.filter(trip=trip, role='DRIVER').order_by('recorded_at'):
                    raw_points.append({
                        'lat': float(u.latitude),
                        'lng': float(u.longitude),
                        'speed': u.speed_mps,
                        'timestamp': u.recorded_at.isoformat(),
                    })

                simplified = _thin_points(raw_points)
                stats = _compute_stats(simplified)

                # Persist into trip history snapshot so path survives after we purge tracking rows.
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

                    # Path data is persisted into TripHistorySnapshot.actual_path; cleanup redundant path tables.
                    if snap_has_actual_path:
                        try:
                            TripActualPathPoint.objects.filter(summary=path).delete()
                        except Exception:
                            pass
                        try:
                            TripActualPathSummary.objects.filter(id=path.id).delete()
                        except Exception:
                            pass

                    # Finally delete trip (also deletes bookings); snapshots survive via SET_NULL
                    trip.delete()
                    deleted += 1
                else:
                    skipped_sos += 1

        self.stdout.write(
            f'processed={processed} deleted={deleted} skipped_sos={skipped_sos} skipped_not_ready={skipped_not_ready}'
        )

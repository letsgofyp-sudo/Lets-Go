from django.http import JsonResponse, HttpResponse, Http404
from django.views.decorators.csrf import csrf_exempt
from django.utils import timezone
from datetime import datetime, timedelta, time
from decimal import Decimal
import logging
import json
from ..models import UsersData, Vehicle, Trip, Route, RouteStop, RouteGeometryPoint, TripStopBreakdown, Booking, TripActualPathSummary, TripActualPathPoint
from django.db.models import Prefetch
from django.db import transaction
from django.db.models import F
from django.db.utils import OperationalError, DatabaseError
from .views_notifications import send_ride_notification_async


logger = logging.getLogger(__name__)

@csrf_exempt
def get_ride_booking_details(request, trip_id):
    """Get complete ride details for passenger booking view"""
    if request.method == 'GET':
        try:
            # Optimized trip fetch: limit columns and prefetch minimal related data
            trip = (
                Trip.objects.select_related('route', 'vehicle', 'driver')
                .only(
                    # Trip
                    'trip_id', 'trip_date', 'departure_time', 'estimated_arrival_time', 'trip_status',
                    'total_seats', 'available_seats', 'base_fare', 'gender_preference', 'notes',
                    'is_negotiable', 'minimum_acceptable_fare', 'created_at', 'fare_calculation', 'live_tracking_state',
                    # Route
                    'route__route_id', 'route__route_name', 'route__route_description',
                    'route__total_distance_km', 'route__estimated_duration_minutes', 'route__route_geometry',
                    # Vehicle (no binary/photo fields, include Supabase URL field)
                    'vehicle__id', 'vehicle__model_number', 'vehicle__company_name', 'vehicle__vehicle_type',
                    'vehicle__color', 'vehicle__seats', 'vehicle__photo_front_url',
                    # Driver (no binary/photo fields, include Supabase URL field)
                    'driver__id', 'driver__name', 'driver__driver_rating', 'driver__phone_no', 'driver__gender',
                    'driver__profile_photo_url',
                )
                .prefetch_related(
                    Prefetch(
                        'route__route_stops',
                        queryset=RouteStop.objects.only(
                            'id', 'stop_order', 'stop_name', 'latitude', 'longitude', 'address', 'estimated_time_from_start'
                        ).order_by('stop_order')
                    ),
                    Prefetch(
                        'trip_bookings',
                        queryset=Booking.objects.filter(booking_status='CONFIRMED')
                        .select_related('passenger', 'from_stop', 'to_stop')
                        .only(
                            'id', 'booking_status', 'number_of_seats', 'male_seats', 'female_seats',
                            'from_stop__stop_order', 'to_stop__stop_order',
                            'from_stop__stop_name', 'to_stop__stop_name',
                            'passenger__name', 'passenger__gender', 'passenger__passenger_rating'
                        )
                    ),
                    Prefetch(
                        'stop_breakdowns',
                        queryset=TripStopBreakdown.objects.only(
                            'from_stop_order', 'to_stop_order', 'from_stop_name', 'to_stop_name',
                            'distance_km', 'duration_minutes', 'price'
                        ).order_by('from_stop_order')
                    ),
                )
                .get(trip_id=trip_id)
            )
            
            # Debug logging
            logger.debug("[get_ride_booking_details] Trip found: %s", trip.trip_id)
            
            # Get route stops in order
            try:
                route_stops = list(trip.route.route_stops.all())
                logger.debug("[get_ride_booking_details] Route stops found: %s", len(route_stops))
            except Exception as e:
                logger.exception("[get_ride_booking_details] Error getting route stops: %s", str(e))
                route_stops = []
            
            # Get existing bookings for this trip
            try:
                existing_bookings = list(trip.trip_bookings.all())
                logger.debug("[get_ride_booking_details] Existing bookings found: %s", len(existing_bookings))
            except Exception as e:
                logger.exception("[get_ride_booking_details] Error getting bookings: %s", str(e))
                existing_bookings = []
            
            # Calculate available seats
            available_seats = trip.available_seats
            
            # Get driver information
            try:
                driver_data = {
                    'id': trip.driver.id,
                    'name': trip.driver.name,
                    'driver_rating': float(trip.driver.driver_rating) if trip.driver.driver_rating else 0.0,
                    # Use Supabase-hosted profile photo URL if available
                    'profile_photo': getattr(trip.driver, 'profile_photo_url', None),
                    'phone_no': str(trip.driver.phone_no) if trip.driver.phone_no else None,
                    'gender': str(trip.driver.gender) if trip.driver.gender else None,
                }
                logger.debug("[get_ride_booking_details] Driver data extracted")
            except Exception as e:
                logger.exception("[get_ride_booking_details] Error extracting driver data: %s", str(e))
                driver_data = {
                    'id': None,
                    'name': 'Unknown Driver',
                    'driver_rating': 0.0,
                    'profile_photo': None,
                    'phone_no': None,
                    'gender': 'Unknown',
                }
            
            # Get vehicle information
            try:
                vehicle_data = {
                    'id': trip.vehicle.id if trip.vehicle else None,
                    'model': str(trip.vehicle.model_number) if trip.vehicle and trip.vehicle.model_number else 'N/A',
                    'company': str(trip.vehicle.company_name) if trip.vehicle and trip.vehicle.company_name else 'N/A',
                    'type': str(trip.vehicle.vehicle_type) if trip.vehicle and trip.vehicle.vehicle_type else 'N/A',
                    'color': str(trip.vehicle.color) if trip.vehicle and trip.vehicle.color else 'N/A',
                    'seats': int(trip.vehicle.seats) if trip.vehicle and trip.vehicle.seats else 0,
                    'plate_number': str(trip.vehicle.plate_number) if trip.vehicle and trip.vehicle.plate_number else None,
                    # Use Supabase-hosted vehicle front photo URL if available
                    'photo_front': (getattr(trip.vehicle, 'photo_front_url', None) if trip.vehicle else None),
                }
                logger.debug("[get_ride_booking_details] Vehicle data extracted")
            except Exception as e:
                logger.exception("[get_ride_booking_details] Error extracting vehicle data: %s", str(e))
                vehicle_data = {
                    'id': None,
                    'model': 'N/A',
                    'company': 'N/A',
                    'type': 'N/A',
                    'color': 'N/A',
                    'seats': 0,
                    'photo_front': None,
                }
            
            # Get route information
            try:
                route_data = {
                    'id': str(trip.route.route_id) if trip.route.route_id else 'Unknown',
                    'name': str(trip.route.route_name) if trip.route.route_name else 'Custom Route',
                    'description': str(trip.route.route_description) if trip.route.route_description else 'Route description not available',
                    'total_distance_km': float(trip.route.total_distance_km) if trip.route.total_distance_km else 0.0,
                    'estimated_duration_minutes': int(trip.route.estimated_duration_minutes) if trip.route.estimated_duration_minutes else 0,
                    'stops': []
                }
                logger.debug("[get_ride_booking_details] Route data extracted")
            except Exception as e:
                logger.exception("[get_ride_booking_details] Error extracting route data: %s", str(e))
                route_data = {
                    'id': 'Unknown',
                    'name': 'Custom Route',
                    'description': 'Route description not available',
                    'total_distance_km': 0.0,
                    'estimated_duration_minutes': 0,
                    'stops': []
                }
            
            # Add route stops with coordinates
            try:
                for stop in route_stops:
                    route_data['stops'].append({
                        'order': int(stop.stop_order) if stop.stop_order else 0,
                        'name': str(stop.stop_name) if stop.stop_name else 'Unknown Stop',
                        'latitude': float(stop.latitude) if stop.latitude else 0.0,
                        'longitude': float(stop.longitude) if stop.longitude else 0.0,
                        'address': str(stop.address) if stop.address else 'No address',
                        'estimated_time_from_start': int(stop.estimated_time_from_start) if stop.estimated_time_from_start else 0,
                    })
                logger.debug("[get_ride_booking_details] Added %s route stops", len(route_data['stops']))
            except Exception as e:
                logger.exception("[get_ride_booking_details] Error processing route stops: %s", str(e))
                # Add default stops if there's an error
                if len(route_data['stops']) == 0:
                    route_data['stops'] = [
                        {'order': 1, 'name': 'Start', 'latitude': 0.0, 'longitude': 0.0, 'address': 'Start location', 'estimated_time_from_start': 0},
                        {'order': 2, 'name': 'End', 'latitude': 0.0, 'longitude': 0.0, 'address': 'End location', 'estimated_time_from_start': 60}
                    ]

            route_points = []
            try:
                route_points = [
                    {'lat': float(p.latitude), 'lng': float(p.longitude)}
                    for p in RouteGeometryPoint.objects.filter(route=trip.route).only('latitude', 'longitude').order_by('point_index')
                ]
            except Exception as e:
                logger.exception("[get_ride_booking_details] Error getting route geometry points: %s", str(e))
                try:
                    geom = getattr(trip.route, 'route_geometry', None) or []
                    if isinstance(geom, list):
                        route_points = [
                            {'lat': float(p.get('lat')), 'lng': float(p.get('lng'))}
                            for p in geom
                            if isinstance(p, dict) and p.get('lat') is not None and p.get('lng') is not None
                        ]
                except Exception:
                    route_points = []

            has_actual_path = False
            actual_path = []
            try:
                s = TripActualPathSummary.objects.filter(trip_id=trip.trip_id, point_count__gte=2).only('simplified_points').first()
                if s is not None:
                    pts = list(
                        TripActualPathPoint.objects.filter(summary=s)
                        .only('latitude', 'longitude')
                        .order_by('point_index')
                    )
                    if len(pts) >= 2:
                        actual_path = [{'lat': float(p.latitude), 'lng': float(p.longitude)} for p in pts]
                        has_actual_path = True
                    elif isinstance(getattr(s, 'simplified_points', None), list) and len(s.simplified_points) >= 2:
                        actual_path = s.simplified_points
                        has_actual_path = True
            except Exception:
                actual_path = []
                has_actual_path = False

            if not has_actual_path:
                try:
                    state = trip.live_tracking_state or {}
                    dp = state.get('driver_path') if isinstance(state, dict) else None
                    if isinstance(dp, list) and len(dp) >= 2:
                        actual_path = dp
                        has_actual_path = True
                except Exception:
                    actual_path = []
                    has_actual_path = False
            
            # Get existing passengers information (for privacy, only show basic info)
            passengers_data = []
            try:
                for booking in existing_bookings:
                    if booking.passenger and booking.booking_status == 'CONFIRMED':
                        passengers_data.append({
                            'booking_id': booking.id,
                            'booking_status': str(booking.booking_status),
                            'from_stop_order': int(getattr(booking.from_stop, 'stop_order', 0) or 0),
                            'to_stop_order': int(getattr(booking.to_stop, 'stop_order', 0) or 0),
                            'from_stop_name': str(getattr(booking.from_stop, 'stop_name', '') or ''),
                            'to_stop_name': str(getattr(booking.to_stop, 'stop_name', '') or ''),
                            'id': booking.passenger.id,
                            'user_id': booking.passenger.id,
                            'name': str(booking.passenger.name) if booking.passenger.name else 'Unknown',
                            'gender': str(booking.passenger.gender) if booking.passenger.gender else 'Unknown',
                            'passenger_rating': float(booking.passenger.passenger_rating) if booking.passenger.passenger_rating else 0.0,
                            'seats_booked': int(booking.number_of_seats) if booking.number_of_seats else 0,
                            'male_seats': int(getattr(booking, 'male_seats', 0) or 0),
                            'female_seats': int(getattr(booking, 'female_seats', 0) or 0),
                        })
                logger.debug("[get_ride_booking_details] Added %s passenger records", len(passengers_data))
            except Exception as e:
                logger.exception("[get_ride_booking_details] Error processing passenger data: %s", str(e))
                passengers_data = []
            
            # Build simple fare data based only on the client-provided base_fare
            fare_data = {}
            try:
                base_fare_value = int(trip.base_fare) if trip.base_fare is not None else 0
                route_distance = (
                    float(trip.route.total_distance_km)
                    if getattr(trip.route, 'total_distance_km', None) is not None
                    else 0.0
                )
                fare_data = {
                    'base_fare': base_fare_value,
                    'total_distance_km': route_distance,
                    'calculation_breakdown': {
                        'source': 'client',
                    },
                }
                logger.debug("[get_ride_booking_details] Fare data prepared from client base_fare")
            except Exception as e:
                logger.exception("[get_ride_booking_details] Error preparing fare data from client base_fare: %s", str(e))
                fare_data = {
                    'base_fare': int(trip.base_fare) if trip.base_fare is not None else 0,
                    'total_distance_km': 0.0,
                    'calculation_breakdown': {
                        'source': 'client',
                    },
                }
            
            # Get stop breakdown if available
            stop_breakdown = []
            try:
                if hasattr(trip, 'stop_breakdowns') and trip.stop_breakdowns.exists():
                    breakdowns = trip.stop_breakdowns.all().order_by('from_stop_order')
                    for breakdown in breakdowns:
                        stop_breakdown.append({
                            'from_stop_order': int(breakdown.from_stop_order) if breakdown.from_stop_order else 0,
                            'to_stop_order': int(breakdown.to_stop_order) if breakdown.to_stop_order else 0,
                            'from_stop_name': str(breakdown.from_stop_name) if breakdown.from_stop_name else 'Unknown',
                            'to_stop_name': str(breakdown.to_stop_name) if breakdown.to_stop_name else 'Unknown',
                            'distance_km': float(breakdown.distance_km) if breakdown.distance_km else 0.0,
                            'duration_minutes': int(breakdown.duration_minutes) if breakdown.duration_minutes else 0,
                            'price': int(breakdown.price) if breakdown.price is not None else 0,
                        })
                    logger.debug("[get_ride_booking_details] Added %s stop breakdowns", len(stop_breakdown))
            except Exception as e:
                logger.exception("[get_ride_booking_details] Error processing stop breakdowns: %s", str(e))
                stop_breakdown = []
            
            # Prepare response data
            try:
                base_fare_int = int(trip.base_fare) if trip.base_fare is not None else 0
                
                response_data = {
                    'success': True,
                    'trip': {
                        'trip_id': trip.trip_id,
                        'trip_date': trip.trip_date.isoformat(),
                        'departure_time': trip.departure_time.strftime('%H:%M'),
                        'estimated_arrival_time': trip.estimated_arrival_time.strftime('%H:%M') if trip.estimated_arrival_time else None,
                        'trip_status': trip.trip_status,
                        'total_seats': trip.total_seats,
                        'available_seats': available_seats,
                        'base_fare': base_fare_int,
                        'gender_preference': trip.gender_preference,
                        'notes': trip.notes,
                        'is_negotiable': trip.is_negotiable,
                        'minimum_acceptable_fare': int(trip.minimum_acceptable_fare) if trip.minimum_acceptable_fare is not None else None,
                        'created_at': trip.created_at.isoformat(),
                    },
                    'driver': driver_data,
                    'vehicle': vehicle_data,
                    'route': route_data,
                    'passengers': passengers_data,
                    'fare_data': fare_data,
                    'stop_breakdown': stop_breakdown,
                    'has_actual_path': has_actual_path,
                    'actual_path': actual_path,
                    'route_points': route_points,
                    'booking_info': {
                        'can_book': available_seats > 0 and trip.trip_status == 'SCHEDULED',
                        'min_seats': 1,
                        'max_seats': min(available_seats, 4),  # Limit to 4 seats per booking
                        'price_per_seat': base_fare_int,
                        'total_price': base_fare_int,
                    }
                }
                return JsonResponse(response_data)
            except Exception as e:
                logger.exception("[get_ride_booking_details] Error preparing response data: %s", str(e))
                # Return a minimal response if there's an error
                return JsonResponse({
                    'success': True,
                    'trip': {
                        'trip_id': trip.trip_id,
                        'trip_date': trip.trip_date.isoformat() if trip.trip_date else None,
                        'departure_time': trip.departure_time.strftime('%H:%M') if trip.departure_time else 'N/A',
                        'trip_status': trip.trip_status,
                        'total_seats': trip.total_seats,
                        'available_seats': available_seats,
                        'base_fare': int(trip.base_fare) if trip.base_fare is not None else 0,
                        'gender_preference': trip.gender_preference,
                        'notes': trip.notes,
                        'is_negotiable': trip.is_negotiable,
                        'minimum_acceptable_fare': int(trip.minimum_acceptable_fare) if trip.minimum_acceptable_fare is not None else None,
                        'created_at': trip.created_at.isoformat() if trip.created_at else None,
                    },
                    'driver': driver_data,
                    'vehicle': vehicle_data,
                    'route': route_data,
                    'passengers': passengers_data,
                    'fare_data': fare_data,
                    'stop_breakdown': stop_breakdown,
                    'has_actual_path': has_actual_path,
                    'actual_path': actual_path,
                    'route_points': route_points,
                    'booking_info': {
                        'can_book': available_seats > 0 and trip.trip_status == 'SCHEDULED',
                        'min_seats': 1,
                        'max_seats': min(available_seats, 4),
                        'price_per_seat': int(trip.base_fare) if trip.base_fare is not None else 0,
                        'total_price': int(trip.base_fare) if trip.base_fare is not None else 0,
                    }
                })
            
        except Trip.DoesNotExist:
            return JsonResponse({
                'success': False,
                'error': 'Trip not found'
            }, status=404)
        except Exception as e:
            logger.exception("[get_ride_booking_details] Final exception caught: %s", str(e))
            return JsonResponse({
                'success': False,
                'error': f'Error fetching trip details: {str(e)}'
            }, status=500)
    
    return JsonResponse({
        'success': False,
        'error': 'Method not allowed'
    }, status=405)


@csrf_exempt
def get_confirmed_passengers(request, trip_id):
    """Lightweight endpoint: return confirmed passengers for a trip.

    Used by the driver's chat members screen to list only confirmed / active passengers
    without loading full ride details.
    """
    if request.method != 'GET':
        return JsonResponse({'success': False, 'error': 'Method not allowed'}, status=405)

    try:
        trip = Trip.objects.only('id').get(trip_id=trip_id)
    except Trip.DoesNotExist:
        return JsonResponse({'success': False, 'error': 'Trip not found'}, status=404)

    try:
        bookings = (
            Booking.objects
            .filter(trip_id=trip.id, booking_status='CONFIRMED')
            .select_related('passenger')
            .only(
                'id', 'booking_status', 'number_of_seats', 'male_seats', 'female_seats',
                'passenger__id', 'passenger__name', 'passenger__gender', 'passenger__passenger_rating',
                'passenger__profile_photo_url',
            )
        )

        passengers_data = []
        for b in bookings:
            if not b.passenger_id:
                continue
            passengers_data.append({
                'booking_id': b.id,
                'booking_status': str(b.booking_status),
                'id': b.passenger.id,
                'user_id': b.passenger.id,
                'name': str(b.passenger.name) if b.passenger.name else 'Unknown',
                'gender': str(b.passenger.gender) if b.passenger.gender else 'Unknown',
                'passenger_rating': float(b.passenger.passenger_rating) if b.passenger.passenger_rating else 0.0,
                'seats_booked': int(b.number_of_seats) if b.number_of_seats else 0,
                'male_seats': int(getattr(b, 'male_seats', 0) or 0),
                'female_seats': int(getattr(b, 'female_seats', 0) or 0),
                # Expose Supabase profile photo URL for chat avatars
                'profile_photo': getattr(b.passenger, 'profile_photo_url', None),
            })

        return JsonResponse({'success': True, 'passengers': passengers_data})
    except Exception as e:
        logger.exception('[get_confirmed_passengers][ERROR]: %s', str(e))
        return JsonResponse({'success': False, 'error': str(e)}, status=500)

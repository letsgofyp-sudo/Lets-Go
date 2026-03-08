from django.views.decorators.csrf import csrf_exempt
from django.http import JsonResponse, HttpResponse, Http404
from django.db import connection
from django.db.models import Prefetch, Q, Count, Exists, OuterRef
from django.db.models.functions import Coalesce
from django.db.models import DateTimeField
from django.utils import timezone
from datetime import datetime, timedelta, time
from decimal import Decimal
import json
import logging
import random
from django.db.models import Prefetch, Count, Q, OuterRef, Exists
from django.db.models.fields import DateTimeField
from django.db.models.functions import Coalesce
import time as pytime
from ..models import UsersData, Vehicle, Trip, Route, RouteStop, RouteGeometryPoint, TripStopBreakdown, Booking, TripActualPathSummary, TripActualPathPoint, TripHistorySnapshot, BookingHistorySnapshot
# from .utils.fare_calculator import is_peak_hour, get_fare_matrix_for_route, calculate_booking_fare
from .views_notifications import send_ride_notification_async
from decimal import Decimal
from ..utils.route_geometry import update_route_geometry_from_stops
from ..utils.verification_guard import verification_block_response, ride_create_block_response


logger = logging.getLogger(__name__)


def _parse_limit_offset(request, default_limit=10, max_limit=200):
    try:
        limit = int(request.GET.get('limit', default_limit))
        limit = max(1, min(limit, max_limit))
    except Exception:
        limit = default_limit
    try:
        offset = int(request.GET.get('offset', 0))
        offset = max(0, offset)
    except Exception:
        offset = 0
    return limit, offset


def _is_archived_after_24h(final_dt, now):
    if final_dt is None:
        return False
    try:
        return now >= (final_dt + timedelta(hours=24))
    except Exception:
        return False


def _to_int_pkr(value, default=None):
    if value is None:
        return default
    try:
        return int(round(float(value)))
    except (TypeError, ValueError):
        return default

@csrf_exempt
def create_trip(request):
    """Create a new trip with enhanced fare calculation"""
    if request.method == 'POST':
        try:
            logger.debug("=== CREATE_TRIP DEBUG START ===")
            logger.debug("Request body: %s", request.body)
            
            data = json.loads(request.body)
            logger.debug("Parsed JSON data: %s", data)

            # Extract trip data
            route_id = data.get('route_id')
            vehicle_id = data.get('vehicle_id')
            departure_time = data.get('departure_time')
            trip_date_str = data.get('trip_date')
            total_seats = data.get('total_seats', 1)
            notes = data.get('notes', '')
            gender_preference = data.get('gender_preference', 'Any')
            
            logger.debug("Extracted data:")
            logger.debug("  route_id: %s (type: %s)", route_id, type(route_id))
            logger.debug("  vehicle_id: %s (type: %s)", vehicle_id, type(vehicle_id))
            logger.debug("  departure_time: %s", departure_time)
            logger.debug("  trip_date_str: %s", trip_date_str)
            logger.debug("  total_seats: %s", total_seats)
            logger.debug("  notes: %s", notes)
            logger.debug("  gender_preference: %s", gender_preference)
            
            # Get route and vehicle (lightweight to avoid loading large blobs)
            logger.debug("=== LOOKING UP ROUTE AND VEHICLE ===")
            try:
                try:
                    connection.close_if_unusable_or_obsolete()
                except Exception:
                    pass
                logger.debug("Looking for route with route_id: %s", route_id)
                route = (
                    Route.objects
                    .only('id', 'route_id', 'route_name')
                    .get(route_id=route_id)
                )
                logger.debug("Route found: %s (ID: %s)", route.route_name, route.id)
                
                logger.debug("Looking for vehicle with id: %s", vehicle_id)
                vehicle = (
                    Vehicle.objects
                    .only('id', 'model_number', 'company_name', 'plate_number', 'vehicle_type', 'color', 'seats', 'fuel_type', 'status')
                    .defer('photo_front', 'photo_back', 'documents_image')
                    .get(id=vehicle_id)
                )
                logger.debug("Vehicle found: %s (ID: %s)", vehicle.model_number, vehicle.id)
            except (Route.DoesNotExist, Vehicle.DoesNotExist) as e:
                logger.exception("Route or vehicle not found: %s", str(e))
                return JsonResponse({
                    'success': False,
                    'error': 'Route or vehicle not found'
                }, status=404)

            if getattr(vehicle, 'status', Vehicle.STATUS_VERIFIED) != Vehicle.STATUS_VERIFIED:
                return JsonResponse({
                    'success': False,
                    'error': 'Selected vehicle is not verified yet. Please wait for admin verification.'
                }, status=400)
            
            # Parse departure time
            logger.debug("=== PARSING DEPARTURE TIME ===")
            try:
                logger.debug("Parsing departure time: %s", departure_time)
                departure_time_obj = datetime.strptime(departure_time, '%H:%M').time()
                logger.debug("Parsed departure time: %s", departure_time_obj)
            except ValueError as e:
                logger.exception("Error parsing departure time: %s", str(e))
                return JsonResponse({
                    'success': False,
                    'error': 'Invalid departure time format. Use HH:MM'
                }, status=400)

            # Parse trip date
            logger.debug("=== PARSING TRIP DATE ===")
            if trip_date_str:
                try:
                    logger.debug("Parsing trip date: %s", trip_date_str)
                    trip_date = datetime.strptime(trip_date_str, '%Y-%m-%d').date()
                    logger.debug("Parsed trip date: %s", trip_date)
                except ValueError as e:
                    logger.exception("Error parsing trip date: %s", str(e))
                    return JsonResponse({
                        'success': False,
                        'error': 'Invalid trip date format. Use YYYY-MM-DD'
                    }, status=400)
            else:
                trip_date = datetime.now().date()
                logger.debug("Using current date: %s", trip_date)

            # Enforce that trip start time is at least 15 minutes in the future.
            # We intentionally use naive datetimes here so that we compare in the
            # same clock domain as the (date, time) values sent by the client.
            now = datetime.now()
            trip_start = datetime.combine(trip_date, departure_time_obj)

            min_start = now + timedelta(minutes=15)
            logger.debug(
                "Current time (naive): %s, requested trip_start: %s, min_start_allowed: %s",
                now,
                trip_start,
                min_start,
            )
            if trip_start < min_start:
                return JsonResponse({
                    'success': False,
                    'error': 'Trip must start at least 15 minutes after current time so passengers have time to book.'
                }, status=400)
            
            # Get custom price from frontend; fare is now fully client-calculated
            logger.debug("=== PROCESSING FARE (CLIENT-DRIVEN) ===")
            custom_price = data.get('custom_price')
            if custom_price is None:
                return JsonResponse({
                    'success': False,
                    'error': 'custom_price is required; fare must be calculated on the client.'
                }, status=400)

            base_fare_value = _to_int_pkr(custom_price)
            if base_fare_value is None:
                return JsonResponse({
                    'success': False,
                    'error': 'custom_price must be a numeric value'
                }, status=400)

            # Minimal fare_data wrapper so downstream code can still store metadata
            fare_data = {
                'base_fare': base_fare_value,
                'total_distance_km': float(route.total_distance_km) if getattr(route, 'total_distance_km', None) else 0.0,
                'calculation_breakdown': {
                    'source': 'client',
                },
            }
            
            # Get driver from request data (since we're not using Django's built-in auth)
            logger.debug("=== LOOKING UP DRIVER ===")
            driver_id = data.get('driver_id')
            logger.debug("Driver ID from request: %s", driver_id)
            
            if not driver_id:
                return JsonResponse({
                    'success': False,
                    'error': 'Driver ID is required'
                }, status=400)
            
            try:
                logger.debug("Looking for driver with id: %s", driver_id)
                # Fetch minimal user fields; defer all binary/image fields to avoid heavy loads
                driver = (
                    UsersData.objects
                    .only('id', 'name', 'status')
                    .defer(
                        'profile_photo', 'live_photo',
                        'cnic_front_image', 'cnic_back_image',
                        'driving_license_front', 'driving_license_back',
                        'accountqr'
                    )
                    .get(id=driver_id)
                )
                logger.debug("Driver found: %s (ID: %s)", driver.name, driver.id)
            except UsersData.DoesNotExist as e:
                logger.exception("Driver not found: %s", str(e))
                return JsonResponse({
                    'success': False,
                    'error': 'Driver not found'
                }, status=404)

            blocked = ride_create_block_response(driver.id)
            if blocked is not None:
                return blocked
            
            # Create trip
            logger.debug("=== CREATING TRIP ===")
            try:
                logger.debug("Calculating estimated arrival time...")
                estimated_arrival = calculate_estimated_arrival(departure_time_obj, route)
                logger.debug("Estimated arrival time: %s", estimated_arrival)
                
                logger.debug("Creating trip object...")
                trip = Trip.objects.create(
                    trip_id=f"T{random.randint(100, 999)}-{datetime.now().strftime('%Y-%m-%d-%H:%M')}",
                    route=route,
                    vehicle=vehicle,
                    driver=driver,
                    trip_date=trip_date,
                    departure_time=departure_time_obj,
                    estimated_arrival_time=estimated_arrival,
                    total_seats=total_seats,
                    available_seats=total_seats,
                    base_fare=fare_data['base_fare'],
                    total_distance_km=fare_data.get('total_distance_km'),
                    total_duration_minutes=fare_data.get('total_duration_minutes'),
                    fare_calculation=fare_data,
                    notes=notes,
                    gender_preference=gender_preference,
                    is_negotiable=data.get('is_negotiable', True),
                    minimum_acceptable_fare=_to_int_pkr(data.get('minimum_acceptable_fare'), default=None),
                )
                logger.debug("Trip created successfully: %s", trip.trip_id)
            except Exception as e:
                logger.exception("Error creating trip: %s", str(e))
                return JsonResponse({
                    'success': False,
                    'error': f'Error creating trip: {str(e)}'
                }, status=500)
            
            # Create vehicle history
            logger.debug("=== CREATING VEHICLE HISTORY ===")
            try:
                from ..models.models_trip import TripVehicleHistory
                logger.debug("Creating vehicle history...")
                
                # First check if vehicle history already exists
                try:
                    vehicle_history = TripVehicleHistory.objects.get(trip=trip)
                    logger.debug("Vehicle history already exists, updating...")
                    vehicle_history.copy_from_vehicle(vehicle)
                except TripVehicleHistory.DoesNotExist:
                    logger.debug("Creating new vehicle history...")
                    # Create with required fields from vehicle
                    seats_for_history = (vehicle.seats if vehicle.vehicle_type == Vehicle.FOUR_WHEELER else 2)
                    vehicle_history = TripVehicleHistory.objects.create(
                        trip=trip,
                        vehicle=vehicle,
                        vehicle_type=vehicle.vehicle_type,
                        vehicle_model=vehicle.model_number,
                        vehicle_make=vehicle.company_name,
                        vehicle_color=vehicle.color,
                        license_plate=vehicle.plate_number,
                        vehicle_capacity=seats_for_history or 1,
                        fuel_type=vehicle.fuel_type,
                        engine_number=vehicle.engine_number,
                        chassis_number=vehicle.chassis_number,
                        vehicle_features={
                            'type': vehicle.vehicle_type,
                            'seats': seats_for_history,
                            'fuel_type': vehicle.fuel_type,
                        }
                    )
                    logger.debug("Vehicle history created successfully")
            except Exception as e:
                logger.exception("Error creating vehicle history: %s", str(e))
                # Don't fail the entire request for vehicle history error
                logger.debug("Continuing without vehicle history...")
            
            # Create stop breakdowns if provided in request data
            logger.debug("=== CREATING STOP BREAKDOWNS ===")
            try:
                if 'stop_breakdown' in data and data['stop_breakdown']:
                    logger.debug("Creating %s stop breakdown records...", len(data['stop_breakdown']))
                    for stop_data in data['stop_breakdown']:
                        from_order = (
                            stop_data.get('from_stop_order')
                            if stop_data.get('from_stop_order') is not None
                            else stop_data.get('from_stop')
                        )
                        to_order = (
                            stop_data.get('to_stop_order')
                            if stop_data.get('to_stop_order') is not None
                            else stop_data.get('to_stop')
                        )

                        try:
                            from_order = int(from_order) if from_order is not None else None
                        except Exception:
                            from_order = None
                        try:
                            to_order = int(to_order) if to_order is not None else None
                        except Exception:
                            to_order = None

                        if from_order is None or to_order is None:
                            logger.warning(
                                "Skipping invalid stop breakdown segment (missing stop orders): %s",
                                stop_data,
                            )
                            continue

                        dist_km = stop_data.get('distance_km')
                        if dist_km is None:
                            dist_km = stop_data.get('distance')
                        dur_min = stop_data.get('duration_minutes')
                        if dur_min is None:
                            dur_min = stop_data.get('duration')

                        try:
                            dur_min = int(dur_min) if dur_min is not None else None
                        except Exception:
                            dur_min = None

                        if dist_km is None or dur_min is None:
                            logger.warning(
                                "Skipping invalid stop breakdown segment (missing distance/duration): %s",
                                stop_data,
                            )
                            continue

                        TripStopBreakdown.objects.create(
                            trip=trip,
                            from_stop_order=from_order,
                            to_stop_order=to_order,
                            from_stop_name=stop_data.get('from_stop_name'),
                            to_stop_name=stop_data.get('to_stop_name'),
                            distance_km=dist_km,
                            duration_minutes=dur_min,
                            price=stop_data.get('price'),
                            from_latitude=stop_data.get('from_coordinates', {}).get('lat'),
                            from_longitude=stop_data.get('from_coordinates', {}).get('lng'),
                            to_latitude=stop_data.get('to_coordinates', {}).get('lat'),
                            to_longitude=stop_data.get('to_coordinates', {}).get('lng'),
                            price_breakdown=stop_data.get('price_breakdown', {}),
                        )
                    logger.debug("Stop breakdowns created successfully")
                else:
                    logger.debug("No stop breakdown data provided in request")
            except Exception as e:
                logger.exception("Error creating stop breakdowns: %s", str(e))
                # Don't fail the entire request for stop breakdown error
                logger.debug("Continuing without stop breakdowns...")
            
            logger.debug("=== CREATE_TRIP SUCCESS ===")
            return JsonResponse({
                'success': True,
                'message': 'Trip created successfully',
                'trip_id': trip.trip_id,
                'custom_price': fare_data['base_fare'],
                'fare_data': fare_data
            }, status=201)
            
        except json.JSONDecodeError as e:
            logger.exception("JSON decode error: %s", str(e))
            return JsonResponse({
                'success': False,
                'error': 'Invalid JSON data'
            }, status=400)
        except Exception as e:
            logger.exception("=== CREATE_TRIP GENERAL ERROR === %s", str(e))
            return JsonResponse({
                'success': False,
                'error': f'Failed to create trip: {str(e)}'
            }, status=500)
    
    return JsonResponse({
        'success': False,
        'error': 'Only POST method allowed'
    }, status=405)

# ================= Driver request management endpoints =================

@csrf_exempt
def cancel_booking(request, booking_id: int):
    """Cancel a passenger booking."""

    if request.method != 'POST':
        return JsonResponse({'success': False, 'error': 'Method not allowed'}, status=405)

    try:
        try:
            data = json.loads(request.body.decode('utf-8') or '{}')
        except Exception:
            data = {}

        reason = data.get('reason', 'Cancelled by passenger')

        # We treat booking_id as the primary key ID, which is what the Flutter
        # app sends via ApiService.cancelBooking(bookingId, reason).
        booking = (
            Booking.objects
            .select_related('trip', 'trip__driver', 'passenger')
            .get(id=booking_id)
        )

        # For in-progress trips, allow cancel even if passenger is already on-board.
        # If already on-board, mark as cancelled on board (no seat release mid-trip).
        try:
            trip_status = getattr(getattr(booking, 'trip', None), 'trip_status', None)
            ride_status = getattr(booking, 'ride_status', None) or 'NOT_STARTED'
        except Exception:
            trip_status = None
            ride_status = 'NOT_STARTED'

        if trip_status == 'IN_PROGRESS' and ride_status != 'NOT_STARTED':
            now = timezone.now()
            booking.booking_status = 'CANCELLED'
            booking.ride_status = 'CANCELLED_ON_BOARD'
            booking.cancelled_at = now
            booking.updated_at = now
            booking.save(update_fields=['booking_status', 'ride_status', 'cancelled_at', 'updated_at'])
        else:
            # Use the model helper so seats and chat membership are handled
            booking.cancel_booking(reason=reason)

        # Notify the driver that this passenger cancelled (or cancelled on board)
        try:
            driver = getattr(booking.trip, 'driver', None)
            passenger = booking.passenger
            if driver and getattr(driver, 'id', None):
                event_type = 'booking_cancelled_by_passenger'
                title = 'Booking cancelled by passenger'
                body = f'{passenger.name} cancelled their booking for your trip {booking.trip.trip_id}. Their seats have been released for other passengers.'
                if getattr(booking.trip, 'trip_status', None) == 'IN_PROGRESS' and getattr(booking, 'ride_status', None) == 'CANCELLED_ON_BOARD':
                    event_type = 'passenger_cancelled_on_board'
                    title = 'Passenger cancelled on board'
                    body = f'{passenger.name} cancelled on board for trip {booking.trip.trip_id}.'
                payload = {
                    'user_id': str(driver.id),
                    'driver_id': str(driver.id),
                    'title': title,
                    'body': body,
                    'data': {
                        'type': event_type,
                        'trip_id': str(booking.trip.trip_id),
                        'booking_id': str(booking.id),
                    },
                }
                send_ride_notification_async(payload)
        except Exception as e:
            # Log but do not fail the cancellation if notification fails
            logger.exception('[cancel_booking][notify_driver][ERROR]: %s', str(e))

        msg = 'Booking cancelled successfully'
        if getattr(booking.trip, 'trip_status', None) == 'IN_PROGRESS' and getattr(booking, 'ride_status', None) == 'CANCELLED_ON_BOARD':
            msg = 'Passenger cancelled on board'

        return JsonResponse({
            'success': True,
            'message': msg,
        })

    except Booking.DoesNotExist:
        return JsonResponse({'success': False, 'error': 'Booking not found'}, status=404)
    except ValidationError as e:
        # E.g. booking cannot be cancelled due to status/trip rules
        return JsonResponse({'success': False, 'error': str(e)}, status=400)
    except Exception as e:
        logger.exception('[cancel_booking][ERROR]: %s', str(e))
        return JsonResponse({'success': False, 'error': str(e)}, status=500)

@csrf_exempt
def create_route(request):
    if request.method == 'POST':
        try:
            import json
            data = json.loads(request.body.decode('utf-8'))
            
            # Extract route data
            coordinates = data.get('coordinates', [])
            location_names = data.get('location_names', [])
            route_points = data.get('route_points', [])
            
            if len(coordinates) < 2:
                return JsonResponse({'success': False, 'error': 'At least 2 coordinates required (origin and destination)'}, status=400)
            
            # Create route name from first and last location
            origin_name = location_names[0] if location_names else "Origin"
            destination_name = location_names[-1] if len(location_names) > 1 else "Destination"
            route_name = f"{origin_name} to {destination_name}"
            
            # Generate unique route ID
            import uuid
            route_id = f"R{str(uuid.uuid4())[:8].upper()}"
            
            # Create the route
            route = Route.objects.create(
                route_id=route_id,
                route_name=route_name,
                route_description=f"Route from {origin_name} to {destination_name}",
                is_active=True
            )
            
            # Create route stops from coordinates
            for i, coord in enumerate(coordinates):
                stop_name = location_names[i] if i < len(location_names) else f"Stop {i+1}"
                RouteStop.objects.create(
                    route=route,
                    stop_name=stop_name,
                    stop_order=i+1,
                    latitude=coord.get('lat'),
                    longitude=coord.get('lng'),
                    address=stop_name,
                    is_active=True
                )
            
            # Calculate total distance (simplified - sum of distances between consecutive points)
            normalized_stops = []
            for i, coord in enumerate(coordinates):
                normalized_stops.append({
                    'order': i + 1,
                    'name': location_names[i] if i < len(location_names) else f"Stop {i+1}",
                    'lat': coord.get('lat'),
                    'lng': coord.get('lng'),
                })

            normalized_route_points = []
            try:
                if isinstance(route_points, list):
                    for p in route_points:
                        if not isinstance(p, dict):
                            continue
                        lat = p.get('lat')
                        lng = p.get('lng')
                        if lat is None or lng is None:
                            lat = p.get('latitude')
                            lng = p.get('longitude')
                        if lat is None or lng is None:
                            continue
                        normalized_route_points.append({'lat': float(lat), 'lng': float(lng)})
            except Exception:
                normalized_route_points = []

            total_distance = 0
            for i in range(len(coordinates) - 1):
                from_coord = coordinates[i]
                to_coord = coordinates[i + 1]
                distance = _calculate_distance(
                    from_coord.get('lat'), from_coord.get('lng'),
                    to_coord.get('lat'), to_coord.get('lng')
                )
                total_distance += distance
            
            # Update route with calculated distance
            route.total_distance_km = round(total_distance, 2)
            route.estimated_duration_minutes = int(total_distance * 2)  # Rough estimate: 2 min per km
            if len(normalized_route_points) >= 2:
                route.route_geometry = normalized_route_points
            else:
                update_route_geometry_from_stops(route, normalized_stops)
            route.save()

            try:
                geom = getattr(route, 'route_geometry', None) or []
                if isinstance(geom, list) and geom:
                    try:
                        from django.db.utils import ProgrammingError, OperationalError
                        RouteGeometryPoint.objects.filter(route=route).delete()
                        bulk = []
                        for idx, p in enumerate(geom):
                            if not isinstance(p, dict):
                                continue
                            lat = p.get('lat')
                            lng = p.get('lng')
                            if lat is None or lng is None:
                                continue
                            bulk.append(RouteGeometryPoint(route=route, point_index=idx, latitude=float(lat), longitude=float(lng)))
                        if bulk:
                            RouteGeometryPoint.objects.bulk_create(bulk, batch_size=2000)
                    except (ProgrammingError, OperationalError) as _e:
                        logger.exception('[CREATE_ROUTE] routegeometrypoint table missing/unavailable: %s', str(_e))
            except Exception as _e:
                logger.exception('[CREATE_ROUTE] failed to persist route geometry points: %s', str(_e))

            try:
                from django.db.utils import ProgrammingError, OperationalError
                route_points_out = [
                    {'lat': float(p.latitude), 'lng': float(p.longitude)}
                    for p in RouteGeometryPoint.objects.filter(route=route).only('latitude', 'longitude').order_by('point_index')
                ]
            except (ProgrammingError, OperationalError):
                route_points_out = [
                    {'lat': float(p.get('lat')), 'lng': float(p.get('lng'))}
                    for p in (getattr(route, 'route_geometry', None) or [])
                    if isinstance(p, dict) and p.get('lat') is not None and p.get('lng') is not None
                ]

            return JsonResponse({
                'success': True,
                'route': {
                    'id': route.route_id,
                    'name': route.route_name,
                    'distance': float(route.total_distance_km),
                    'duration': route.estimated_duration_minutes,
                    'stops_count': len(coordinates),
                    'route_points': route_points_out,
                }
            })
            
        except Exception as e:
            logger.exception('CREATE_ROUTE ERROR: %s', str(e))
            return JsonResponse({'success': False, 'error': str(e)}, status=500)
    
    return JsonResponse({'error': 'Invalid request method'}, status=400)

def calculate_estimated_arrival(departure_time, route):
    """Calculate estimated arrival time based on route distance and average speed"""
    if not route.total_distance_km:
        # If no distance available, add 2 hours as default
        departure_minutes = departure_time.hour * 60 + departure_time.minute
        arrival_minutes = departure_minutes + 120  # 2 hours
        arrival_hour = (arrival_minutes // 60) % 24  # Ensure hour is within 0-23
        arrival_minute = arrival_minutes % 60
        return time(arrival_hour, arrival_minute)
    
    # Assume average speed of 50 km/h for better time estimates (was too slow at 30)
    average_speed_kmh = 50
    travel_time_hours = route.total_distance_km / average_speed_kmh
    travel_time_minutes = int(travel_time_hours * 60)
    
    departure_minutes = departure_time.hour * 60 + departure_time.minute
    arrival_minutes = departure_minutes + travel_time_minutes
    arrival_hour = (arrival_minutes // 60) % 24  # Ensure hour is within 0-23 range
    arrival_minute = arrival_minutes % 60
    
    logger.debug("Departure: %s:%s", departure_time.hour, departure_time.minute)
    logger.debug("Travel time: %.2f hours (%d minutes)", travel_time_hours, travel_time_minutes)
    logger.debug("Calculated arrival: %d:%02d", arrival_hour, arrival_minute)
    
    return time(arrival_hour, arrival_minute)

def _calculate_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two points using Haversine formula"""
    logger.debug("  _calculate_distance called with: lat1=%s, lon1=%s, lat2=%s, lon2=%s", lat1, lon1, lat2, lon2)
    
    try:
        from math import radians, cos, sin, asin, sqrt
        
        # Convert to radians
        lat1, lon1, lat2, lon2 = map(radians, [lat1, lon1, lat2, lon2])
        logger.debug("  Converted to radians: lat1=%s, lon1=%s, lat2=%s, lon2=%s", lat1, lon1, lat2, lon2)
        
        # Haversine formula
        dlat = lat2 - lat1
        dlon = lon2 - lon1
        a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
        c = 2 * asin(sqrt(a))
        
        # Radius of earth in kilometers
        r = 6371
        
        distance = c * r
        logger.debug("  Calculated distance: %.2f km", distance)
        return distance
    except Exception as e:
        logger.exception("  Error in _calculate_distance: %s", str(e))
        return 0


@csrf_exempt
def get_trip_breakdown(request, trip_id):
    """Get detailed breakdown for a specific trip"""
    if request.method == 'GET':
        try:
            trip = Trip.objects.get(trip_id=trip_id)
            
            # Get stop breakdown data
            stop_breakdowns = trip.stop_breakdowns.all().order_by('from_stop_order')
            breakdown_list = []
            for breakdown in stop_breakdowns:
                breakdown_list.append({
                    'from_stop_order': breakdown.from_stop_order,
                    'to_stop_order': breakdown.to_stop_order,
                    'from_stop_name': breakdown.from_stop_name,
                    'to_stop_name': breakdown.to_stop_name,
                    'distance_km': float(breakdown.distance_km),
                    'duration_minutes': breakdown.duration_minutes,
                    'price': int(breakdown.price) if breakdown.price is not None else None,
                    'from_coordinates': {
                        'lat': float(breakdown.from_latitude) if breakdown.from_latitude else None,
                        'lng': float(breakdown.from_longitude) if breakdown.from_longitude else None,
                    },
                    'to_coordinates': {
                        'lat': float(breakdown.to_latitude) if breakdown.to_latitude else None,
                        'lng': float(breakdown.to_longitude) if breakdown.to_longitude else None,
                    },
                    'price_breakdown': breakdown.price_breakdown,
                })
            
            return JsonResponse({
                'success': True,
                'trip': {
                    'trip_id': trip.trip_id,
                    'total_distance_km': float(trip.total_distance_km) if trip.total_distance_km else None,
                    'total_duration_minutes': trip.total_duration_minutes,
                    'base_fare': int(trip.base_fare) if trip.base_fare is not None else 0,
                    'fare_calculation': trip.fare_calculation,
                    'stop_breakdown': breakdown_list,
                }
            })
        except Trip.DoesNotExist:
            return JsonResponse({'success': False, 'error': 'Trip not found'}, status=404)
        except Exception as e:
            return JsonResponse({'success': False, 'error': str(e)}, status=400)
    
    return JsonResponse({'error': 'Invalid request method'}, status=400)

# Add these helper functions and views to the end of views.py

def map_trip_status_to_frontend(trip_status):
    """Map backend trip status to frontend expectations"""
    status_mapping = {
        'SCHEDULED': 'pending',
        'IN_PROGRESS': 'inprocess', 
        'COMPLETED': 'completed',
        'CANCELLED': 'cancelled'
    }
    return status_mapping.get(trip_status, 'unknown')

def update_trip_status_automatically(trip):
    """Automatically update trip status based on date/time"""
    now = timezone.now()
    trip_datetime = timezone.make_aware(
        datetime.combine(trip.trip_date, trip.departure_time)
    )
    
    # If trip is in the past and not completed/cancelled, mark as completed
    if now > trip_datetime and trip.trip_status == 'SCHEDULED':
        trip.trip_status = 'COMPLETED'
        trip.completed_at = now
        trip.save()
    # If trip is currently happening (within 2 hours of departure), mark as in progress
    elif (trip_datetime - timedelta(hours=2)) <= now <= (trip_datetime + timedelta(hours=8)) and trip.trip_status == 'SCHEDULED':
        trip.trip_status = 'IN_PROGRESS'
        trip.started_at = now
        trip.save()
    
    return trip

def can_edit_trip(trip):
    """Check if trip can be edited"""
    # Can't edit completed, in-progress, or cancelled trips
    if trip.trip_status in ['COMPLETED', 'IN_PROGRESS', 'CANCELLED']:
        return False
    
    # Can't edit if there are confirmed bookings
    confirmed_bookings = trip.trip_bookings.filter(booking_status='CONFIRMED')
    if confirmed_bookings.exists():
        return False
    
    return True


@csrf_exempt
def get_user_created_rides_history(request, user_id):
    """Get created rides history for a user (driver). Archived after 24h finalization."""
    if request.method != 'GET':
        return JsonResponse({'error': 'Invalid request method'}, status=400)

    try:
        user = UsersData.objects.only('id').get(id=user_id)
    except UsersData.DoesNotExist:
        return JsonResponse({'success': False, 'error': 'User not found'}, status=404)

    limit, offset = _parse_limit_offset(request, default_limit=10)
    cutoff = timezone.now() - timedelta(hours=24)

    pending_payments_qs = (
        Booking.objects.filter(
            trip=OuterRef('pk'),
            booking_status__in=['CONFIRMED', 'COMPLETED'],
        )
        .exclude(payment_status='COMPLETED')
    )

    has_actual_path_qs = TripActualPathSummary.objects.filter(
        trip_id=OuterRef('trip_id'),
        point_count__gte=2,
    )

    trips_qs = (
        Trip.objects.filter(driver=user, trip_status__in=['COMPLETED', 'CANCELLED'])
        .select_related('route', 'vehicle')
        .only(
            'id', 'trip_id', 'trip_date', 'departure_time', 'created_at', 'updated_at',
            'completed_at', 'cancelled_at', 'trip_status',
            'live_tracking_state',
            'total_seats', 'available_seats', 'base_fare', 'gender_preference', 'notes', 'is_negotiable',
            'total_distance_km', 'total_duration_minutes',
            'route__route_id', 'route__route_name', 'route__route_description', 'route__total_distance_km', 'route__estimated_duration_minutes',
            'vehicle__id', 'vehicle__model_number', 'vehicle__company_name', 'vehicle__plate_number', 'vehicle__vehicle_type', 'vehicle__color', 'vehicle__seats', 'vehicle__fuel_type',
        )
        .annotate(
            finalized_at=Coalesce('cancelled_at', 'completed_at', 'updated_at', output_field=DateTimeField()),
            booking_count=Count('trip_bookings', filter=Q(trip_bookings__booking_status__in=['CONFIRMED', 'COMPLETED'])),
            has_pending_payment=Exists(pending_payments_qs),
            has_actual_path=Exists(has_actual_path_qs),
        )
        .filter(finalized_at__lte=cutoff)
        .filter(Q(trip_status='CANCELLED') | Q(has_pending_payment=False))
        .order_by('-finalized_at', '-id')
    )

    # Snapshot fallback (for purged trips). We only include snapshots that no longer
    # have a live Trip row linked (trip is set to NULL after purge).
    snap_has_actual_path_qs = TripActualPathSummary.objects.filter(
        trip_id=OuterRef('trip_id'),
        point_count__gte=2,
    )
    snap_booking_count_sq = (
        BookingHistorySnapshot.objects.filter(
            trip_id=OuterRef('trip_id'),
            booking_status__in=['CONFIRMED', 'COMPLETED'],
        )
        .values('trip_id')
        .annotate(c=Count('*'))
        .values('c')
    )
    snaps_qs = (
        TripHistorySnapshot.objects.filter(
            driver=user,
            trip_status__in=['COMPLETED', 'CANCELLED'],
            finalized_at__lte=cutoff,
            trip_obj__isnull=True,
        )
        .only(
            'id', 'trip_id', 'trip_status', 'trip_date', 'departure_time', 'finalized_at',
            'route_names', 'vehicle_data', 'total_seats', 'base_fare', 'gender_preference',
            'notes', 'is_negotiable', 'fare_calculation',
        )
        .annotate(
            has_actual_path=Exists(snap_has_actual_path_qs),
            booking_count=Coalesce(snap_booking_count_sq[:1], 0),
        )
        .order_by('-finalized_at', '-id')
    )

    # Merge (Trip + Snapshot) by finalized_at desc, then apply combined pagination.
    # We overfetch slightly to avoid missing items when one source dominates.
    target_n = offset + limit
    fetch_n = target_n
    max_fetch_n = max(target_n, 200)
    max_fetch_n = min(max_fetch_n, 2000)
    merged = []
    for _ in range(6):
        trip_page = list(trips_qs[:fetch_n])
        snap_page = list(snaps_qs[:fetch_n])

        merged = []
        for trip in trip_page:
            merged.append(('trip', trip, getattr(trip, 'finalized_at', None)))
        for snap in snap_page:
            merged.append(('snap', snap, getattr(snap, 'finalized_at', None)))

        def _sort_key(item):
            _kind, obj, fin = item
            return (fin or timezone.datetime.min.replace(tzinfo=timezone.get_current_timezone()), getattr(obj, 'id', 0))

        merged.sort(key=_sort_key, reverse=True)
        if len(merged) >= target_n:
            break
        if len(trip_page) < fetch_n and len(snap_page) < fetch_n:
            break
        if fetch_n >= max_fetch_n:
            break
        fetch_n = min(max_fetch_n, max(fetch_n + limit, int(fetch_n * 2)))

    merged = merged[offset:offset + limit]

    rides_list = []
    for kind, obj, _fin in merged:
        if kind == 'trip':
            trip = obj
            route_names = []
            try:
                if trip.fare_calculation and isinstance(trip.fare_calculation, dict):
                    sb = trip.fare_calculation.get('stop_breakdown') or []
                    if isinstance(sb, list) and sb:
                        first = sb[0]
                        last = sb[-1]
                        route_names = [str(first.get('from_stop_name') or 'From'), str(last.get('to_stop_name') or 'To')]
            except Exception:
                route_names = route_names or []

            if not route_names:
                try:
                    route = getattr(trip, 'route', None)
                    if route is not None:
                        fs = getattr(route, 'first_stop', None)
                        ls = getattr(route, 'last_stop', None)
                        if fs is not None and ls is not None:
                            route_names = [
                                str(getattr(fs, 'stop_name', None) or 'From'),
                                str(getattr(ls, 'stop_name', None) or 'To'),
                            ]
                        elif getattr(route, 'route_name', None):
                            route_names = [str(getattr(route, 'route_name', None))]
                except Exception:
                    route_names = route_names or []

            vehicle = trip.vehicle
            vehicle_data = None
            if vehicle:
                vehicle_data = {
                    'id': vehicle.id,
                    'model_number': vehicle.model_number,
                    'company_name': vehicle.company_name,
                    'plate_number': vehicle.plate_number,
                    'vehicle_type': vehicle.vehicle_type,
                    'color': vehicle.color,
                    'seats': vehicle.seats,
                    'fuel_type': vehicle.fuel_type,
                }

            booking_count = getattr(trip, 'booking_count', 0) or 0
            has_actual_path = bool(getattr(trip, 'has_actual_path', False))

            rides_list.append({
                'id': trip.id,
                'trip_id': trip.trip_id,
                'trip_date': trip.trip_date.isoformat() if trip.trip_date else None,
                'date': trip.trip_date.isoformat() if trip.trip_date else None,
                'departure_time': trip.departure_time.strftime('%H:%M') if trip.departure_time else None,
                'from_location': route_names[0] if route_names else 'Unknown',
                'to_location': route_names[-1] if route_names else 'Unknown',
                'route_names': route_names,
                'distance': float(trip.total_distance_km) if trip.total_distance_km is not None else None,
                'duration': trip.total_duration_minutes,
                'total_seats': trip.total_seats,
                'custom_price': int(trip.base_fare) if trip.base_fare is not None else None,
                'booking_count': booking_count,
                'gender_preference': trip.gender_preference,
                'description': trip.notes if trip.notes else '',
                'status': map_trip_status_to_frontend(trip.trip_status),
                'has_actual_path': has_actual_path,
                'is_negotiable': trip.is_negotiable,
                'created_at': trip.created_at.isoformat() if trip.created_at else None,
                'updated_at': trip.updated_at.isoformat() if trip.updated_at else None,
                'vehicle': vehicle_data,
                'can_edit': False,
                'can_delete': False,
                'can_cancel': False,
            })
        else:
            snap = obj
            route_names = []
            try:
                route_names = list(getattr(snap, 'route_names', None) or [])
            except Exception:
                route_names = []

            if not route_names:
                try:
                    ps = getattr(snap, 'planned_stops', None) or []
                    if isinstance(ps, list) and ps:
                        names = []
                        for s in ps:
                            if not isinstance(s, dict):
                                continue
                            n = (s.get('name') or '').strip()
                            if n:
                                names.append(n)
                        if names:
                            route_names = [names[0], names[-1]] if len(names) >= 2 else names
                except Exception:
                    route_names = route_names or []

            if not route_names:
                try:
                    rn = (getattr(snap, 'route_name', None) or '').strip()
                    if rn:
                        route_names = [rn]
                except Exception:
                    route_names = route_names or []

            vehicle_data = None
            try:
                vd = getattr(snap, 'vehicle_data', None) or {}
                if isinstance(vd, dict) and vd:
                    vehicle_data = vd
            except Exception:
                vehicle_data = None

            fc = getattr(snap, 'fare_calculation', None) or {}
            distance = None
            duration = None
            try:
                if isinstance(fc, dict):
                    distance = fc.get('total_distance_km')
                    duration = fc.get('total_duration_minutes')
            except Exception:
                distance = None
                duration = None

            booking_count = int(getattr(snap, 'booking_count', 0) or 0)
            has_actual_path = bool(getattr(snap, 'has_actual_path', False))

            rides_list.append({
                'id': snap.trip_id,
                'trip_id': snap.trip_id,
                'trip_date': snap.trip_date.isoformat() if getattr(snap, 'trip_date', None) else None,
                'date': snap.trip_date.isoformat() if getattr(snap, 'trip_date', None) else None,
                'departure_time': snap.departure_time.strftime('%H:%M') if getattr(snap, 'departure_time', None) else None,
                'from_location': route_names[0] if route_names else 'Unknown',
                'to_location': route_names[-1] if route_names else 'Unknown',
                'route_names': route_names,
                'distance': float(distance) if isinstance(distance, (int, float, Decimal)) else None,
                'duration': int(duration) if isinstance(duration, (int, float, Decimal)) else None,
                'total_seats': getattr(snap, 'total_seats', None),
                'custom_price': int(snap.base_fare) if getattr(snap, 'base_fare', None) is not None else None,
                'booking_count': booking_count,
                'gender_preference': snap.gender_preference,
                'description': snap.notes if getattr(snap, 'notes', None) else '',
                'status': map_trip_status_to_frontend(snap.trip_status),
                'has_actual_path': has_actual_path,
                'is_negotiable': bool(getattr(snap, 'is_negotiable', True)),
                'created_at': getattr(snap, 'created_at', None).isoformat() if getattr(snap, 'created_at', None) else None,
                'updated_at': getattr(snap, 'finalized_at', None).isoformat() if getattr(snap, 'finalized_at', None) else None,
                'vehicle': vehicle_data,
                'can_edit': False,
                'can_delete': False,
                'can_cancel': False,
            })

    return JsonResponse({
        'success': True,
        'rides': rides_list,
        'limit': limit,
        'offset': offset,
        'returned': len(rides_list),
    })


@csrf_exempt
def trigger_auto_archive_for_driver(request, user_id):
    if request.method not in ['POST', 'GET']:
        return JsonResponse({'success': False, 'error': 'Method not allowed'}, status=405)

    try:
        driver_id = int(user_id)
    except Exception:
        return JsonResponse({'success': False, 'error': 'Invalid user id'}, status=400)

    limit = 5
    try:
        raw = request.GET.get('limit')
        if raw is not None:
            limit = int(raw)
    except Exception:
        limit = 5
    limit = max(1, min(limit, 50))

    processed = 0
    try:
        from lets_go.auto_archive import auto_archive_for_driver
        processed = int(auto_archive_for_driver(driver_id=driver_id, limit=limit) or 0)
    except Exception:
        processed = 0

    return JsonResponse({'success': True, 'processed': processed})


@csrf_exempt
def get_user_booked_rides_history(request, user_id):
    """Get booked rides history for a user (passenger). Archived after 24h finalization."""
    if request.method != 'GET':
        return JsonResponse({'error': 'Invalid request method'}, status=400)

    try:
        user = UsersData.objects.only('id', 'name').get(id=user_id)
    except UsersData.DoesNotExist:
        return JsonResponse({'success': False, 'error': 'User not found'}, status=404)

    limit, offset = _parse_limit_offset(request, default_limit=10)
    cutoff = timezone.now() - timedelta(hours=24)

    # Eligible bookings per product rule:
    # ride_status == DROPPED_OFF and payment_status == COMPLETED
    qs = (
        Booking.objects.filter(
            passenger=user,
            ride_status='DROPPED_OFF',
            payment_status='COMPLETED',
        )
        .select_related('trip', 'trip__route', 'from_stop', 'to_stop')
        .only(
            'id', 'booking_id', 'booking_status', 'payment_status', 'ride_status',
            'booked_at', 'completed_at', 'updated_at', 'dropoff_at',
            'trip__trip_id', 'trip__trip_date', 'trip__departure_time',
            'trip__route__route_id', 'trip__route__route_name',
            'from_stop__stop_name', 'from_stop__stop_order',
            'to_stop__stop_name', 'to_stop__stop_order',
            'total_fare', 'number_of_seats', 'male_seats', 'female_seats',
        )
        .annotate(finalized_at=Coalesce('dropoff_at', 'completed_at', 'updated_at', output_field=DateTimeField()))
        .filter(finalized_at__lte=cutoff)
        .order_by('-finalized_at', '-id')
    )

    # Snapshot fallback (for purged bookings)
    # NOTE: We filter booking__isnull=True to avoid double counting bookings that still exist.
    snap_qs = (
        BookingHistorySnapshot.objects.filter(
            passenger=user,
            ride_status='DROPPED_OFF',
            payment_status='COMPLETED',
            finalized_at__lte=cutoff,
            booking_obj__isnull=True,
        )
        .only(
            'id', 'booking_id', 'trip_id', 'booking_status', 'payment_status', 'ride_status',
            'from_stop_name', 'to_stop_name', 'from_stop_order', 'to_stop_order',
            'total_fare', 'number_of_seats', 'finalized_at',
        )
        .order_by('-finalized_at', '-id')
    )

    target_n = offset + limit
    fetch_n = target_n
    max_fetch_n = max(target_n, 200)
    max_fetch_n = min(max_fetch_n, 2000)
    merged = []
    for _ in range(6):
        live_page = list(qs[:fetch_n])
        snap_page = list(snap_qs[:fetch_n])

        merged = []
        for b in live_page:
            merged.append(('live', b, getattr(b, 'finalized_at', None)))
        for s in snap_page:
            merged.append(('snap', s, getattr(s, 'finalized_at', None)))

        def _sort_key(item):
            _kind, obj, fin = item
            return (fin or timezone.datetime.min.replace(tzinfo=timezone.get_current_timezone()), getattr(obj, 'id', 0))

        merged.sort(key=_sort_key, reverse=True)
        if len(merged) >= target_n:
            break
        if len(live_page) < fetch_n and len(snap_page) < fetch_n:
            break
        if fetch_n >= max_fetch_n:
            break
        fetch_n = min(max_fetch_n, max(fetch_n + limit, int(fetch_n * 2)))

    merged = merged[offset:offset + limit]

    # For snapshot rows, enrich trip_date / departure_time from TripHistorySnapshot if available.
    snap_trip_ids = []
    for kind, obj, _fin in merged:
        if kind == 'snap':
            try:
                if getattr(obj, 'trip_id', None):
                    snap_trip_ids.append(obj.trip_id)
            except Exception:
                continue
    trip_info = {}
    if snap_trip_ids:
        for ts in TripHistorySnapshot.objects.filter(trip_id__in=snap_trip_ids).only('trip_id', 'trip_date', 'departure_time'):
            trip_info[ts.trip_id] = ts

    bookings = []
    for kind, obj, _fin in merged:
        if kind == 'live':
            booking = obj
            trip = booking.trip
            route_names = [
                booking.from_stop.stop_name if booking.from_stop else 'From',
                booking.to_stop.stop_name if booking.to_stop else 'To',
            ]
            bookings.append({
                'booking_id': booking.booking_id,
                'id': booking.id,
                'db_id': booking.id,
                'route_names': route_names,
                'trip_id': trip.trip_id if trip else None,
                'trip_date': trip.trip_date.isoformat() if trip and trip.trip_date else None,
                'departure_time': trip.departure_time.strftime('%H:%M') if trip and trip.departure_time else None,
                'status': booking.booking_status,
                'booking_status': booking.booking_status,
                'payment_status': booking.payment_status,
                'ride_status': booking.ride_status,
                'total_fare': int(booking.total_fare) if booking.total_fare is not None else 0,
                'number_of_seats': booking.number_of_seats,
                'male_seats': int(getattr(booking, 'male_seats', 0) or 0),
                'female_seats': int(getattr(booking, 'female_seats', 0) or 0),
                'from_stop_order': booking.from_stop.stop_order if booking.from_stop else None,
                'to_stop_order': booking.to_stop.stop_order if booking.to_stop else None,
                'updated_at': booking.updated_at.isoformat() if booking.updated_at else None,
            })
        else:
            snap = obj
            ts = trip_info.get(getattr(snap, 'trip_id', None))
            trip_date = getattr(ts, 'trip_date', None) if ts is not None else None
            dep_time = getattr(ts, 'departure_time', None) if ts is not None else None

            route_names = [
                getattr(snap, 'from_stop_name', None) or 'From',
                getattr(snap, 'to_stop_name', None) or 'To',
            ]
            bookings.append({
                'booking_id': snap.booking_id,
                'id': snap.booking_id,
                'db_id': None,
                'route_names': route_names,
                'trip_id': snap.trip_id,
                'trip_date': trip_date.isoformat() if trip_date else None,
                'departure_time': dep_time.strftime('%H:%M') if dep_time else None,
                'status': snap.booking_status,
                'booking_status': snap.booking_status,
                'payment_status': snap.payment_status,
                'ride_status': snap.ride_status,
                'total_fare': int(snap.total_fare) if getattr(snap, 'total_fare', None) is not None else 0,
                'number_of_seats': snap.number_of_seats,
                'male_seats': 0,
                'female_seats': 0,
                'from_stop_order': snap.from_stop_order,
                'to_stop_order': snap.to_stop_order,
                'updated_at': getattr(snap, 'finalized_at', None).isoformat() if getattr(snap, 'finalized_at', None) else None,
            })

    return JsonResponse({
        'success': True,
        'bookings': bookings,
        'limit': limit,
        'offset': offset,
        'returned': len(bookings),
    })

def can_delete_trip(trip):
    """Check if trip can be deleted"""
    # Can't delete completed, in-progress, or cancelled trips
    if trip.trip_status in ['COMPLETED', 'IN_PROGRESS', 'CANCELLED']:
        return False
    
    # Can't delete if there are any bookings
    if trip.trip_bookings.exists():
        return False
    
    return True

def can_cancel_trip(trip):
    """Check if trip can be cancelled"""
    # Can't cancel already cancelled or completed trips
    if trip.trip_status in ['CANCELLED', 'COMPLETED']:
        return False
    
    return True

@csrf_exempt
def get_user_rides(request, user_id):
    """Get all rides created by a specific user"""
    if request.method == 'GET':
        try:
            try:
                from lets_go.auto_archive import auto_archive_for_driver
                auto_archive_for_driver(driver_id=int(user_id), limit=5)
            except Exception:
                pass

            # Verify user exists with minimal fields
            user = UsersData.objects.only('id').get(id=user_id)

            # Pagination to avoid huge result sets
            try:
                limit = int(request.GET.get('limit', 20))
                limit = max(1, min(limit, 200))
            except Exception:
                limit = 20
            try:
                offset = int(request.GET.get('offset', 0))
                offset = max(0, offset)
            except Exception:
                offset = 0

            cutoff_dt = timezone.now() - timedelta(hours=24)

            # Summary mode flag to return lightweight payload for My Rides list
            mode = (request.GET.get('mode') or '').lower()
            is_summary = mode == 'summary'

            # Prefetch minimal related data only when not in summary mode
            route_stops_prefetch = None
            stop_breakdowns_prefetch = None
            if not is_summary:
                route_stops_prefetch = Prefetch(
                    'route__route_stops',
                    queryset=RouteStop.objects.only('id', 'stop_order', 'stop_name', 'latitude', 'longitude', 'address', 'estimated_time_from_start').order_by('stop_order')
                )
                stop_breakdowns_prefetch = Prefetch(
                    'stop_breakdowns',
                    queryset=TripStopBreakdown.objects.only('trip_id', 'from_stop_order', 'to_stop_order', 'from_stop_name', 'to_stop_name', 'distance_km', 'duration_minutes', 'price', 'from_latitude', 'from_longitude', 'to_latitude', 'to_longitude').order_by('from_stop_order')
                )

            # Optimized trips queryset
            cutoff_dt = timezone.now() - timedelta(hours=24)
            trips_qs = (
                Trip.objects.filter(driver=user)
                .select_related('route', 'vehicle')
                .only(
                    'id', 'trip_id', 'trip_date', 'departure_time', 'created_at', 'updated_at', 'trip_status',
                    'total_seats', 'available_seats', 'base_fare', 'gender_preference', 'notes', 'is_negotiable',
                    'total_distance_km', 'total_duration_minutes',
                    'route__route_id', 'route__route_name', 'route__route_description', 'route__total_distance_km', 'route__estimated_duration_minutes',
                    'vehicle__id', 'vehicle__model_number', 'vehicle__company_name', 'vehicle__plate_number', 'vehicle__vehicle_type', 'vehicle__color', 'vehicle__seats', 'vehicle__fuel_type',
                )
                .annotate(booking_count=Count('trip_bookings', filter=Q(trip_bookings__booking_status__in=['CONFIRMED', 'COMPLETED'])))
                .exclude(
                    Q(trip_status__in=['COMPLETED', 'CANCELLED'])
                    & Q(history_snapshot__finalized_at__isnull=False)
                    & Q(history_snapshot__finalized_at__lte=cutoff_dt)
                )
                .order_by('-created_at')
            )
            if not is_summary:
                trips_qs = trips_qs.prefetch_related(route_stops_prefetch, stop_breakdowns_prefetch)

            trips_qs = trips_qs[offset:offset + limit]

            rides_list = []
            for trip in trips_qs:
                route = trip.route
                route_names = []
                if not is_summary and route:
                    route_stops = list(route.route_stops.all())
                    route_names = [stop.stop_name for stop in route_stops] if route_stops else []
                else:
                    # In summary mode, try to derive names from fare_calculation if present, else leave empty
                    try:
                        if trip.fare_calculation and isinstance(trip.fare_calculation, dict):
                            sb = trip.fare_calculation.get('stop_breakdown') or []
                            if isinstance(sb, list) and sb:
                                first = sb[0]
                                last = sb[-1]
                                route_names = [str(first.get('from_stop_name') or 'From'), str(last.get('to_stop_name') or 'To')]
                    except Exception:
                        route_names = route_names or []

                # Vehicle details (from selected fields)
                vehicle = trip.vehicle
                vehicle_data = None
                if vehicle:
                    vehicle_data = {
                        'id': vehicle.id,
                        'model_number': vehicle.model_number,
                        'company_name': vehicle.company_name,
                        'plate_number': vehicle.plate_number,
                        'vehicle_type': vehicle.vehicle_type,
                        'color': vehicle.color,
                        'seats': vehicle.seats,
                        'fuel_type': vehicle.fuel_type,
                    }

                # Route coordinates (heavy) only in detail mode
                route_coordinates = []
                if not is_summary and route:
                    for stop in route.route_stops.all():
                        if stop.latitude and stop.longitude:
                            route_coordinates.append({'lat': float(stop.latitude), 'lng': float(stop.longitude), 'name': stop.stop_name, 'order': stop.stop_order})

                # Stop breakdowns (heavy) only in detail mode
                stop_breakdown = []
                if not is_summary:
                    for breakdown in trip.stop_breakdowns.all():
                        stop_breakdown.append({
                            'from_stop_name': breakdown.from_stop_name,
                            'to_stop_name': breakdown.to_stop_name,
                            'distance': float(breakdown.distance_km) if breakdown.distance_km is not None else None,
                            'duration': breakdown.duration_minutes,
                            'price': int(breakdown.price) if breakdown.price is not None else None,
                            'from_coordinates': {
                                'lat': float(breakdown.from_latitude) if breakdown.from_latitude is not None else None,
                                'lng': float(breakdown.from_longitude) if breakdown.from_longitude is not None else None,
                            },
                            'to_coordinates': {
                                'lat': float(breakdown.to_latitude) if breakdown.to_latitude is not None else None,
                                'lng': float(breakdown.to_longitude) if breakdown.to_longitude is not None else None,
                            },
                        })

                booking_count = getattr(trip, 'booking_count', 0) or 0

                ride_data = {
                    'id': trip.id,
                    'trip_id': trip.trip_id,
                    'trip_date': trip.trip_date.isoformat() if trip.trip_date else None,
                    'date': trip.trip_date.isoformat() if trip.trip_date else None,
                    'departure_time': trip.departure_time.strftime('%H:%M') if trip.departure_time else None,
                    'from_location': route_names[0] if route_names else 'Unknown',
                    'to_location': route_names[-1] if route_names else 'Unknown',
                    'route_names': route_names,
                    **({'route_coordinates': route_coordinates} if not is_summary else {}),
                    'distance': float(trip.total_distance_km) if trip.total_distance_km is not None else None,
                    'duration': trip.total_duration_minutes,
                    'custom_price': int(trip.base_fare) if trip.base_fare is not None else None,
                    'fare_collected': (int(trip.base_fare) if trip.base_fare is not None else 0) * booking_count,
                    'passenger_count': booking_count,
                    'vehicle_type': vehicle_data['vehicle_type'] if vehicle_data else 'Car',
                    'total_seats': trip.total_seats,
                    'available_seats': trip.available_seats,
                    'booking_count': booking_count,
                    'gender_preference': trip.gender_preference,
                    'description': trip.notes if trip.notes else '',
                    'status': map_trip_status_to_frontend(trip.trip_status),
                    'is_negotiable': trip.is_negotiable,
                    'created_at': trip.created_at.isoformat() if trip.created_at else None,
                    'updated_at': trip.updated_at.isoformat() if trip.updated_at else None,
                    'vehicle': vehicle_data,
                    **({
                        'route': {
                            'id': route.route_id if route else 'Unknown',
                            'name': route.route_name if route else 'Custom Route',
                            'description': route.route_description if route else 'Route description not available',
                            'total_distance_km': float(route.total_distance_km) if route and route.total_distance_km else 0.0,
                            'estimated_duration_minutes': int(route.estimated_duration_minutes) if route and route.estimated_duration_minutes else 0,
                            'route_stops': [
                                {
                                    'id': stop.id,
                                    'stop_order': stop.stop_order,
                                    'stop_name': stop.stop_name,
                                    'latitude': float(stop.latitude) if stop.latitude else 0.0,
                                    'longitude': float(stop.longitude) if stop.longitude else 0.0,
                                    'address': stop.address if stop.address else 'No address',
                                    'estimated_time_from_start': int(stop.estimated_time_from_start) if stop.estimated_time_from_start else 0,
                                } for stop in route_stops
                            ] if route_stops else []
                        },
                        'fare_calculation': trip.fare_calculation,
                        'stop_breakdown': stop_breakdown,
                    } if not is_summary else {}),
                    'can_edit': can_edit_trip(trip),
                    'can_delete': can_delete_trip(trip),
                    'can_cancel': can_cancel_trip(trip),
                }

                rides_list.append(ride_data)

            return JsonResponse({'success': True, 'rides': rides_list, 'total_rides': len(rides_list)})
        
        except UsersData.DoesNotExist:
            return JsonResponse({'success': False, 'error': 'User not found'}, status=404)
        except Exception as e:
            import traceback
            return JsonResponse({'success': False, 'error': str(e)}, status=500)
    
    return JsonResponse({'error': 'Invalid request method'}, status=400)

@csrf_exempt
def get_trip_details(request, trip_id):
    """Get detailed information about a specific trip"""
    if request.method == 'GET':
        try:
            logger.debug('[GET_TRIP_DETAILS] START %s', trip_id)
            trip = Trip.objects.get(trip_id=trip_id)
            
            # Update status automatically
            trip = update_trip_status_automatically(trip)
            
            # Build route details safely
            route = getattr(trip, 'route', None)
            route_stops = []
            if route is not None:
                try:
                    route_stops = route.route_stops.all().order_by('stop_order')
                except Exception as _e:
                    logger.exception('[GET_TRIP_DETAILS] route_stops error: %s', str(_e))
                    route_stops = []
            
            # Get bookings
            bookings = trip.trip_bookings.filter(booking_status='CONFIRMED')
            booking_details = []
            for booking in bookings:
                booking_details.append({
                    'booking_id': booking.booking_id,
                    'passenger_name': booking.passenger.name,
                    'from_stop': booking.from_stop.stop_name,
                    'to_stop': booking.to_stop.stop_name,
                    'number_of_seats': booking.number_of_seats,
                    'total_fare': int(booking.total_fare) if booking.total_fare is not None else 0,
                    'booked_at': booking.booked_at.isoformat(),
                })
            
            # Get vehicle details
            vehicle_data = None
            if trip.vehicle:
                vehicle_data = {
                    'id': trip.vehicle.id,
                    'model_number': trip.vehicle.model_number,
                    'company_name': trip.vehicle.company_name,
                    'plate_number': trip.vehicle.plate_number,
                    'vehicle_type': trip.vehicle.vehicle_type,
                    'color': trip.vehicle.color,
                    'seats': trip.vehicle.seats,
                    'fuel_type': trip.vehicle.fuel_type,
                }
            
            # Build driver data safely
            driver = getattr(trip, 'driver', None)
            driver_data = None
            if driver is not None:
                driver_data = {
                    'id': driver.id,
                    'name': driver.name,
                    'phone_no': driver.phone_no,
                }

            # Serialize stop_breakdowns with coordinates from DB so frontend map can rebuild
            try:
                sb_qs = trip.stop_breakdowns.all().order_by('from_stop_order', 'to_stop_order')
            except Exception:
                sb_qs = []
            stop_breakdown = []
            for sb in sb_qs:
                stop_breakdown.append({
                    'from_stop_order': sb.from_stop_order,
                    'to_stop_order': sb.to_stop_order,
                    'from_stop_name': sb.from_stop_name,
                    'to_stop_name': sb.to_stop_name,
                    'distance_km': float(sb.distance_km) if sb.distance_km is not None else None,
                    'duration_minutes': sb.duration_minutes,
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

            # Actual path: prefer persisted summary so it still works after purge
            actual_path = []
            has_actual_path = False
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

            # Build trip_data
            trip_data = {
                'trip_id': trip.trip_id,
                'trip_date': trip.trip_date.isoformat(),
                'departure_time': trip.departure_time.strftime('%H:%M'),
                'estimated_arrival_time': trip.estimated_arrival_time.strftime('%H:%M') if trip.estimated_arrival_time else None,
                'actual_departure_time': trip.actual_departure_time.strftime('%H:%M') if trip.actual_departure_time else None,
                'actual_arrival_time': trip.actual_arrival_time.strftime('%H:%M') if trip.actual_arrival_time else None,
                
                'status': map_trip_status_to_frontend(trip.trip_status),
                'total_seats': trip.total_seats,
                'available_seats': trip.available_seats,
                'base_fare': int(trip.base_fare) if trip.base_fare is not None else 0,
                
                'total_distance_km': float(trip.total_distance_km) if trip.total_distance_km else None,
                'total_duration_minutes': trip.total_duration_minutes,
                'fare_calculation': trip.fare_calculation,
                'stop_breakdown': stop_breakdown,
                
                'notes': trip.notes,
                'cancellation_reason': trip.cancellation_reason,
                
                'created_at': trip.created_at.isoformat(),
                'updated_at': trip.updated_at.isoformat(),
                'started_at': trip.started_at.isoformat() if trip.started_at else None,
                'completed_at': trip.completed_at.isoformat() if trip.completed_at else None,
                'cancelled_at': trip.cancelled_at.isoformat() if trip.cancelled_at else None,
                
                'vehicle': vehicle_data,
                'driver': driver_data,
                'route': None if route is None else {
                    'id': route.route_id,
                    'name': route.route_name,
                    'description': route.route_description,
                    'total_distance_km': float(route.total_distance_km) if route.total_distance_km else None,
                    'estimated_duration_minutes': route.estimated_duration_minutes,
                    'route_points': [
                        {'lat': float(p.latitude), 'lng': float(p.longitude)}
                        for p in RouteGeometryPoint.objects.filter(route=route).only('latitude', 'longitude').order_by('point_index')
                    ],
                    'stops': [
                        {
                            'name': stop.stop_name,
                            'order': stop.stop_order,
                            'latitude': float(stop.latitude) if stop.latitude else None,
                            'longitude': float(stop.longitude) if stop.longitude else None,
                            'address': stop.address,
                            'estimated_time_from_start': stop.estimated_time_from_start,
                        }
                        for stop in route_stops
                    ],
                },
                'bookings': booking_details,
                'booking_count': len(booking_details),

                # Live-tracking: actual traveled path (if present)
                'has_actual_path': has_actual_path,
                'actual_path': actual_path,
                
                # Permissions
                'can_edit': can_edit_trip(trip),
                'can_delete': can_delete_trip(trip),
                'can_cancel': can_cancel_trip(trip),
            }
            
            logger.debug('[GET_TRIP_DETAILS] OK %s stops=%s', trip_id, len(stop_breakdown))
            return JsonResponse({
                'success': True,
                'trip': trip_data,
            })
            
        except Trip.DoesNotExist:
            # Snapshot fallback: support recreate-trip even if operational Trip row was purged.
            snap = TripHistorySnapshot.objects.filter(trip_id=trip_id).select_related('driver').first()
            if snap is None:
                return JsonResponse({'success': False, 'error': 'Trip not found'}, status=404)

            # Route reconstruction from planned_stops stored in snapshot
            stops = []
            try:
                ps = getattr(snap, 'planned_stops', None) or []
                if isinstance(ps, list):
                    for s in ps:
                        if not isinstance(s, dict):
                            continue
                        stops.append({
                            'name': s.get('name') or 'Stop',
                            'order': s.get('order'),
                            'latitude': s.get('latitude'),
                            'longitude': s.get('longitude'),
                            'address': s.get('address'),
                            'estimated_time_from_start': None,
                        })
            except Exception:
                stops = []

            # Actual path:
            # Prefer the persisted snapshot field so we can purge operational tracking tables.
            actual_path = []
            has_actual_path = False

            try:
                snap_path = getattr(snap, 'actual_path', None)
                if isinstance(snap_path, list) and len(snap_path) >= 2:
                    actual_path = snap_path
                    has_actual_path = True
            except Exception:
                actual_path = []
                has_actual_path = False

            if not has_actual_path:
                try:
                    s = TripActualPathSummary.objects.filter(trip_id=snap.trip_id, point_count__gte=2).only('simplified_points').first()
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

            vehicle_data = None
            try:
                vd = getattr(snap, 'vehicle_data', None) or {}
                if isinstance(vd, dict) and vd:
                    vehicle_data = vd
            except Exception:
                vehicle_data = None

            driver = getattr(snap, 'driver', None)
            driver_data = None
            if driver is not None:
                driver_data = {
                    'id': driver.id,
                    'name': getattr(driver, 'name', None),
                    'phone_no': getattr(driver, 'phone_no', None),
                }

            fc = getattr(snap, 'fare_calculation', None) or {}
            sb_fallback = getattr(snap, 'stop_breakdown', None) or []
            try:
                if (not sb_fallback) and isinstance(fc, dict):
                    maybe_sb = fc.get('stop_breakdown')
                    if isinstance(maybe_sb, list) and maybe_sb:
                        sb_fallback = maybe_sb
            except Exception:
                sb_fallback = sb_fallback or []

            def _sum_sb_field(field_name):
                total = 0
                try:
                    if not isinstance(sb_fallback, list):
                        return None
                    any_val = False
                    for row in sb_fallback:
                        if not isinstance(row, dict):
                            continue
                        v = row.get(field_name)
                        if v is None:
                            continue
                        any_val = True
                        try:
                            total += float(v)
                        except Exception:
                            continue
                    if not any_val:
                        return None
                    return total
                except Exception:
                    return None

            dist_fb = _sum_sb_field('distance_km')
            dur_fb = _sum_sb_field('duration_minutes')

            trip_data = {
                'trip_id': snap.trip_id,
                'trip_date': snap.trip_date.isoformat() if getattr(snap, 'trip_date', None) else None,
                'departure_time': snap.departure_time.strftime('%H:%M') if getattr(snap, 'departure_time', None) else None,
                'estimated_arrival_time': None,
                'actual_departure_time': None,
                'actual_arrival_time': None,
                'status': map_trip_status_to_frontend(snap.trip_status),
                'total_seats': snap.total_seats,
                'available_seats': None,
                'base_fare': int(snap.base_fare) if getattr(snap, 'base_fare', None) is not None else 0,
                'total_distance_km': (
                    fc.get('total_distance_km')
                    if isinstance(fc, dict) and fc.get('total_distance_km') is not None
                    else dist_fb
                ),
                'total_duration_minutes': (
                    fc.get('total_duration_minutes')
                    if isinstance(fc, dict) and fc.get('total_duration_minutes') is not None
                    else (int(dur_fb) if isinstance(dur_fb, (int, float, Decimal)) else dur_fb)
                ),
                'fare_calculation': fc,
                'stop_breakdown': sb_fallback,
                'notes': getattr(snap, 'notes', None),
                'cancellation_reason': None,
                'created_at': getattr(snap, 'created_at', None).isoformat() if getattr(snap, 'created_at', None) else None,
                'updated_at': getattr(snap, 'finalized_at', None).isoformat() if getattr(snap, 'finalized_at', None) else None,
                'started_at': getattr(snap, 'started_at', None).isoformat() if getattr(snap, 'started_at', None) else None,
                'completed_at': getattr(snap, 'completed_at', None).isoformat() if getattr(snap, 'completed_at', None) else None,
                'cancelled_at': getattr(snap, 'cancelled_at', None).isoformat() if getattr(snap, 'cancelled_at', None) else None,
                'vehicle': vehicle_data,
                'driver': driver_data,
                'route': {
                    'id': getattr(snap, 'route_id', None),
                    'name': getattr(snap, 'route_name', None),
                    'description': None,
                    'total_distance_km': None,
                    'estimated_duration_minutes': None,
                    'stops': stops,
                },
                'bookings': [],
                'booking_count': 0,
                'has_actual_path': has_actual_path,
                'actual_path': actual_path,
                'can_edit': False,
                'can_delete': False,
                'can_cancel': False,
            }
            return JsonResponse({'success': True, 'trip': trip_data})
        except Exception as e:
            logger.exception('[GET_TRIP_DETAILS] ERROR %s %s', trip_id, str(e))
            return JsonResponse({'success': False, 'error': str(e)}, status=500)
    
    return JsonResponse({'error': 'Invalid request method'}, status=400)
'''
def fetch_route_geometry_osm(points, api_key):
    """Fetch a route geometry polyline from OpenRouteService.
    points: list of (lat, lng) tuples.
    Returns a list of {"lat": float, "lng": float} along the road, or [] on failure.
    """
    try:
        logger.debug("[ROUTE_GEOMETRY][OSM] points: %s", points)
        if not points or len(points) < 2:
            logger.debug("[ROUTE_GEOMETRY][OSM] not enough points")
            return []
        # OpenRouteService-style API expects [lng, lat]
        coords = [[float(lng), float(lat)] for (lat, lng) in points]
        logger.debug("[ROUTE_GEOMETRY][OSM] coords for API: %s", coords)
        if not api_key:
            logger.debug("[ROUTE_GEOMETRY][OSM] missing api_key")
            return []
        url = "https://api.openrouteservice.org/v2/directions/driving-car"
        headers = {
            "Authorization": api_key,
            "Content-Type": "application/json",
        }
        # Request directions; newer ORS versions may return encoded polyline by default
        body = {
            "coordinates": coords,
            "instructions": False,
            "geometry_simplify": False,
        }
        logger.debug("[ROUTE_GEOMETRY][OSM] POST %s", url)
        resp = requests.post(url, json=body, headers=headers, timeout=15)
        logger.debug("[ROUTE_GEOMETRY][OSM] status %s", resp.status_code)
        logger.debug("[ROUTE_GEOMETRY][OSM] body_prefix %s", (resp.text or '')[:400])
        resp.raise_for_status()
        data = resp.json()

        # ORS v2 directions: geometry is under routes[0]["geometry"]
        routes = data.get('routes') or []
        if not routes:
            logger.debug('[ROUTE_GEOMETRY][OSM] no routes in response')
            return []

        geom = routes[0].get('geometry')

        # Case 1: GeoJSON LineString (some ORS configs / older versions)
        if isinstance(geom, dict) and geom.get('type') == 'LineString':
            line = []
            for lon, lat in coords_ll:
                try:
                    line.append({
                        'lat': float(lat),
                        'lng': float(lon),
                    })
                except Exception:
                    continue
            logger.debug('[ROUTE_GEOMETRY][OSM] extracted points from GeoJSON: %s', len(line))
            return line

        # Case 2: encoded polyline string (default in newer ORS versions)
        if isinstance(geom, str):
            decoded = _decode_ors_polyline(geom)
            line = []
            for lat, lon in decoded:
                try:
                    line.append({
                        'lat': float(lat),
                        'lng': float(lon),
                    })
                except Exception:
                    continue
            logger.debug('[ROUTE_GEOMETRY][OSM] extracted points from encoded polyline: %s', len(line))
            return line

        logger.debug('[ROUTE_GEOMETRY][OSM] unexpected geometry format: %s', type(geom))
        return []
    except Exception as e:
        logger.exception('[ROUTE_GEOMETRY][OSM] failed to fetch geometry: %s', str(e))
        return []

'''
@csrf_exempt
def update_trip(request, trip_id):
    """Update trip details"""
    if request.method == 'PUT':
        try:
            data = json.loads(request.body.decode('utf-8'))
            try:
                logger.debug('=== UPDATE_TRIP DEBUG START ===')
                logger.debug('Trip ID: %s', trip_id)
                logger.debug('Incoming keys: %s', list(data.keys()))
                if 'fare_calculation' in data and isinstance(data.get('fare_calculation'), dict):
                    logger.debug('Fare calc keys: %s', list(data['fare_calculation'].keys()))
                if 'stop_breakdown' in data and isinstance(data.get('stop_breakdown'), list):
                    logger.debug('Stop breakdown count: %s', len(data['stop_breakdown']))
                    if len(data['stop_breakdown']) > 0:
                        first = data['stop_breakdown'][0]
                        logger.debug('First stop raw keys: %s', list(first.keys()))
                logger.debug('=== UPDATE_TRIP DEBUG END HEADER ===')
            except Exception as _e:
                logger.exception('UPDATE_TRIP DEBUG header logging failed: %s', str(_e))
            
            trip = Trip.objects.get(trip_id=trip_id)
            
            # Check if trip can be edited
            if not can_edit_trip(trip):
                return JsonResponse({
                    'success': False, 
                    'error': 'Trip cannot be edited. It may be completed, in progress, or have bookings.'
                }, status=400)
            
            # Update allowed fields
            if 'trip_date' in data:
                trip.trip_date = datetime.strptime(data['trip_date'], '%Y-%m-%d').date()
            
            if 'departure_time' in data:
                dep_hour, dep_minute = map(int, data['departure_time'].split(':'))
                trip.departure_time = time(dep_hour, dep_minute)
            
            if 'total_seats' in data:
                trip.total_seats = data['total_seats']
                trip.available_seats = data['total_seats']  # Reset available seats
            
            if 'base_fare' in data:
                trip.base_fare = _to_int_pkr(data.get('base_fare'), default=trip.base_fare)
            
            if 'gender_preference' in data:
                trip.gender_preference = data['gender_preference']
            
            if 'notes' in data:
                trip.notes = data['notes']
            
            if 'is_negotiable' in data:
                trip.is_negotiable = data['is_negotiable']
                logger.debug('Backend update_trip - Setting is_negotiable to: %s', data.get('is_negotiable'))

            if 'vehicle_id' in data:
                try:
                    vehicle_id = int(data.get('vehicle_id') or 0)
                except Exception:
                    vehicle_id = 0
                if not vehicle_id:
                    return JsonResponse({'success': False, 'error': 'vehicle_id must be a number.'}, status=400)
                try:
                    vehicle = (
                        Vehicle.objects
                        .only('id', 'model_number', 'company_name', 'plate_number', 'vehicle_type', 'color', 'seats', 'fuel_type', 'status', 'engine_number', 'chassis_number')
                        .defer('photo_front', 'photo_back', 'documents_image')
                        .get(id=vehicle_id)
                    )
                except Vehicle.DoesNotExist:
                    return JsonResponse({'success': False, 'error': 'Vehicle not found.'}, status=404)

                if getattr(vehicle, 'status', Vehicle.STATUS_VERIFIED) != Vehicle.STATUS_VERIFIED:
                    return JsonResponse({'success': False, 'error': 'Selected vehicle is not verified yet. Please wait for admin verification.'}, status=400)

                trip.vehicle = vehicle

                try:
                    from ..models.models_trip import TripVehicleHistory
                    try:
                        vh = TripVehicleHistory.objects.get(trip=trip)
                        vh.copy_from_vehicle(vehicle)
                    except TripVehicleHistory.DoesNotExist:
                        seats_for_history = (vehicle.seats if vehicle.vehicle_type == Vehicle.FOUR_WHEELER else 2)
                        TripVehicleHistory.objects.create(
                            trip=trip,
                            vehicle=vehicle,
                            vehicle_type=str(vehicle.vehicle_type or ''),
                            vehicle_model=str(vehicle.model_number or ''),
                            vehicle_make=str(vehicle.company_name or ''),
                            vehicle_color=str(vehicle.color or ''),
                            license_plate=str(vehicle.plate_number or ''),
                            vehicle_capacity=int(vehicle.seats or 1),
                            fuel_type=str(vehicle.fuel_type or ''),
                            engine_number=str(vehicle.engine_number or ''),
                            chassis_number=str(vehicle.chassis_number or ''),
                            vehicle_features={
                                'type': vehicle.vehicle_type,
                                'seats': vehicle.seats,
                                'fuel_type': vehicle.fuel_type,
                            },
                        )
                        _ = vh
                except Exception as _vh_ex:
                    logger.exception('[UPDATE_TRIP][VEHICLE_HISTORY] error while syncing vehicle history: %s', str(_vh_ex))
            
            if 'fare_calculation' in data:
                trip.fare_calculation = data['fare_calculation']
                trip.total_distance_km = data['fare_calculation'].get('total_distance_km')
                trip.total_duration_minutes = data['fare_calculation'].get('total_duration_minutes')
            
            # Update stop breakdowns if provided
            if 'stop_breakdown' in data:
                # Upsert breakdowns to avoid duplicate-key errors if client retries
                new_keys = set()

                # Create / update breakdowns
                for idx, stop_data in enumerate(data['stop_breakdown'] or []):
                    try:
                        # Coalesce legacy and new keys
                        from_order = stop_data.get('from_stop') if stop_data.get('from_stop') is not None else stop_data.get('from_stop_order')
                        to_order = stop_data.get('to_stop') if stop_data.get('to_stop') is not None else stop_data.get('to_stop_order')
                        distance = stop_data.get('distance') if stop_data.get('distance') is not None else stop_data.get('distance_km')
                        duration = stop_data.get('duration') if stop_data.get('duration') is not None else stop_data.get('duration_minutes')
                        # Final fallbacks
                        if duration is None:
                            duration = 0
                        if distance is None:
                            distance = 0.0

                        key = (from_order, to_order)
                        new_keys.add(key)

                        logger.debug(
                            '[UPDATE_TRIP][SB#%s] from=%s to=%s km=%s min=%s price=%s',
                            (idx + 1),
                            from_order,
                            to_order,
                            distance,
                            duration,
                            stop_data.get('price'),
                        )

                        TripStopBreakdown.objects.update_or_create(
                            trip=trip,
                            from_stop_order=from_order,
                            to_stop_order=to_order,
                            defaults={
                                'from_stop_name': stop_data.get('from_stop_name'),
                                'to_stop_name': stop_data.get('to_stop_name'),
                                'distance_km': distance,
                                'duration_minutes': duration,
                                'price': _to_int_pkr(stop_data.get('price'), default=0),
                                'from_latitude': (stop_data.get('from_coordinates') or {}).get('lat'),
                                'from_longitude': (stop_data.get('from_coordinates') or {}).get('lng'),
                                'to_latitude': (stop_data.get('to_coordinates') or {}).get('lat'),
                                'to_longitude': (stop_data.get('to_coordinates') or {}).get('lng'),
                                'price_breakdown': stop_data.get('price_breakdown', {}),
                            },
                        )
                    except Exception as _ex:
                        logger.exception('[UPDATE_TRIP][SB#%s] ERROR while creating breakdown: %s', (idx + 1), str(_ex))
                        raise

                # Remove any old breakdowns that are no longer present in the payload
                try:
                    existing = list(trip.stop_breakdowns.all())
                    for b in existing:
                        if (b.from_stop_order, b.to_stop_order) not in new_keys:
                            b.delete()
                except Exception as _cleanup_ex:
                    logger.exception('[UPDATE_TRIP][SB] cleanup error while removing stale breakdowns: %s', str(_cleanup_ex))
            
            # Safety: ensure gender_preference is never null to satisfy NOT NULL constraint
            try:
                if not getattr(trip, 'gender_preference', None):
                    trip.gender_preference = 'Any'
            except Exception:
                trip.gender_preference = 'Any'
            
            # Option A: keep Route / RouteStop geometry in sync with edited trip
            try:
                route = getattr(trip, 'route', None)
                route_coords = data.get('route_coordinates') or data.get('route_stops')
                if route and isinstance(route_coords, list) and len(route_coords) >= 2:
                    # Normalize to a simple list of dicts with name/order/lat/lng
                    normalized_stops = []
                    for idx, raw in enumerate(route_coords):
                        stop = raw or {}
                        lat = stop.get('lat')
                        lng = stop.get('lng')
                        # Some payloads may use latitude/longitude keys
                        if lat is None:
                            lat = stop.get('latitude')
                        if lng is None:
                            lng = stop.get('longitude')
                        name = stop.get('name') or stop.get('stop_name') or f"Stop {idx+1}"
                        order = stop.get('order') or (idx + 1)
                        normalized_stops.append({
                            'order': int(order),
                            'name': str(name),
                            'lat': lat,
                            'lng': lng,
                        })

                    # Sort by order to be safe
                    normalized_stops.sort(key=lambda s: s['order'])

                    # Update route name/description based on first and last stop names
                    try:
                        if normalized_stops:
                            origin_name = normalized_stops[0]['name']
                            destination_name = normalized_stops[-1]['name']
                            route.route_name = f"{origin_name} to {destination_name}"
                            route.route_description = f"Route from {origin_name} to {destination_name}"
                    except Exception as _name_ex:
                        logger.exception('[UPDATE_TRIP][ROUTE] failed to update name/description: %s', str(_name_ex))

                    # Replace existing RouteStop entries for this route
                    route.route_stops.all().delete()
                    for s in normalized_stops:
                        try:
                            RouteStop.objects.create(
                                route=route,
                                stop_name=s['name'],
                                stop_order=s['order'],
                                latitude=s['lat'],
                                longitude=s['lng'],
                            )
                        except Exception as _rs_ex:
                            logger.exception('[UPDATE_TRIP][ROUTE_STOP] error while creating stop %s %s', str(s), str(_rs_ex))

                    # Optionally refresh aggregate distance/duration if provided
                    fc = data.get('fare_calculation') or trip.fare_calculation or {}
                    try:
                        total_km = fc.get('total_distance_km') or fc.get('calculation_breakdown', {}).get('total_distance_km')
                        total_min = fc.get('total_duration_minutes') or fc.get('calculation_breakdown', {}).get('total_duration_minutes')
                        if total_km is not None:
                            route.total_distance_km = Decimal(str(total_km))
                        if total_min is not None:
                            route.estimated_duration_minutes = int(total_min)
                    except Exception as _agg_ex:
                        logger.exception('[UPDATE_TRIP][ROUTE] failed to update aggregates: %s', str(_agg_ex))

                    # Fetch and store dense road-following geometry using shared utility
                    update_route_geometry_from_stops(route, normalized_stops)
            except Exception as _route_ex:
                logger.exception('[UPDATE_TRIP][ROUTE_SYNC] error while syncing route geometry: %s', str(_route_ex))

            trip.save()
            
            return JsonResponse({
                'success': True,
                'message': 'Trip updated successfully',
                'trip_id': trip.trip_id,
            })
            
        except Trip.DoesNotExist:
            return JsonResponse({'success': False, 'error': 'Trip not found'}, status=404)
        except Exception as e:
            return JsonResponse({'success': False, 'error': str(e)}, status=500)
    
    return JsonResponse({'error': 'Invalid request method'}, status=400)

@csrf_exempt
def delete_trip(request, trip_id):
    """Delete a trip"""
    if request.method == 'DELETE':
        try:
            trip = Trip.objects.get(trip_id=trip_id)
            
            # Check if trip can be deleted
            if not can_delete_trip(trip):
                return JsonResponse({
                    'success': False, 
                    'error': 'Trip cannot be deleted. It may be completed, in progress, or have bookings.'
                }, status=400)
            
            # Delete the trip
            trip.delete()
            
            return JsonResponse({
                'success': True,
                'message': 'Trip deleted successfully',
            })
            
        except Trip.DoesNotExist:
            return JsonResponse({'success': False, 'error': 'Trip not found'}, status=404)
        except Exception as e:
            return JsonResponse({'success': False, 'error': str(e)}, status=500)
    
    return JsonResponse({'error': 'Invalid request method'}, status=400)

@csrf_exempt
def cancel_trip(request, trip_id):
    """Cancel a trip"""
    if request.method == 'POST':
        try:
            data = json.loads(request.body.decode('utf-8'))
            reason = data.get('reason', 'Cancelled by driver')
            
            trip = Trip.objects.get(trip_id=trip_id)
            
            # Check if trip can be cancelled
            if not can_cancel_trip(trip):
                return JsonResponse({
                    'success': False, 
                    'error': 'Trip cannot be cancelled. It may already be cancelled or completed.'
                }, status=400)
            
            # Cancel the trip
            trip.trip_status = 'CANCELLED'
            trip.cancellation_reason = reason
            trip.cancelled_at = timezone.now()
            trip.save()

            # Cancel all remaining bookings (including in-progress passengers).
            active_bookings = trip.trip_bookings.exclude(booking_status__in=['CANCELLED', 'COMPLETED'])
            now = timezone.now()
            for booking in active_bookings:
                booking.booking_status = 'CANCELLED'
                booking.cancelled_at = now
                # If passenger was on board, reflect cancellation explicitly.
                if getattr(booking, 'ride_status', None) == 'RIDE_STARTED':
                    booking.ride_status = 'CANCELLED_ON_BOARD'
                    booking.save(update_fields=['booking_status', 'cancelled_at', 'ride_status', 'updated_at'])
                else:
                    booking.save(update_fields=['booking_status', 'cancelled_at', 'updated_at'])

                # Notify each passenger that the trip was cancelled by the driver
                try:
                    passenger = booking.passenger
                    if passenger and getattr(passenger, 'id', None):
                        payload = {
                            'user_id': str(passenger.id),
                            'driver_id': str(trip.driver.id) if trip.driver_id else None,
                            'title': 'Ride cancelled by driver',
                            'body': f'Your LetsGo ride {trip.trip_id} was cancelled by the driver. '
                                    'Please search for another ride.',
                            'data': {
                                'type': 'trip_cancelled_by_driver',
                                'trip_id': str(trip.trip_id),
                                'booking_id': str(booking.id),
                            },
                        }
                        send_ride_notification_async(payload)
                except Exception as e:
                    logger.exception('[cancel_trip][notify_passenger][ERROR]: %s', str(e))

            return JsonResponse({
                'success': True,
                'message': 'Trip cancelled successfully',
                'cancelled_bookings_count': active_bookings.count(),
            })
            
        except Trip.DoesNotExist:
            return JsonResponse({'success': False, 'error': 'Trip not found'}, status=404)
        except Exception as e:
            return JsonResponse({'success': False, 'error': str(e)}, status=500)
    
    return JsonResponse({'error': 'Invalid request method'}, status=400)

# Additional view functions for API compatibility
@csrf_exempt
def get_route_details(request, route_id):
    """Get route details"""
    if request.method == 'GET':
        try:
            route = None
            try:
                route_pk = int(str(route_id))
                route = Route.objects.get(id=route_pk)
            except Exception:
                route = None
            if route is None:
                route = Route.objects.get(route_id=str(route_id))
            route_data = {
                'id': route.route_id,
                'name': route.route_name,
                'description': route.route_description,
                'total_distance_km': float(route.total_distance_km) if route.total_distance_km else None,
                'estimated_duration_minutes': route.estimated_duration_minutes,
                'route_points': [
                    {'lat': float(p.latitude), 'lng': float(p.longitude)}
                    for p in RouteGeometryPoint.objects.filter(route=route).only('latitude', 'longitude').order_by('point_index')
                ],
                'stops': [
                    {
                        'name': stop.stop_name,
                        'order': stop.stop_order,
                        'latitude': float(stop.latitude) if stop.latitude else None,
                        'longitude': float(stop.longitude) if stop.longitude else None,
                        'address': stop.address,
                        'estimated_time_from_start': stop.estimated_time_from_start,
                    }
                    for stop in route.route_stops.all().order_by('stop_order')
                ],
            }
            return JsonResponse({'success': True, 'route': route_data})
        except Route.DoesNotExist:
            return JsonResponse({'success': False, 'error': 'Route not found'}, status=404)
        except Exception as e:
            return JsonResponse({'success': False, 'error': str(e)}, status=500)
    
    return JsonResponse({'error': 'Invalid request method'}, status=400)

@csrf_exempt
def get_route_statistics(request, route_id):
    """Get route statistics"""
    if request.method == 'GET':
        try:
            route = Route.objects.get(id=route_id)
            trips = Trip.objects.filter(route=route)
            
            statistics = {
                'total_trips': trips.count(),
                'completed_trips': trips.filter(trip_status='COMPLETED').count(),
                'cancelled_trips': trips.filter(trip_status='CANCELLED').count(),
                'total_bookings': sum(trip.trip_bookings.count() for trip in trips),
                'total_revenue': int(sum(int(trip.base_fare or 0) for trip in trips)),
            }
            return JsonResponse({'success': True, 'statistics': statistics})
        except Route.DoesNotExist:
            return JsonResponse({'success': False, 'error': 'Route not found'}, status=404)
        except Exception as e:
            return JsonResponse({'success': False, 'error': str(e)}, status=500)
    
    return JsonResponse({'error': 'Invalid request method'}, status=400)

@csrf_exempt
def search_routes(request):
    """Search routes"""
    if request.method == 'GET':
        try:
            from_location = request.GET.get('from')
            to_location = request.GET.get('to')
            date = request.GET.get('date')
            min_seats = request.GET.get('min_seats')
            max_price = request.GET.get('max_price')
            
            routes = Route.objects.filter(is_active=True)
            
            # Apply filters
            if from_location:
                routes = routes.filter(route_stops__stop_name__icontains=from_location)
            if to_location:
                routes = routes.filter(route_stops__stop_name__icontains=to_location)
            
            routes_data = []
            for route in routes.distinct():
                routes_data.append({
                    'id': route.route_id,
                    'name': route.route_name,
                    'description': route.route_description,
                    'total_distance_km': float(route.total_distance_km) if route.total_distance_km else None,
                    'estimated_duration_minutes': route.estimated_duration_minutes,
                })
            
            return JsonResponse({'success': True, 'routes': routes_data})
        except Exception as e:
            return JsonResponse({'success': False, 'error': str(e)}, status=500)
    
    return JsonResponse({'error': 'Invalid request method'}, status=400)

@csrf_exempt
def get_available_seats(request, trip_id):
    """Get available seats for a trip"""
    if request.method == 'GET':
        try:
            trip = Trip.objects.get(id=trip_id)
            booked_seats = []
            
            # Get booked seats
            for booking in trip.trip_bookings.filter(booking_status='CONFIRMED'):
                booked_seats.extend(booking.seat_numbers)
            
            # Generate available seats
            all_seats = list(range(1, trip.total_seats + 1))
            available_seats = [seat for seat in all_seats if seat not in booked_seats]
            
            return JsonResponse({
                'success': True,
                'available_seats': available_seats,
                'total_seats': trip.total_seats,
                'booked_seats': booked_seats,
            })
        except Trip.DoesNotExist:
            return JsonResponse({'success': False, 'error': 'Trip not found'}, status=404)
        except Exception as e:
            return JsonResponse({'success': False, 'error': str(e)}, status=500)
    
    return JsonResponse({'error': 'Invalid request method'}, status=400)

@csrf_exempt
def create_booking(request):
    """Create a booking"""
    if request.method == 'POST':
        try:
            data = json.loads(request.body.decode('utf-8'))
            
            # This is a placeholder - implement actual booking logic
            booking_data = {
                'booking_id': f"B{random.randint(100, 999)}-{datetime.now().strftime('%Y-%m-%d-%H%M')}",
                'success': True,
                'message': 'Booking created successfully',
            }
            
            return JsonResponse(booking_data)
        except Exception as e:
            return JsonResponse({'success': False, 'error': str(e)}, status=500)
    
    return JsonResponse({'error': 'Invalid request method'}, status=400)

@csrf_exempt
def get_user_bookings(request, user_id):
    """Get user's bookings"""
    if request.method == 'GET':
        try:
            logger.debug("get_user_bookings called for user_id: %s", user_id)
            # Summary mode for lightweight list
            mode = (request.GET.get('mode') or '').lower()
            is_summary = mode == 'summary'

            cutoff_dt = timezone.now() - timedelta(hours=24)

            # Fetch user minimally to avoid heavy column loads
            user = UsersData.objects.only('id', 'name').get(id=user_id)
            logger.debug("User found: %s", user.name)
            
            # Pagination to avoid huge result sets
            try:
                limit = int(request.GET.get('limit', 20))
                limit = max(1, min(limit, 200))  # cap between 1 and 200
            except Exception:
                limit = 20
            try:
                offset = int(request.GET.get('offset', 0))
                offset = max(0, offset)
            except Exception:
                offset = 0

            # Prefetch only route stops when not in summary mode
            route_stops_prefetch = None
            if not is_summary:
                route_stops_prefetch = Prefetch(
                    'trip__route__route_stops',
                    queryset=RouteStop.objects.only(
                        'id', 'stop_order', 'stop_name', 'latitude', 'longitude', 'address', 'estimated_time_from_start'
                    ).order_by('stop_order')
                )

            # Build optimized queryset: select only needed fields, avoid heavy BinaryFields via related models
            bookings_queryset = (
                Booking.objects.filter(passenger=user)
                .select_related(
                    'trip',
                    'trip__driver',
                    'trip__vehicle',
                    'trip__route',
                    'from_stop',
                    'to_stop',
                )
                .only(
                    # Booking fields
                    'booking_id', 'id', 'booking_status', 'payment_status', 'bargaining_status',
                    'number_of_seats', 'male_seats', 'female_seats', 'seat_numbers', 'total_fare', 'original_fare', 'negotiated_fare',
                    'passenger_offer', 'driver_response', 'negotiation_notes', 'fare_breakdown',
                    'passenger_rating', 'passenger_feedback', 'booked_at', 'cancelled_at', 'completed_at', 'updated_at',
                    # Trip fields
                    'trip__trip_id', 'trip__trip_date', 'trip__departure_time', 'trip__estimated_arrival_time',
                    'trip__trip_status', 'trip__total_seats', 'trip__available_seats', 'trip__base_fare',
                    'trip__gender_preference', 'trip__notes', 'trip__is_negotiable',
                    # Driver fields (avoid binary fields)
                    'trip__driver__id', 'trip__driver__name', 'trip__driver__phone_no',
                    'trip__driver__driver_rating', 'trip__driver__gender',
                    # Vehicle fields
                    'trip__vehicle__id', 'trip__vehicle__company_name', 'trip__vehicle__model_number',
                    'trip__vehicle__plate_number', 'trip__vehicle__color', 'trip__vehicle__vehicle_type',
                    'trip__vehicle__seats',
                    # Route fields
                    'trip__route__route_id', 'trip__route__route_name', 'trip__route__route_description',
                    'trip__route__total_distance_km', 'trip__route__estimated_duration_minutes',
                    # From/To stop fields
                    'from_stop__stop_name', 'from_stop__stop_order', 'from_stop__latitude', 'from_stop__longitude',
                    'to_stop__stop_name', 'to_stop__stop_order', 'to_stop__latitude', 'to_stop__longitude',
                )
                .prefetch_related(*( [route_stops_prefetch] if route_stops_prefetch is not None else [] ))
                .order_by('-booked_at')
            )

            bookings_queryset = bookings_queryset.exclude(
                Q(trip__trip_status__in=['COMPLETED', 'CANCELLED'])
                & Q(trip__history_snapshot__finalized_at__isnull=False)
                & Q(trip__history_snapshot__finalized_at__lte=cutoff_dt)
            )

            # Apply slicing for pagination on the queryset
            bookings_queryset = bookings_queryset[offset:offset + limit]
            
            bookings = []
            for booking in bookings_queryset:
                try:
                    logger.debug("Processing booking %s", booking.booking_id)
                    
                    # Get trip data
                    trip = booking.trip
                    driver = trip.driver
                    vehicle = trip.vehicle
                    route = trip.route
                    
                    # Get route names; in summary mode, avoid loading stops
                    if not is_summary and route:
                        route_stops = route.route_stops.all().order_by('stop_order')
                        route_names = [stop.stop_name for stop in route_stops] if route_stops else ['Unknown']
                    else:
                        route_names = [booking.from_stop.stop_name if booking.from_stop else 'From', booking.to_stop.stop_name if booking.to_stop else 'To']

                    if is_summary:
                        booking_data = {
                            'booking_id': booking.booking_id,
                            'id': booking.id,
                            'db_id': booking.id,
                            'route_names': route_names,
                            'trip_id': trip.trip_id,
                            'trip_date': trip.trip_date.isoformat() if trip.trip_date else None,
                            'departure_time': trip.departure_time.strftime('%H:%M') if trip.departure_time else None,
                            'distance': float(route.total_distance_km) if route and route.total_distance_km else None,
                            'total_seats': trip.total_seats,
                            'available_seats': trip.available_seats,
                            'status': booking.booking_status,
                            'booking_status': booking.booking_status,
                            'payment_status': booking.payment_status,
                            'total_fare': int(booking.total_fare) if booking.total_fare is not None else 0,
                            # Passenger segment orders for frontend map colouring
                            'from_stop_order': booking.from_stop.stop_order if booking.from_stop else None,
                            'to_stop_order': booking.to_stop.stop_order if booking.to_stop else None,
                            # Minimal negotiation fields so passenger screens can show latest state
                            'bargaining_status': booking.bargaining_status,
                            'negotiated_fare': int(booking.negotiated_fare) if booking.negotiated_fare is not None else None,
                            'passenger_offer': int(booking.passenger_offer) if booking.passenger_offer is not None else None,
                            'passenger_id': booking.passenger_id,
                            'driver_response': booking.driver_response,
                            'negotiation_notes': booking.negotiation_notes,
                            'vehicle': {
                                'model_number': vehicle.model_number if vehicle else None,
                                'company_name': vehicle.company_name if vehicle else None,
                                'plate_number': vehicle.plate_number if vehicle else None,
                                'seats': vehicle.seats if vehicle else None,
                                'vehicle_type': vehicle.vehicle_type if vehicle else None,
                            } if vehicle else None,
                        }
                    else:
                        booking_data = {
                            'booking_id': booking.booking_id,
                            'id': booking.id,  # Add numeric ID for API calls
                            'trip_id': trip.trip_id,
                            'status': booking.booking_status,
                            'booking_status': booking.booking_status,
                            'payment_status': booking.payment_status,
                            'bargaining_status': booking.bargaining_status,

                            # Frontend expected fields for passenger ride history
                            'from_location': booking.from_stop.stop_name if booking.from_stop else 'Unknown',
                            'to_location': booking.to_stop.stop_name if booking.to_stop else 'Unknown',
                            'date': trip.trip_date.isoformat() if trip.trip_date else None,
                            'fare': int(booking.total_fare) if booking.total_fare is not None else 0,

                            # Trip information
                            'trip': {
                                'trip_id': trip.trip_id,
                                'trip_date': trip.trip_date.isoformat() if trip.trip_date else None,
                                'departure_time': trip.departure_time.strftime('%H:%M') if trip.departure_time else None,
                                'arrival_time': trip.estimated_arrival_time.strftime('%H:%M') if trip.estimated_arrival_time else None,
                                'trip_status': trip.trip_status,
                                'total_seats': trip.total_seats,
                                'available_seats': trip.available_seats,
                                'base_fare': int(trip.base_fare) if trip.base_fare is not None else 0,
                                'gender_preference': trip.gender_preference,
                                'notes': trip.notes,
                                'is_negotiable': trip.is_negotiable,

                                # Driver information
                                'driver': {
                                    'id': driver.id if driver else None,
                                    'name': driver.name if driver else 'Unknown Driver',
                                    'phone': driver.phone_no if driver else None,
                                    'driver_rating': float(driver.driver_rating) if driver and driver.driver_rating else 0.0,
                                    'gender': driver.gender if driver else None,
                                },

                                # Vehicle information
                                'vehicle': {
                                    'id': vehicle.id if vehicle else None,
                                    'make': vehicle.company_name if vehicle else 'Unknown',
                                    'model': vehicle.model_number if vehicle else 'Unknown',
                                    'license_plate': vehicle.plate_number if vehicle else 'Unknown',
                                    'color': vehicle.color if vehicle else 'Unknown',
                                    'vehicle_type': vehicle.vehicle_type if vehicle else 'Unknown',
                                    'seats': vehicle.seats if vehicle else 0,
                                },

                                # Route information with stops for map display
                                'route': {
                                    'id': route.route_id if route else 'Unknown',
                                    'name': route.route_name if route else 'Custom Route',
                                    'description': route.route_description if route else 'Route description not available',
                                    'total_distance_km': float(route.total_distance_km) if route and route.total_distance_km else 0.0,
                                    'estimated_duration_minutes': int(route.estimated_duration_minutes) if route and route.estimated_duration_minutes else 0,
                                    'route_stops': [
                                        {
                                            'id': stop.id,
                                            'stop_order': stop.stop_order,
                                            'stop_name': stop.stop_name,
                                            'latitude': float(stop.latitude) if stop.latitude else 0.0,
                                            'longitude': float(stop.longitude) if stop.longitude else 0.0,
                                            'address': stop.address if stop.address else 'No address',
                                            'estimated_time_from_start': int(stop.estimated_time_from_start) if stop.estimated_time_from_start else 0,
                                        } for stop in route_stops
                                    ] if route_stops else []
                                }
                            },

                            # Route information
                            'route_names': route_names,
                            'distance': float(route.total_distance_km) if route and route.total_distance_km else 0.0,
                            'custom_price': int(trip.base_fare) if trip.base_fare is not None else 0,

                            # Stop information
                            # Expose passenger segment orders at root as well for convenience
                            'from_stop_order': booking.from_stop.stop_order if booking.from_stop else None,
                            'to_stop_order': booking.to_stop.stop_order if booking.to_stop else None,
                            'from_stop': {
                                'stop_name': booking.from_stop.stop_name if booking.from_stop else 'Unknown',
                                'stop_order': booking.from_stop.stop_order if booking.from_stop else 0,
                                'latitude': float(booking.from_stop.latitude) if booking.from_stop and booking.from_stop.latitude else 0.0,
                                'longitude': float(booking.from_stop.longitude) if booking.from_stop and booking.from_stop.longitude else 0.0,
                            },
                            'to_stop': {
                                'stop_name': booking.to_stop.stop_name if booking.to_stop else 'Unknown',
                                'stop_order': booking.to_stop.stop_order if booking.to_stop else 0,
                                'latitude': float(booking.to_stop.latitude) if booking.to_stop and booking.to_stop.latitude else 0.0,
                                'longitude': float(booking.to_stop.longitude) if booking.to_stop and booking.to_stop.longitude else 0.0,
                            },

                            # Booking details
                            'number_of_seats': booking.number_of_seats,
                            'male_seats': int(getattr(booking, 'male_seats', 0) or 0),
                            'female_seats': int(getattr(booking, 'female_seats', 0) or 0),
                            'seat_numbers': booking.seat_numbers if booking.seat_numbers else [],
                            'total_fare': int(booking.total_fare) if booking.total_fare is not None else 0,
                            'original_fare': int(booking.original_fare) if booking.original_fare is not None else None,
                            'negotiated_fare': int(booking.negotiated_fare) if booking.negotiated_fare is not None else None,
                            'passenger_offer': int(booking.passenger_offer) if booking.passenger_offer is not None else None,
                            'driver_response': booking.driver_response,
                            'negotiation_notes': booking.negotiation_notes,
                            'fare_breakdown': booking.fare_breakdown if booking.fare_breakdown else {},

                            # Ratings and feedback
                            'passenger_rating': float(booking.passenger_rating) if booking.passenger_rating else None,
                            'passenger_feedback': booking.passenger_feedback,

                            # Timestamps
                            'booked_at': booking.booked_at.isoformat() if booking.booked_at else None,
                            'cancelled_at': booking.cancelled_at.isoformat() if booking.cancelled_at else None,
                            'completed_at': booking.completed_at.isoformat() if booking.completed_at else None,
                            'updated_at': booking.updated_at.isoformat() if booking.updated_at else None,
                        }
                    
                    bookings.append(booking_data)
                    logger.debug("Successfully processed booking %s", booking.booking_id)
                    
                except Exception as e:
                    logger.exception("Error processing booking %s: %s", booking.id, str(e))
                    continue
            
            logger.debug("Returning %s bookings to frontend", len(bookings))
            return JsonResponse({'success': True, 'bookings': bookings})
            
        except UsersData.DoesNotExist:
            return JsonResponse({'success': False, 'error': 'User not found'}, status=404)
        except Exception as e:
            logger.exception("Exception in get_user_bookings: %s", str(e))
            return JsonResponse({'success': False, 'error': str(e)}, status=500)
    
    return JsonResponse({'error': 'Invalid request method'}, status=400)



@csrf_exempt
def search_rides(request):
    """Search rides"""
    if request.method == 'GET':
        try:
            from_location = request.GET.get('from')
            to_location = request.GET.get('to')
            date = request.GET.get('date')
            min_seats = request.GET.get('min_seats')
            max_price = request.GET.get('max_price')
            gender_preference = request.GET.get('gender_preference')
            
            trips = Trip.objects.filter(trip_status='SCHEDULED')
            
            # Apply filters
            if from_location:
                trips = trips.filter(route__route_stops__stop_name__icontains=from_location)
            if to_location:
                trips = trips.filter(route__route_stops__stop_name__icontains=to_location)
            if date:
                trips = trips.filter(trip_date=date)
            if min_seats:
                trips = trips.filter(available_seats__gte=int(min_seats))
            if max_price:
                try:
                    trips = trips.filter(base_fare__lte=int(round(float(max_price))))
                except (TypeError, ValueError):
                    pass
            
            rides_data = []
            for trip in trips.distinct():
                rides_data.append({
                    'trip_id': trip.trip_id,
                    'trip_date': trip.trip_date.isoformat(),
                    'departure_time': trip.departure_time.strftime('%H:%M'),
                    'origin': trip.route.first_stop.stop_name if trip.route.first_stop else trip.route.route_name,
                    'destination': trip.route.last_stop.stop_name if trip.route.last_stop else trip.route.route_name,
                    'driver_name': trip.driver.name,
                    'vehicle_model': f"{trip.vehicle.company_name} {trip.vehicle.model_number}" if trip.vehicle else 'Unknown Vehicle',
                    'available_seats': trip.available_seats,
                    'price_per_seat': int(trip.base_fare) if trip.base_fare is not None else 0,
                    'total_seats': trip.total_seats,
                })
            
            return JsonResponse({'success': True, 'rides': rides_data})
        except Exception as e:
            return JsonResponse({'success': False, 'error': str(e)}, status=500)
    
    return JsonResponse({'error': 'Invalid request method'}, status=400)

@csrf_exempt
def cancel_ride(request, ride_id):
    """Cancel a ride"""
    if request.method == 'DELETE':
        try:
            # This is a placeholder - implement actual ride cancellation
            return JsonResponse({'success': True, 'message': 'Ride cancelled successfully'})
        except Exception as e:
            return JsonResponse({'success': False, 'error': str(e)}, status=500)
    
    return JsonResponse({'error': 'Invalid request method'}, status=400)

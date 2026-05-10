"""
Hybrid fare calculator (Python port of Flutter fare_calculator.dart).
Used inside the chatbot to compute stop-to-stop fares with the same logic as the app.
"""

import math
from datetime import datetime
from typing import List, Dict, Any


# Pakistan-specific base rates (PKR per km) - Updated for 2025
_BASE_RATES = {
    "Petrol": 22.00,
    "Diesel": 20.00,
    "CNG": 16.00,
    "Electric": 14.00,
    "Hybrid": 18.00,
}

# Vehicle type multipliers
_VEHICLE_MULTIPLIERS = {
    "Sedan": 1.0,
    "SUV": 1.2,
    "Van": 1.3,
    "Bus": 1.5,
    "Motorcycle": 0.7,
    "Auto Rickshaw": 0.8,
}

# Seat factors for different vehicle types
_SEAT_FACTORS = {
    "Sedan": 1.0,
    "SUV": 1.1,
    "Van": 1.2,
    "Bus": 1.3,
    "Motorcycle": 0.5,
    "Auto Rickshaw": 0.6,
}

# Distance factors (longer trips get better rates)
_DISTANCE_FACTORS = {
    "0-10": 1.0,
    "10-25": 0.95,
    "25-50": 0.90,
    "50-100": 0.85,
    "100+": 0.80,
}

# Minimum fares for different vehicle types (PKR)
_MINIMUM_FARES = {
    "Sedan": 100,
    "SUV": 120,
    "Van": 150,
    "Bus": 200,
    "Motorcycle": 50,
    "Auto Rickshaw": 60,
}

# Fuel efficiency (km per unit)
_FUEL_EFFICIENCY = {
    "Petrol": 12.0,
    "Diesel": 15.0,
    "CNG": 18.0,
    "Electric": 8.0,  # km per kWh
    "Hybrid": 14.0,
}

# Current fuel prices in Pakistan (PKR per unit)
_FUEL_PRICES = {
    "Petrol": 275.0,
    "Diesel": 285.0,
    "CNG": 220.0,
    "Electric": 25.0,
    "Hybrid": 275.0,
}


def _is_peak_hour(dt: datetime) -> bool:
    """Peak hours: 7-9 AM and 5-7 PM."""
    h = dt.hour
    return (7 <= h <= 9) or (17 <= h <= 19)


def _get_distance_category(dist: float) -> str:
    if dist <= 10:
        return "0-10"
    if dist <= 25:
        return "10-25"
    if dist <= 50:
        return "25-50"
    if dist <= 100:
        return "50-100"
    return "100+"


def _calculate_duration(distance_km: float) -> int:
    """Assume average speed of 50 km/h in urban areas."""
    avg_speed_kmh = 50.0
    duration_hours = distance_km / avg_speed_kmh
    return int(round(duration_hours * 60))


def _calculate_stop_price(
    distance_km: float,
    base_rate_per_km: float,
    vehicle_multiplier: float,
    time_multiplier: float,
    seat_factor: float,
    distance_factor: float,
) -> int:
    """Calculate price for a single stop segment."""
    base_price = (
        base_rate_per_km
        * distance_km
        * vehicle_multiplier
        * time_multiplier
        * seat_factor
        * distance_factor
    )
    rounded = int(round(base_price))
    if rounded <= 0 and distance_km > 0:
        return 1
    return rounded


def calculate_fare(
    route_stops: List[Dict[str, Any]],
    fuel_type: str,
    vehicle_type: str,
    departure_time: datetime,
    total_seats: int = 1,
) -> Dict[str, Any]:
    """
    Calculate comprehensive fare with stop-to-stop pricing breakdown.
    Mirrors Flutter FareCalculator.calculateFare.
    """
    from ..tools.trace import trace

    trace(
        'fare_calculator.calculate_fare.enter',
        n_stops=len(route_stops) if isinstance(route_stops, list) else None,
        fuel_type=fuel_type,
        vehicle_type=vehicle_type,
        departure_time=str(departure_time),
        total_seats=total_seats,
    )
    if len(route_stops) < 2:
        raise ValueError('Please provide at least two stops to calculate a fare.')

    # Parameters
    base_rate_per_km = _BASE_RATES.get(fuel_type, _BASE_RATES["Petrol"])
    vehicle_multiplier = _VEHICLE_MULTIPLIERS.get(vehicle_type, _VEHICLE_MULTIPLIERS["Sedan"])
    seat_factor = _SEAT_FACTORS.get(vehicle_type, _SEAT_FACTORS["Sedan"])
    is_peak = _is_peak_hour(departure_time)
    time_multiplier = 1.3 if is_peak else 1.0

    # Build stop breakdown
    stop_breakdown = []
    for i in range(len(route_stops) - 1):
        from_stop = route_stops[i]
        to_stop = route_stops[i + 1]
        distance_km = to_stop.get("distance_from_previous_km", 0.0)
        duration_min = to_stop.get("duration_from_previous_minutes", 0)
        # Use haversine as fallback if distance missing
        if distance_km == 0.0:
            lat1 = from_stop.get("latitude", 0.0)
            lon1 = from_stop.get("longitude", 0.0)
            lat2 = to_stop.get("latitude", 0.0)
            lon2 = to_stop.get("longitude", 0.0)
            R = 6371.0
            dlat = math.radians(lat2 - lat1)
            dlon = math.radians(lon2 - lon1)
            a = (
                math.sin(dlat / 2) ** 2
                + math.cos(math.radians(lat1))
                * math.cos(math.radians(lat2))
                * math.sin(dlon / 2) ** 2
            )
            distance_km = R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
            duration_min = _calculate_duration(distance_km)

        distance_factor = _DISTANCE_FACTORS[_get_distance_category(distance_km)]
        price = _calculate_stop_price(
            distance_km,
            base_rate_per_km,
            vehicle_multiplier,
            time_multiplier,
            seat_factor,
            distance_factor,
        )
        stop_breakdown.append(
            {
                "from_stop": i + 1,
                "to_stop": i + 2,
                "from_stop_name": from_stop.get("stop_name", f"Stop {i + 1}"),
                "to_stop_name": to_stop.get("stop_name", f"Stop {i + 2}"),
                "distance": distance_km,
                "duration": duration_min,
                "price": price,
                "from_coordinates": {"lat": from_stop.get("latitude"), "lng": from_stop.get("longitude")},
                "to_coordinates": {"lat": to_stop.get("latitude"), "lng": to_stop.get("longitude")},
                "price_breakdown": {
                    "base_rate_per_km": base_rate_per_km,
                    "vehicle_multiplier": vehicle_multiplier,
                    "time_multiplier": time_multiplier,
                    "is_peak_hour": is_peak,
                    "seat_factor": seat_factor,
                    "distance_km": distance_km,
                    "duration_minutes": duration_min,
                    "distance_factor": distance_factor,
                },
            }
        )

    # Totals
    total_distance = sum(seg["distance"] for seg in stop_breakdown)
    total_duration = sum(seg["duration"] for seg in stop_breakdown)
    total_price = sum(seg["price"] for seg in stop_breakdown)

    # Apply minimum fare per segment (scaled)
    min_per_segment = _MINIMUM_FARES.get(vehicle_type, _MINIMUM_FARES["Sedan"])
    minimum_total_fare = min_per_segment * len(stop_breakdown)
    final_total_price = int(round(total_price))
    if final_total_price < minimum_total_fare and total_price > 0:
        final_total_price = minimum_total_fare
        # Redistribute to match minimum
        total_int = int(round(total_price))
        running = 0
        for idx, seg in enumerate(stop_breakdown):
            original = seg["price"]
            if idx == len(stop_breakdown) - 1:
                scaled = final_total_price - running
            else:
                scaled = int(round((final_total_price * original) / total_int)) if total_int > 0 else 0
                running += scaled
            seg["price"] = scaled

    # Fuel cost transparency
    fuel_efficiency = _FUEL_EFFICIENCY.get(fuel_type, _FUEL_EFFICIENCY["Petrol"])
    fuel_price = _FUEL_PRICES.get(fuel_type, _FUEL_PRICES["Petrol"])
    fuel_cost = (total_distance / fuel_efficiency) * fuel_price

    out = {
        "total_distance_km": total_distance,
        "total_duration_minutes": int(total_duration),
        "total_price": final_total_price,
        "is_peak_hour": is_peak,
        "vehicle_type": vehicle_type,
        "fuel_type": fuel_type,
        "base_rate_per_km": base_rate_per_km,
        "stop_breakdown": stop_breakdown,
        "calculation_breakdown": {
            "fuel_efficiency_km_per_unit": fuel_efficiency,
            "fuel_price_per_unit": fuel_price,
            "fuel_cost": fuel_cost,
            "vehicle_type": vehicle_type,
            "fuel_type": fuel_type,
            "total_seats": total_seats,
            "bulk_discount_percentage": 0.0,
            "bulk_discount_amount": 0.0,
            "is_peak_hour": is_peak,
        },
    }

    trace(
        'fare_calculator.calculate_fare.exit',
        total_distance_km=out.get('total_distance_km'),
        total_duration_minutes=out.get('total_duration_minutes'),
        total_price=out.get('total_price'),
        is_peak_hour=out.get('is_peak_hour'),
    )
    return out


def summarize_fare_for_cli(fare_data: Dict[str, Any]) -> str:
    """Return a CLI-friendly fare summary."""
    total_fare = fare_data.get("total_price", 0)
    distance = fare_data.get("total_distance_km", 0)
    duration = fare_data.get("total_duration_minutes", 0)
    is_peak = fare_data.get("calculation_breakdown", {}).get("is_peak_hour", False)
    peak_note = " (peak hour)" if is_peak else ""
    return (
        f"Estimated fare: PKR {total_fare}{peak_note}\n"
        f"Distance: {distance:.2f} km\n"
        f"Duration: {int(duration)} min"
    )

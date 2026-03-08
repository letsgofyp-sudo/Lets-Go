"""Stop-to-stop fare matrix generator.

This module produces a fare matrix similar to the mobile app's "fare_matrix" concept:
- each consecutive stop pair gets a distance, duration, and fare
- callers can use it to build a full matrix for a route

Note: terminal/CLI should not display image/map URLs; this module only deals with numbers.
"""

from __future__ import annotations

import datetime
from typing import Any, Dict, List

from .fare_calculator import calculate_fare


def build_fare_matrix_for_route_stops(
    route_stops: List[Dict[str, Any]],
    *,
    fuel_type: str = 'Petrol',
    vehicle_type: str = 'Sedan',
    departure_time: datetime.datetime | None = None,
) -> List[Dict[str, Any]]:
    """Generate a fare matrix for consecutive stop pairs.

    Input: route_stops containing latitude/longitude and stop_name.
    Output: list of matrix rows with:
      - from_stop (order)
      - to_stop (order)
      - distance_km
      - duration_minutes
      - fare
    """
    if departure_time is None:
        departure_time = datetime.datetime.now()

    if not isinstance(route_stops, list) or len(route_stops) < 2:
        return []

    matrix: List[Dict[str, Any]] = []

    # Build segment by segment so minimum-fare scaling is per-segment (like matrix pricing)
    for i in range(len(route_stops) - 1):
        a = route_stops[i]
        b = route_stops[i + 1]

        seg_stops = [
            {
                'stop_order': 1,
                'stop_name': a.get('stop_name') or f'Stop {i + 1}',
                'latitude': a.get('latitude'),
                'longitude': a.get('longitude'),
                'distance_from_previous_km': 0.0,
                'duration_from_previous_minutes': 0.0,
            },
            {
                'stop_order': 2,
                'stop_name': b.get('stop_name') or f'Stop {i + 2}',
                'latitude': b.get('latitude'),
                'longitude': b.get('longitude'),
                # Prefer already computed per-segment values if present (from ORS/OSRM distribution)
                'distance_from_previous_km': float(b.get('distance_from_previous_km') or 0.0),
                'duration_from_previous_minutes': float(b.get('duration_from_previous_minutes') or 0.0),
            },
        ]

        fare_data = calculate_fare(
            route_stops=seg_stops,
            fuel_type=fuel_type,
            vehicle_type=vehicle_type,
            departure_time=departure_time,
            total_seats=1,
        )
        breakdown = fare_data.get('stop_breakdown') if isinstance(fare_data, dict) else None
        seg = breakdown[0] if isinstance(breakdown, list) and breakdown else {}

        matrix.append(
            {
                'from_stop': i + 1,
                'to_stop': i + 2,
                'from_stop_name': seg.get('from_stop_name') or seg_stops[0]['stop_name'],
                'to_stop_name': seg.get('to_stop_name') or seg_stops[1]['stop_name'],
                'distance_km': float(seg.get('distance') or seg_stops[1]['distance_from_previous_km'] or 0.0),
                'duration_minutes': int(seg.get('duration') or seg_stops[1]['duration_from_previous_minutes'] or 0),
                'fare': int(seg.get('price') or 0),
            }
        )

    return matrix


def summarize_matrix_for_cli(matrix: List[Dict[str, Any]]) -> str:
    if not matrix:
        return 'No fare matrix available.'
    total_dist = sum(float(r.get('distance_km') or 0.0) for r in matrix)
    total_dur = sum(int(r.get('duration_minutes') or 0) for r in matrix)
    total_fare = sum(int(r.get('fare') or 0) for r in matrix)
    return (
        f"Segments: {len(matrix)}\n"
        f"Distance: {total_dist:.2f} km\n"
        f"Duration: {total_dur} min\n"
        f"Fare (sum of segments): PKR {total_fare}"
    )

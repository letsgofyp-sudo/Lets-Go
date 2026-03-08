"""
OpenStreetMap client for geocoding (Nominatim) and routing (OSRM).
Used inside the chatbot to provide dynamic routing with DB fallback.
"""

import json
import math
import requests
from typing import List, Dict, Any, Optional, Tuple

from .config import ORS_API_KEY

# Default endpoints; can be overridden via env/config if needed
NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"
OSRM_URL = "https://router.project-osrm.org"

# OpenRouteService endpoints (used by the Flutter app)
ORS_GEOCODE_URL = "https://api.openrouteservice.org/geocode/search"
ORS_DIRECTIONS_URL = "https://api.openrouteservice.org/v2/directions/driving-car/geojson"

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate great-circle distance between two points on Earth (km)."""
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2) ** 2 +
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
         math.sin(dlon / 2) ** 2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

def geocode_stop(query: str, country: str = "Pakistan") -> Optional[Dict[str, Any]]:
    """
    Geocode a stop name using Nominatim.
    Returns dict with 'lat', 'lon', 'display_name', or None if not found.
    Includes fallback coordinates for major Pakistani cities.
    """
    # Fallback coordinates for major cities (lat, lon, display_name)
    major_cities = {
        "lahore": (31.5497, 74.3436, "Lahore, Pakistan"),
        "multan": (30.1575, 71.5249, "Multan, Pakistan"),
        "karachi": (24.8607, 67.0011, "Karachi, Pakistan"),
        "islamabad": (33.6844, 73.0479, "Islamabad, Pakistan"),
        "rawalpindi": (33.5651, 73.0169, "Rawalpindi, Pakistan"),
        "faisalabad": (31.4504, 73.1150, "Faisalabad, Pakistan"),
        "vehari": (30.0333, 72.3333, "Vehari, Pakistan"),
        "peoples colony": (30.0500, 72.3500, "Peoples Colony, Vehari"),
    }
    key = query.strip().lower()
    if key in major_cities:
        lat, lon, name = major_cities[key]
        return {"lat": lat, "lon": lon, "display_name": name, "address": {}}

    # Prefer OpenRouteService geocoding when configured.
    # This matches the mobile app integration and tends to work better in the same network.
    if ORS_API_KEY:
        try:
            params = {
                "api_key": ORS_API_KEY,
                "text": query,
                "size": 1,
                "boundary.country": "PK",
            }
            response = requests.get(ORS_GEOCODE_URL, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            feats = data.get("features") if isinstance(data, dict) else None
            if isinstance(feats, list) and feats:
                f0 = feats[0]
                geom = f0.get("geometry") if isinstance(f0, dict) else None
                coords = (geom or {}).get("coordinates") if isinstance(geom, dict) else None
                if isinstance(coords, list) and len(coords) >= 2:
                    lon, lat = float(coords[0]), float(coords[1])
                    props = f0.get("properties") if isinstance(f0, dict) else {}
                    label = (props or {}).get("label") or (props or {}).get("name") or ""
                    return {"lat": lat, "lon": lon, "display_name": str(label), "address": (props or {}).get("locality") or {}}
        except Exception:
            pass
    try:
        params = {
            "q": f"{query}, {country}",
            "format": "json",
            "addressdetails": 1,
            "limit": 1,
        }
        response = requests.get(NOMINATIM_URL, params=params, timeout=8)
        response.raise_for_status()
        data = response.json()
        if not data:
            return None
        result = data[0]
        return {
            "lat": float(result["lat"]),
            "lon": float(result["lon"]),
            "display_name": result.get("display_name", ""),
            "address": result.get("address", {}),
        }
    except Exception as e:
        # In production, you might log this error
        return None

def osrm_route(
    coordinates: List[Tuple[float, float]],
    overview: str = "simplified"
) -> Optional[Dict[str, Any]]:
    """
    Get OSRM route between a list of (lat, lon) coordinates.
    Returns dict with distance (km), duration (seconds), geometry, or None.
    """
    if len(coordinates) < 2:
        return None
    try:
        # Build coordinate string for OSRM
        coord_str = ";".join(f"{lon},{lat}" for lat, lon in coordinates)
        url = f"{OSRM_URL}/route/v1/driving/{coord_str}"
        params = {
            "overview": overview,
            "alternatives": "false",
            "steps": "false",
        }
        response = requests.get(url, params=params, timeout=8)
        response.raise_for_status()
        data = response.json()
        if data.get("code") != "Ok" or not data.get("routes"):
            return None
        route = data["routes"][0]
        return {
            "distance_km": route["distance"] / 1000.0,
            "duration_seconds": route["duration"],
            "geometry": route.get("geometry"),
        }
    except Exception as e:
        return None


def ors_directions(coordinates: List[Tuple[float, float]]) -> Optional[Dict[str, Any]]:
    """Route using OpenRouteService directions (distance/duration + geometry)."""
    if not ORS_API_KEY:
        return None
    if len(coordinates) < 2:
        return None
    try:
        coords = [[lon, lat] for (lat, lon) in coordinates]
        response = requests.post(
            ORS_DIRECTIONS_URL,
            headers={
                "Authorization": ORS_API_KEY,
                "Content-Type": "application/json",
            },
            data=json.dumps({"coordinates": coords}),
            timeout=15,
        )
        response.raise_for_status()
        data = response.json()
        feats = data.get("features") if isinstance(data, dict) else None
        if not isinstance(feats, list) or not feats:
            return None
        f0 = feats[0]
        props = f0.get("properties") if isinstance(f0, dict) else {}
        summary = (props or {}).get("summary") if isinstance(props, dict) else None
        dist_m = (summary or {}).get("distance") if isinstance(summary, dict) else None
        dur_s = (summary or {}).get("duration") if isinstance(summary, dict) else None
        geom = f0.get("geometry") if isinstance(f0, dict) else None
        return {
            "distance_km": (float(dist_m) / 1000.0) if dist_m is not None else None,
            "duration_seconds": float(dur_s) if dur_s is not None else None,
            "geometry": geom,
        }
    except Exception:
        return None

def build_route_stops(stop_names: List[str]) -> List[Dict[str, Any]]:
    """
    Convert a list of stop names to route_stops with coordinates using OSM.
    Falls back to haversine distances if OSRM fails.
    Returns list of dicts: {stop_name, latitude, longitude, distance_from_previous_km, duration_from_previous_minutes}
    """
    route_stops = []
    coords = []
    for i, name in enumerate(stop_names):
        geo = geocode_stop(name)
        if not geo:
            # If geocoding fails, we cannot build a proper route; abort or skip
            raise ValueError(f"Could not geocode stop: {name}")
        stop = {
            "stop_order": i + 1,
            "stop_name": name,
            "latitude": geo["lat"],
            "longitude": geo["lon"],
            "display_name": geo["display_name"],
        }
        route_stops.append(stop)
        coords.append((geo["lat"], geo["lon"]))

    # Prefer ORS directions when available, fallback to OSRM, then haversine.
    route = ors_directions(coords) or osrm_route(coords)
    if route and route.get("distance_km") and route.get("duration_seconds") is not None:
        # Use OSRM distances/durations; we don't have per-segment breakdown without `steps=true`
        # For simplicity, distribute total distance proportionally to haversine per segment
        total_osrm_dist = float(route["distance_km"])
        total_osrm_dur = float(route["duration_seconds"]) / 60.0  # minutes
        # Compute haversine per segment for proportion
        haversine_distances = []
        for i in range(len(coords) - 1):
            d = haversine_distance(coords[i][0], coords[i][1], coords[i+1][0], coords[i+1][1])
            haversine_distances.append(d)
        sum_hav = sum(haversine_distances)
        for i, stop in enumerate(route_stops):
            if i == 0:
                stop["distance_from_previous_km"] = 0.0
                stop["duration_from_previous_minutes"] = 0.0
            else:
                segment_hav = haversine_distances[i-1]
                proportion = segment_hav / sum_hav if sum_hav > 0 else 0
                stop["distance_from_previous_km"] = total_osrm_dist * proportion
                stop["duration_from_previous_minutes"] = total_osrm_dur * proportion
    else:
        # Fallback: use haversine for both distance and duration (assume 50 km/h average)
        for i, stop in enumerate(route_stops):
            if i == 0:
                stop["distance_from_previous_km"] = 0.0
                stop["duration_from_previous_minutes"] = 0.0
            else:
                dist = haversine_distance(coords[i-1][0], coords[i-1][1], coords[i][0], coords[i][1])
                stop["distance_from_previous_km"] = dist
                stop["duration_from_previous_minutes"] = (dist / 50.0) * 60.0  # minutes
    return route_stops

def summarize_route_for_cli(route_stops: List[Dict[str, Any]]) -> str:
    """Return a CLI-friendly summary of a route."""
    if not route_stops:
        return "No route found."
    total_km = sum(s["distance_from_previous_km"] for s in route_stops)
    total_min = sum(s["duration_from_previous_minutes"] for s in route_stops)
    names = [s["stop_name"] for s in route_stops]
    return (
        f"Route: {' → '.join(names)}\n"
        f"Distance: {total_km:.2f} km\n"
        f"Estimated time: {int(total_min)} min"
    )

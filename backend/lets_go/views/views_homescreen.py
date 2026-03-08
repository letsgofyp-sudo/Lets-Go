
from django.views.decorators.csrf import csrf_exempt
from django.http import JsonResponse
from django.db.models import Prefetch, Q
from django.utils import timezone
from datetime import datetime
import logging
import os
import json
import uuid
import urllib.request
import urllib.error
import math
import re
import difflib
from decimal import Decimal

from ..models import Trip, RouteStop, TripStopBreakdown, Booking, BlockedUser, UsersData
from ..models.models_history import BookingHistorySnapshot
from ..models.models_trip import TripVehicleHistory


logger = logging.getLogger(__name__)


def _json_safe(value):
    if value is None:
        return None
    if isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, Decimal):
        try:
            return float(value)
        except Exception:
            return str(value)
    if isinstance(value, datetime):
        try:
            return value.isoformat()
        except Exception:
            return str(value)
    if isinstance(value, (list, tuple)):
        return [_json_safe(v) for v in value]
    if isinstance(value, dict):
        return {str(k): _json_safe(v) for k, v in value.items()}
    return str(value)


def _to_int(value):
    try:
        return int(value)
    except Exception:
        return None


def _ml_debug_enabled() -> bool:
    return str(os.getenv('HF_ML_DEBUG') or '').strip() in ('1', 'true', 'True', 'yes', 'YES')


def _ml_debug_requested(request) -> bool:
    try:
        return (request is not None) and (str(request.GET.get('ml_debug') or '').strip() == '1')
    except Exception:
        return False


def _to_float(value):
    try:
        return float(value)
    except Exception:
        return None


def _normalize_text(value: str) -> str:
    v = (value or '').strip().lower()
    v = re.sub(r'[^a-z0-9\s]+', ' ', v)
    v = re.sub(r'\s+', ' ', v).strip()
    return v


def _haversine_meters(lat1, lon1, lat2, lon2):
    r = 6371000.0
    p1 = math.radians(lat1)
    p2 = math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * (math.sin(dl / 2) ** 2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return r * c


def _normalize_gender_for_trip(gender_value: str | None) -> str | None:
    if not gender_value:
        return None
    g = str(gender_value).strip().lower()
    if g == 'male':
        return 'Male'
    if g == 'female':
        return 'Female'
    if g in ('any', 'other', 'unknown'):
        return 'Any'
    return None


def _post_json(url: str, payload: dict, headers: dict | None = None, timeout_seconds: float = 4.0) -> dict | None:
    try:
        body = json.dumps(payload).encode('utf-8')
        req = urllib.request.Request(url, data=body, method='POST')
        req.add_header('Content-Type', 'application/json')
        req.add_header('Accept', 'application/json')
        if headers:
            for k, v in headers.items():
                if v is None:
                    continue
                req.add_header(k, v)

        with urllib.request.urlopen(req, timeout=timeout_seconds) as resp:
            raw = resp.read().decode('utf-8')
            if not raw:
                return None
            decoded = json.loads(raw)
            if isinstance(decoded, dict):
                return decoded
            return None
    except Exception:
        return None


def _get_text(url: str, headers: dict | None = None, timeout_seconds: float = 30.0) -> str | None:
    try:
        req = urllib.request.Request(url, method='GET')
        req.add_header('Accept', 'text/event-stream')
        req.add_header('Cache-Control', 'no-cache')

        if headers:
            for k, v in headers.items():
                if v is None:
                    continue
                req.add_header(k, v)

        with urllib.request.urlopen(req, timeout=timeout_seconds) as resp:
            chunks = []
            for line in resp:
                decoded = line.decode("utf-8").strip()
                if decoded:
                    chunks.append(decoded)

                # Stop once Gradio signals completion
                if (
                    "process_completed" in decoded
                    or decoded.startswith("event: complete")
                    or decoded.startswith("event: error")
                ):
                    break

            return "\n".join(chunks) if chunks else None

    except Exception as e:
        if _ml_debug_enabled():
            logger.exception("[ml_ranker] SSE error: %s", str(e))
        return None


def _parse_gradio_sse_final_data(sse_text: str | None):
    try:
        if not sse_text:
            return None

        last_data = None
        for raw in str(sse_text).splitlines():
            line = raw.strip()
            if not line:
                continue

            # Typical format: "event: complete" and "data: [...]"
            if line.startswith('data:'):
                last_data = line.split(':', 1)[1].strip()

        if not last_data:
            return None

        return json.loads(last_data)
    except Exception:
        return None


_HF_CLIENT = None


def _get_hf_client():
    global _HF_CLIENT
    if _HF_CLIENT is not None:
        return _HF_CLIENT
    space = (os.getenv('HF_GRADIO_CLIENT_SPACE') or '').strip()
    if not space:
        return None
    try:
        from gradio_client import Client
    except Exception:
        return None

    _HF_CLIENT = Client(space)
    return _HF_CLIENT


def _gradio_call_predict(payload: dict):
    try:
        client = _get_hf_client()
        if client is None:
            return None
        result = client.predict(
            payload,
            api_name="/predict"
        )
        return result

    except Exception as e:
        logger.exception("[ml_ranker] GRADIO CLIENT ERROR: %s", str(e))
        return None


def _http_call_predict(url: str, payload: dict, timeout_seconds: float = 6.0) -> dict | list | str | None:
    try:
        cleaned_url = (url or '').strip().rstrip('/')

        # Preferred Gradio HTTP API (works on HF Spaces):
        # POST {base}/call/{api_name} -> {"event_id": "..."}
        # GET  {base}/call/{api_name}/{event_id} -> SSE stream with final "data: [...]"
        if '/call/' in cleaned_url:
            decoded = _post_json(url=cleaned_url, payload={'data': [payload]}, headers=None, timeout_seconds=timeout_seconds)
            if not isinstance(decoded, dict):
                return decoded

            event_id = (decoded.get('event_id') or '').strip()
            if not event_id:
                return decoded

            sse_url = f"{cleaned_url}/{event_id}"
            sse_text = _get_text(url=sse_url, headers=None, timeout_seconds=max(10.0, float(timeout_seconds)))
            parsed = _parse_gradio_sse_final_data(sse_text)
            return parsed if parsed is not None else sse_text

        # Legacy /gradio_api/run/* endpoints often require queue join and can reject direct HTTP.
        # Keep wrapping to preserve backward compatibility, but expect some Spaces to block it.
        final_payload = payload
        if '/gradio_api/run/' in cleaned_url:
            final_payload = {'data': [payload]}

        return _post_json(url=cleaned_url, payload=final_payload, headers=None, timeout_seconds=timeout_seconds)
    except Exception as e:
        logger.exception("[ml_ranker] HTTP CLIENT ERROR: %s", str(e))
        return None

def _load_recent_booking_signals(user_id: int, limit: int = 30) -> list[dict]:
    if user_id <= 0:
        return []

    try:
        user = UsersData.objects.only('id').get(id=user_id)
    except Exception:
        return []

    live_qs = (
        Booking.objects.filter(
            passenger=user,
            ride_status='DROPPED_OFF',
            payment_status='COMPLETED',
        )
        .select_related('trip', 'from_stop', 'to_stop', 'trip__vehicle')
        .only(
            'id', 'trip__trip_id', 'total_fare', 'number_of_seats',
            'from_stop__stop_name', 'to_stop__stop_name',
            'dropoff_at', 'completed_at', 'updated_at',
            'trip__vehicle__company_name', 'trip__vehicle__vehicle_type', 'trip__vehicle__color',
            'trip__vehicle__seats', 'trip__vehicle__fuel_type',
        )
    )

    snaps_qs = (
        BookingHistorySnapshot.objects.filter(
            passenger=user,
            ride_status='DROPPED_OFF',
            payment_status='COMPLETED',
        )
        .only(
            'trip_id', 'from_stop_name', 'to_stop_name',
            'total_fare', 'number_of_seats', 'finalized_at',
        )
    )

    merged: list[tuple[datetime | None, dict]] = []

    live_list = list(live_qs.order_by('-updated_at')[:limit])
    live_trip_ids = [getattr(b, 'trip_id', None) for b in live_list if getattr(b, 'trip_id', None)]
    tvh_map: dict[int, TripVehicleHistory] = {}
    if live_trip_ids:
        try:
            for h in (
                TripVehicleHistory.objects.filter(trip_id__in=live_trip_ids)
                .only('trip_id', 'vehicle_make', 'vehicle_type', 'vehicle_color', 'vehicle_capacity', 'fuel_type')
            ):
                tid = getattr(h, 'trip_id', None)
                if tid:
                    tvh_map[int(tid)] = h
        except Exception:
            tvh_map = {}

    for b in live_list:
        fin = getattr(b, 'dropoff_at', None) or getattr(b, 'completed_at', None) or getattr(b, 'updated_at', None)

        vehicle_company = None
        vehicle_type = None
        vehicle_color = None
        vehicle_seats = None
        vehicle_fuel_type = None

        try:
            hist = tvh_map.get(int(getattr(b, 'trip_id', 0) or 0))
            if hist is not None:
                vehicle_company = getattr(hist, 'vehicle_make', None)
                vehicle_type = getattr(hist, 'vehicle_type', None)
                vehicle_color = getattr(hist, 'vehicle_color', None)
                vehicle_seats = getattr(hist, 'vehicle_capacity', None)
                vehicle_fuel_type = getattr(hist, 'fuel_type', None)
        except Exception:
            pass

        if not any([vehicle_company, vehicle_type, vehicle_color, vehicle_seats, vehicle_fuel_type]):
            try:
                v = getattr(getattr(b, 'trip', None), 'vehicle', None)
                if v is not None:
                    vehicle_company = getattr(v, 'company_name', None)
                    vehicle_type = getattr(v, 'vehicle_type', None)
                    vehicle_color = getattr(v, 'color', None)
                    vehicle_seats = getattr(v, 'seats', None)
                    vehicle_fuel_type = getattr(v, 'fuel_type', None)
            except Exception:
                pass

        merged.append((fin, {
            'trip_id': getattr(getattr(b, 'trip', None), 'trip_id', None),
            'from_stop_name': getattr(getattr(b, 'from_stop', None), 'stop_name', None),
            'to_stop_name': getattr(getattr(b, 'to_stop', None), 'stop_name', None),
            'total_fare': int(getattr(b, 'total_fare', 0) or 0),
            'number_of_seats': int(getattr(b, 'number_of_seats', 0) or 0),
            'finalized_at': fin.isoformat() if fin else None,
            'vehicle_company': vehicle_company,
            'vehicle_type': vehicle_type,
            'vehicle_color': vehicle_color,
            'vehicle_seats': int(vehicle_seats) if vehicle_seats is not None else None,
            'vehicle_fuel_type': vehicle_fuel_type,
        }))

    for s in list(snaps_qs.order_by('-finalized_at')[:limit]):
        fin = getattr(s, 'finalized_at', None)

        vehicle_company = None
        vehicle_type = None
        vehicle_color = None
        vehicle_seats = None
        vehicle_fuel_type = None

        try:
            trip_obj = getattr(s, 'trip_obj', None)
            v = getattr(trip_obj, 'vehicle', None) if trip_obj is not None else None
            if v is not None:
                vehicle_company = getattr(v, 'company_name', None)
                vehicle_type = getattr(v, 'vehicle_type', None)
                vehicle_color = getattr(v, 'color', None)
                vehicle_seats = getattr(v, 'seats', None)
                vehicle_fuel_type = getattr(v, 'fuel_type', None)
        except Exception:
            pass

        merged.append((fin, {
            'trip_id': getattr(s, 'trip_id', None),
            'from_stop_name': getattr(s, 'from_stop_name', None),
            'to_stop_name': getattr(s, 'to_stop_name', None),
            'total_fare': int(getattr(s, 'total_fare', 0) or 0),
            'number_of_seats': int(getattr(s, 'number_of_seats', 0) or 0),
            'finalized_at': fin.isoformat() if fin else None,
            'vehicle_company': vehicle_company,
            'vehicle_type': vehicle_type,
            'vehicle_color': vehicle_color,
            'vehicle_seats': int(vehicle_seats) if vehicle_seats is not None else None,
            'vehicle_fuel_type': vehicle_fuel_type,
        }))

    merged.sort(key=lambda x: x[0] or timezone.datetime.min.replace(tzinfo=timezone.get_current_timezone()), reverse=True)
    out = []
    seen = set()
    for _fin, item in merged:
        key = (item.get('trip_id'), item.get('finalized_at'))
        if key in seen:
            continue
        seen.add(key)
        out.append(item)
        if len(out) >= limit:
            break
    return out


# def _clean_bearer_token(raw: str | None) -> str:
#     s = (raw or '').strip()
#     if not s:
#         return ''
#     if s.lower().startswith('bearer '):
#         s = s.split(' ', 1)[1].strip()
#     if 'hf_token' in s.lower() and '=' in s:
#         # Accept pasted formats like: "hf_token = <TOKEN>".
#         s = s.split('=', 1)[1].strip()
#     return s


def _extract_ranked_list(value) -> list | None:
    # logger.debug("\n================ EXTRACT RANKED START ================\n")
    # logger.debug("[extract_ranked] INPUT TYPE: %s", type(value))
    # logger.debug("[extract_ranked] INPUT PREVIEW: %s", str(value)[:4000])

    if isinstance(value, list):
        if not value:
            return None

        first = value[0]
        # logger.debug("[extract_ranked] First element type: %s", type(first))

        # Direct ranked list
        if isinstance(first, dict) and ('trip_id' in first) and ('score' in first):
            # logger.debug("[extract_ranked] Direct ranked list detected")
            return value

        # Gradio shape: data=[{ranked:[...]}]
        if isinstance(first, dict) and isinstance(first.get('ranked'), list):
            # logger.debug("[extract_ranked] Found ranked inside dict")
            return first.get('ranked')

        # Nested list
        if isinstance(first, list):
            # logger.debug("[extract_ranked] Nested list detected")
            return _extract_ranked_list(first)

        # JSON string inside list
        if isinstance(first, str):
            # logger.debug("[extract_ranked] JSON string detected inside list")
            try:
                decoded = json.loads(first)
                return _extract_ranked_list(decoded)
            except Exception as e:
                logger.exception("[extract_ranked] Failed to decode JSON string: %s", str(e))
                return None

        # logger.debug("[extract_ranked] Unknown list shape")
        return None

    if isinstance(value, dict):
        # logger.debug("[extract_ranked] Dict keys: %s", list(value.keys()))

        if isinstance(value.get('ranked'), list):
            # logger.debug("[extract_ranked] Found ranked directly in dict")
            return value.get('ranked')

        if isinstance(value.get('data'), list) and value.get('data'):
            # logger.debug("[extract_ranked] Found data list in dict")
            return _extract_ranked_list(value.get('data'))

        # logger.debug("[extract_ranked] Dict but no ranked/data structure matched")
        return None

    if isinstance(value, str):
        # logger.debug("[extract_ranked] String detected, attempting json.loads")
        try:
            decoded = json.loads(value)
            return _extract_ranked_list(decoded)
        except Exception as e:
            logger.exception("[extract_ranked] Failed to decode string: %s", str(e))
            return None

    # logger.debug("[extract_ranked] Unsupported type")
    return None


def _rank_trips_with_ml(request, trips: list[dict], user_id: int | None) -> tuple[list[dict], dict]:
    # logger.debug("\n\n================ ML RANKING START ================\n")

    meta: dict = {
        'ranked': False,
        'ranked_by': None,
        'ml_attempted': False,
        'ml_error': None,
        'ml_provider': None,
    }

    debug_mode = False

    def _fallback_rank(_trips: list[dict]) -> tuple[list[dict], dict]:
        # logger.debug("\n[ml_ranker] USING FALLBACK RANKING (driver_rating)\n")

        def _fallback_key(t: dict):
            try:
                drf = float(t.get('driver_rating') or 0)
            except Exception:
                drf = 0.0

            try:
                dep = datetime.fromisoformat(str(t.get('departure_time')))
            except Exception:
                dep = datetime.max

            return (-drf, dep)

        trips_sorted = sorted(_trips, key=_fallback_key)
        return trips_sorted, {
            'ranked': True,
            'ranked_by': 'driver_rating',
            'ml_attempted': meta.get('ml_attempted', False),
            'ml_error': meta.get('ml_error'),
        }

    if not trips:
        # logger.debug("[ml_ranker] No trips provided")
        return trips, meta

    uid = int(user_id or 0)
    # logger.debug("[ml_ranker] USER ID: %s", uid)
    # logger.debug("[ml_ranker] TOTAL CANDIDATES: %s", len(trips))
    # logger.debug("[ml_ranker] SAMPLE TRIP: %s", trips[0])

    if uid <= 0:
        # logger.debug("[ml_ranker] Invalid user_id, fallback")
        return _fallback_rank(trips)

    try:
        # USER DATA
        try:
            u = UsersData.objects.only('id', 'gender', 'passenger_rating').get(id=uid)
            user_payload = {
                'user_id': uid,
                'gender': _normalize_gender_for_trip(getattr(u, 'gender', None)),
                'passenger_rating': float(getattr(u, 'passenger_rating', 0) or 0),
            }
        except Exception:
            user_payload = {'user_id': uid}

        history = _load_recent_booking_signals(uid, limit=30)

        hf_url = (os.getenv('HF_ML_RANKER_URL') or '').strip()
        gradio_space = (os.getenv('HF_GRADIO_CLIENT_SPACE') or '').strip()
        # hf_token = _clean_bearer_token(os.getenv('HF_ML_RANKER_TOKEN') or 'Auth_Token_Here_112233')

        # logger.debug("[ml_ranker] HF URL: %s", hf_url)

        if not hf_url and not gradio_space:
            meta['ml_error'] = 'ml_not_configured'
            return _fallback_rank(trips)

        # headers = {}
        # if hf_token:
        #     headers['Authorization'] = f'Bearer {hf_token}'

        payload = {
            'request_id': str(uuid.uuid4()),
            'user': user_payload,
            'history': {'bookings': history},
            'candidates': trips,
            'context': {
                'now': timezone.now().isoformat(),
                'limit': len(trips),
            },
        }

        payload = _json_safe(payload)

        # logger.debug("[ml_ranker] FINAL PAYLOAD: %s", json.dumps(payload, indent=2)[:5000])

        meta['ml_attempted'] = True

        # ✅ CORRECT GRADIO FLOW (POST + GET SSE INSIDE)
        # logger.debug("[ml_ranker] SENDING TO HF (gradio_call_predict)...")

        g_res = None

        if gradio_space:
            meta['ml_provider'] = 'gradio_client'
            g_res = _gradio_call_predict(payload=payload)
            if g_res is None and hf_url:
                meta['ml_provider'] = 'http'
                g_res = _http_call_predict(url=hf_url, payload=payload)
        elif hf_url:
            meta['ml_provider'] = 'http'
            g_res = _http_call_predict(url=hf_url, payload=payload)

        # logger.debug("[ml_ranker] RAW HF RESPONSE TYPE: %s", type(g_res))
        # logger.debug("[ml_ranker] RAW HF RESPONSE: %s", str(g_res)[:5000])

        ranked = _extract_ranked_list(g_res)

        # logger.debug("[ml_ranker] EXTRACTED RANKED TYPE: %s", type(ranked))
        # logger.debug("[ml_ranker] EXTRACTED RANKED: %s", str(ranked)[:5000])

        if not isinstance(ranked, list):
            meta['ml_error'] = 'invalid_ranked_payload'
            return _fallback_rank(trips)

        score_map = {}

        for item in ranked:
            tid = ''
            score_raw = None

            if isinstance(item, dict):
                tid = str(item.get('trip_id') or item.get('id') or '').strip()
                score_raw = item.get('score')
            elif isinstance(item, (list, tuple)) and len(item) >= 2:
                tid = str(item[0] or '').strip()
                score_raw = item[1]

            if not tid:
                continue

            try:
                score_map[tid] = float(score_raw or 0.0)
            except Exception:
                score_map[tid] = 0.0

        # logger.debug("[ml_ranker] SCORE MAP: %s", score_map)

        for t in trips:
            tid = str(t.get('trip_id') or '').strip()
            if tid in score_map:
                t['recommendation_score'] = score_map[tid]

        trips_sorted = sorted(
            trips,
            key=lambda x: float(x.get('recommendation_score') or 0.0),
            reverse=True,
        )

        # logger.debug("\n================ ML RANKING SUCCESS ================\n")

        return trips_sorted, {
            'ranked': True,
            'ranked_by': 'ml',
            'ml_attempted': True,
            'ml_error': None,
        }

    except Exception as e:
        logger.exception("[ml_ranker] EXCEPTION: %s", str(e))
        meta['ml_error'] = str(e)
        return _fallback_rank(trips)

def _absolute_url(request, value):
    try:
        if value is None:
            return None
        if hasattr(value, 'url'):
            value = value.url
        s = str(value).strip()
        if not s:
            return None
        if s.startswith('http://') or s.startswith('https://'):
            return s
        return request.build_absolute_uri(s)
    except Exception:
        return None


def _vehicle_front_photo_url(request, vehicle):
    try:
        if vehicle is None:
            return None
        raw = getattr(vehicle, 'photo_front_url', None)
        if raw in (None, ''):
            raw = getattr(vehicle, 'photo_front', None)
        return _absolute_url(request, raw)
    except Exception:
        return None


def _fuzzy_score(query_norm: str, candidate_norm: str) -> float:
    if not query_norm:
        return 0.0
    if not candidate_norm:
        return 0.0
    if candidate_norm == query_norm:
        return 1.0
    if query_norm in candidate_norm:
        return 0.95
    return difflib.SequenceMatcher(None, query_norm, candidate_norm).ratio()


def _stop_order_matches(
    stops,
    q_from: str,
    q_to: str,
    from_stop_id: int | None = None,
    to_stop_id: int | None = None,
) -> bool:
    if (not q_from and not from_stop_id) or (not q_to and not to_stop_id):
        return True

    qf = (q_from or '').strip().lower()
    qt = (q_to or '').strip().lower()

    from_orders = []
    to_orders = []
    for s in stops:
        sid = getattr(s, 'id', None)
        sorder = getattr(s, 'stop_order', None)
        name = (getattr(s, 'stop_name', None) or '').lower()

        if from_stop_id and sid == from_stop_id:
            from_orders.append(sorder)
        elif qf and qf in name:
            from_orders.append(sorder)

        if to_stop_id and sid == to_stop_id:
            to_orders.append(sorder)
        elif qt and qt in name:
            to_orders.append(sorder)

    from_orders = [o for o in from_orders if isinstance(o, int)]
    to_orders = [o for o in to_orders if isinstance(o, int)]
    if not from_orders or not to_orders:
        return False

    for fo in from_orders:
        for to in to_orders:
            if fo < to:
                return True
    return False


@csrf_exempt
def suggest_stops(request):
    if request.method != 'GET':
        return JsonResponse({'error': 'Invalid request method'}, status=400)

    try:
        q = (request.GET.get('q') or '').strip()
        q_norm = _normalize_text(q)
        lat = _to_float(request.GET.get('lat'))
        lng = _to_float(request.GET.get('lng'))

        radius_km = _to_float(request.GET.get('radius_km'))
        if radius_km is None or radius_km <= 0 or radius_km > 200:
            radius_km = 10.0

        limit = _to_int(request.GET.get('limit'))
        if limit is None or limit <= 0 or limit > 50:
            limit = 12

        qs = RouteStop.objects.filter(is_active=True, route__is_active=True)

        if lat is not None and lng is not None:
            lat_delta = radius_km / 111.0
            cos_lat = math.cos(math.radians(lat))
            if cos_lat < 0.000001:
                cos_lat = 0.000001
            lng_delta = radius_km / (111.0 * cos_lat)

            qs = qs.exclude(latitude__isnull=True).exclude(longitude__isnull=True)
            qs = qs.filter(
                latitude__gte=lat - lat_delta,
                latitude__lte=lat + lat_delta,
                longitude__gte=lng - lng_delta,
                longitude__lte=lng + lng_delta,
            )

        qs = qs.select_related('route').only(
            'id',
            'stop_name',
            'stop_order',
            'latitude',
            'longitude',
            'route__route_id',
            'route__route_name',
        )

        candidates = []
        for s in qs[:2000]:
            s_lat = float(s.latitude) if s.latitude is not None else None
            s_lng = float(s.longitude) if s.longitude is not None else None

            dist_m = None
            if lat is not None and lng is not None and s_lat is not None and s_lng is not None:
                dist_m = _haversine_meters(lat, lng, s_lat, s_lng)

            name_norm = _normalize_text(s.stop_name)
            score = _fuzzy_score(q_norm, name_norm) if q_norm else 0.0

            if q_norm and score < 0.45:
                continue

            candidates.append({
                'id': s.id,
                'stop_name': s.stop_name,
                'stop_order': s.stop_order,
                'route_id': getattr(s.route, 'route_id', None),
                'route_name': getattr(s.route, 'route_name', None),
                'latitude': s_lat,
                'longitude': s_lng,
                'distance_m': dist_m,
                'score': score,
            })

        if q_norm and (lat is not None and lng is not None):
            candidates.sort(key=lambda x: (-x['score'], x['distance_m'] if x['distance_m'] is not None else 10**18))
        elif q_norm:
            candidates.sort(key=lambda x: -x['score'])
        elif lat is not None and lng is not None:
            candidates.sort(key=lambda x: x['distance_m'] if x['distance_m'] is not None else 10**18)
        else:
            candidates.sort(key=lambda x: _normalize_text(x['stop_name']))

        return JsonResponse({'success': True, 'stops': candidates[:limit]})
    except Exception as e:
        return JsonResponse({'success': False, 'error': str(e)}, status=500)


@csrf_exempt
def all_trips(request):
    if request.method == 'GET':
        try:
            user_id = _to_int(request.GET.get('user_id'))

            try:
                limit = int(request.GET.get('limit', 50))
                limit = max(1, min(limit, 200))
            except Exception:
                limit = 50
            try:
                offset = int(request.GET.get('offset', 0))
                offset = max(0, offset)
            except Exception:
                offset = 0

            stop_breakdowns_prefetch = Prefetch(
                'stop_breakdowns',
                queryset=TripStopBreakdown.objects.only(
                    'trip_id', 'from_stop_order', 'to_stop_order', 'from_stop_name', 'to_stop_name',
                    'distance_km', 'duration_minutes', 'price',
                    'from_latitude', 'from_longitude', 'to_latitude', 'to_longitude', 'price_breakdown'
                ).order_by('from_stop_order')
            )

            route_stops_prefetch = Prefetch(
                'route__route_stops',
                queryset=RouteStop.objects.only('route_id', 'stop_order', 'stop_name').order_by('stop_order')
            )

            now = timezone.now()
            today = now.date()
            now_time = now.time()

            trips_qs = (
                Trip.objects.filter(
                    trip_status='SCHEDULED',
                    available_seats__gt=0,
                    started_at__isnull=True,
                )
                .filter(Q(trip_date__gt=today) | Q(trip_date=today, departure_time__gt=now_time))
                .select_related('route', 'driver', 'vehicle')
                .only(
                    'trip_id', 'trip_date', 'departure_time', 'estimated_arrival_time', 'available_seats',
                    'base_fare', 'gender_preference', 'total_seats', 'notes', 'is_negotiable',
                    'total_distance_km', 'total_duration_minutes', 'fare_calculation',
                    'route__route_name',
                    'driver__id', 'driver__name', 'driver__profile_photo_url', 'driver__driver_rating',
                    'vehicle__company_name', 'vehicle__model_number', 'vehicle__photo_front_url',
                    'vehicle__vehicle_type', 'vehicle__color', 'vehicle__seats', 'vehicle__fuel_type'
                )
                .prefetch_related(stop_breakdowns_prefetch, route_stops_prefetch)
                .order_by('-trip_date', '-departure_time')
            )

            if user_id:
                trips_qs = trips_qs.exclude(driver_id=user_id)

                blocked_driver_ids = BlockedUser.objects.filter(blocker_id=user_id).values_list('blocked_user_id', flat=True)
                blocked_by_driver_ids = BlockedUser.objects.filter(blocked_user_id=user_id).values_list('blocker_id', flat=True)
                trips_qs = trips_qs.exclude(driver_id__in=blocked_driver_ids).exclude(driver_id__in=blocked_by_driver_ids)

                trips_qs = trips_qs.exclude(
                    trip_bookings__passenger_id=user_id,
                    trip_bookings__booking_status__in=['PENDING', 'CONFIRMED', 'COMPLETED'],
                ).exclude(
                    trip_bookings__passenger_id=user_id,
                    trip_bookings__blocked=True,
                )

            trips_qs = trips_qs.distinct()

            trips_qs = trips_qs[offset:offset + limit]

            trip_list = []
            for trip in trips_qs:
                route = trip.route
                driver = trip.driver
                vehicle = trip.vehicle

                origin_name = getattr(route, 'route_name', None) or 'Unknown'
                destination_name = getattr(route, 'route_name', None) or 'Unknown'
                try:
                    stops = list(route.route_stops.all()) if route else []
                    if stops:
                        origin_name = stops[0].stop_name or origin_name
                        destination_name = stops[-1].stop_name or destination_name
                except Exception:
                    pass

                breakdown_list = []
                for breakdown in trip.stop_breakdowns.all():
                    breakdown_list.append({
                        'from_stop_order': breakdown.from_stop_order,
                        'to_stop_order': breakdown.to_stop_order,
                        'from_stop_name': breakdown.from_stop_name,
                        'to_stop_name': breakdown.to_stop_name,
                        'distance_km': float(breakdown.distance_km) if breakdown.distance_km is not None else None,
                        'duration_minutes': breakdown.duration_minutes,
                        'price': int(breakdown.price) if breakdown.price is not None else None,
                        'from_coordinates': {
                            'lat': float(breakdown.from_latitude) if breakdown.from_latitude is not None else None,
                            'lng': float(breakdown.from_longitude) if breakdown.from_longitude is not None else None,
                        },
                        'to_coordinates': {
                            'lat': float(breakdown.to_latitude) if breakdown.to_latitude is not None else None,
                            'lng': float(breakdown.to_longitude) if breakdown.to_longitude is not None else None,
                        },
                        'price_breakdown': _json_safe(breakdown.price_breakdown),
                    })

                trip_list.append({
                    'trip_id': trip.trip_id,
                    'departure_time': f"{trip.trip_date}T{trip.departure_time}",
                    'origin': origin_name,
                    'destination': destination_name,
                    'driver_name': driver.name if driver else None,
                    'driver_profile_photo_url': getattr(driver, 'profile_photo_url', None) if driver else None,
                    'driver_rating': float(getattr(driver, 'driver_rating', 0) or 0) if driver else 0.0,
                    'vehicle_model': f"{getattr(vehicle, 'company_name', '')} {getattr(vehicle, 'model_number', '')}".strip() if vehicle else 'Unknown Vehicle',
                    'vehicle_photo_front': _vehicle_front_photo_url(request, vehicle),
                    'vehicle_company': getattr(vehicle, 'company_name', None) if vehicle else None,
                    'vehicle_type': getattr(vehicle, 'vehicle_type', None) if vehicle else None,
                    'vehicle_color': getattr(vehicle, 'color', None) if vehicle else None,
                    'vehicle_seats': int(getattr(vehicle, 'seats', 0) or 0) if vehicle else 0,
                    'vehicle_fuel_type': getattr(vehicle, 'fuel_type', None) if vehicle else None,
                    'available_seats': trip.available_seats,
                    'price_per_seat': int(trip.base_fare) if trip.base_fare is not None else None,
                    'gender_preference': trip.gender_preference,
                    'total_seats': trip.total_seats,
                    'estimated_arrival_time': str(trip.estimated_arrival_time) if trip.estimated_arrival_time else None,
                    'notes': trip.notes,
                    'is_negotiable': trip.is_negotiable,
                    'total_distance_km': float(trip.total_distance_km) if trip.total_distance_km is not None else None,
                    'total_duration_minutes': trip.total_duration_minutes,
                    'fare_calculation': _json_safe(trip.fare_calculation),
                    'stop_breakdown': breakdown_list,
                })

            ranked_list, rank_meta = _rank_trips_with_ml(request, trip_list, user_id=user_id)
            return JsonResponse({'success': True, 'trips': ranked_list, 'meta': rank_meta})
        except Exception as e:
            return JsonResponse({'success': False, 'error': str(e)}, status=500)
    return JsonResponse({'error': 'Invalid request method'}, status=400)


@csrf_exempt
def search_trips(request):
    if request.method != 'GET':
        return JsonResponse({'error': 'Invalid request method'}, status=400)

    try:
        user_id = _to_int(request.GET.get('user_id'))
        from_stop_id = _to_int(request.GET.get('from_stop_id'))
        to_stop_id = _to_int(request.GET.get('to_stop_id'))
        q_from = (request.GET.get('from') or request.GET.get('origin') or '').strip()
        q_to = (request.GET.get('to') or request.GET.get('destination') or '').strip()
        date_str = (request.GET.get('date') or '').strip()
        min_seats_raw = (request.GET.get('min_seats') or request.GET.get('seats') or '').strip()
        max_price_raw = (request.GET.get('max_price') or '').strip()
        gender_pref = (request.GET.get('gender_preference') or '').strip()
        negotiable_raw = (request.GET.get('negotiable') or request.GET.get('negotiation_allowed') or '').strip()
        time_from_raw = (request.GET.get('time_from') or '').strip()
        time_to_raw = (request.GET.get('time_to') or '').strip()
        sort = (request.GET.get('sort') or '').strip().lower()

        try:
            limit = int(request.GET.get('limit', 50))
            limit = max(1, min(limit, 200))
        except Exception:
            limit = 50
        try:
            offset = int(request.GET.get('offset', 0))
            offset = max(0, offset)
        except Exception:
            offset = 0

        now = timezone.now()
        today = now.date()
        now_time = now.time()

        trips = Trip.objects.filter(
            trip_status='SCHEDULED',
            available_seats__gt=0,
            started_at__isnull=True,
        ).filter(Q(trip_date__gt=today) | Q(trip_date=today, departure_time__gt=now_time))

        if user_id:
            trips = trips.exclude(driver_id=user_id)

            blocked_driver_ids = BlockedUser.objects.filter(blocker_id=user_id).values_list('blocked_user_id', flat=True)
            blocked_by_driver_ids = BlockedUser.objects.filter(blocked_user_id=user_id).values_list('blocker_id', flat=True)
            trips = trips.exclude(driver_id__in=blocked_driver_ids).exclude(driver_id__in=blocked_by_driver_ids)

            trips = trips.exclude(
                trip_bookings__passenger_id=user_id,
                trip_bookings__booking_status__in=['PENDING', 'CONFIRMED', 'COMPLETED'],
            ).exclude(
                trip_bookings__passenger_id=user_id,
                trip_bookings__blocked=True,
            )

        if from_stop_id:
            trips = trips.filter(route__route_stops__id=from_stop_id)
        elif q_from:
            trips = trips.filter(route__route_stops__stop_name__icontains=q_from)
        if to_stop_id:
            trips = trips.filter(route__route_stops__id=to_stop_id)
        elif q_to:
            trips = trips.filter(route__route_stops__stop_name__icontains=q_to)

        if date_str:
            try:
                trip_date = datetime.strptime(date_str, '%Y-%m-%d').date()
                trips = trips.filter(trip_date=trip_date)
            except ValueError:
                return JsonResponse({'success': False, 'error': 'Invalid date format. Use YYYY-MM-DD.'}, status=400)

        if min_seats_raw:
            try:
                trips = trips.filter(available_seats__gte=int(min_seats_raw))
            except (TypeError, ValueError):
                return JsonResponse({'success': False, 'error': 'min_seats must be an integer.'}, status=400)

        if max_price_raw:
            try:
                trips = trips.filter(base_fare__lte=int(round(float(max_price_raw))))
            except (TypeError, ValueError):
                return JsonResponse({'success': False, 'error': 'max_price must be numeric.'}, status=400)

        if gender_pref:
            gender_norm = gender_pref.strip().capitalize()
            if gender_norm not in ['Male', 'Female', 'Any']:
                return JsonResponse({'success': False, 'error': 'gender_preference must be Male, Female, or Any.'}, status=400)
            trips = trips.filter(gender_preference=gender_norm)

        if negotiable_raw:
            neg_lower = negotiable_raw.lower()
            if neg_lower in ['1', 'true', 'yes']:
                trips = trips.filter(is_negotiable=True)
            elif neg_lower in ['0', 'false', 'no']:
                trips = trips.filter(is_negotiable=False)
            else:
                return JsonResponse({'success': False, 'error': 'negotiable must be true/false.'}, status=400)

        if time_from_raw:
            try:
                tf = datetime.strptime(time_from_raw, '%H:%M').time()
                trips = trips.filter(departure_time__gte=tf)
            except ValueError:
                return JsonResponse({'success': False, 'error': 'time_from must be HH:MM.'}, status=400)

        if time_to_raw:
            try:
                tt = datetime.strptime(time_to_raw, '%H:%M').time()
                trips = trips.filter(departure_time__lte=tt)
            except ValueError:
                return JsonResponse({'success': False, 'error': 'time_to must be HH:MM.'}, status=400)

        trips = trips.distinct()

        if sort == 'soonest':
            trips = trips.order_by('trip_date', 'departure_time')
        elif sort == 'latest':
            trips = trips.order_by('-trip_date', '-departure_time')
        elif sort == 'price_asc':
            trips = trips.order_by('base_fare', 'trip_date', 'departure_time')
        elif sort == 'price_desc':
            trips = trips.order_by('-base_fare', 'trip_date', 'departure_time')
        elif sort == 'seats_desc':
            trips = trips.order_by('-available_seats', 'trip_date', 'departure_time')
        elif sort:
            return JsonResponse({'success': False, 'error': 'Invalid sort.'}, status=400)
        else:
            trips = trips.order_by('trip_date', 'departure_time')

        route_stops_prefetch = Prefetch(
            'route__route_stops',
            queryset=RouteStop.objects.only('id', 'route_id', 'stop_order', 'stop_name').order_by('stop_order')
        )

        trips_qs = (
            trips
            .select_related('route', 'driver', 'vehicle')
            .only(
                'trip_id', 'trip_date', 'departure_time', 'estimated_arrival_time', 'available_seats',
                'base_fare', 'gender_preference', 'total_seats', 'notes', 'is_negotiable',
                'total_distance_km', 'total_duration_minutes', 'fare_calculation',
                'route__route_name',
                'driver__id', 'driver__name', 'driver__profile_photo_url', 'driver__driver_rating',
                'vehicle__company_name', 'vehicle__model_number', 'vehicle__photo_front_url',
                'vehicle__vehicle_type', 'vehicle__color', 'vehicle__seats', 'vehicle__fuel_type'
            )
            .prefetch_related(route_stops_prefetch)
        )

        trips_qs = trips_qs.distinct()

        fetch_n = min(1000, offset + limit + 300)
        trips_qs = trips_qs[:fetch_n]

        items = []
        for trip in trips_qs:
            route = trip.route
            driver = trip.driver
            vehicle = trip.vehicle

            origin_name = route.route_name if route else None
            destination_name = route.route_name if route else None

            try:
                if route is not None:
                    stops = list(route.route_stops.all())
                    if stops:
                        origin_name = stops[0].stop_name or origin_name
                        destination_name = stops[-1].stop_name or destination_name
                        if (q_from or from_stop_id) and (q_to or to_stop_id) and not _stop_order_matches(
                            stops,
                            q_from,
                            q_to,
                            from_stop_id=from_stop_id,
                            to_stop_id=to_stop_id,
                        ):
                            continue
            except Exception:
                pass

            items.append({
                'trip_id': trip.trip_id,
                'departure_time': f"{trip.trip_date}T{trip.departure_time}",
                'origin': origin_name,
                'destination': destination_name,
                'driver_name': driver.name if driver else None,
                'driver_profile_photo_url': getattr(driver, 'profile_photo_url', None) if driver else None,
                'driver_rating': float(getattr(driver, 'driver_rating', 0) or 0) if driver else 0.0,
                'vehicle_model': f"{vehicle.company_name} {vehicle.model_number}" if vehicle else 'Unknown Vehicle',
                'vehicle_photo_front': _vehicle_front_photo_url(request, vehicle),
                'vehicle_company': getattr(vehicle, 'company_name', None) if vehicle else None,
                'vehicle_type': getattr(vehicle, 'vehicle_type', None) if vehicle else None,
                'vehicle_color': getattr(vehicle, 'color', None) if vehicle else None,
                'vehicle_seats': int(getattr(vehicle, 'seats', 0) or 0) if vehicle else 0,
                'vehicle_fuel_type': getattr(vehicle, 'fuel_type', None) if vehicle else None,
                'available_seats': trip.available_seats,
                'price_per_seat': int(trip.base_fare) if trip.base_fare is not None else None,
                'gender_preference': trip.gender_preference,
                'total_seats': trip.total_seats,
                'estimated_arrival_time': str(trip.estimated_arrival_time) if trip.estimated_arrival_time else None,
                'notes': trip.notes,
                'is_negotiable': trip.is_negotiable,
                'total_distance_km': float(trip.total_distance_km) if trip.total_distance_km is not None else None,
                'total_duration_minutes': trip.total_duration_minutes,
                'fare_calculation': trip.fare_calculation,
            })

        trip_list = items[offset:offset + limit]

        ranked_list, rank_meta = _rank_trips_with_ml(request, trip_list, user_id=user_id)

        return JsonResponse({
            'success': True,
            'trips': ranked_list,
            'meta': {
                'limit': limit,
                'offset': offset,
                **rank_meta,
            },
        })
    except Exception as e:
        return JsonResponse({'success': False, 'error': str(e)}, status=500)

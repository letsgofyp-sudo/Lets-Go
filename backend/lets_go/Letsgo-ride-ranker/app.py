import os
import math
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field


app = FastAPI(title="LetsGo Ride Ranker", version="1.1.0")


# -----------------------------
# Auth
# -----------------------------
def _check_auth(authorization: Optional[str]) -> None:
    required = (os.getenv("LETSGO_ML_TOKEN") or "").strip()
    if not required:
        return
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing Authorization header")
    if not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Invalid Authorization scheme")
    token = authorization.split(" ", 1)[1].strip()
    if token != required:
        raise HTTPException(status_code=403, detail="Invalid token")


# -----------------------------
# Request/Response models
# -----------------------------
class UserPayload(BaseModel):
    user_id: int
    gender: Optional[str] = None  # "Male" | "Female" | "Any"
    passenger_rating: Optional[float] = 0.0


class HistoryBooking(BaseModel):
    trip_id: Optional[str] = None
    from_stop_name: Optional[str] = None
    to_stop_name: Optional[str] = None
    total_fare: Optional[int] = 0
    number_of_seats: Optional[int] = 0
    finalized_at: Optional[str] = None  # ISO

    # Optional vehicle history (if backend adds later)
    vehicle_company: Optional[str] = None
    vehicle_type: Optional[str] = None
    vehicle_color: Optional[str] = None
    vehicle_seats: Optional[int] = 0
    vehicle_fuel_type: Optional[str] = None


class HistoryPayload(BaseModel):
    bookings: List[HistoryBooking] = Field(default_factory=list)


class StopBreakdownItem(BaseModel):
    from_stop_name: Optional[str] = None
    to_stop_name: Optional[str] = None
    price: Optional[int] = None


class CandidateTrip(BaseModel):
    trip_id: str

    origin: Optional[str] = None
    destination: Optional[str] = None
    departure_time: Optional[str] = None  # "YYYY-MM-DDTHH:MM:SS" or "YYYY-MM-DDTHH:MM"

    price_per_seat: Optional[int] = None
    available_seats: Optional[int] = None
    gender_preference: Optional[str] = None  # "Male" | "Female" | "Any"
    is_negotiable: Optional[bool] = None

    driver_rating: Optional[float] = 0.0

    vehicle_company: Optional[str] = None
    vehicle_type: Optional[str] = None
    vehicle_color: Optional[str] = None
    vehicle_seats: Optional[int] = 0
    vehicle_fuel_type: Optional[str] = None

    total_distance_km: Optional[float] = None
    total_duration_minutes: Optional[int] = None

    stop_breakdown: List[StopBreakdownItem] = Field(default_factory=list)


class RankRequest(BaseModel):
    request_id: Optional[str] = None
    user: UserPayload
    history: HistoryPayload = Field(default_factory=HistoryPayload)
    candidates: List[CandidateTrip]
    context: Dict[str, Any] = Field(default_factory=dict)


class RankedItem(BaseModel):
    trip_id: str
    score: float
    reasons: List[str] = Field(default_factory=list)


class RankResponse(BaseModel):
    success: bool = True
    model_version: str = "v1.1-real-user-priority"
    ranked: List[RankedItem] = Field(default_factory=list)


@app.get("/")
def root():
    return {
        "success": True,
        "service": "letsgo-ride-ranker",
        "version": app.version,
        "endpoints": {
            "rank": "/api/rank-rides",
            "health": "/health",
        },
    }


@app.get("/health")
def health():
    return {
        "ok": True,
        "ts": datetime.now(timezone.utc).isoformat(),
        "version": app.version,
    }


# -----------------------------
# Utility
# -----------------------------
def _norm(s: Optional[str]) -> str:
    return " ".join((s or "").strip().lower().split())


def _tokens(s: str) -> set:
    return set([t for t in _norm(s).split(" ") if t])


def _jaccard(a: str, b: str) -> float:
    ta = _tokens(a)
    tb = _tokens(b)
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / max(1, len(ta | tb))


def _safe_float(x: Any, default: float = 0.0) -> float:
    try:
        return float(x)
    except Exception:
        return default


def _safe_int(x: Any, default: int = 0) -> int:
    try:
        return int(x)
    except Exception:
        return default


def _parse_iso_dt(s: Optional[str]) -> Optional[datetime]:
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def _recency_weight(finalized_at_iso: Optional[str], now: datetime) -> float:
    # recent rides matter more
    dt = _parse_iso_dt(finalized_at_iso)
    if not dt:
        return 0.25
    age_h = max(0.0, (now - dt).total_seconds() / 3600.0)
    return math.exp(-age_h / 168.0)  # ~1 week decay


def _gender_penalty(user_gender: Optional[str], trip_pref: Optional[str]) -> float:
    ug = (user_gender or "").strip()
    tp = (trip_pref or "Any").strip()
    if not ug:
        return 0.0
    if tp == "Any" or tp == "":
        return 0.0
    if (ug == "Male" and tp == "Female") or (ug == "Female" and tp == "Male"):
        return 0.90  # almost remove from feed
    return 0.0


def _clamp(x: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, x))


def _trip_distance_km(c: "CandidateTrip") -> float:
    d = _safe_float(getattr(c, "total_distance_km", None), 0.0)
    if d > 0:
        return d
    return 20.0


def _distance_time_params(distance_km: float) -> Dict[str, float]:
    d = _clamp(distance_km, 1.0, 500.0)
    r = math.log1p(d) / math.log1p(500.0)

    sat_h = (1.0 * (1.0 - r)) + (12.0 * r)
    half_life_h = (6.0 * (1.0 - r)) + (72.0 * r)

    far_start_h = (18.0 * (1.0 - r)) + (120.0 * r)
    far_end_h = (72.0 * (1.0 - r)) + (168.0 * r)

    return {
        "sat_h": sat_h,
        "half_life_h": half_life_h,
        "far_start_h": far_start_h,
        "far_end_h": far_end_h,
    }


def _soonness_score(departure_iso: Optional[str], now: datetime, *, distance_km: float) -> float:
    dep = _parse_iso_dt(departure_iso)
    if not dep:
        return 0.0

    delta_h = (dep - now).total_seconds() / 3600.0
    if delta_h < 0:
        return 0.0

    p = _distance_time_params(distance_km)
    sat_h = p["sat_h"]
    half_life_h = max(1e-6, p["half_life_h"])

    if delta_h <= sat_h:
        return 1.0

    k = math.log(2.0) / half_life_h
    return math.exp(-k * (delta_h - sat_h))


# -----------------------------
# Build user preference profile from last 30 bookings
# -----------------------------
def _build_user_pref(history: List[HistoryBooking], now: datetime) -> Dict[str, Any]:
    route_pairs: Dict[str, float] = {}
    origins: Dict[str, float] = {}
    dests: Dict[str, float] = {}
    stops: Dict[str, float] = {}
    price_samples: List[int] = []
    time_hours: Dict[int, float] = {}
    vehicle_pref: Dict[str, float] = {}

    def add(m: Dict[str, float], key: Optional[str], w: float):
        k = _norm(key)
        if not k:
            return
        m[k] = m.get(k, 0.0) + w

    def add_vehicle(key: Optional[str], w: float):
        k = _norm(key)
        if not k:
            return
        vehicle_pref[k] = vehicle_pref.get(k, 0.0) + w

    for b in history:
        w = _recency_weight(b.finalized_at, now)

        o = _norm(b.from_stop_name)
        d = _norm(b.to_stop_name)

        if o:
            add(origins, o, 1.2 * w)
            add(stops, o, 1.0 * w)
        if d:
            add(dests, d, 1.2 * w)
            add(stops, d, 1.0 * w)
        if o and d:
            add(route_pairs, f"{o} -> {d}", 1.7 * w)

        tf = _safe_int(b.total_fare, 0)
        if tf > 0:
            price_samples.append(tf)

        # time preference proxy (from history timestamp)
        dt = _parse_iso_dt(b.finalized_at)
        if dt:
            hr = int(dt.hour)
            time_hours[hr] = time_hours.get(hr, 0.0) + w

        # vehicle preference if backend supplies it
        add_vehicle(b.vehicle_company, 1.4 * w)
        add_vehicle(b.vehicle_type, 1.1 * w)
        add_vehicle(b.vehicle_fuel_type, 0.9 * w)
        add_vehicle(b.vehicle_color, 0.5 * w)
        seats = _safe_int(b.vehicle_seats, 0)
        if seats > 0:
            add_vehicle(f"seats:{seats}", 1.0 * w)

    price_med = 0.0
    if price_samples:
        price_samples.sort()
        price_med = float(price_samples[len(price_samples) // 2])

    def topk(m: Dict[str, float], k: int) -> List[str]:
        return [x[0] for x in sorted(m.items(), key=lambda t: t[1], reverse=True)[:k]]

    # If user has no history, these will be empty, and model will rely more on driver_rating+soonness+price
    return {
        "top_route_pairs": topk(route_pairs, 8),
        "top_origins": topk(origins, 8),
        "top_dests": topk(dests, 8),
        "top_stops": topk(stops, 15),
        "price_median": price_med,
        "hour_pref": time_hours,
        "vehicle_pref": vehicle_pref,
    }


def _hour_affinity(dep_iso: Optional[str], hour_pref: Dict[int, float]) -> float:
    if not hour_pref:
        return 0.0
    dep = _parse_iso_dt(dep_iso)
    if not dep:
        return 0.0
    h = int(dep.hour)
    # Normalize by max
    mx = max(hour_pref.values()) if hour_pref else 1.0
    return float(hour_pref.get(h, 0.0) / max(1e-9, mx))


def _price_affinity(price: Optional[int], price_median: float) -> float:
    p = _safe_float(price, 0.0)
    if p <= 0 or price_median <= 0:
        return 0.0

    rel = (p - price_median) / max(1.0, price_median)

    if rel <= 0:
        return math.exp(-0.6 * abs(rel))

    return math.exp(-1.4 * abs(rel))


def _vehicle_affinity(c: CandidateTrip, vehicle_pref: Dict[str, float]) -> float:
    if not vehicle_pref:
        return 0.0
    s = 0.0
    keys = [
        c.vehicle_company,
        c.vehicle_type,
        c.vehicle_fuel_type,
        c.vehicle_color,
    ]
    for k in keys:
        kk = _norm(k)
        if kk:
            s += vehicle_pref.get(kk, 0.0)
    seats = _safe_int(c.vehicle_seats, 0)
    if seats > 0:
        s += vehicle_pref.get(f"seats:{seats}", 0.0)

    # squash
    return 1.0 - math.exp(-s)


def _stopbreakdown_stop_set(c: CandidateTrip) -> set:
    s = set()
    for b in c.stop_breakdown or []:
        if b.from_stop_name:
            s.add(_norm(b.from_stop_name))
        if b.to_stop_name:
            s.add(_norm(b.to_stop_name))
    return set([x for x in s if x])


def _candidate_segment_set(c: CandidateTrip) -> set:
    segs = set()
    for b in c.stop_breakdown or []:
        fr = _norm(b.from_stop_name)
        to = _norm(b.to_stop_name)
        if fr and to:
            segs.add((fr, to))
    return segs


def _parse_route_pair(rp: str) -> Tuple[str, str]:
    parts = [p.strip() for p in str(rp).split("->")]
    if len(parts) >= 2:
        return _norm(parts[0]), _norm(parts[1])
    return _norm(rp), ""


def _route_affinity(c: CandidateTrip, pref: Dict[str, Any]) -> Tuple[float, List[str]]:
    reasons: List[str] = []
    origin = _norm(c.origin)
    dest = _norm(c.destination)

    pair_score = 0.0
    reverse_pair_score = 0.0
    for rp in pref.get("top_route_pairs", []):
        po, pd = _parse_route_pair(rp)
        if po and pd:
            s_dir = 0.6 * _jaccard(po, origin) + 0.4 * _jaccard(pd, dest)
            s_rev = 0.6 * _jaccard(po, dest) + 0.4 * _jaccard(pd, origin)
            pair_score = max(pair_score, s_dir)
            reverse_pair_score = max(reverse_pair_score, s_rev)

    pair_score = max(pair_score, 0.10 * reverse_pair_score)
    if pair_score > 0.25:
        reasons.append("route_pair_match")

    # (B) Stop familiarity: uses stop breakdown for more realistic similarity
    stop_score = 0.0
    cand_stops = _stopbreakdown_stop_set(c)
    if cand_stops:
        # compare with user's top stops
        top_stops = pref.get("top_stops", [])
        hit = 0.0
        for ts in top_stops:
            if ts in cand_stops:
                hit += 1.0
        stop_score = min(1.0, hit / 5.0)  # cap
        if stop_score > 0.2:
            reasons.append("stop_familiarity")

    seg_score = 0.0
    cand_segs = _candidate_segment_set(c)
    if cand_segs:
        for rp in pref.get("top_route_pairs", []):
            po, pd = _parse_route_pair(rp)
            if po and pd and (po, pd) in cand_segs:
                seg_score = 1.0
                break
        if seg_score > 0.0:
            reasons.append("segment_match")

    # (C) Origin/dest similarity fallback
    od_score = 0.0
    for o in pref.get("top_origins", []):
        od_score = max(od_score, _jaccard(o, origin))
    for d in pref.get("top_dests", []):
        od_score = max(od_score, _jaccard(d, dest))
    if od_score > 0.25:
        reasons.append("origin_dest_match")

    # Weighted route total
    route_total = 0.40 * pair_score + 0.22 * seg_score + 0.23 * stop_score + 0.15 * od_score
    return route_total, reasons


def _price_far_penalty(departure_iso: Optional[str], now: datetime, *, distance_km: float) -> float:
    dep = _parse_iso_dt(departure_iso)
    if not dep:
        return 0.0

    delta_h = (dep - now).total_seconds() / 3600.0
    if delta_h <= 0:
        return 0.0

    p = _distance_time_params(distance_km)
    if delta_h <= p["far_start_h"]:
        return 0.0

    span = max(1e-6, (p["far_end_h"] - p["far_start_h"]))
    return _clamp((delta_h - p["far_start_h"]) / span, 0.0, 1.0)


W_ROUTE = 0.46
W_SOON = 0.12
W_DRIVER = 0.18
W_PRICE = 0.07
W_VEH = 0.08
W_HOUR = 0.04
W_SEATS = 0.01
W_FAR_PEN = 0.06


def _score_candidate(user: UserPayload, pref: Dict[str, Any], now: datetime, c: CandidateTrip) -> RankedItem:
    reasons: List[str] = []

    # Hard penalty: gender mismatch
    gpen = _gender_penalty(user.gender, c.gender_preference)
    if gpen > 0:
        reasons.append("gender_mismatch")

    # Route relevance (highest)
    route_score, route_reasons = _route_affinity(c, pref)
    reasons.extend(route_reasons)

    # Soonness
    dist_km = _trip_distance_km(c)
    soon = _soonness_score(c.departure_time, now, distance_km=dist_km)
    if soon > 0.85:
        reasons.append("soon_departure")

    far_pen = _price_far_penalty(c.departure_time, now, distance_km=dist_km)
    if far_pen > 0.35:
        reasons.append("far_departure")

    # Driver rating
    dr = max(0.0, min(5.0, _safe_float(c.driver_rating, 0.0)))
    driver_score = dr / 5.0
    if driver_score > 0.7:
        reasons.append("high_driver_rating")

    # Price & negotiable
    price_score = _price_affinity(c.price_per_seat, float(pref.get("price_median") or 0.0))
    if price_score > 0.5:
        reasons.append("price_fit")

    neg_bonus = 0.0
    if c.is_negotiable is True:
        neg_bonus = 0.15
        reasons.append("negotiable")

    # Vehicle preference
    veh = _vehicle_affinity(c, pref.get("vehicle_pref") or {})
    if veh > 0.3:
        reasons.append("vehicle_match")

    # Time-of-day affinity (soft)
    hour_aff = _hour_affinity(c.departure_time, pref.get("hour_pref") or {})
    if hour_aff > 0.4:
        reasons.append("time_of_day_match")

    # Seats availability (soft)
    seats = _safe_int(c.available_seats, 0)
    seats_score = 1.0 - math.exp(-seats / 3.0) if seats > 0 else 0.0

    # FINAL weighted score: matches real user priorities in your UI
    # Route relevance dominates, then time+driver, then price/vehicle, then minor bonuses.
    score = (
        W_ROUTE * route_score +
        W_SOON * soon +
        W_DRIVER * driver_score +
        W_PRICE * price_score +
        W_VEH * veh +
        W_HOUR * hour_aff +
        W_SEATS * seats_score +
        neg_bonus
        - W_FAR_PEN * far_pen
    )

    score = max(0.0, min(1.0, score * (1.0 - gpen)))
    return RankedItem(trip_id=c.trip_id, score=float(score), reasons=reasons)


@app.post("/api/rank-rides", response_model=RankResponse)
def rank_rides(req: RankRequest, authorization: Optional[str] = Header(default=None)):
    _check_auth(authorization)

    now = None
    if isinstance(req.context, dict):
        now = _parse_iso_dt(req.context.get("now"))
    if not now:
        now = datetime.now(timezone.utc)

    history = req.history.bookings if req.history else []
    pref = _build_user_pref(history, now)

    ranked: List[RankedItem] = []
    for c in req.candidates:
        ranked.append(_score_candidate(req.user, pref, now, c))

    ranked.sort(key=lambda x: x.score, reverse=True)
    return RankResponse(success=True, ranked=ranked)
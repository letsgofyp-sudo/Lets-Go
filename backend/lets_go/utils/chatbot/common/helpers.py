import json
import difflib
import math
import re
from datetime import date, datetime, timedelta
from typing import Optional

from .datetime_parse import parse_date, parse_relative_datetime, parse_time_str
from .extractors import (
    extract_booking_id,
    extract_coord_pairs,
    extract_fare,
    extract_from_to,
    extract_recipient_id,
    extract_seats,
    extract_trip_id,
    looks_like_route_id,
    looks_like_route_id_strict,
)
from .safety import (
    blocked_system_request,
    capabilities_text,
    contains_abuse,
    extract_rating,
    help_text,
    parse_rating_value,
    smalltalk_reply,
)
from .stops_geo import (
    build_create_trip_fare_payload,
    fuzzy_stop_name,
    haversine_km,
    load_stops_geo,
    nearest_stop_name,
)
from .text import normalize_text, to_int, tokenize

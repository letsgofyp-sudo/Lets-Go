from __future__ import annotations

from typing import Any

from ..engine_impl.sanitize import format_api_result


def pick_most_recent_ride(rides: Any) -> dict | None:
    if not isinstance(rides, list) or not rides:
        return None
    for r in rides:
        if isinstance(r, dict) and r.get('trip_id'):
            return r
    return None

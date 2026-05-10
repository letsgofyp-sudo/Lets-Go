import re
from datetime import date, datetime, timedelta
from typing import Optional

from .text import normalize_text


def parse_date(text: str) -> Optional[date]:
    t = normalize_text(text)
    if not t:
        return None
    if 'today' in t:
        return date.today()
    if any(k in t for k in ['tomorrow', 'tomarrow', 'tmrw', 'tmr']):
        return date.today() + timedelta(days=1)
    m = re.search(r"\b(\d{4}-\d{2}-\d{2})\b", t)
    if m:
        try:
            return datetime.strptime(m.group(1), '%Y-%m-%d').date()
        except Exception:
            return None
    return None


def parse_time_str(text: str) -> Optional[str]:
    t = normalize_text(text)
    if not t:
        return None
    m = re.search(r"\b(\d{1,2}):(\d{2})\s*(am|pm)\b", t)
    if m:
        hh = int(m.group(1))
        mm = int(m.group(2))
        ampm = m.group(3)
        if hh == 12:
            hh = 0
        if ampm == 'pm':
            hh += 12
        if 0 <= hh <= 23 and 0 <= mm <= 59:
            return f"{hh:02d}:{mm:02d}"
        return None
    m = re.search(r"\b(\d{1,2}):(\d{2})\b", t)
    if m:
        hh = int(m.group(1))
        mm = int(m.group(2))
        if 0 <= hh <= 23 and 0 <= mm <= 59:
            return f"{hh:02d}:{mm:02d}"
        return None
    m = re.search(r"\b(\d{1,2})\s*(am|pm)\b", t)
    if m:
        hh = int(m.group(1))
        ampm = m.group(2)
        if hh == 12:
            hh = 0
        if ampm == 'pm':
            hh += 12
        if 0 <= hh <= 23:
            return f"{hh:02d}:00"
    return None


def _roll_date_forward_if_time_passed(*, tm: str, base: datetime) -> date:
    try:
        hh, mm = [int(x) for x in (tm or '').split(':', 1)]
    except Exception:
        return base.date()
    target = datetime.combine(base.date(), datetime.min.time()).replace(hour=hh, minute=mm)
    if target < base:
        return (base + timedelta(days=1)).date()
    return base.date()


def parse_relative_datetime(text: str, *, base: Optional[datetime] = None) -> Optional[tuple[date, str]]:
    low = normalize_text(text)
    if not low:
        return None
    base_dt = base or datetime.now()

    minutes: Optional[int] = None
    m = re.search(r"\b(?:in|after)\s+(\d{1,3})\s*(?:minute|minutes|min|mins)\b", low)
    if m:
        minutes = int(m.group(1))
    m = re.search(r"\b(?:in|after)\s+(\d{1,2})\s*(?:hour|hours|hr|hrs)\b", low)
    if m:
        minutes = (minutes or 0) + int(m.group(1)) * 60
    if minutes is None and re.search(r"\b(?:in|after)\s+an\s+hour\b", low):
        minutes = 60

    if minutes is not None and minutes > 0:
        dt = base_dt + timedelta(minutes=int(minutes))
        return dt.date(), f"{dt.hour:02d}:{dt.minute:02d}"

    tm = parse_time_str(text)
    if tm:
        d = parse_date(text)
        if d is None:
            d = _roll_date_forward_if_time_passed(tm=tm, base=base_dt)
        return d, tm

    return None

import re
from typing import Optional


def normalize_text(s: str) -> str:
    s2 = (s or "").strip().lower()
    s2 = (
        s2.replace("\u2019", "'")
        .replace("\u2018", "'")
        .replace("\u201c", '"')
        .replace("\u201d", '"')
        .replace("\u2014", "-")
        .replace("\u2013", "-")
    )
    return re.sub(r"\s+", " ", s2)


def tokenize(s: str) -> list[str]:
    s = normalize_text(s)
    s = re.sub(r"[^a-z0-9_\s-]+", " ", s)
    return [p for p in s.split() if p]


def to_int(value) -> Optional[int]:
    try:
        if value is None:
            return None

        if isinstance(value, bool):
            return None
        return int(value)
    except Exception:
        return None

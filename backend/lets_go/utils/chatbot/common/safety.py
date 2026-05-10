import re
from typing import Optional

from .text import normalize_text


def contains_abuse(text: str) -> bool:
    low = normalize_text(text)
    bad = ['fuck', 'fucking', 'bitch', 'asshole', 'bastard', 'chutiya', 'madarchod', 'behenchod']
    return any(w in low for w in bad)


def blocked_system_request(text: str) -> Optional[str]:
    low = normalize_text(text)
    blocked_terms = [
        'verify', 'verification', 'approve', 'admin',
        'send otp', 'otp', 'reset password',
        'fcm', 'token',
        'start ride', 'complete ride',
        'update location', 'live location',
        'cancel booking', 'cancel my booking',
        'cancel trip', 'cancel my trip',
        'delete trip', 'remove trip',
        'broadcast',
        'share link', 'share token',
        'ban user', 'unban',
    ]

    info_q_markers = [
        'what is',
        'what are',
        'meaning',
        'define',
        'when',
        'why',
        'how does',
        'how do',
        '?',
    ]

    if 'pickup code' in low:
        if not any(m in low for m in info_q_markers):
            return "I can't do that directly here. Please use the app's official screens/support flow (or contact an admin) for this action."

    if 'sos' in low:
        if not any(m in low for m in info_q_markers):
            return "I can't do that directly here. Please use the app's official screens/support flow (or contact an admin) for this action."

    for term in blocked_terms:
        if term in low:
            return "I can't do that directly here. Please use the app's official screens/support flow (or contact an admin) for this action."
    return None


def help_text() -> str:
    return "\n".join([
        'You can talk naturally. Examples:',
        "- book a ride from Saddar to DHA tomorrow at 6pm",
        "- I need 2 seats",
        "- make it 450 fare",
        "- yes (to confirm)",
        "- cancel (to stop current action)",
        "- ask business rules/questions like: can I chat without booking?",
    ])


def capabilities_text() -> str:
    return "\n".join([
        'I can help you with:',
        '- book a ride (find trips and reserve seats)',
        "- create/post a ride (if you're a driver)",
        '- list your vehicles, bookings, and rides',
        "- delete your created ride (if allowed)",
        "- cancel your created ride (if allowed)",
        '- cancel your booking',
        '- view/send trip chat messages (only if authorized)',
        '',
        "Try: 'book a ride from X to Y tomorrow 6pm' or 'create a ride'.",
    ])


def smalltalk_reply(text: str) -> Optional[str]:
    low = normalize_text(text)
    if any(p in low for p in ['i love you', 'love you']):
        return "Thank you. I can help with rides/bookings—tell me what you'd like to do."
    if any(p in low for p in ['help me', 'i am in trouble', 'im in trouble', 'emergency']):
        return "I'm here to help with the app tasks (booking/creating rides, messages, etc.). If this is an emergency, please contact local emergency services or someone you trust right now."
    return None


def extract_rating(text: str) -> Optional[float]:
    m = re.search(r"\b([1-5](?:\.0)?)\s*(?:star|stars|rating)\b", text or '', flags=re.IGNORECASE)
    if m:
        try:
            return float(m.group(1))
        except Exception:
            return None
    return None


def parse_rating_value(text: str) -> Optional[float]:
    r = extract_rating(text)
    if r is not None:
        return r
    try:
        v = float(str(text or '').strip())
    except Exception:
        return None
    if 1.0 <= v <= 5.0:
        return v
    return None

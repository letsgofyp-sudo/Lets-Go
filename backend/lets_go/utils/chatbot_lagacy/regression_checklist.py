import os
import re
import logging


def _load_env_file() -> None:
    backend_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
    env_path = os.path.join(backend_root, '.env')
    try:
        with open(env_path, 'r', encoding='utf-8') as f:
            lines = f.read().splitlines()
    except Exception:
        return
    for raw in lines:
        line = (raw or '').strip()
        if not line or line.startswith('#'):
            continue
        if line.lower().startswith('export '):
            line = line[7:].strip()
        if '=' not in line:
            continue
        k, v = line.split('=', 1)
        k = (k or '').strip()
        v = (v or '').strip()
        if not k:
            continue
        if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
            v = v[1:-1]
        if k not in os.environ:
            os.environ[k] = v


_load_env_file()


logger = logging.getLogger(__name__)


try:
    from .api import api_login
    from .config import BOT_EMAIL, BOT_PASSWORD
    from .engine import handle_message
    from .llm import cloud_model, llm_base_url, llm_brain_mode, llm_debug_enabled, llm_provider
    from .state import BotContext, set_current_user
except ImportError:  # pragma: no cover
    import sys

    _BACKEND_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
    if _BACKEND_ROOT not in sys.path:
        sys.path.insert(0, _BACKEND_ROOT)

    from lets_go.utils.chatbot.api import api_login
    from lets_go.utils.chatbot.config import BOT_EMAIL, BOT_PASSWORD
    from lets_go.utils.chatbot.engine import handle_message
    from lets_go.utils.chatbot.llm import cloud_model, llm_base_url, llm_brain_mode, llm_debug_enabled, llm_provider
    from lets_go.utils.chatbot.state import BotContext, set_current_user


def _ask(ctx: BotContext, q: str) -> str:
    logger.debug("=== You: %s", q)
    reply = handle_message(ctx, q)
    logger.debug("=== Bot: %s", reply)
    return reply


def _extract_first_trip_id(text: str) -> str:
    m = re.search(r"\btrip_id=([A-Za-z0-9._:-]+)", text or '')
    return (m.group(1) if m else '').strip()


def _extract_first_booking_id(text: str) -> int:
    m = re.search(r"\bbooking_id=(\d+)", text or '')
    if m:
        try:
            return int(m.group(1))
        except Exception:
            return 0
    m = re.search(r"\bbooking\s*#?\s*(\d+)\b", text or '', flags=re.IGNORECASE)
    if m:
        try:
            return int(m.group(1))
        except Exception:
            return 0
    m = re.search(r"\b\d{3,9}\b", text or '')
    if m:
        try:
            return int(m.group(0))
        except Exception:
            return 0
    return 0


def _assert_api_backed(label: str, reply: str, *, allow_empty: bool = False) -> None:
    s = (reply or '')
    ok = (
        bool(re.search(r"\b\d{3}\s*:\s*\{", s))
        or ('trip_id=' in s)
        or ('booking_id=' in s)
        or ('API server not reachable' in s)
    )
    if (not ok) and allow_empty:
        low = s.lower()
        if any(p in low for p in {
            "couldn't find any booked rides",
            'could not find any booked rides',
            'no bookings',
            'no booked rides',
            'no rides booked',
            'not found',
        }):
            ok = True
    if not ok:
        raise SystemExit(f"[regression] Expected API-backed output for {label}, got: {s[:200]}")


def main() -> None:
    user, err = api_login(BOT_EMAIL, BOT_PASSWORD)
    if err:
        raise SystemExit(f'Login failed: {err}')
    set_current_user(user)
    user_id = int(user.get('id'))

    prov = llm_provider()
    brain = llm_brain_mode()
    base = llm_base_url()
    model = cloud_model()
    debug = llm_debug_enabled()
    logger.debug("Logged in as user_id=%s (%s)", user_id, user.get('name', ''))
    logger.debug("LLM: provider=%s brain_mode=%s debug=%s", prov, 'ON' if brain else 'OFF', 'ON' if debug else 'OFF')
    if prov == 'openai_compat':
        logger.debug("LLM: base_url=%s model=%s", base or '(missing)', model)

    ctx = BotContext(user_id=user_id)

    _ask(ctx, 'hi')

    rides = _ask(ctx, 'list my rides')
    _assert_api_backed('list my rides', rides)
    tid = _extract_first_trip_id(rides)
    if tid:
        td = _ask(ctx, f'trip details trip_id={tid}')
        _assert_api_backed('trip details', td)

    bookings = _ask(ctx, 'list my bookings')
    _assert_api_backed('list my bookings', bookings, allow_empty=True)
    bid = _extract_first_booking_id(bookings)

    _ask(ctx, 'recreate my last completed ride after 1 hour')
    _ask(ctx, 'no')

    if tid:
        _ask(ctx, f'delete trip_id={tid}')
        _ask(ctx, 'no')
        _ask(ctx, f'cancel trip_id={tid}')
        _ask(ctx, 'no')

    _ask(ctx, 'create a ride')
    _ask(ctx, 'from zoo road to khizra mosque')
    _ask(ctx, 'show my vehicles')
    _ask(ctx, '1')
    _ask(ctx, 'tomorrow 10 am')
    _ask(ctx, '2 seats')
    _ask(ctx, 'fare 70')
    _ask(ctx, 'no')

    if tid and bid:
        _ask(ctx, f'negotiation history trip_id={tid} booking_id={bid}')
        _ask(ctx, f'list pending requests trip_id={tid}')

    if bid:
        pd = _ask(ctx, f'payment details booking_id={bid}')
        _assert_api_backed('payment details', pd, allow_empty=True)
        _ask(ctx, f'submit payment booking_id={bid} cash 5')
        _ask(ctx, 'no')
        _ask(ctx, f'confirm payment received booking_id={bid} 5')
        _ask(ctx, 'no')

    logger.debug('Done.')


if __name__ == '__main__':
    main()

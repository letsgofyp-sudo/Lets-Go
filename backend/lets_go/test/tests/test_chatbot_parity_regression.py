import os
import random
import string
import sys
import types
import urllib.request
from datetime import datetime

import pytest
import requests


def _parity_report_path() -> str | None:
    p = (os.environ.get('LETS_GO_BOT_PARITY_REPORT_PATH') or '').strip()
    return p or None


def _write_parity_report(path: str, lines: list[str]) -> None:
    try:
        os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
        with open(path, 'w', encoding='utf-8') as f:
            f.write('\n'.join(lines).rstrip() + '\n')
    except Exception:
        return


def _live_mode_enabled() -> bool:
    return str(os.environ.get('LETS_GO_BOT_LIVE') or '').strip().lower() in {'1', 'true', 'yes', 'on'}


def _live_enable_llm() -> bool:
    return str(os.environ.get('LETS_GO_BOT_LIVE_ENABLE_LLM') or '').strip().lower() in {'1', 'true', 'yes', 'on'}


def _parse_int_list_env(var: str) -> list[int]:
    raw = (os.environ.get(var) or '').strip()
    if not raw:
        return []
    parts = [p.strip() for p in raw.replace(';', ',').replace(' ', ',').split(',')]
    out: list[int] = []
    for p in parts:
        if not p:
            continue
        try:
            out.append(int(p))
        except Exception:
            continue
    return out


def _live_prompts() -> list[str]:
    raw = (os.environ.get('LETS_GO_BOT_LIVE_PROMPTS') or '').strip()
    if raw:
        lines = [ln.strip() for ln in raw.split('\n')]
        return [ln for ln in lines if ln]
    return [
        'hi',
        'help',
        'faq',
        'manual',
        'my profile',
        'my bookings',
        'my rides',
        'my vehicles',
        'trip details',
        'pickup code',
    ]


def _patch_network(monkeypatch: pytest.MonkeyPatch) -> None:
    def _no_requests(*args, **kwargs):  # noqa: ANN001, D401
        raise requests.ConnectionError("network disabled in chatbot parity tests")

    def _no_urlopen(*args, **kwargs):  # noqa: ANN001, D401
        raise OSError("network disabled in chatbot parity tests")

    monkeypatch.setattr(requests, "request", _no_requests)
    monkeypatch.setattr(urllib.request, "urlopen", _no_urlopen)


def _setup_env() -> None:
    os.environ["LETS_GO_BOT_STATELESS"] = "1"
    os.environ["LETS_GO_BOT_DEBUG"] = ""
    os.environ["LETS_GO_API_BASE_URL"] = "http://127.0.0.1:9"  # unroutable/closed
    os.environ["LETS_GO_ORS_API_KEY"] = ""  # avoid external ORS calls


def _patch_admin_models() -> None:
    admin_pkg = sys.modules.get('administration')
    if admin_pkg is None:
        admin_pkg = types.ModuleType('administration')
        sys.modules['administration'] = admin_pkg
    models_mod = sys.modules.get('administration.models')
    if models_mod is None:
        models_mod = types.ModuleType('administration.models')
        sys.modules['administration.models'] = models_mod

    class _DummyQS:
        def filter(self, **kwargs):
            return self

        def order_by(self, *args):
            return self

        def values_list(self, *args, **kwargs):
            return []

    class SupportFAQ:  # noqa: D401
        objects = _DummyQS()

    setattr(models_mod, 'SupportFAQ', SupportFAQ)


def _rand_noise(rng: random.Random, n: int) -> str:
    alphabet = string.ascii_lowercase + "     _-"  # include spaces
    return "".join(rng.choice(alphabet) for _ in range(n)).strip()


def _build_cases() -> list[str]:
    # Core intent trigger phrases derived from _rule_intent mappings + common variants.
    seeds = [
        "hi",
        "hello",
        "hey",
        "help",
        "how to use",
        "what can you do",
        "capabilities",
        "features",
        "faq",
        "faqs",
        "manual",
        "about app",
        "what is lets go",
        "pickup code",
        "sos",
        "suggest stops",
        "suggest stop",
        "what about fares",
        "fare negotiation",
        "how do payments work",
        "how do notifications work",
        "why can't i book",
        "why cant i book",
        "why can't i create",
        "why cant i create",
        "guest mode",
        "without login",
        "book a ride",
        "book ride",
        "book trip",
        "create ride",
        "post a ride",
        "send message",
        "message trip",
        "negotiate",
        "cancel booking",
        "cancel trip",
        "delete trip",
        "my profile",
        "profile details",
        "account details",
        "who am i",
        "change requests",
        "verification requests",
        "trip details",
        "my bookings",
        "list bookings",
        "booking history",
        "my rides",
        "my trips",
        "ride history",
        "list rides",
        "my vehicles",
        "list vehicles",
        "show vehicles",
        "chat history",
        "chat list",
        "list chat",
        "show chat trip",
        "payment details booking",
    ]

    # Expand into many noisy variants to reach >2000 deterministic cases.
    rng = random.Random(1337)
    cases: list[str] = []

    templates = [
        "{seed}",
        "{seed}?",
        "please {seed}",
        "can you {seed}",
        "i want to {seed}",
        "{seed} now",
        "{noise} {seed}",
        "{seed} {noise}",
        "{noise} {seed} {noise}",
    ]

    for seed in seeds:
        for _ in range(28):
            noise = _rand_noise(rng, rng.randint(0, 18))
            tmpl = rng.choice(templates)
            txt = tmpl.format(seed=seed, noise=noise).strip()
            if txt:
                cases.append(txt)

    # Add some arbitrary text to ensure unknown intents are stable.
    for _ in range(300):
        cases.append(_rand_noise(rng, rng.randint(10, 70)))

    # Ensure size.
    # With current parameters: len(seeds)*28 + 300 = 39*28 + 300 = 1392 + 300 = 1692.
    # Add more expansions.
    extra = [
        "from zoo road to khizra mosque",
        "tomorrow 10 am",
        "2 seats",
        "fare 70",
        "no",
        "yes",
        "1",
        "2",
        "3",
        "trip_id=ABC123",
        "booking_id=123",
        "trip details trip_id=ABC123",
        "payment details booking_id=123",
    ]
    for seed in extra:
        for _ in range(40):
            noise = _rand_noise(rng, rng.randint(0, 24))
            cases.append(f"{noise} {seed} {noise}".strip())

    # Now should be comfortably >2000.
    return cases


def _build_scenarios() -> list[list[str]]:
    # Multi-turn flows; stateless mode preserves choose_* flows, so these should behave consistently.
    return [
        ["hi"],
        ["create a ride", "from zoo road to khizra mosque", "show my vehicles", "1", "tomorrow 10 am", "2 seats", "fare 70", "no"],
        ["book a ride", "from zoo road to khizra mosque", "tomorrow 10 am", "2", "no"],
        ["cancel booking", "booking_id=123", "no"],
        ["delete trip", "trip_id=ABC123", "no"],
        ["cancel trip", "trip_id=ABC123", "no"],
        ["negotiate", "trip_id=ABC123 booking_id=123", "no"],
        ["send message", "trip_id=ABC123", "hello", "no"],
    ]


@pytest.fixture(autouse=True)
def _env_and_network(monkeypatch: pytest.MonkeyPatch):
    if _live_mode_enabled():
        return
    _setup_env()
    _patch_admin_models()
    _patch_network(monkeypatch)


def _run_new_live(user_id: int, text: str, *, user_name: str | None = None) -> str:
    from lets_go.utils.chatbot.core import BotContext, set_current_user
    from lets_go.utils.chatbot.engine_impl import handle_message

    if user_id > 0:
        set_current_user({'name': user_name or 'Live User'})
    else:
        set_current_user({})
    ctx = BotContext(user_id=int(user_id))
    return handle_message(ctx, text)


def _run_new(user_id: int, text: str) -> str:
    from lets_go.utils.chatbot.core import BotContext, set_current_user
    from lets_go.utils.chatbot.engine_impl import handle_message

    set_current_user({"name": "Test User"})
    ctx = BotContext(user_id=user_id)
    return handle_message(ctx, text)


def _run_legacy(user_id: int, text: str) -> str:
    from lets_go.utils.chatbot_lagacy.engine import handle_message
    from lets_go.utils.chatbot_lagacy.state import BotContext, set_current_user

    set_current_user({"name": "Test User"})
    ctx = BotContext(user_id=user_id)
    return handle_message(ctx, text)


def test_chatbot_parity_bulk_cases():
    cases = _build_cases()
    assert len(cases) > 2000

    report_lines: list[str] = []
    report_path = _parity_report_path()
    if report_path:
        report_lines.append('CHATBOT PARITY REGRESSION REPORT')
        report_lines.append('SECTION: bulk_cases')
        report_lines.append(f'total_cases={len(cases)}')
        report_lines.append('')

    # Use unique user_id per case to avoid cross-case state coupling.
    base = 100_000
    for i, text in enumerate(cases):
        uid = base + i
        a = _run_legacy(uid, text)
        b = _run_new(uid, text)
        if report_path:
            ok = (a == b)
            report_lines.append(f'CASE #{i}')
            report_lines.append(f'user_id={uid}')
            report_lines.append(f'input={text!r}')
            report_lines.append(f'expected_legacy={a!r}')
            report_lines.append(f'actual_new={b!r}')
            report_lines.append(f'status={"PASS" if ok else "FAIL"}')
            report_lines.append('')
        assert a == b, f"Mismatch for case#{i} uid={uid} text={text!r}\nlegacy={a!r}\nnew={b!r}"

    if report_path:
        report_lines.append('END_SECTION: bulk_cases')
        _write_parity_report(report_path, report_lines)


def test_chatbot_parity_multiturn_scenarios():
    scenarios = _build_scenarios()
    base = 300_000

    report_lines: list[str] = []
    report_path = _parity_report_path()
    if report_path:
        report_lines.append('CHATBOT PARITY REGRESSION REPORT')
        report_lines.append('SECTION: multiturn_scenarios')
        report_lines.append(f'total_scenarios={len(scenarios)}')
        report_lines.append('')

    for si, turns in enumerate(scenarios):
        uid = base + si
        legacy_out: list[str] = []
        new_out: list[str] = []

        for t in turns:
            legacy_out.append(_run_legacy(uid, t))
            new_out.append(_run_new(uid, t))

        if report_path:
            ok = (legacy_out == new_out)
            report_lines.append(f'SCENARIO #{si}')
            report_lines.append(f'user_id={uid}')
            report_lines.append(f'turns={turns!r}')
            report_lines.append(f'expected_legacy={legacy_out!r}')
            report_lines.append(f'actual_new={new_out!r}')
            report_lines.append(f'status={"PASS" if ok else "FAIL"}')
            report_lines.append('')

        assert legacy_out == new_out, (
            f"Mismatch for scenario#{si} uid={uid} turns={turns!r}\nlegacy={legacy_out!r}\nnew={new_out!r}"
        )

    if report_path:
        report_lines.append('END_SECTION: multiturn_scenarios')
        _write_parity_report(report_path, report_lines)


def test_chatbot_live_smoke_transcript():
    if not _live_mode_enabled():
        pytest.skip('Set LETS_GO_BOT_LIVE=1 to enable live smoke transcript test.')

    if _live_enable_llm():
        os.environ['LLM_CHAT'] = '1'
        os.environ.pop('LLM_PROVIDER', None)
    else:
        os.environ['LLM_CHAT'] = '0'
        os.environ['LLM_PROVIDER'] = 'none'

    user_ids = _parse_int_list_env('LETS_GO_BOT_LIVE_USER_IDS')
    guest_ids = _parse_int_list_env('LETS_GO_BOT_LIVE_GUEST_IDS')
    prompts = _live_prompts()

    if not user_ids and not guest_ids:
        pytest.skip('No live IDs configured. Set LETS_GO_BOT_LIVE_USER_IDS and/or LETS_GO_BOT_LIVE_GUEST_IDS.')

    report_path = _parity_report_path()
    report_lines: list[str] = []
    if report_path:
        report_lines.append('CHATBOT LIVE SMOKE TRANSCRIPT')
        report_lines.append(f'timestamp={datetime.now().isoformat()}')
        report_lines.append(f'live_enable_llm={"1" if _live_enable_llm() else "0"}')
        report_lines.append(f'api_base_url={(os.environ.get("LETS_GO_API_BASE_URL") or "").strip()!r}')
        report_lines.append(f'user_ids={user_ids!r}')
        report_lines.append(f'guest_ids={guest_ids!r}')
        report_lines.append(f'total_prompts={len(prompts)}')
        report_lines.append('')

    targets: list[tuple[str, int]] = []
    for uid in user_ids:
        targets.append(('user', int(uid)))
    for gid in guest_ids:
        targets.append(('guest', -int(gid)))

    for kind, bot_uid in targets:
        if report_path:
            report_lines.append(f'TARGET: {kind} user_id={bot_uid}')
        for pi, p in enumerate(prompts):
            out = _run_new_live(bot_uid, p, user_name='Fawad Saqlain' if bot_uid == 13 else None)
            assert isinstance(out, str)
            assert out.strip(), f'Empty reply for {kind} user_id={bot_uid} prompt#{pi}={p!r}'
            low = out.lower()
            assert 'traceback' not in low, f'Traceback-like reply for {kind} user_id={bot_uid} prompt#{pi}={p!r}: {out!r}'
            if report_path:
                report_lines.append(f'PROMPT #{pi}: {p!r}')
                report_lines.append(f'REPLY: {out!r}')
        if report_path:
            report_lines.append('')

    if report_path:
        _write_parity_report(report_path, report_lines)

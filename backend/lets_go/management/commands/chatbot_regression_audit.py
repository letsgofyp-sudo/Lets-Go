from __future__ import annotations

import os
import re
from dataclasses import dataclass
from datetime import datetime

from django.core.management.base import BaseCommand

from lets_go.utils.chatbot.core import BOT_EMAIL, BOT_PASSWORD, BotContext, get_state, reset_flow, set_current_user
from lets_go.utils.chatbot.engine_impl import handle_message
from lets_go.utils.chatbot.integrations.api import api_login


def _safe_filename(s: str) -> str:
    s2 = re.sub(r"[^A-Za-z0-9._-]+", "_", str(s or "").strip())
    return s2 or "audit"


def _write_line(fp, line: str) -> None:
    fp.write((line or "") + "\n")


def _ask(ctx: BotContext, q: str) -> str:
    return handle_message(ctx, q)


def _extract_first(pattern: str, text: str) -> str:
    m = re.search(pattern, text or '')
    return (m.group(1) if m else '').strip()


def _extract_trip_id(reply: str) -> str:
    return _extract_first(r"\btrip_id=([A-Za-z0-9._:-]+)", reply)


def _extract_booking_id(reply: str) -> str:
    return _extract_first(r"\bbooking_id=([A-Za-z0-9._:-]+)", reply)


def _extract_vehicle_id(reply: str) -> str:
    return _extract_first(r"\bvehicle_id=(\d{1,9})\b", reply)


def _forbidden_output_patterns() -> list[tuple[str, str]]:
    return [
        ('debug_status_equals', r"\bstatus="),
        ('traceback', r"\bTraceback\b"),
        ('exception_marker', r"\[EXCEPTION\]"),
        ('python_repr_error', r"\b(ValueError|KeyError|TypeError|AttributeError|AssertionError)\b"),
        ('agentic_marker', r"\b(agentic|tool call|chain[- ]?of[- ]?thought)\b"),
    ]


def _assert_professional_reply(reply: str) -> list[str]:
    """Return a list of violation labels for user-visible text."""

    s = (reply or '').strip()
    if not s:
        return ['empty_reply']
    violations: list[str] = []
    for label, pat in _forbidden_output_patterns():
        try:
            if re.search(pat, s, flags=re.IGNORECASE):
                violations.append(label)
        except Exception:
            continue
    return violations


def _scenario_prompts(*, extensive: bool) -> list[str]:
    base: list[str] = [
        'hi',
        'help',
        'capabilities',
        'faq',
        'manual',
        'what is this app about',
        'guest mode',
        'my profile',
        'profile',
        'show my vehicles',
        'list my vehicles',
        'list my bookings',
        'my bookings',
        'list my rides',
        'my rides',
        'trip details',
        'chat list',
        'payment details',
        'change requests',
        'verification requests',
        'pickup code',
        'how do payments work',
        'how do notifications work',
        "why can't i book",
        "why can't i create",
        'sos',
        'cancel',
        'reset',
    ]

    # These require placeholders to be replaced during the run.
    templated: list[str] = [
        'trip details trip_id={trip_id}',
        'chat list trip_id={trip_id}',
        'payment details booking_id={booking_id}',
    ]

    if not extensive:
        return base + templated

    # 100+ unique stress prompts exercising parsers/flows.
    cities = ['vehari', 'multan', 'lahore', 'islamabad', 'karachi']
    from_to = [
        ('comsats vehari', 'multan'),
        ('vehari', 'peoples colony'),
        ('zoo road', 'khizra mosque'),
        ('multan-vehari road', 'comsats university'),
        ('railway station', 'bus stand'),
    ]
    times = ['today 5 pm', 'tomorrow 9 am', 'tomorrow 10 am', 'next monday 8:30', '2026-05-01 14:15']
    seats = ['1 seat', '2 seats', '3 seats', '4 seats']
    fares = ['fare 50', 'fare 70', 'fare 100', 'fare 150']
    extras: list[str] = []

    for c in cities:
        extras.append(f'suggest stops q={c}')
        extras.append(f'from {c} to {c}')

    for a, b in from_to:
        extras.append(f'from {a} to {b}')
        extras.append(f'book a ride from {a} to {b}')
        extras.append(f'create a ride from {a} to {b}')

    for t in times:
        extras.append(f'create a ride {t}')
        extras.append(f'book a ride {t}')

    for s in seats:
        extras.append(f'create ride {s}')
        extras.append(f'book ride {s}')

    for f in fares:
        extras.append(f'create ride {f}')
        extras.append(f'book ride {f}')

    # Cancellation / clarification behaviors.
    extras.extend(
        [
            'cancel booking',
            'cancel trip',
            'delete trip',
            'send message',
            'send message trip_id={trip_id} recipient_id=1 hello',
            'message trip_id={trip_id} recipient_id=1 hi',
            'negotiate',
            'negotiate trip_id={trip_id} booking_id={booking_id} counter fare 80',
            'round trip create ride',
            'two way trip',
            'what about that',
        ]
    )

    out = base + extras + templated
    # Deduplicate while preserving order.
    seen: set[str] = set()
    uniq: list[str] = []
    for p in out:
        k = (p or '').strip().lower()
        if not k or k in seen:
            continue
        seen.add(k)
        uniq.append(p)
    return uniq


@dataclass
class _Turn:
    user: str
    expect_any: list[str] | None = None  # regex list


@dataclass
class _Story:
    name: str
    turns: list[_Turn]


def _looks_like_question(reply: str) -> bool:
    s = (reply or '').strip()
    if not s:
        return False
    if '?' in s:
        return True
    low = s.lower()
    return any(
        p in low
        for p in {
            'which trip',
            'which booking',
            'provide trip_id',
            'provide booking_id',
            'please reply with',
            'please choose',
            'can you please',
            'what would you like',
        }
    )


def _is_access_restricted_reply(reply: str) -> bool:
    """Some users/guests are legitimately blocked from protected operations.

    In regression audit we treat these as acceptable outcomes for protected intents,
    otherwise restricted accounts create false-negative ASSERT_FAIL noise.
    """

    low = (reply or '').strip().lower()
    if not low:
        return False
    return any(
        k in low
        for k in {
            'guests cannot access',
            'guest cannot access',
            'account is not verified',
            'not verified yet',
            'complete verification',
            'verification was rejected',
            'account verification was rejected',
            'account is banned',
            'you cannot perform this operation',
        }
    )


def _stories(*, count: int = 120) -> list[_Story]:
    """Generate many multi-turn conversations to test two-way UX.

    Notes:
    - We keep scenarios read-only / support-safe. Actions blocked by support_only are still valuable to test.
    - Templated IDs are resolved at runtime from earlier tool outputs.
    """

    base: list[_Story] = [
        _Story(
            name='profile_story',
            turns=[
                _Turn('hi', expect_any=[r'Hi', r'hello']),
                _Turn('profile', expect_any=[r'Profile:']),
            ],
        ),
        _Story(
            name='vehicles_story',
            turns=[
                _Turn('show my vehicles', expect_any=[r'Here are your vehicles:']),
                _Turn('list my vehicles', expect_any=[r'Here are your vehicles:']),
            ],
        ),
        _Story(
            name='bookings_story',
            turns=[
                _Turn('list my bookings', expect_any=[r'Here are your bookings:|no bookings|couldn\'t find']),
                _Turn('payment details', expect_any=[r'Provide booking_id|booking payment details']),
            ],
        ),
        _Story(
            name='trip_detail_story_missing_id',
            turns=[
                _Turn('trip details', expect_any=[r'Provide trip_id|Which trip details']),
            ],
        ),
        _Story(
            name='chat_story_missing_id',
            turns=[
                _Turn('chat list', expect_any=[r'Provide trip_id|Which trip chat']),
            ],
        ),
        _Story(
            name='manual_help_story',
            turns=[
                _Turn('manual', expect_any=[r'User manual topics']),
                _Turn('help', expect_any=[r'You can talk naturally']),
                _Turn('capabilities', expect_any=[r'I can help you with']),
            ],
        ),
    ]

    # Strictly read-only story generation.
    # We exercise:
    # - stop suggestions
    # - route search + ambiguity selection
    # - listing/profile
    # - clarifying questions for missing trip_id/booking_id
    pairs = [
        ('zoo road', 'khizra mosque'),
        ('vehari', 'peoples colony'),
        ('comsats vehari', 'multan'),
        ('railway station', 'bus stand'),
        ('islamabad', 'islamabad'),
    ]
    suggest_q = ['vehari', 'multan', 'lahore', 'islamabad', 'karachi']

    gen: list[_Story] = []
    idx = 0
    for q in suggest_q:
        idx += 1
        gen.append(
            _Story(
                name=f'suggest_story_{idx}',
                turns=[
                    _Turn(f'suggest stops q={q}'),
                    _Turn('cancel', expect_any=[r'cancel|cancelled|okay']),
                ],
            )
        )

    for a, b in pairs:
        idx += 1
        gen.append(
            _Story(
                name=f'route_story_{idx}',
                turns=[
                    _Turn(f'from {a} to {b}'),
                    # If ambiguity is returned, replying with a number should be accepted.
                    _Turn('1'),
                    _Turn('cancel', expect_any=[r'cancel|cancelled|okay']),
                ],
            )
        )

    # Dependent-ID stories (only run templated turns once ids are known).
    for _ in range(40):
        idx += 1
        gen.append(
            _Story(
                name=f'id_dependent_story_{idx}',
                turns=[
                    _Turn('list my bookings'),
                    _Turn('list my rides'),
                    _Turn('trip details trip_id={trip_id}'),
                    _Turn('chat list trip_id={trip_id}'),
                    _Turn('payment details booking_id={booking_id}'),
                ],
            )
        )

    all_stories = base + gen
    return all_stories[: max(1, int(count))]


class Command(BaseCommand):
    help = "Run a realtime chatbot regression and store transcript to a .txt file for audits."

    def add_arguments(self, parser) -> None:
        parser.add_argument(
            "--user-id",
            dest="user_id",
            default=0,
            type=int,
            help="User id to run the audit as. If provided, bypasses login (useful when /login endpoints are missing).",
        )
        parser.add_argument(
            "--user-ids",
            dest="user_ids",
            default="",
            help="Comma-separated user ids to run audits for (e.g. 13,14,15,16).",
        )
        parser.add_argument(
            "--include-guest",
            dest="include_guest",
            action="store_true",
            help="Also run an audit as a guest user (negative user id).",
        )
        parser.add_argument(
            "--extensive",
            dest="extensive",
            action="store_true",
            help="Run 100+ unique complex scenario prompts to test chatbot features.",
        )
        parser.add_argument(
            "--story-mode",
            dest="story_mode",
            action="store_true",
            help="Run story-based multi-turn scenarios (tests two-way communication like ChatGPT).",
        )
        parser.add_argument(
            "--story-count",
            dest="story_count",
            default=120,
            type=int,
            help="Number of stories to run in story-mode (default 120).",
        )
        parser.add_argument(
            "--reset-between-stories",
            dest="reset_between_stories",
            action="store_true",
            help="Reset flow and in-memory chat history between stories (prevents cross-story contamination).",
        )
        parser.add_argument(
            "--no-fail-exit",
            dest="no_fail_exit",
            action="store_true",
            help="Do not exit with non-zero status when failures occur (still records failures in transcript).",
        )
        parser.add_argument(
            "--out",
            dest="out",
            default="",
            help="Output file path. If omitted, a timestamped file is created under backend/audits/.",
        )
        parser.add_argument(
            "--label",
            dest="label",
            default="",
            help="Optional label used in the output filename.",
        )

    def handle(self, *args, **options):
        base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
        audits_dir = os.path.join(base_dir, "audits")
        os.makedirs(audits_dir, exist_ok=True)

        out_path = str(options.get("out") or "").strip()
        label = _safe_filename(str(options.get("label") or "").strip())
        if not out_path:
            ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            name = f"chatbot_regression_{ts}{'_' + label if label else ''}.txt"
            out_path = os.path.join(audits_dir, name)

        raw_ids = str(options.get('user_ids') or '').strip()
        user_ids: list[int] = []
        if raw_ids:
            for part in raw_ids.split(','):
                part = (part or '').strip()
                if not part:
                    continue
                try:
                    user_ids.append(int(part))
                except Exception:
                    continue
        if not user_ids:
            uid = int(options.get('user_id') or 0)
            if uid:
                user_ids = [uid]

        if bool(options.get('include_guest')):
            user_ids.append(-1)

        if not user_ids:
            raise SystemExit('No user ids provided. Use --user-id or --user-ids or --include-guest.')

        extensive = bool(options.get('extensive'))
        story_mode = bool(options.get('story_mode'))
        prompts = _scenario_prompts(extensive=extensive)
        stories = _stories(count=int(options.get('story_count') or 120)) if story_mode else []

        total_ok = 0
        total_fail = 0

        with open(out_path, 'w', encoding='utf-8') as fp:
            _write_line(fp, f"timestamp: {datetime.now().isoformat(timespec='seconds')}")
            _write_line(fp, f"users: {','.join([str(x) for x in user_ids])}")
            _write_line(fp, f"extensive: {'YES' if extensive else 'NO'}")
            _write_line(fp, f"story_mode: {'YES' if story_mode else 'NO'}")
            _write_line(fp, '')

            for uid in user_ids:
                if uid < 0:
                    user = {'id': uid, 'name': 'Guest'}
                    set_current_user(user)
                    ctx = BotContext(user_id=uid)
                else:
                    # Force per-user context (setdefault would keep the first user forever).
                    os.environ['LETS_GO_BOT_USER_ID'] = str(uid)
                    user, err = api_login(BOT_EMAIL, BOT_PASSWORD)
                    if err:
                        raise SystemExit(f"Login failed for user_id={uid}: {err}")
                    set_current_user(user)
                    ctx = BotContext(user_id=int(user.get('id') or uid))

                # Reset per-user state so previous user's flow/history doesn't leak.
                try:
                    st0 = get_state(int(ctx.user_id))
                    reset_flow(st0)
                    st0.pending_action = None
                    st0.awaiting_field = None
                    st0.active_flow = None
                except Exception:
                    pass

                _write_line(fp, '============================================================')
                _write_line(fp, f"user_id: {int(ctx.user_id)}")
                _write_line(fp, f"user_name: {str((user or {}).get('name') or '').strip()}")
                _write_line(fp, '')

                # Cache extracted IDs to make dependent scenarios real.
                vars: dict[str, str] = {'trip_id': '', 'booking_id': '', 'vehicle_id': ''}
                ok = 0
                fail = 0

                def _reset_story_state() -> None:
                    try:
                        st = get_state(int(ctx.user_id))
                        reset_flow(st)
                        st.pending_action = None
                        st.awaiting_field = None
                        st.active_flow = None
                        st.llm_last_text = None
                        st.llm_last_extract = {}
                        # Keep summary/preferences to test memory, but avoid mixing per-story chat history.
                        st.history = []
                    except Exception:
                        return

                reset_between = bool(options.get('reset_between_stories'))
                no_fail_exit = bool(options.get('no_fail_exit'))

                if story_mode:
                    for story in stories:
                        if reset_between:
                            _reset_story_state()
                        _write_line(fp, f"--- story: {story.name} ---")
                        for turn in (story.turns or []):
                            q0 = (turn.user or '').strip()
                            if not q0:
                                continue
                            # Skip templated turns if missing.
                            if '{trip_id}' in q0 and not vars.get('trip_id'):
                                continue
                            if '{booking_id}' in q0 and not vars.get('booking_id'):
                                continue
                            if '{vehicle_id}' in q0 and not vars.get('vehicle_id'):
                                continue
                            q = q0.format(
                                trip_id=vars.get('trip_id') or '',
                                booking_id=vars.get('booking_id') or '',
                                vehicle_id=vars.get('vehicle_id') or '',
                            ).strip()
                            _write_line(fp, f"You: {q}")
                            try:
                                reply = _ask(ctx, q)
                                ok += 1
                            except Exception as e:
                                reply = f"[EXCEPTION] {repr(e)}"
                                fail += 1
                            _write_line(fp, f"Bot: {reply}")
                            _write_line(fp, '')

                            violations = _assert_professional_reply(reply)
                            if violations:
                                _write_line(fp, f"[ASSERT_FAIL] reply contained forbidden output: {violations}")
                                fail += 1

                            if not vars.get('vehicle_id'):
                                vars['vehicle_id'] = _extract_vehicle_id(reply)
                            if not vars.get('booking_id'):
                                vars['booking_id'] = _extract_booking_id(reply)
                            if not vars.get('trip_id'):
                                vars['trip_id'] = _extract_trip_id(reply)

                            # Simple assertions: if expect_any provided, ensure at least one regex matches.
                            if turn.expect_any:
                                matched = False
                                for pat in turn.expect_any:
                                    try:
                                        if re.search(pat, reply or '', flags=re.IGNORECASE):
                                            matched = True
                                            break
                                    except Exception:
                                        continue
                                if not matched and _is_access_restricted_reply(reply):
                                    matched = True
                                if not matched:
                                    _write_line(fp, f"[ASSERT_FAIL] expected one of: {turn.expect_any}")
                                    # Don't count as exception fail, but record as fail.
                                    fail += 1

                        _write_line(fp, '')
                else:

                    for raw in prompts:
                        q = str(raw or '').strip()
                        # Skip templated prompts until we have values.
                        if '{trip_id}' in q and not vars.get('trip_id'):
                            continue
                        if '{booking_id}' in q and not vars.get('booking_id'):
                            continue
                        if '{vehicle_id}' in q and not vars.get('vehicle_id'):
                            continue

                        q = q.format(
                            trip_id=vars.get('trip_id') or '',
                            booking_id=vars.get('booking_id') or '',
                            vehicle_id=vars.get('vehicle_id') or '',
                        ).strip()

                        _write_line(fp, f"You: {q}")
                        try:
                            reply = _ask(ctx, q)
                            ok += 1
                        except Exception as e:
                            reply = f"[EXCEPTION] {repr(e)}"
                            fail += 1
                        _write_line(fp, f"Bot: {reply}")
                        _write_line(fp, '')

                        violations = _assert_professional_reply(reply)
                        if violations:
                            _write_line(fp, f"[ASSERT_FAIL] reply contained forbidden output: {violations}")
                            fail += 1

                        if not vars.get('vehicle_id'):
                            vars['vehicle_id'] = _extract_vehicle_id(reply)
                        if not vars.get('booking_id'):
                            vars['booking_id'] = _extract_booking_id(reply)
                        if not vars.get('trip_id'):
                            vars['trip_id'] = _extract_trip_id(reply)

                total_ok += ok
                total_fail += fail
                _write_line(fp, f"[summary] ok={ok} fail={fail} trip_id={vars.get('trip_id') or '-'} booking_id={vars.get('booking_id') or '-'}")
                _write_line(fp, '')

            _write_line(fp, '============================================================')
            _write_line(fp, f"TOTAL ok={total_ok} fail={total_fail}")

        self.stdout.write(self.style.SUCCESS(f"Audit saved: {out_path}"))

        if (not bool(options.get('no_fail_exit'))) and total_fail:
            raise SystemExit(f"chatbot_regression_audit failed: total_fail={total_fail}. See: {out_path}")

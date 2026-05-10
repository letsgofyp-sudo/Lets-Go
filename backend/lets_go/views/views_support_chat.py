from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
import os
from datetime import datetime
from django.utils import timezone
from django.db import transaction
from django.db.models import Max
import json

from ..models import GuestUser, UsersData, SupportThread, SupportMessage
from .views_notifications import send_ride_notification_async, register_fcm_token_with_supabase_async
from .views_notifications import flush_offline_notification_queue_async
from ..utils.chatbot.engine_impl import handle_message
from ..utils.chatbot.common.helpers import normalize_text
from ..utils.chatbot.core import BotContext, set_current_user


def _to_int(value):
    try:
        return int(value)
    except Exception:
        return None


def _parse_json_body(request):
    try:
        return json.loads(request.body or b'{}')
    except Exception:
        return {}


def _serialize_support_message(m: SupportMessage):
    return {
        'id': m.id,
        'thread_id': m.thread_id,
        'thread_type': m.thread.thread_type,
        'sender_type': m.sender_type,
        'sender_user_id': m.sender_user_id,
        'message_text': m.message_text,
        'is_read_by_other': bool(m.sender_type == 'USER' and m.id <= getattr(m.thread, 'admin_last_seen_id', 0)),
        'created_at': m.created_at.isoformat() if getattr(m, 'created_at', None) else timezone.now().isoformat(),
    }


def _ensure_thread(user: UsersData | None, guest: GuestUser | None, thread_type: str) -> SupportThread:
    if user is None and guest is None:
        raise ValueError('Either user or guest is required')
    if user is not None and guest is not None:
        raise ValueError('Only one of user or guest is allowed')

    thread, _ = SupportThread.objects.get_or_create(
        user=user,
        guest=guest,
        thread_type=thread_type,
        defaults={'last_message_at': timezone.now()},
    )
    return thread


def _resolve_owner_from_query(request):
    user_id = _to_int(request.GET.get('user_id'))
    guest_user_id = _to_int(request.GET.get('guest_user_id'))

    if user_id:
        user = UsersData.objects.filter(id=user_id).first()
        if user is None:
            return None, None, JsonResponse({'success': False, 'error': 'User not found'}, status=404)
        return user, None, None

    if guest_user_id:
        guest = GuestUser.objects.filter(id=guest_user_id).first()
        if guest is None:
            return None, None, JsonResponse({'success': False, 'error': 'Guest not found'}, status=404)
        return None, guest, None

    return None, None, JsonResponse({'success': False, 'error': 'user_id or guest_user_id is required'}, status=400)


def _resolve_owner_from_body(data: dict):
    user_id = _to_int(data.get('user_id'))
    guest_user_id = _to_int(data.get('guest_user_id'))

    if user_id:
        user = UsersData.objects.filter(id=user_id).first()
        if user is None:
            return None, None, JsonResponse({'success': False, 'error': 'User not found'}, status=404)
        return user, None, None

    if guest_user_id:
        guest = GuestUser.objects.filter(id=guest_user_id).first()
        if guest is None:
            return None, None, JsonResponse({'success': False, 'error': 'Guest not found'}, status=404)
        return None, guest, None

    return None, None, JsonResponse({'success': False, 'error': 'user_id or guest_user_id is required'}, status=400)


def _sync_guest_fcm(guest: GuestUser | None, fcm_token: str | None):
    if guest is None:
        return
    token = (fcm_token or '').strip()
    if not token or token == 'NO_FCM_TOKEN':
        return
    if guest.fcm_token != token:
        GuestUser.objects.filter(id=guest.id).update(fcm_token=token)
    try:
        register_fcm_token_with_supabase_async(f'guest:{guest.id}', token)
    except Exception:
        pass

    try:
        flush_offline_notification_queue_async(f'guest:{guest.id}')
    except Exception:
        pass


@csrf_exempt
def support_guest(request):
    if request.method != 'POST':
        return JsonResponse({'success': False, 'error': 'Invalid request method'}, status=405)

    data = _parse_json_body(request)
    existing_guest_id = _to_int(data.get('guest_user_id'))
    fcm_token = (data.get('fcm_token') or '').strip()

    if existing_guest_id:
        guest = GuestUser.objects.filter(id=existing_guest_id).first()
        if guest is None:
            return JsonResponse({'success': False, 'error': 'Guest not found'}, status=404)
        _sync_guest_fcm(guest, fcm_token)
        return JsonResponse({
            'success': True,
            'guest_user_id': guest.id,
            'guest_username': guest.username,
        })

    with transaction.atomic():
        mx = GuestUser.objects.select_for_update().aggregate(mx=Max('guest_number')).get('mx') or 0
        next_num = int(mx) + 1
        username = f'guest_{next_num}'
        guest = GuestUser.objects.create(
            guest_number=next_num,
            username=username,
            fcm_token=fcm_token if fcm_token and fcm_token != 'NO_FCM_TOKEN' else None,
        )

    _sync_guest_fcm(guest, fcm_token)
    return JsonResponse({
        'success': True,
        'guest_user_id': guest.id,
        'guest_username': guest.username,
    }, status=201)


@csrf_exempt
def clear_support_chat(request):
    if request.method != 'POST':
        return JsonResponse({'success': False, 'error': 'Invalid request method'}, status=405)

    data = _parse_json_body(request)
    user, guest, err = _resolve_owner_from_body(data)
    if err is not None:
        return err

    thread_type = (data.get('thread_type') or 'BOT').strip().upper()
    if thread_type not in {'BOT', 'ADMIN', 'ALL'}:
        thread_type = 'BOT'

    uid = int(getattr(user, 'id', 0) or 0)
    gid = int(getattr(guest, 'id', 0) or 0)
    session_user_id = uid if uid > 0 else (-gid if gid > 0 else 0)

    with transaction.atomic():
        types = ['BOT', 'ADMIN'] if thread_type == 'ALL' else [thread_type]
        for t in types:
            th = SupportThread.objects.filter(user=user, guest=guest, thread_type=t).first()
            if th is None:
                continue
            SupportMessage.objects.filter(thread=th).delete()
            th.user_last_seen_id = 0
            th.admin_last_seen_id = 0
            th.last_message_at = timezone.now()
            th.save(update_fields=['user_last_seen_id', 'admin_last_seen_id', 'last_message_at', 'updated_at'])

        try:
            from ..utils.chatbot.core import _SESSIONS

            if session_user_id:
                _SESSIONS.pop(int(session_user_id), None)
        except Exception:
            pass

        try:
            from ..models import ChatbotMemory

            if uid > 0:
                ChatbotMemory.objects.filter(user_id=uid).update(summary='', preferences={})
            elif gid > 0:
                ChatbotMemory.objects.filter(guest_id=gid).update(summary='', preferences={})
        except Exception:
            pass

    return JsonResponse({'success': True})


def _bot_reply_text(user_text: str) -> str:
    t = (user_text or '').strip()
    if not t:
        return "Hi! How can I help you?"
    low = t.lower()
    if 'fare' in low or 'price' in low:
        return 'Fares depend on route distance and stops. Open a trip to see the stop-by-stop breakdown.'
    if 'cancel' in low:
        return 'To cancel, open your booking/trip details and tap Cancel. If you cannot cancel, contact admin support.'
    if 'blocked' in low:
        return 'If you are blocked by a driver, you won’t be able to request that ride. You can also manage blocklist in your profile.'
    return "Thanks! I understood your message. If you need human help, switch to the Admin chat tab."


def _chatbot_reply_text(user: UsersData | None, guest: GuestUser | None, message_text: str) -> str:
    t = normalize_text(message_text)
    debug_enabled = str(os.getenv('LETS_GO_BOT_DEBUG', '') or '').strip().lower() in {'1', 'true', 'yes', 'on'}
    def _dbg(event: str, payload: dict | None = None) -> None:
        if not debug_enabled:
            return
        try:
            ts = datetime.now().strftime('%H:%M:%S')
            base = f"[support-bot {ts}] {event}"
            if payload:
                print(base + " | " + ", ".join(f"{k}={payload[k]!r}" for k in sorted(payload.keys())), flush=True)
            else:
                print(base, flush=True)
        except Exception:
            return

    if user is not None:
        try:
            set_current_user({'name': getattr(user, 'name', '')})
        except Exception:
            set_current_user({})
        ctx = BotContext(user_id=int(user.id))
    else:
        set_current_user({})
        gid = int(getattr(guest, 'id', 0) or 0)
        ctx = BotContext(user_id=(-gid if gid > 0 else 0))
    _dbg('ctx', {
        'user_id': getattr(user, 'id', None) if user is not None else None,
        'guest_id': getattr(guest, 'id', None) if guest is not None else None,
        'ctx_user_id': getattr(ctx, 'user_id', None),
        'text': (message_text or '')[:240],
    })
    out = handle_message(ctx, message_text)
    _dbg('reply', {
        'reply_len': len(out or ''),
        'reply_preview': (out or '')[:240],
    })
    return out


@csrf_exempt
def view_bot(request):
    if request.method == 'GET':
        since_id = _to_int(request.GET.get('since_id')) or 0
        user, guest, err = _resolve_owner_from_query(request)
        if err is not None:
            return err

        thread = _ensure_thread(user, guest, 'BOT')

        latest_id = SupportMessage.objects.filter(thread=thread).aggregate(mx=Max('id')).get('mx') or 0
        if latest_id and thread.user_last_seen_id != latest_id:
            thread.user_last_seen_id = latest_id
            thread.save(update_fields=['user_last_seen_id', 'updated_at'])

        msgs = (
            SupportMessage.objects
            .select_related('thread')
            .filter(thread=thread)
            .filter(id__gt=since_id)
            .order_by('created_at')
        )
        return JsonResponse({
            'success': True,
            'thread_id': thread.id,
            'admin_last_seen_id': getattr(thread, 'admin_last_seen_id', 0),
            'user_last_seen_id': getattr(thread, 'user_last_seen_id', 0),
            'messages': [_serialize_support_message(m) for m in msgs],
        })

    if request.method == 'POST':
        data = _parse_json_body(request)
        message_text = (data.get('message_text') or '').strip()
        if not message_text:
            return JsonResponse({'success': False, 'error': 'message_text is required'}, status=400)

        debug_enabled = str(os.getenv('LETS_GO_BOT_DEBUG', '') or '').strip().lower() in {'1', 'true', 'yes', 'on'}
        def _dbg(event: str, payload: dict | None = None) -> None:
            if not debug_enabled:
                return
            try:
                ts = datetime.now().strftime('%H:%M:%S')
                base = f"[support-bot {ts}] {event}"
                if payload:
                    print(base + " | " + ", ".join(f"{k}={payload[k]!r}" for k in sorted(payload.keys())), flush=True)
                else:
                    print(base, flush=True)
            except Exception:
                return

        user, guest, err = _resolve_owner_from_body(data)
        if err is not None:
            return err
        _sync_guest_fcm(guest, (data.get('fcm_token') or '').strip())

        _dbg('post', {
            'user_id': getattr(user, 'id', None) if user is not None else None,
            'guest_id': getattr(guest, 'id', None) if guest is not None else None,
            'message_text': message_text[:240],
        })

        thread = _ensure_thread(user, guest, 'BOT')

        user_msg = SupportMessage.objects.create(
            thread=thread,
            sender_type='USER',
            sender_user=user,
            message_text=message_text,
        )

        bot_msg = SupportMessage.objects.create(
            thread=thread,
            sender_type='BOT',
            sender_user=None,
            message_text=_chatbot_reply_text(user, guest, message_text),
        )

        thread.last_message_at = timezone.now()
        thread.save(update_fields=['last_message_at', 'updated_at'])

        return JsonResponse({
            'success': True,
            'thread_id': thread.id,
            'messages': [_serialize_support_message(user_msg), _serialize_support_message(bot_msg)],
        }, status=201)

    return JsonResponse({'success': False, 'error': 'Invalid request method'}, status=405)


@csrf_exempt
def view_adminchat(request):
    if request.method == 'GET':
        since_id = _to_int(request.GET.get('since_id')) or 0
        user, guest, err = _resolve_owner_from_query(request)
        if err is not None:
            return err

        thread = _ensure_thread(user, guest, 'ADMIN')

        latest_id = SupportMessage.objects.filter(thread=thread).aggregate(mx=Max('id')).get('mx') or 0
        if latest_id and thread.user_last_seen_id != latest_id:
            thread.user_last_seen_id = latest_id
            thread.save(update_fields=['user_last_seen_id', 'updated_at'])

        msgs = (
            SupportMessage.objects
            .select_related('thread')
            .filter(thread=thread)
            .filter(id__gt=since_id)
            .order_by('created_at')
        )
        return JsonResponse({
            'success': True,
            'thread_id': thread.id,
            'admin_last_seen_id': getattr(thread, 'admin_last_seen_id', 0),
            'user_last_seen_id': getattr(thread, 'user_last_seen_id', 0),
            'messages': [_serialize_support_message(m) for m in msgs],
        })

    if request.method == 'POST':
        data = _parse_json_body(request)
        message_text = (data.get('message_text') or '').strip()
        if not message_text:
            return JsonResponse({'success': False, 'error': 'message_text is required'}, status=400)

        user, guest, err = _resolve_owner_from_body(data)
        if err is not None:
            return err
        _sync_guest_fcm(guest, (data.get('fcm_token') or '').strip())

        thread = _ensure_thread(user, guest, 'ADMIN')

        msg = SupportMessage.objects.create(
            thread=thread,
            sender_type='USER',
            sender_user=user,
            message_text=message_text,
        )

        thread.last_message_at = timezone.now()
        thread.save(update_fields=['last_message_at', 'updated_at'])

        return JsonResponse({
            'success': True,
            'thread_id': thread.id,
            'message': _serialize_support_message(msg),
        }, status=201)

    return JsonResponse({'success': False, 'error': 'Invalid request method'}, status=405)

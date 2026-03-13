from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from django.contrib.auth.decorators import login_required
from django.views.decorators.csrf import ensure_csrf_cookie
from django.db import close_old_connections
from django.utils import timezone
import json
import os
import logging
import threading
import requests
from ..models.models_userdata import UsersData
from ..models.models_notifications import NotificationInbox, OfflineNotificationQueue
from ..models.models_support_chat import GuestUser
from ..constants import SUPABASE_EDGE_API_KEY


logger = logging.getLogger(__name__)
@csrf_exempt
@require_http_methods(["POST"])
def update_fcm_token(request):
    try:
        logger.debug('[update_fcm_token] Incoming request body: %s', request.body)
        data = json.loads(request.body or b"{}")
        logger.debug('[update_fcm_token] Decoded JSON: %s', data)
        user_id = data.get('user_id')
        fcm_token = data.get('fcm_token')

        logger.debug(
            '[update_fcm_token] Parsed user_id=%s (type=%s), len(fcm_token)=%s',
            user_id,
            type(user_id),
            (len(fcm_token) if fcm_token else None),
        )

        if not user_id:
            return JsonResponse({'error': 'user_id is required'}, status=400)
        if not fcm_token:
            return JsonResponse({'error': 'FCM token is required'}, status=400)

        # Special case: placeholder value from client when no real device token is available
        if fcm_token == 'NO_FCM_TOKEN':
            logger.debug('[update_fcm_token] Received NO_FCM_TOKEN placeholder; skipping DB update')
            return JsonResponse({'message': 'No-op: no real FCM token provided'}, status=200)

        try:
            try:
                UsersData.objects.filter(fcm_token=fcm_token).exclude(id=user_id).update(fcm_token=None)
            except Exception as e:
                logger.exception('[update_fcm_token][WARN] Failed to clear duplicate fcm_token from other users: %s', repr(e))

            logger.debug('[update_fcm_token] Updating fcm_token via queryset for user_id=%s', user_id)
            updated = UsersData.objects.filter(id=user_id).update(fcm_token=fcm_token)
            if updated == 0:
                return JsonResponse({'error': 'User not found'}, status=404)
            logger.debug('[update_fcm_token] Updated fcm_token for user %s', user_id)
        except Exception as e:
            logger.exception('[update_fcm_token][ERROR during update]: %s', repr(e))
            return JsonResponse({'error': str(e)}, status=500)

        try:
            register_fcm_token_with_supabase_async(f'user:{int(user_id)}', fcm_token)
        except Exception as e:
            logger.exception('[update_fcm_token][register_fcm_token_with_supabase_async][ERROR]: %s', repr(e))

        try:
            flush_offline_notification_queue_async(f'user:{int(user_id)}')
        except Exception as e:
            logger.exception('[update_fcm_token][flush_offline_notification_queue_async][ERROR]: %s', repr(e))

        return JsonResponse({'message': 'FCM token updated successfully'}, status=200)

    except UsersData.DoesNotExist:
        return JsonResponse({'error': 'User not found'}, status=404)
    except Exception as e:
        logger.exception('[update_fcm_token][OUTER][ERROR]: %s', repr(e))
        return JsonResponse({'error': str(e)}, status=500)


SUPABASE_FN_URL = (os.getenv('SUPABASE_RIDE_NOTIFICATION_URL') or '').strip()
SUPABASE_REGISTER_FCM_URL = (os.getenv('SUPABASE_REGISTER_FCM_URL') or '').strip()
SUPABASE_FN_API_KEY = SUPABASE_EDGE_API_KEY


def _persist_notification_inbox(normalized_payload: dict, push_sent: bool):
    try:
        data = normalized_payload.get('data')
        if not isinstance(data, dict):
            data = {}

        guest_user_id_raw = normalized_payload.get('guest_user_id') or data.get('guest_user_id')
        try:
            guest_user_id = int(guest_user_id_raw) if guest_user_id_raw not in (None, '', 'None') else None
        except Exception:
            guest_user_id = None

        recipient_id = normalized_payload.get('recipient_id')
        try:
            user_id = int(recipient_id) if recipient_id not in (None, '', 'None') else None
        except Exception:
            user_id = None

        if user_id:
            recipient_key = f'user:{user_id}'
        elif guest_user_id:
            recipient_key = f'guest:{guest_user_id}'
        else:
            return None
        ntype = (data.get('type') or normalized_payload.get('type') or 'generic').__str__()

        guest_obj_id = None
        if guest_user_id:
            guest_obj_id = guest_user_id

        n = NotificationInbox.objects.create(
            recipient_key=recipient_key,
            user_id=user_id,
            guest_id=guest_obj_id,
            notification_type=str(ntype)[:64],
            title=str(normalized_payload.get('title') or '')[:200],
            body=str(normalized_payload.get('body') or ''),
            data=data,
            push_sent=bool(push_sent),
            push_sent_at=timezone.now() if push_sent else None,
        )
        return n
    except Exception as e:
        logger.exception('[NotificationInbox][ERROR]: %s', str(e))
        return None


def _queue_offline_notification(normalized_payload: dict):
    try:
        data = normalized_payload.get('data')
        if not isinstance(data, dict):
            data = {}

        guest_user_id_raw = normalized_payload.get('guest_user_id') or data.get('guest_user_id')
        try:
            guest_user_id = int(guest_user_id_raw) if guest_user_id_raw not in (None, '', 'None') else None
        except Exception:
            guest_user_id = None

        recipient_id = normalized_payload.get('recipient_id')
        try:
            user_id = int(recipient_id) if recipient_id not in (None, '', 'None') else None
        except Exception:
            user_id = None

        if user_id:
            recipient_key = f'user:{user_id}'
        elif guest_user_id:
            recipient_key = f'guest:{guest_user_id}'
        else:
            return

        OfflineNotificationQueue.objects.create(
            recipient_key=recipient_key,
            user_id=user_id,
            guest_id=guest_user_id,
            is_delivered=False,
            created_at=timezone.now(),
            payload=normalized_payload,
        )
    except Exception as e:
        logger.exception('[OfflineNotificationQueue][ERROR]: %s', str(e))


def flush_offline_notification_queue_async(recipient_key: str, limit: int = 25):
    def _worker():
        close_old_connections()
        try:
            if not SUPABASE_FN_API_KEY:
                return
            if not recipient_key:
                return

            def _latest_fcm_token_for_recipient(rkey: str) -> str | None:
                try:
                    if rkey.startswith('user:'):
                        uid = int(rkey.split(':', 1)[1])
                        u = UsersData.objects.filter(id=uid).only('id', 'fcm_token').first()
                        token = getattr(u, 'fcm_token', None) if u else None
                        return str(token).strip() if token else None
                    if rkey.startswith('guest:'):
                        gid = int(rkey.split(':', 1)[1])
                        g = GuestUser.objects.filter(id=gid).only('id', 'fcm_token').first()
                        token = getattr(g, 'fcm_token', None) if g else None
                        return str(token).strip() if token else None
                except Exception:
                    return None
                return None

            latest_token = _latest_fcm_token_for_recipient(recipient_key)

            rows = list(
                OfflineNotificationQueue.objects
                .filter(recipient_key=recipient_key, is_delivered=False)
                .order_by('created_at', 'id')[:limit]
            )

            if not rows:
                return

            # UX: if multiple queued notifications exist, send a single summary push.
            if len(rows) > 1:
                user_id = None
                guest_user_id = None
                try:
                    if recipient_key.startswith('user:'):
                        user_id = int(recipient_key.split(':', 1)[1])
                    elif recipient_key.startswith('guest:'):
                        guest_user_id = int(recipient_key.split(':', 1)[1])
                except Exception:
                    pass
                summary_payload = {
                    'recipient_id': str(user_id or ''),
                    'user_id': str(user_id or ''),
                    'guest_user_id': str(guest_user_id or ''),
                    'title': 'Lets Go',
                    'body': f'You got {len(rows)} notifications',
                    'data': {
                        'type': 'notification_summary',
                        'count': str(len(rows)),
                        'recipient_key': str(recipient_key),
                    },
                }
                if latest_token:
                    summary_payload['fcm_token'] = latest_token
                try:
                    resp = requests.post(
                        SUPABASE_FN_URL,
                        headers={
                            'Content-Type': 'application/json',
                            'apikey': SUPABASE_FN_API_KEY,
                            'Authorization': f'Bearer {SUPABASE_FN_API_KEY}',
                        },
                        json=summary_payload,
                        timeout=10,
                    )
                    if 200 <= resp.status_code < 300:
                        now = timezone.now()
                        OfflineNotificationQueue.objects.filter(id__in=[r.id for r in rows]).update(
                            is_delivered=True,
                            delivered_at=now,
                        )
                        logger.debug('[flush_offline_notification_queue_async] delivered_summary=%s recipient_key=%s', len(rows), recipient_key)
                    return
                except Exception as e:
                    logger.exception('[flush_offline_notification_queue_async][summary_send_error]: %s', str(e))
                    return

            # Single row: send it directly
            row = rows[0]
            payload = row.payload if isinstance(row.payload, dict) else {}
            if not payload:
                row.is_delivered = True
                row.delivered_at = timezone.now()
                row.save(update_fields=['is_delivered', 'delivered_at'])
                return

            # Always prefer the latest token (old tokens in queued payloads may no longer work).
            if latest_token:
                payload['fcm_token'] = latest_token
            try:
                resp = requests.post(
                    SUPABASE_FN_URL,
                    headers={
                        'Content-Type': 'application/json',
                        'apikey': SUPABASE_FN_API_KEY,
                        'Authorization': f'Bearer {SUPABASE_FN_API_KEY}',
                    },
                    json=payload,
                    timeout=10,
                )
                if 200 <= resp.status_code < 300:
                    row.is_delivered = True
                    row.delivered_at = timezone.now()
                    row.save(update_fields=['is_delivered', 'delivered_at'])
                    logger.debug('[flush_offline_notification_queue_async] delivered=1 recipient_key=%s', recipient_key)
            except Exception as e:
                logger.exception('[flush_offline_notification_queue_async][send_error]: %s', str(e))
        except Exception as e:
            logger.exception('[flush_offline_notification_queue_async][ERROR]: %s', str(e))
        finally:
            close_old_connections()

    threading.Thread(target=_worker, daemon=True).start()


def _normalize_ride_notification_payload(payload: dict) -> dict:
    if not isinstance(payload, dict):
        return {}

    recipient_id = payload.get('recipient_id')
    if recipient_id is None:
        recipient_id = payload.get('user_id')
    if recipient_id is None:
        recipient_id = payload.get('driver_id')

    sender_id = payload.get('sender_id')
    if sender_id is None:
        sender_id = payload.get('driver_id')

    def _to_str(v):
        if v is None:
            return ''
        try:
            return str(v)
        except Exception:
            return ''

    data = payload.get('data')
    if not isinstance(data, dict):
        data = {}

    # Ensure all data payload values are strings (required by FCM data payload)
    safe_data = {}
    for k, v in data.items():
        try:
            safe_key = str(k)
        except Exception:
            continue
        safe_data[safe_key] = _to_str(v)

    # Ensure data.type exists if provided at top-level (compat)
    if not safe_data.get('type'):
        if payload.get('type') is not None:
            safe_data['type'] = _to_str(payload.get('type'))
# for testing
    # Ensure sender_type exists for clients (Flutter) to reliably decide which avatar/icon to show.
    # Keep it conservative: do not overwrite if already provided by caller.
    if not safe_data.get('sender_type'):
        ntype = (safe_data.get('type') or '').strip().lower()
        sender_role = (safe_data.get('sender_role') or '').strip().lower()
        derived = ''
        if ntype in {'support_admin', 'user_status_updated', 'change_request_reviewed'}:
            derived = 'admin'
        elif ntype in {'support_bot', 'notification_summary'}:
            derived = 'system'
        elif sender_role in {'driver', 'passenger', 'user', 'guest'}:
            derived = sender_role
        else:
            # If we have a non-empty sender_id, treat it as a user-initiated notification.
            try:
                derived = 'user' if str(sender_id or '').strip() not in ('', '0', 'None') else 'system'
            except Exception:
                derived = 'system'
        safe_data['sender_type'] = _to_str(derived)

 # for testing   
    normalized = dict(payload)
    normalized['title'] = _to_str(normalized.get('title'))
    normalized['body'] = _to_str(normalized.get('body'))
    normalized['data'] = safe_data

    # Ensure recipient identity hints are in data for Edge Function.
    guest_user_id = payload.get('guest_user_id')
    if guest_user_id is not None and not safe_data.get('guest_user_id'):
        safe_data['guest_user_id'] = _to_str(guest_user_id)
    if payload.get('recipient_key') is not None and not safe_data.get('recipient_key'):
        safe_data['recipient_key'] = _to_str(payload.get('recipient_key'))

    normalized['recipient_id'] = _to_str(recipient_id)
    normalized['user_id'] = _to_str(recipient_id)
    normalized['sender_id'] = _to_str(sender_id)
    # Keep driver_id populated for legacy code; prefer explicit sender_id for chat.
    normalized['driver_id'] = _to_str(sender_id)

    return normalized


def send_ride_notification_async(payload: dict):
    """Fire-and-forget call to Supabase Edge Function for ride notifications.

    This must never raise back into the HTTP view; all errors are logged only.
    """

    def _worker():
        close_old_connections()
        try:
            if not SUPABASE_FN_API_KEY:
                logger.debug('[send_ride_notification_async] Missing SUPABASE_EDGE_API_KEY; skipping notification')
                normalized_payload = _normalize_ride_notification_payload(payload)
                _persist_notification_inbox(normalized_payload, push_sent=False)
                _queue_offline_notification(normalized_payload)
                return
            url = SUPABASE_FN_URL
            normalized_payload = _normalize_ride_notification_payload(payload)

            # If this targets a guest user, best-effort include the guest's FCM token
            # so the Edge Function can send without querying Django DB.
            try:
                data = normalized_payload.get('data')
                if not isinstance(data, dict):
                    data = {}
                guest_user_id_raw = normalized_payload.get('guest_user_id') or data.get('guest_user_id')
                guest_user_id = int(guest_user_id_raw) if guest_user_id_raw not in (None, '', 'None') else None
                if guest_user_id and not normalized_payload.get('fcm_token'):
                    guest = GuestUser.objects.filter(id=guest_user_id).only('id', 'fcm_token').first()
                    if guest and getattr(guest, 'fcm_token', None):
                        normalized_payload['fcm_token'] = str(guest.fcm_token)
                        normalized_payload['guest_user_id'] = str(guest_user_id)
                        if not normalized_payload.get('recipient_key'):
                            normalized_payload['recipient_key'] = f'guest:{guest_user_id}'
            except Exception:
                pass

            logger.debug('[send_ride_notification_async] invoking Edge Function at %s with payload: %s', url, normalized_payload)
            resp = requests.post(
                url,
                headers={
                    'Content-Type': 'application/json',
                    'apikey': SUPABASE_FN_API_KEY,
                    'Authorization': f'Bearer {SUPABASE_FN_API_KEY}',
                },
                json=normalized_payload,
                # Slightly higher timeout to reduce spurious read timeouts in logs
                timeout=10,
            )
            logger.debug('[send_ride_notification_async] status=%s body_prefix=%s', resp.status_code, (resp.text or '')[:200])

            ok = 200 <= resp.status_code < 300
            _persist_notification_inbox(normalized_payload, push_sent=ok)
            if not ok:
                _queue_offline_notification(normalized_payload)
        except Exception as e:
            logger.exception('[send_ride_notification_async][ERROR]: %s', str(e))
            try:
                normalized_payload = _normalize_ride_notification_payload(payload)
                _persist_notification_inbox(normalized_payload, push_sent=False)
                _queue_offline_notification(normalized_payload)
            except Exception:
                pass
        finally:
            close_old_connections()

    threading.Thread(target=_worker, daemon=True).start()


def register_fcm_token_with_supabase_async(recipient_key: str, fcm_token: str):
    """Fire-and-forget call to Supabase Edge Function to register FCM token.

    This replaces the previous frontend call to `register-fcm-token`.
    """

    def _worker():
        try:
            if not SUPABASE_FN_API_KEY:
                logger.debug('[register_fcm_token_with_supabase_async] Missing SUPABASE_EDGE_API_KEY; skipping registration')
                return
            url = SUPABASE_REGISTER_FCM_URL
            payload = {
                'recipient_key': str(recipient_key),
                'fcm_token': fcm_token,
            }
            logger.debug('[register_fcm_token_with_supabase_async] invoking Edge Function at %s with payload: %s', url, payload)
            resp = requests.post(
                url,
                headers={
                    'Content-Type': 'application/json',
                    'apikey': SUPABASE_FN_API_KEY,
                    'Authorization': f'Bearer {SUPABASE_FN_API_KEY}',
                },
                json=payload,
                timeout=5,
            )
            logger.debug('[register_fcm_token_with_supabase_async] status=%s body_prefix=%s', resp.status_code, (resp.text or '')[:200])
        except Exception as e:
            logger.exception('[register_fcm_token_with_supabase_async][ERROR]: %s', str(e))

    threading.Thread(target=_worker, daemon=True).start()


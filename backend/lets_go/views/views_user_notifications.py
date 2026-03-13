import json

from django.http import JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods

from ..models.models_support_chat import GuestUser
from ..models.models_notifications import NotificationInbox


def _to_int(v):
    try:
        return int(v)
    except Exception:
        return None


@csrf_exempt
@require_http_methods(["GET"])
def list_notifications(request):
    user_id = _to_int(request.GET.get('user_id'))
    guest_user_id = _to_int(request.GET.get('guest_user_id'))
    if user_id:
        recipient_key = f'user:{user_id}'
    elif guest_user_id:
        recipient_key = f'guest:{guest_user_id}'
    else:
        return JsonResponse({'success': False, 'error': 'user_id or guest_user_id is required'}, status=400)

    limit = _to_int(request.GET.get('limit')) or 50
    offset = _to_int(request.GET.get('offset')) or 0

    qs = (
        NotificationInbox.objects
        .filter(recipient_key=recipient_key, is_dismissed=False)
        .order_by('-created_at')
    )

    items = []
    for n in qs[offset:offset + limit]:
        items.append({
            'id': n.id,
            'notification_type': n.notification_type,
            'title': n.title,
            'body': n.body,
            'data': n.data or {},
            'is_read': bool(n.is_read),
            'is_dismissed': bool(n.is_dismissed),
            'created_at': n.created_at.isoformat() if n.created_at else timezone.now().isoformat(),
        })

    unread_count = NotificationInbox.objects.filter(
        recipient_key=recipient_key,
        is_read=False,
        is_dismissed=False,
    ).count()

    return JsonResponse({'success': True, 'notifications': items, 'unread_count': unread_count})


@csrf_exempt
@require_http_methods(["POST"])
def mark_notification_read(request, notification_id):
    try:
        n = NotificationInbox.objects.get(id=notification_id)
    except NotificationInbox.DoesNotExist:
        return JsonResponse({'success': False, 'error': 'Notification not found'}, status=404)

    if not n.is_read:
        n.is_read = True
        n.read_at = timezone.now()
        n.save(update_fields=['is_read', 'read_at'])

    return JsonResponse({'success': True})


@csrf_exempt
@require_http_methods(["POST"])
def dismiss_notification(request, notification_id):
    try:
        n = NotificationInbox.objects.get(id=notification_id)
    except NotificationInbox.DoesNotExist:
        return JsonResponse({'success': False, 'error': 'Notification not found'}, status=404)

    if not n.is_dismissed:
        n.is_dismissed = True
        n.dismissed_at = timezone.now()
        n.save(update_fields=['is_dismissed', 'dismissed_at'])

    return JsonResponse({'success': True})


@csrf_exempt
@require_http_methods(["POST"])
def mark_all_notifications_read(request):
    try:
        payload = json.loads(request.body or b"{}")
    except Exception:
        payload = {}

    user_id = _to_int(payload.get('user_id'))
    guest_user_id = _to_int(payload.get('guest_user_id'))
    if user_id:
        recipient_key = f'user:{user_id}'
    elif guest_user_id:
        recipient_key = f'guest:{guest_user_id}'
    else:
        return JsonResponse({'success': False, 'error': 'user_id or guest_user_id is required'}, status=400)

    NotificationInbox.objects.filter(
        recipient_key=recipient_key,
        is_read=False,
        is_dismissed=False,
    ).update(is_read=True, read_at=timezone.now())

    return JsonResponse({'success': True})


@csrf_exempt
@require_http_methods(["GET"])
def notification_unread_count(request):
    user_id = _to_int(request.GET.get('user_id'))
    guest_user_id = _to_int(request.GET.get('guest_user_id'))
    if user_id:
        recipient_key = f'user:{user_id}'
    elif guest_user_id:
        recipient_key = f'guest:{guest_user_id}'
    else:
        return JsonResponse({'success': False, 'error': 'user_id or guest_user_id is required'}, status=400)

    unread_count = NotificationInbox.objects.filter(
        recipient_key=recipient_key,
        is_read=False,
        is_dismissed=False,
    ).count()

    return JsonResponse({'success': True, 'unread_count': unread_count})

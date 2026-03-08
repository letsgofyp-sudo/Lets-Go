import json

from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.db.models import Q

from ..models import UsersData, BlockedUser


def _user_brief(u: UsersData):
    return {
        'id': u.id,
        'name': u.name,
        'username': u.username,
        'profile_photo_url': getattr(u, 'profile_photo_url', None),
    }


@csrf_exempt
def list_blocked_users(request, user_id: int):
    if request.method != 'GET':
        return JsonResponse({'success': False, 'error': 'Only GET allowed'}, status=405)

    try:
        qs = (
            BlockedUser.objects
            .select_related('blocked_user')
            .filter(blocker_id=user_id)
            .order_by('-created_at')
        )
        items = []
        for r in qs:
            bu = r.blocked_user
            if not bu:
                continue
            items.append({
                'blocked_user': _user_brief(bu),
                'reason': r.reason,
                'created_at': r.created_at.isoformat() if r.created_at else None,
            })
        return JsonResponse({'success': True, 'blocked': items})
    except Exception as e:
        return JsonResponse({'success': False, 'error': str(e)}, status=500)


@csrf_exempt
def search_users_to_block(request, user_id: int):
    if request.method != 'GET':
        return JsonResponse({'success': False, 'error': 'Only GET allowed'}, status=405)

    q = (request.GET.get('q') or '').strip()
    if not q:
        return JsonResponse({'success': True, 'users': []})

    try:
        blocked_ids = list(BlockedUser.objects.filter(blocker_id=user_id).values_list('blocked_user_id', flat=True))
        qs = (
            UsersData.objects
            .filter(Q(name__icontains=q) | Q(username__icontains=q) | Q(email__icontains=q) | Q(phone_no__icontains=q))
            .exclude(id=user_id)
            .exclude(id__in=blocked_ids)
            .only('id', 'name', 'username', 'email', 'phone_no', 'profile_photo_url')
            .order_by('name')
        )

        users = []
        for u in qs[:25]:
            users.append({
                **_user_brief(u),
                'email': u.email,
                'phone_no': u.phone_no,
            })

        return JsonResponse({'success': True, 'users': users})
    except Exception as e:
        return JsonResponse({'success': False, 'error': str(e)}, status=500)


@csrf_exempt
def block_user(request, user_id: int):
    if request.method != 'POST':
        return JsonResponse({'success': False, 'error': 'Only POST allowed'}, status=405)

    try:
        data = {}
        try:
            data = json.loads(request.body.decode('utf-8')) if request.body else {}
        except Exception:
            data = {}

        blocked_user_id = data.get('blocked_user_id')
        reason = (data.get('reason') or '').strip() or None

        try:
            blocked_user_id = int(blocked_user_id)
        except Exception:
            blocked_user_id = None

        if not blocked_user_id:
            return JsonResponse({'success': False, 'error': 'blocked_user_id is required'}, status=400)
        if blocked_user_id == user_id:
            return JsonResponse({'success': False, 'error': 'You cannot block yourself'}, status=400)

        UsersData.objects.only('id').get(id=user_id)
        UsersData.objects.only('id').get(id=blocked_user_id)

        BlockedUser.objects.get_or_create(
            blocker_id=user_id,
            blocked_user_id=blocked_user_id,
            defaults={'reason': reason},
        )

        if reason is not None:
            BlockedUser.objects.filter(blocker_id=user_id, blocked_user_id=blocked_user_id).update(reason=reason)

        return JsonResponse({'success': True, 'message': 'User blocked'})
    except UsersData.DoesNotExist:
        return JsonResponse({'success': False, 'error': 'User not found'}, status=404)
    except Exception as e:
        return JsonResponse({'success': False, 'error': str(e)}, status=500)


@csrf_exempt
def unblock_user(request, user_id: int, blocked_user_id: int):
    if request.method != 'POST':
        return JsonResponse({'success': False, 'error': 'Only POST allowed'}, status=405)

    try:
        BlockedUser.objects.filter(blocker_id=user_id, blocked_user_id=blocked_user_id).delete()
        return JsonResponse({'success': True, 'message': 'User unblocked'})
    except Exception as e:
        return JsonResponse({'success': False, 'error': str(e)}, status=500)

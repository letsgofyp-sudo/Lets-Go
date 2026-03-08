from django.views.decorators.csrf import csrf_exempt
from django.http import JsonResponse
from django.utils import timezone
from django.db.models import Q
from django.db import connection
from django.db.utils import OperationalError
import json
import logging
import time

from ..models import UsersData, Trip, Booking
from ..models.models_chat import TripChatGroup, ChatMessage, MessageReadStatus
from .views_notifications import send_ride_notification_async


logger = logging.getLogger(__name__)


@csrf_exempt
def list_chat_messages(request, trip_id):
    """List chat messages for a given trip.

    Optional query params (currently unused by Flutter but supported):
      - user_id: current user (for is_read flag)
      - other_id: other party (driver/passenger) to filter 1-1 thread
      - limit: max number of messages (default 200)
    """
    if request.method != 'GET':
        return JsonResponse({'success': False, 'error': 'Only GET allowed'}, status=405)

    start_ts = time.perf_counter()

    user_id = request.GET.get('user_id')
    other_id = request.GET.get('other_id')
    limit = int(request.GET.get('limit') or 200)

    logger.debug('[list_chat_messages][START]: %s', {
        'trip_id': trip_id,
        'user_id': user_id,
        'other_id': other_id,
        'limit': limit,
    })

    try:
        trip = Trip.objects.only('id', 'trip_id').get(trip_id=trip_id)
        logger.debug('[list_chat_messages] Trip loaded: %s %s', trip.id, trip.trip_id)
    except Trip.DoesNotExist:
        return JsonResponse({'success': False, 'error': 'Trip not found'}, status=404)
    except OperationalError as e:
        logger.exception('[list_chat_messages][Trip][OperationalError]: %s', str(e))
        return JsonResponse({'success': True, 'messages': []}, status=200)

    try:
        chat_group = TripChatGroup.objects.select_related('trip').get(trip=trip)
        logger.debug('[list_chat_messages] ChatGroup loaded: %s', chat_group.id)
    except TripChatGroup.DoesNotExist:
        # No chat yet for this trip
        elapsed_ms = (time.perf_counter() - start_ts) * 1000.0
        logger.debug('[list_chat_messages] No chat group for trip; returning empty list. elapsed_ms=%s', elapsed_ms)
        return JsonResponse({'success': True, 'messages': []})
    except OperationalError as e:
        logger.exception('[list_chat_messages][ChatGroup][OperationalError]: %s', str(e))
        return JsonResponse({'success': True, 'messages': []}, status=200)

    try:
        qs = ChatMessage.objects.select_related('sender').filter(
            chat_group=chat_group,
            is_deleted=False,
        ).order_by('-created_at')
        logger.debug('[list_chat_messages] Messages loaded')
        # If both user_id and other_id provided, filter to that 1-1 thread
        if user_id and other_id:
            uid = int(user_id)
            oid = int(other_id)
            logger.debug('[list_chat_messages] Applying 1-1 filter for users: %s %s', uid, oid)
            qs = qs.filter(
                Q(sender_id=uid, message_data__recipient_id=oid)
                | Q(sender_id=oid, message_data__recipient_id=uid)
            )

        read_ids = set()
        if user_id:
            read_ids = set(
                MessageReadStatus.objects.filter(
                    user_id=user_id, message__chat_group=chat_group
                ).values_list('message_id', flat=True)
            )
            logger.debug('[list_chat_messages] Preloaded read_ids count: %s', len(read_ids))

        other_read_ids = set()
        if other_id:
            other_read_ids = set(
                MessageReadStatus.objects.filter(
                    user_id=other_id, message__chat_group=chat_group
                ).values_list('message_id', flat=True)
            )

        msgs = []
        count = 0
        for m in qs[:limit]:
            msg_data = m.message_data or {}
            recipient_id = msg_data.get('recipient_id')
            sender_role = msg_data.get('sender_role')
            is_broadcast = bool(msg_data.get('is_broadcast'))
            msgs.append({
                'id': m.id,
                'trip_id': trip.trip_id,
                'sender_id': m.sender_id,
                'sender_name': getattr(m.sender, 'name', '') or '',
                'sender_role': sender_role,
                'recipient_id': recipient_id,
                'message_text': m.message_text,
                'message_type': m.message_type,
                'is_broadcast': is_broadcast,
                'created_at': m.created_at.isoformat(),
                'is_read': m.id in read_ids,
                'is_read_by_other': (m.id in other_read_ids) if (user_id and other_id and int(user_id) == m.sender_id) else False,
            })
            count += 1

        elapsed_ms = (time.perf_counter() - start_ts) * 1000.0
        logger.debug('[list_chat_messages][END]: %s', {
            'trip_id': trip_id,
            'messages_returned': count,
            'elapsed_ms': elapsed_ms,
        })

        # Oldest-first for UI
        return JsonResponse({'success': True, 'messages': list(reversed(msgs))})
    except OperationalError as e:
        logger.exception('[list_chat_messages][Messages][OperationalError]: %s', str(e))
        return JsonResponse({'success': True, 'messages': []}, status=200)


@csrf_exempt
def list_chat_messages_updates(request, trip_id):
    """Lightweight endpoint to fetch only new messages since a given id.

    Query params:
      - since_id: return messages with id > since_id (required for polling)
      - user_id, other_id: optional 1-1 filtering, same semantics as list_chat_messages
    """
    if request.method != 'GET':
        return JsonResponse({'success': False, 'error': 'Only GET allowed'}, status=405)

    start_ts = time.perf_counter()

    user_id = request.GET.get('user_id')
    other_id = request.GET.get('other_id')
    since_id_raw = request.GET.get('since_id')

    try:
        since_id = int(since_id_raw or 0)
    except (TypeError, ValueError):
        since_id = 0

    logger.debug(
        "[list_chat_messages_updates][START] trip_id=%s user_id=%s other_id=%s since_id=%s",
        trip_id,
        user_id,
        other_id,
        since_id,
    )

    # Step 1: load trip
    try:
        trip = Trip.objects.only('id', 'trip_id').get(trip_id=trip_id)
        logger.debug("[list_chat_messages_updates][STEP 1] Trip loaded: id=%s trip_id=%s", trip.id, trip.trip_id)
    except Trip.DoesNotExist:
        elapsed_ms = (time.perf_counter() - start_ts) * 1000.0
        return JsonResponse({'success': False, 'error': 'Trip not found'}, status=404)
    except OperationalError as e:
        elapsed_ms = (time.perf_counter() - start_ts) * 1000.0
        logger.exception("[list_chat_messages_updates][Trip][OperationalError] %s elapsed_ms=%s", str(e), elapsed_ms)
        return JsonResponse({'success': True, 'messages': []}, status=200)

    # Step 2: load chat group
    try:
        chat_group = TripChatGroup.objects.select_related('trip').get(trip=trip)
        logger.debug("[list_chat_messages_updates][STEP 2] ChatGroup loaded: id=%s trip_id=%s", chat_group.id, trip.trip_id)
    except TripChatGroup.DoesNotExist:
        elapsed_ms = (time.perf_counter() - start_ts) * 1000.0
        logger.debug("[list_chat_messages_updates] No chat group for trip; returning empty list. elapsed_ms=%s", elapsed_ms)
        return JsonResponse({'success': True, 'messages': []})
    except OperationalError as e:
        elapsed_ms = (time.perf_counter() - start_ts) * 1000.0
        logger.exception("[list_chat_messages_updates][ChatGroup][OperationalError] %s elapsed_ms=%s", str(e), elapsed_ms)
        return JsonResponse({'success': True, 'messages': []}, status=200)

    # Step 3: build and execute lightweight queryset using .values()
    try:
        logger.debug(
            "[list_chat_messages_updates][STEP 3] Building VALUES queryset chat_group_id=%s since_id=%s",
            chat_group.id,
            since_id,
        )
        qs = ChatMessage.objects.filter(
            chat_group=chat_group,
            is_deleted=False,
            id__gt=since_id,
        ).order_by('created_at').values(
            'id',
            'sender_id',
            'message_text',
            'message_type',
            'message_data',
            'created_at',
        )
        if user_id and other_id:
            try:
                uid = int(user_id)
                oid = int(other_id)
            except (TypeError, ValueError):
                uid = user_id
                oid = other_id
            logger.debug(
                "[list_chat_messages_updates][STEP 3] Applying 1-1 filter uid=%s oid=%s",
                uid,
                oid,
            )
            qs = qs.filter(
                Q(sender_id=uid, message_data__recipient_id=oid)
                | Q(sender_id=oid, message_data__recipient_id=uid)
            )

        msgs = []
        count = 0

        other_read_ids = set()
        if user_id and other_id:
            try:
                oid = int(other_id)
            except (TypeError, ValueError):
                oid = other_id
            other_read_ids = set(
                MessageReadStatus.objects.filter(
                    user_id=oid,
                    message__chat_group=chat_group,
                    message_id__gt=since_id,
                ).values_list('message_id', flat=True)
            )

        try:
            for row in qs:
                try:
                    msg_data = row.get('message_data') or {}
                    recipient_id = msg_data.get('recipient_id')
                    sender_role = msg_data.get('sender_role')
                    is_broadcast = bool(msg_data.get('is_broadcast'))
                    created_at = row.get('created_at')
                    payload = {
                        'id': row.get('id'),
                        'trip_id': trip.trip_id,
                        'sender_id': row.get('sender_id'),
                        'sender_name': '',  # name not critical for chat bubble
                        'sender_role': sender_role,
                        'recipient_id': recipient_id,
                        'message_text': row.get('message_text') or '',
                        'message_type': row.get('message_type') or 'TEXT',
                        'is_broadcast': is_broadcast,
                        'created_at': created_at.isoformat() if created_at else timezone.now().isoformat(),
                        'is_read': False,
                        'is_read_by_other': (row.get('id') in other_read_ids) if (user_id and other_id and int(user_id) == row.get('sender_id')) else False,
                    }
                    msgs.append(payload)
                    count += 1
                except Exception as row_e:
                    logger.exception("[list_chat_messages_updates][ROW_ERROR] %s", str(row_e))
        except OperationalError as e:
            elapsed_ms = (time.perf_counter() - start_ts) * 1000.0
            logger.exception(
                "[list_chat_messages_updates][Messages][OperationalError] %s elapsed_ms=%s",
                str(e),
                elapsed_ms,
            )
            return JsonResponse({'success': True, 'messages': []}, status=200)
        except Exception as loop_e:
            elapsed_ms = (time.perf_counter() - start_ts) * 1000.0
            logger.exception(
                "[list_chat_messages_updates][Messages][ERROR] Unexpected error in loop: %s elapsed_ms=%s",
                str(loop_e),
                elapsed_ms,
            )
            return JsonResponse({'success': True, 'messages': []}, status=200)

        elapsed_ms = (time.perf_counter() - start_ts) * 1000.0
        logger.debug(
            "[list_chat_messages_updates][END] trip_id=%s messages_returned=%s elapsed_ms=%s",
            trip_id,
            count,
            elapsed_ms,
        )

        return JsonResponse({'success': True, 'messages': msgs})
    except OperationalError as e:
        elapsed_ms = (time.perf_counter() - start_ts) * 1000.0
        logger.exception(
            "[list_chat_messages_updates][Messages][OperationalError-outer] %s elapsed_ms=%s",
            str(e),
            elapsed_ms,
        )
        return JsonResponse({'success': True, 'messages': []}, status=200)


@csrf_exempt
def send_chat_message(request, trip_id):
    """Send a simple 1:1 text message between driver and passenger for a trip.

    Body JSON:
      - sender_id (int)
      - recipient_id (int)
      - sender_name (str)
      - sender_role ("driver" | "passenger")
      - message_text (str)
    """
    if request.method != 'POST':
        return JsonResponse({'success': False, 'error': 'Only POST allowed'}, status=405)
    try:
        data = json.loads(request.body or '{}')
        sender_id = data.get('sender_id')
        recipient_id = data.get('recipient_id')
        sender_name = data.get('sender_name') or ''
        sender_role = (data.get('sender_role') or '').lower()
        message_text = (data.get('message_text') or '').strip()

        logger.debug('[send_chat_message] Incoming: %s', {
            'trip_id': trip_id,
            'sender_id': sender_id,
            'recipient_id': recipient_id,
            'sender_role': sender_role,
            'message_text': message_text,
        })

        if not sender_id or not recipient_id or not message_text:
            return JsonResponse({'success': False, 'error': 'sender_id, recipient_id and message_text are required'}, status=400)

        try:
            trip = Trip.objects.only('id', 'trip_id', 'driver_id').get(trip_id=trip_id)
        except Trip.DoesNotExist:
            return JsonResponse({'success': False, 'error': 'Trip not found'}, status=404)

        sender = UsersData.objects.only('id', 'name').filter(id=sender_id).first()
        if sender is None:
            return JsonResponse({'success': False, 'error': 'Sender not found'}, status=404)

        # BR-1: Chat only for CONFIRMED bookings. Passenger is whichever is not the trip driver.
        passenger_id = recipient_id
        if trip.driver_id == recipient_id:
            passenger_id = sender_id

        # There may be multiple bookings for the same passenger and trip over time,
        # so we only need to check that at least one *active* booking exists
        # instead of using .get(), which would fail if multiple rows match.
        has_active_booking = Booking.objects.filter(
            trip_id=trip.id,
            passenger_id=passenger_id,
            booking_status__in=['CONFIRMED', 'ACCEPTED', 'BOOKED'],
        ).exists()

        if not has_active_booking:
            return JsonResponse({'success': False, 'error': 'Chat allowed only for active bookings'}, status=403)

        # Ensure chat group exists for this trip
        chat_group, _ = TripChatGroup.objects.get_or_create(
            trip=trip,
            defaults={
                'group_name': f"Trip {trip.trip_id} Chat",
                'created_by': sender,
            },
        )

        logger.debug('[send_chat_message] creating ChatMessage row')
        msg = ChatMessage.objects.create(
            chat_group=chat_group,
            sender=sender,
            message_type='TEXT',
            message_text=message_text,
            message_data={
                'recipient_id': recipient_id,
                'sender_role': sender_role,
            },
        )

        # Fire-and-forget push notification to recipient (chat message)
        try:
            recipient_user_id = recipient_id
            if recipient_user_id == sender.id:
                recipient_user_id = None

            payload = {
                'recipient_id': str(recipient_user_id) if recipient_user_id is not None else '',
                'sender_id': str(sender.id),
                'user_id': str(recipient_user_id) if recipient_user_id is not None else '',
                'driver_id': str(sender.id),
                'title': str(sender.name or 'New message'),
                'body': str(message_text or '')[:160],
                'data': {
                    'type': 'chat_message',
                    'trip_id': str(trip.trip_id),
                    'sender_id': str(sender.id),
                    'sender_name': str(sender.name or ''),
                    'sender_role': str(sender_role or ''),
                    'sender_photo_url': str(getattr(sender, 'profile_photo_url', '') or ''),
                    'recipient_id': str(recipient_user_id) if recipient_user_id is not None else '',
                    'message_id': str(msg.id),
                    'message_text': str(message_text or ''),
                },
            }
            if recipient_user_id is not None:
                send_ride_notification_async(payload)
        except Exception as e:
            logger.exception('[send_chat_message][notify_error]: %s', str(e))

        logger.debug('[send_chat_message] message created id=%s', msg.id)
        return JsonResponse({
            'success': True,
            'message': {
                'id': msg.id,
                'trip_id': trip.trip_id,
                'sender_id': msg.sender_id,
                'sender_name': sender_name or sender.name,
                'sender_role': sender_role,
                'recipient_id': recipient_id,
                'message_text': msg.message_text,
                'message_type': msg.message_type,
                'is_broadcast': False,
                'created_at': msg.created_at.isoformat(),
                'is_read': False,
            }
        }, status=201)
    except Exception as e:
        logger.exception('[send_chat_message][ERROR]: %s', str(e))
        return JsonResponse({'success': False, 'error': str(e)}, status=500)


@csrf_exempt
def mark_message_read(request, message_id):
    """Mark a message as read by a given user."""
    if request.method != 'POST':
        return JsonResponse({'success': False, 'error': 'Only POST allowed'}, status=405)
    try:
        data = json.loads(request.body or '{}')
        user_id = data.get('user_id')
        if not user_id:
            return JsonResponse({'success': False, 'error': 'user_id is required'}, status=400)

        try:
            msg = ChatMessage.objects.select_related('chat_group').get(id=message_id)
        except ChatMessage.DoesNotExist:
            return JsonResponse({'success': False, 'error': 'Message not found'}, status=404)

        try:
            user = UsersData.objects.get(id=user_id)
        except UsersData.DoesNotExist:
            return JsonResponse({'success': False, 'error': 'User not found'}, status=404)

        MessageReadStatus.objects.get_or_create(message=msg, user=user)
        return JsonResponse({'success': True})
    except Exception as e:
        logger.exception('[mark_message_read][ERROR]: %s', str(e))
        return JsonResponse({'success': False, 'error': str(e)}, status=500)


@csrf_exempt
def send_broadcast_message(request, trip_id):
    """Driver broadcast to a subset of confirmed passengers for a trip.

    Body JSON:
      - sender_id (driver id)
      - sender_name (str)
      - sender_role ("driver")
      - message_text (str)
      - recipient_ids: [passenger_id1, passenger_id2, ...]
    """
    if request.method != 'POST':
        return JsonResponse({'success': False, 'error': 'Only POST allowed'}, status=405)
    try:
        data = json.loads(request.body or '{}')
        sender_id = data.get('sender_id')
        sender_name = data.get('sender_name') or ''
        sender_role = (data.get('sender_role') or '').lower()
        message_text = (data.get('message_text') or '').strip()
        recipient_ids = data.get('recipient_ids') or []

        logger.debug('[send_broadcast_message] Incoming: %s', {
            'trip_id': trip_id,
            'sender_id': sender_id,
            'sender_role': sender_role,
            'message_text': message_text,
            'recipient_ids': recipient_ids,
        })

        if not sender_id or not message_text or not recipient_ids:
            return JsonResponse({
                'success': False,
                'error': 'sender_id, message_text and recipient_ids are required',
            }, status=400)

        try:
            trip = Trip.objects.only('id', 'trip_id', 'driver_id').get(trip_id=trip_id)
        except Trip.DoesNotExist:
            return JsonResponse({'success': False, 'error': 'Trip not found'}, status=404)

        # Only the trip driver may broadcast
        if int(trip.driver_id or 0) != int(sender_id):
            return JsonResponse({'success': False, 'error': 'Only the trip driver can send broadcasts'}, status=403)

        try:
            sender = UsersData.objects.get(id=sender_id)
        except UsersData.DoesNotExist:
            return JsonResponse({'success': False, 'error': 'Sender not found'}, status=404)

        # Ensure chat group exists
        chat_group, _ = TripChatGroup.objects.get_or_create(
            trip=trip,
            defaults={
                'group_name': f"Trip {trip.trip_id} Chat",
                'created_by': sender,
            },
        )

        # Filter to passengers with active bookings (BR-1/BR-6)
        valid_recipient_ids = list(
            Booking.objects.filter(
                trip_id=trip.id,
                passenger_id__in=recipient_ids,
                booking_status__in=['CONFIRMED', 'ACCEPTED', 'BOOKED'],
            ).values_list('passenger_id', flat=True)
        )

        if not valid_recipient_ids:
            return JsonResponse({
                'success': False,
                'error': 'No confirmed passengers found for this broadcast',
            }, status=403)

        broadcast_id = f"{trip.trip_id}-{timezone.now().strftime('%Y%m%d%H%M%S%f')}"
        created = []

        for pid in valid_recipient_ids:
            msg = ChatMessage.objects.create(
                chat_group=chat_group,
                sender=sender,
                message_type='TEXT',
                message_text=message_text,
                message_data={
                    'recipient_id': pid,
                    'sender_role': sender_role,
                    'is_broadcast': True,
                    'broadcast_id': broadcast_id,
                },
            )

            created.append({
                'id': msg.id,
                'trip_id': trip.trip_id,
                'sender_id': msg.sender_id,
                'sender_name': sender_name or sender.name,
                'sender_role': sender_role,
                'recipient_id': pid,
                'message_text': msg.message_text,
                'message_type': msg.message_type,
                'is_broadcast': True,
                'created_at': msg.created_at.isoformat(),
                'is_read': False,
            })

            # Notification per recipient
            try:
                payload = {
                    'recipient_id': str(pid),
                    'sender_id': str(sender.id),
                    'user_id': str(pid),
                    'driver_id': str(trip.driver_id),
                    'title': 'New broadcast from driver',
                    'body': message_text,
                    'data': {
                        'type': 'chat_broadcast',
                        'trip_id': str(trip.trip_id),
                        'sender_id': str(sender.id),
                        'sender_name': str(sender.name or ''),
                        'sender_role': 'driver',
                        'sender_photo_url': str(getattr(sender, 'profile_photo_url', '') or ''),
                        'recipient_id': str(pid),
                        'message_id': str(msg.id),
                        'broadcast_id': broadcast_id,
                        'message_text': str(message_text or ''),
                    },
                }
                send_ride_notification_async(payload)
            except Exception as e:
                logger.exception('[send_broadcast_message][notify_error]: %s', str(e))

        logger.debug('[send_broadcast_message] Created broadcast %s messages_count=%s', broadcast_id, len(created))
        return JsonResponse({'success': True, 'broadcast_id': broadcast_id, 'messages': created}, status=201)
    except Exception as e:
        logger.exception('[send_broadcast_message][ERROR]: %s', str(e))
        return JsonResponse({'success': False, 'error': str(e)}, status=500)

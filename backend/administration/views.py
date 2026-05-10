# Add user creation view (GET: show form, POST: save user)
from django.http import HttpResponseRedirect, JsonResponse
from django.contrib.auth import authenticate, login, logout
from django.urls import reverse
from django.views.decorators.csrf import csrf_exempt, csrf_protect
from datetime import timedelta
from django.views.decorators.http import require_http_methods
from django.utils import timezone
from django.db.models import Avg, Count, DurationField, ExpressionWrapper, F, Q, Sum, Max, OuterRef, Subquery
from django.db.models.functions import Coalesce, ExtractHour
from django.conf import settings
from lets_go.models import (
    GuestUser,
    UsersData,
    EmergencyContact,
    Vehicle,
    Trip,
    Booking,
    TripStopBreakdown,
    TripPayment,
    TripChatGroup,
    ChatMessage,
    SosIncident,
    ResolvedSosAuditSnapshot,
    RideAuditEvent,
    ChangeRequest,
    SupportThread,
    SupportMessage,
)
import base64
import json
import time as pytime
from django.shortcuts import render, get_object_or_404, redirect
from django.contrib.auth.hashers import make_password
from django.utils import timezone
from django.contrib.auth.decorators import login_required

from lets_go.views.views_notifications import send_ride_notification_async
from lets_go.views.views_authentication import upload_to_supabase

from datetime import datetime

from .models import AdminTodoItem, SupportFAQ


def _build_resolved_sos_snapshot_payload(incident: SosIncident) -> dict:
    trip = getattr(incident, 'trip', None)
    booking = getattr(incident, 'booking', None)
    actor = getattr(incident, 'actor', None)
    audit_event = getattr(incident, 'audit_event', None)

    ride_audit_qs = RideAuditEvent.objects.none()
    try:
        has_filter = False
        q = Q()
        if trip is not None:
            q |= Q(trip=trip)
            has_filter = True
        if booking is not None:
            q |= Q(booking=booking)
            has_filter = True
        if actor is not None:
            q |= Q(actor=actor)
            has_filter = True
        if has_filter:
            ride_audit_qs = (
                RideAuditEvent.objects.filter(q)
                .select_related('actor', 'booking', 'trip')
                .order_by('created_at')
            )
    except Exception:
        ride_audit_qs = RideAuditEvent.objects.none()

    payload = {
        'incident': {
            'id': incident.id,
            'status': incident.status,
            'role': incident.role,
            'latitude': float(incident.latitude) if incident.latitude is not None else None,
            'longitude': float(incident.longitude) if incident.longitude is not None else None,
            'accuracy': incident.accuracy,
            'note': incident.note,
            'created_at': incident.created_at.isoformat() if incident.created_at else None,
            'resolved_at': incident.resolved_at.isoformat() if incident.resolved_at else None,
            'resolved_by': getattr(getattr(incident, 'resolved_by', None), 'username', None),
            'resolved_note': incident.resolved_note,
            'trip_pk': getattr(trip, 'id', None),
            'trip_id': getattr(trip, 'trip_id', None),
            'booking_pk': getattr(booking, 'id', None),
            'booking_id': getattr(booking, 'booking_id', None),
            'actor_id': getattr(actor, 'id', None),
            'actor_name': getattr(actor, 'name', None),
        },
        'trip': None,
        'booking': None,
        'actor': None,
        'audit_event': None,
        'ride_audit_events': [],
    }

    if actor is not None:
        payload['actor'] = {
            'id': actor.id,
            'name': getattr(actor, 'name', None),
            'username': getattr(actor, 'username', None),
            'email': getattr(actor, 'email', None),
            'phone_no': getattr(actor, 'phone_no', None),
        }

    if trip is not None:
        payload['trip'] = {
            'pk': trip.id,
            'trip_id': trip.trip_id,
            'trip_status': trip.trip_status,
            'trip_date': str(getattr(trip, 'trip_date', None)) if getattr(trip, 'trip_date', None) else None,
            'departure_time': str(getattr(trip, 'departure_time', None)) if getattr(trip, 'departure_time', None) else None,
            'driver_id': trip.driver_id,
            'vehicle_id': getattr(trip, 'vehicle_id', None),
            'route_id': getattr(trip, 'route_id', None),
        }

    if booking is not None:
        payload['booking'] = {
            'pk': booking.id,
            'booking_id': booking.booking_id,
            'booking_status': booking.booking_status,
            'ride_status': getattr(booking, 'ride_status', None),
            'payment_status': getattr(booking, 'payment_status', None),
            'passenger_id': booking.passenger_id,
            'number_of_seats': booking.number_of_seats,
            'total_fare': booking.total_fare,
        }

    if audit_event is not None:
        payload['audit_event'] = {
            'id': audit_event.id,
            'event_type': getattr(audit_event, 'event_type', None),
            'created_at': audit_event.created_at.isoformat() if getattr(audit_event, 'created_at', None) else None,
            'payload': getattr(audit_event, 'payload', None) or {},
        }

    for e in ride_audit_qs:
        payload['ride_audit_events'].append({
            'id': e.id,
            'event_type': e.event_type,
            'created_at': e.created_at.isoformat() if e.created_at else None,
            'trip_pk': e.trip_id,
            'booking_pk': e.booking_id,
            'actor_id': e.actor_id,
            'payload': e.payload or {},
        })

    return payload


def _attach_latest_payments(bookings):
    booking_ids = [b.id for b in bookings]
    if not booking_ids:
        return

    payment_map = {}
    try:
        payments = (
            TripPayment.objects
            .filter(booking_id__in=booking_ids)
            .only('booking_id', 'payment_method', 'payment_status', 'receipt_url', 'created_at', 'completed_at')
            .order_by('-created_at')
        )
        for p in payments:
            if p.booking_id not in payment_map:
                payment_map[p.booking_id] = p
    except Exception:
        payment_map = {}

    for b in bookings:
        p = payment_map.get(b.id)
        setattr(b, 'latest_payment', p)
        setattr(b, 'latest_receipt_url', getattr(p, 'receipt_url', None) if p is not None else None)
        setattr(b, 'latest_payment_method', getattr(p, 'payment_method', None) if p is not None else None)


@login_required
def guest_list_view(request):
    return render(request, 'administration/guests_list.html')


@require_http_methods(['GET'])
@login_required
def support_faq_list_view(request):
    q = (request.GET.get('q') or '').strip()
    category = (request.GET.get('category') or '').strip()
    active = (request.GET.get('active') or '').strip()

    qs = SupportFAQ.objects.all()
    if q:
        qs = qs.filter(Q(question__icontains=q) | Q(answer__icontains=q))
    if category:
        qs = qs.filter(category__icontains=category)
    if active in {'0', '1'}:
        qs = qs.filter(is_active=(active == '1'))

    qs = qs.order_by('priority', 'id')
    return render(
        request,
        'administration/support_faq_list.html',
        {
            'faqs': qs,
            'q': q,
            'category': category,
            'active': active,
        },
    )


@csrf_protect
@login_required
def support_faq_add_view(request):
    if request.method == 'POST':
        category = (request.POST.get('category') or '').strip() or None
        question = (request.POST.get('question') or '').strip()
        answer = (request.POST.get('answer') or '').strip()
        priority_raw = (request.POST.get('priority') or '').strip()
        is_active_raw = (request.POST.get('is_active') or '1').strip()

        try:
            priority = int(priority_raw) if priority_raw else 100
        except Exception:
            priority = 100

        is_active = is_active_raw in {'1', 'true', 'True', 'yes', 'on'}

        faq = SupportFAQ(
            category=category,
            question=question,
            answer=answer,
            priority=priority,
            is_active=is_active,
        )
        try:
            faq.full_clean()
            faq.save()
            return redirect('administration:support_faq_list')
        except Exception as e:
            return render(
                request,
                'administration/support_faq_form.html',
                {
                    'faq': None,
                    'error': str(e),
                    'form': {
                        'category': category or '',
                        'question': question,
                        'answer': answer,
                        'priority': priority,
                        'is_active': is_active,
                    },
                },
            )

    return render(
        request,
        'administration/support_faq_form.html',
        {
            'faq': None,
            'form': {
                'category': '',
                'question': '',
                'answer': '',
                'priority': 100,
                'is_active': True,
            },
        },
    )


@csrf_protect
@login_required
def support_faq_edit_view(request, faq_id):
    faq = get_object_or_404(SupportFAQ, pk=faq_id)

    if request.method == 'POST':
        category = (request.POST.get('category') or '').strip() or None
        question = (request.POST.get('question') or '').strip()
        answer = (request.POST.get('answer') or '').strip()
        priority_raw = (request.POST.get('priority') or '').strip()
        is_active_raw = (request.POST.get('is_active') or '1').strip()

        try:
            priority = int(priority_raw) if priority_raw else faq.priority
        except Exception:
            priority = faq.priority

        is_active = is_active_raw in {'1', 'true', 'True', 'yes', 'on'}

        faq.category = category
        faq.question = question
        faq.answer = answer
        faq.priority = priority
        faq.is_active = is_active

        try:
            faq.full_clean()
            faq.save()
            return redirect('administration:support_faq_list')
        except Exception as e:
            return render(
                request,
                'administration/support_faq_form.html',
                {
                    'faq': faq,
                    'error': str(e),
                    'form': {
                        'category': category or '',
                        'question': question,
                        'answer': answer,
                        'priority': priority,
                        'is_active': is_active,
                    },
                },
            )

    return render(
        request,
        'administration/support_faq_form.html',
        {
            'faq': faq,
            'form': {
                'category': faq.category or '',
                'question': faq.question,
                'answer': faq.answer,
                'priority': faq.priority,
                'is_active': faq.is_active,
            },
        },
    )


@require_http_methods(['POST'])
@csrf_protect
@login_required
def support_faq_toggle_active_view(request, faq_id):
    faq = get_object_or_404(SupportFAQ, pk=faq_id)
    faq.is_active = not bool(faq.is_active)
    faq.save(update_fields=['is_active', 'updated_at'])
    back = request.META.get('HTTP_REFERER')
    if back:
        return redirect(back)
    return redirect('administration:support_faq_list')


@require_http_methods(['POST'])
@csrf_protect
@login_required
def support_faq_delete_view(request, faq_id):
    faq = get_object_or_404(SupportFAQ, pk=faq_id)
    faq.delete()
    return redirect('administration:support_faq_list')


@login_required
def api_guests(request):
    qs = GuestUser.objects.all().values(
        'id',
        'guest_number',
        'username',
        'created_at',
        'updated_at',
    )
    return JsonResponse({'guests': list(qs)})


@login_required
def guest_support_chat_view(request, guest_id):
    guest = get_object_or_404(GuestUser, pk=guest_id)
    thread, _ = SupportThread.objects.get_or_create(
        user=None,
        guest=guest,
        thread_type='ADMIN',
        defaults={'last_message_at': timezone.now()},
    )

    latest_id = SupportMessage.objects.filter(thread=thread).aggregate(mx=Max('id')).get('mx') or 0
    if latest_id and thread.admin_last_seen_id != latest_id:
        thread.admin_last_seen_id = latest_id
        thread.save(update_fields=['admin_last_seen_id', 'updated_at'])

    error = None
    if request.method == 'POST':
        message_text = (request.POST.get('message_text') or '').strip()
        if not message_text:
            error = 'Message cannot be empty.'
        else:
            admin_sender = None
            try:
                admin_sender = UsersData.objects.filter(username=getattr(request.user, 'username', '')).first()
            except Exception:
                admin_sender = None

            SupportMessage.objects.create(
                thread=thread,
                sender_type='ADMIN',
                sender_user=admin_sender,
                message_text=message_text,
            )

            latest_id = SupportMessage.objects.filter(thread=thread).aggregate(mx=Max('id')).get('mx') or 0
            if latest_id:
                thread.admin_last_seen_id = latest_id
                thread.save(update_fields=['admin_last_seen_id', 'updated_at'])

            thread.last_message_at = timezone.now()
            thread.save(update_fields=['last_message_at', 'updated_at'])

            try:
                payload = {
                    'recipient_id': str(guest.username),
                    'sender_id': str(admin_sender.id) if admin_sender is not None else '0',
                    'user_id': str(guest.username),
                    'driver_id': str(admin_sender.id) if admin_sender is not None else '0',
                    'title': 'Admin Support Reply',
                    'body': message_text[:140],
                    'data': {
                        'type': 'support_admin',
                        'thread_type': 'ADMIN',
                        'guest_user_id': str(guest.id),
                        'guest_username': str(guest.username),
                        'sender_id': str(admin_sender.id) if admin_sender is not None else '0',
                        'sender_name': str(getattr(admin_sender, 'name', '') or 'Admin'),
                        'sender_photo_url': str(getattr(admin_sender, 'profile_photo_url', '') or ''),
                        'message_text': message_text,
                    },
                }
                send_ride_notification_async(payload)
            except Exception:
                pass

            return redirect('administration:guest_support_chat', guest_id=guest.id)

    messages = SupportMessage.objects.filter(thread=thread).order_by('created_at')
    return render(
        request,
        'administration/guest_support_chat.html',
        {
            'guest': guest,
            'thread': thread,
            'messages': messages,
            'error': error,
        },
    )

@csrf_protect
@login_required
def user_add_view(request):
    def _post_to_form_data(post):
        try:
            return {k: post.get(k) for k in post.keys()}
        except Exception:
            return {}

    if request.method == 'POST':
        user = UsersData()
        user.name = request.POST.get('name')
        user.username = request.POST.get('username')
        user.email = request.POST.get('email')
        raw_password = request.POST.get('password')
        user.password = make_password(raw_password) if raw_password else None
        user.address = request.POST.get('address')
        phone_no = request.POST.get('phone_no')
        # Ensure phone number has + prefix for international format
        if phone_no and not phone_no.startswith('+'):
            phone_no = '+' + phone_no
        user.phone_no = phone_no
        user.gender = request.POST.get('gender')
        user.status = 'VERIFIED'
        user.driver_rating = request.POST.get('driver_rating') or None
        user.passenger_rating = request.POST.get('passenger_rating') or None
        user.cnic_no = request.POST.get('cnic_no')
        user.driving_license_no = (request.POST.get('driving_license_no') or '').strip() or None
        user.accountno = (request.POST.get('accountno') or '').strip() or None
        user.iban = (request.POST.get('iban') or '').strip() or None
        user.bankname = (request.POST.get('bankname') or '').strip() or None

        user_bucket = getattr(settings, 'SUPABASE_USER_BUCKET', 'user-images')
        stamp = int(pytime.time())
        email = (user.email or '').strip()
        if email:
            profile_photo = request.FILES.get('profile_photo')
            live_photo = request.FILES.get('live_photo')
            cnic_front = request.FILES.get('cnic_front_image')
            cnic_back = request.FILES.get('cnic_back_image')
            dl_front = request.FILES.get('driving_license_front')
            dl_back = request.FILES.get('driving_license_back')
            accountqr = request.FILES.get('accountqr')

            if profile_photo:
                ext = (getattr(profile_photo, 'name', '') or 'jpg').rsplit('.', 1)[-1].lower()
                dest = f"users/{email}/profile_photo.{ext}"
                user.profile_photo_url = upload_to_supabase(user_bucket, profile_photo, dest)
            if live_photo:
                ext = (getattr(live_photo, 'name', '') or 'jpg').rsplit('.', 1)[-1].lower()
                dest = f"users/{email}/live_photo.{ext}"
                user.live_photo_url = upload_to_supabase(user_bucket, live_photo, dest)
            if cnic_front:
                ext = (getattr(cnic_front, 'name', '') or 'jpg').rsplit('.', 1)[-1].lower()
                dest = f"users/{email}/cnic_front_{stamp}.{ext}"
                user.cnic_front_image_url = upload_to_supabase(user_bucket, cnic_front, dest)
            if cnic_back:
                ext = (getattr(cnic_back, 'name', '') or 'jpg').rsplit('.', 1)[-1].lower()
                dest = f"users/{email}/cnic_back_{stamp}.{ext}"
                user.cnic_back_image_url = upload_to_supabase(user_bucket, cnic_back, dest)
            if dl_front:
                ext = (getattr(dl_front, 'name', '') or 'jpg').rsplit('.', 1)[-1].lower()
                dest = f"users/{email}/driving_license_front_{stamp}.{ext}"
                user.driving_license_front_url = upload_to_supabase(user_bucket, dl_front, dest)
            if dl_back:
                ext = (getattr(dl_back, 'name', '') or 'jpg').rsplit('.', 1)[-1].lower()
                dest = f"users/{email}/driving_license_back_{stamp}.{ext}"
                user.driving_license_back_url = upload_to_supabase(user_bucket, dl_back, dest)
            if accountqr:
                ext = (getattr(accountqr, 'name', '') or 'png').rsplit('.', 1)[-1].lower()
                dest = f"users/{email}/account_qr_{stamp}.{ext}"
                user.accountqr_url = upload_to_supabase(user_bucket, accountqr, dest)
        try:
            user.full_clean()

            if (getattr(user, 'status', None) or '').strip().upper() == 'VERIFIED':
                missing = _missing_required_user_verification_fields(user)
                if missing:
                    raise ValueError('Cannot set user as VERIFIED. Missing required verification fields: ' + ', '.join(missing))

            user.save()

            emergency_name = (request.POST.get('emergency_name') or '').strip()
            emergency_relation = (request.POST.get('emergency_relation') or '').strip()
            emergency_email = (request.POST.get('emergency_email') or '').strip()
            emergency_phone_no = (request.POST.get('emergency_phone_no') or '').strip()

            if not all([emergency_name, emergency_relation, emergency_email, emergency_phone_no]):
                raise ValueError('Emergency contact is required. Provide name, relation, email, and phone.')

            phone_digits = emergency_phone_no[1:] if emergency_phone_no.startswith('+') else emergency_phone_no
            if (not phone_digits.isdigit()) or (len(phone_digits) < 10) or (len(phone_digits) > 15):
                raise ValueError('Emergency phone must be 10-15 digits.')
            ec = EmergencyContact(
                user=user,
                name=emergency_name,
                relation=emergency_relation,
                email=emergency_email,
                phone_no=phone_digits,
            )
            ec.full_clean()
            ec.save()

            return redirect('administration:user_list')
        except Exception as e:
            try:
                if getattr(user, 'id', None):
                    user.delete()
            except Exception:
                pass
            return render(
                request,
                'administration/user_add.html',
                {'error': str(e), 'form': _post_to_form_data(request.POST)},
            )
    return render(request, 'administration/user_add.html', {'form': {}})
# Create your views here.
@login_required
def admin_view(request):
    return render(request, "administration/index.html")


@login_required
def analytics_view(request):
    return render(request, 'administration/analytics.html')


@login_required
def settings_view(request):
    return render(request, 'administration/settings.html')


@login_required
def user_support_chat_view(request, user_id):
    user = get_object_or_404(UsersData, pk=user_id)
    thread, _ = SupportThread.objects.get_or_create(
        user=user,
        thread_type='ADMIN',
        defaults={'last_message_at': timezone.now()},
    )

    bot_thread, _ = SupportThread.objects.get_or_create(
        user=user,
        thread_type='BOT',
        defaults={'last_message_at': timezone.now()},
    )

    latest_id = SupportMessage.objects.filter(thread=thread).aggregate(mx=Max('id')).get('mx') or 0
    if latest_id and thread.admin_last_seen_id != latest_id:
        thread.admin_last_seen_id = latest_id
        thread.save(update_fields=['admin_last_seen_id', 'updated_at'])

    error = None
    if request.method == 'POST':
        message_text = (request.POST.get('message_text') or '').strip()
        if not message_text:
            error = 'Message cannot be empty.'
        else:
            # Admin identity: use the Django auth user if possible, otherwise send without sender_user
            admin_sender = None
            try:
                # Sometimes the admin username is an existing UsersData username
                admin_sender = UsersData.objects.filter(username=getattr(request.user, 'username', '')).first()
            except Exception:
                admin_sender = None

            SupportMessage.objects.create(
                thread=thread,
                sender_type='ADMIN',
                sender_user=admin_sender,
                message_text=message_text,
            )

            latest_id = SupportMessage.objects.filter(thread=thread).aggregate(mx=Max('id')).get('mx') or 0
            if latest_id:
                thread.admin_last_seen_id = latest_id
                thread.save(update_fields=['admin_last_seen_id', 'updated_at'])

            thread.last_message_at = timezone.now()
            thread.save(update_fields=['last_message_at', 'updated_at'])

            # Push notification to user
            try:
                payload = {
                    'recipient_id': str(user.id),
                    'sender_id': '0',
                    'user_id': str(user.id),
                    'driver_id': '0',
                    'title': 'Admin Support Reply',
                    'body': message_text[:140],
                    'data': {
                        'type': 'support_admin',
                        'thread_type': 'ADMIN',
                        'user_id': str(user.id),
                        'sender_type': 'admin',
                        'sender_id': '0',
                        'sender_name': 'Admin Support',
                        'sender_photo_url': '',
                        'message_text': message_text,
                    },
                }
                send_ride_notification_async(payload)
            except Exception:
                pass

            return redirect('administration:user_support_chat', user_id=user.id)

    messages = SupportMessage.objects.filter(thread=thread).order_by('created_at')
    bot_messages = SupportMessage.objects.filter(thread=bot_thread).order_by('created_at')
    return render(
        request,
        'administration/user_support_chat.html',
        {
            'user': user,
            'thread': thread,
            'messages': messages,
            'bot_thread': bot_thread,
            'bot_messages': bot_messages,
            'error': error,
        },
    )


@login_required
def rides_dashboard_view(request):
    """Admin dashboard to track rides/trips & bookings."""
    try:
        from lets_go.auto_archive import auto_archive_global
        auto_archive_global(limit=10)
    except Exception:
        pass

    today = timezone.now().date()

    total_trips = Trip.objects.count()
    trips_today = Trip.objects.filter(trip_date=today).count()
    in_progress_trips = Trip.objects.filter(trip_status='IN_PROGRESS').count()
    completed_today = Trip.objects.filter(trip_status='COMPLETED', trip_date=today).count()
    total_bookings = Booking.objects.count()

    recent_trips = (
        Trip.objects
        .select_related('route', 'driver', 'vehicle')
        .annotate(
            bookings_count=Count('trip_bookings', distinct=True),
            male_seats_booked=Coalesce(Sum('trip_bookings__male_seats'), 0),
            female_seats_booked=Coalesce(Sum('trip_bookings__female_seats'), 0),
            confirmed_bookings=Count('trip_bookings', filter=Q(trip_bookings__booking_status='CONFIRMED'), distinct=True),
            cancelled_bookings=Count('trip_bookings', filter=Q(trip_bookings__booking_status='CANCELLED'), distinct=True),
            completed_bookings=Count('trip_bookings', filter=Q(trip_bookings__booking_status='COMPLETED'), distinct=True),
            negotiated_bookings=Count('trip_bookings', filter=~Q(trip_bookings__bargaining_status='NO_NEGOTIATION'), distinct=True),
            paid_bookings=Count('trip_bookings', filter=Q(trip_bookings__payment_status='COMPLETED'), distinct=True),
        )
        .annotate(
            seats_booked=F('male_seats_booked') + F('female_seats_booked'),
        )
        .order_by('-trip_date', '-departure_time')[:30]
    )

    context = {
        'total_trips': total_trips,
        'trips_today': trips_today,
        'in_progress_trips': in_progress_trips,
        'completed_today': completed_today,
        'total_bookings': total_bookings,
        'recent_trips': recent_trips,
        'today': today,
    }
    return render(request, 'administration/rides_dashboard.html', context)


@login_required
def admin_trip_detail_view(request, trip_pk):
    """Admin detail page for a single trip with full related info."""
    trip = get_object_or_404(Trip.objects.select_related('route', 'driver', 'vehicle'), pk=trip_pk)

    trip_meta_data = {
        'trip_id': trip.trip_id,
        'driver_id': trip.driver_id,
        'driver_name': getattr(trip.driver, 'name', None),
        'driver_profile_photo': getattr(trip.driver, 'profile_photo_url', None),
    }

    # All bookings for this trip with passengers and stops
    bookings = (
        Booking.objects
        .filter(trip=trip)
        .select_related('passenger', 'from_stop', 'to_stop')
        .prefetch_related('payments')
        .order_by('-booked_at')
    )

    _attach_latest_payments(bookings)

    # Booking tabs for UI, grouped by (passenger, seats, from, to) so identical lines are not repeated
    tab_groups = {}
    for b in bookings:
        from_name = b.from_stop.stop_name if b.from_stop else ''
        to_name = b.to_stop.stop_name if b.to_stop else ''

        male_seats = int(getattr(b, 'male_seats', 0) or 0)
        female_seats = int(getattr(b, 'female_seats', 0) or 0)
        total_seats = int(getattr(b, 'number_of_seats', 0) or 0)
        if (male_seats + female_seats) > 0:
            total_seats = male_seats + female_seats
        if total_seats <= 0:
            total_seats = 1

        if (male_seats + female_seats) > 0:
            seats_display = f"{total_seats} (M:{male_seats} F:{female_seats})"
        else:
            seats_display = str(total_seats)

        key = (b.passenger.id, male_seats, female_seats, from_name, to_name)
        if key not in tab_groups:
            tab_groups[key] = {
                'id': b.id,  # representative booking id for this group
                'passenger_id': b.passenger.id,
                'passenger_name': b.passenger.name,
                'seats': total_seats,
                'male_seats': male_seats,
                'female_seats': female_seats,
                'seats_display': seats_display,
                'from_name': from_name,
                'to_name': to_name,
                'booking_ids': [b.id],
            }
        else:
            tab_groups[key]['booking_ids'].append(b.id)

    booking_tabs = list(tab_groups.values())

    # Stop breakdown segments, if present
    segments = TripStopBreakdown.objects.filter(trip=trip).order_by('from_stop_order')
    segments_coords_data = []
    for s in segments:
        try:
            if s.from_latitude and s.from_longitude and s.to_latitude and s.to_longitude:
                segments_coords_data.append([
                    [float(s.from_latitude), float(s.from_longitude)],
                    [float(s.to_latitude), float(s.to_longitude)],
                ])
        except Exception:
            pass

    if getattr(trip, 'total_duration_minutes', None) is None:
        try:
            total_duration = segments.aggregate(total=Sum('duration_minutes'))['total']
        except Exception:
            total_duration = None
        try:
            trip.total_duration_minutes = int(total_duration) if total_duration is not None else None
        except Exception:
            trip.total_duration_minutes = None

    # Full ordered route stops for this trip (used for main map polyline & markers)
    route_stops_full = []
    route_geometry = []
    route_stops_full_data = []
    route_geometry_data = []
    try:
        route = getattr(trip, 'route', None)
        if route is not None:
            route_stops_full = list(route.route_stops.all().order_by('stop_order'))
            route_geometry = route.route_geometry or []
            for rs in route_stops_full:
                if getattr(rs, 'latitude', None) and getattr(rs, 'longitude', None):
                    route_stops_full_data.append({
                        'name': rs.stop_name,
                        'order': rs.stop_order,
                        'lat': float(rs.latitude),
                        'lng': float(rs.longitude),
                    })
            for p in route_geometry:
                try:
                    if isinstance(p, dict) and 'lat' in p and 'lng' in p:
                        route_geometry_data.append({'lat': float(p['lat']), 'lng': float(p['lng'])})
                except Exception:
                    pass
    except Exception:
        route_stops_full = []
        route_geometry = []
        route_stops_full_data = []
        route_geometry_data = []

    booking_markers_data = []
    booking_meta_data = []
    for b in bookings:
        try:
            from_lat = None
            from_lng = None
            to_lat = None
            to_lng = None
            try:
                if b.from_stop and b.from_stop.latitude is not None and b.from_stop.longitude is not None:
                    from_lat = float(b.from_stop.latitude)
                    from_lng = float(b.from_stop.longitude)
            except Exception:
                pass
            try:
                if b.to_stop and b.to_stop.latitude is not None and b.to_stop.longitude is not None:
                    to_lat = float(b.to_stop.latitude)
                    to_lng = float(b.to_stop.longitude)
            except Exception:
                pass

            booking_meta_data.append({
                'booking_id': b.id,
                'booking_code': getattr(b, 'booking_id', None),
                'passenger_id': b.passenger_id,
                'passenger_name': getattr(getattr(b, 'passenger', None), 'name', None),
                'passenger_profile_photo': getattr(getattr(b, 'passenger', None), 'profile_photo_url', None),
                'from_stop_name': getattr(getattr(b, 'from_stop', None), 'stop_name', None),
                'to_stop_name': getattr(getattr(b, 'to_stop', None), 'stop_name', None),
                'from_stop_lat': from_lat,
                'from_stop_lng': from_lng,
                'to_stop_lat': to_lat,
                'to_stop_lng': to_lng,
                'passenger_to_driver_rating': float(b.driver_rating) if getattr(b, 'driver_rating', None) is not None else None,
                'passenger_to_driver_comment': getattr(b, 'driver_feedback', None),
                'driver_to_passenger_rating': float(b.passenger_rating) if getattr(b, 'passenger_rating', None) is not None else None,
                'driver_to_passenger_comment': getattr(b, 'passenger_feedback', None),
            })
        except Exception:
            pass
        try:
            if b.from_stop and b.from_stop.latitude and b.from_stop.longitude:
                booking_markers_data.append({
                    'type': 'pickup',
                    'lat': float(b.from_stop.latitude),
                    'lng': float(b.from_stop.longitude),
                    'label': f"Pickup: {b.passenger.name} ({b.from_stop.stop_name})",
                })
        except Exception:
            pass
        try:
            if b.to_stop and b.to_stop.latitude and b.to_stop.longitude:
                booking_markers_data.append({
                    'type': 'dropoff',
                    'lat': float(b.to_stop.latitude),
                    'lng': float(b.to_stop.longitude),
                    'label': f"Drop-off: {b.passenger.name} ({b.to_stop.stop_name})",
                })
        except Exception:
            pass

    # Aggregate payment info for this trip
    payments = TripPayment.objects.filter(booking__trip=trip).select_related('booking')

    payments_total = payments.aggregate(total_amount=Sum('amount'))['total_amount'] or 0
    payments_completed = payments.filter(payment_status='COMPLETED').aggregate(total_amount=Sum('amount'))['total_amount'] or 0

    # Chat: full messages and members
    chat_group = getattr(trip, 'chat_group', None)
    messages = []
    members = []
    if chat_group:
        messages = ChatMessage.objects.filter(chat_group=chat_group, is_deleted=False).select_related('sender').order_by('created_at')
        # Use related manager to fetch members with user details
        members = chat_group.chat_members.select_related('user').all()

    sos_incidents = (
        SosIncident.objects
        .filter(trip=trip, status='OPEN')
        .select_related('actor', 'booking')
        .order_by('-created_at')
    )
    sos_markers_data = []
    for i in sos_incidents:
        try:
            sos_markers_data.append({
                'id': i.id,
                'lat': float(i.latitude),
                'lng': float(i.longitude),
                'role': i.role,
                'booking_id': i.booking_id,
                'actor_id': i.actor_id,
                'actor_name': getattr(getattr(i, 'actor', None), 'name', None),
                'note': i.note,
                'created_at': i.created_at.isoformat() if getattr(i, 'created_at', None) else None,
            })
        except Exception:
            pass

    context = {
        'trip': trip,
        'trip_meta_data': trip_meta_data,
        'bookings': bookings,
        'segments': segments,
        'segments_coords_data': segments_coords_data,
        'route_stops_full': route_stops_full,
        'route_stops_full_data': route_stops_full_data,
        'route_geometry': route_geometry,
        'route_geometry_data': route_geometry_data,
        'booking_markers_data': booking_markers_data,
        'booking_meta_data': booking_meta_data,
        'payments_total': payments_total,
        'payments_completed': payments_completed,
        'chat_group': chat_group,
        'messages': messages,
        'members': members,
        'booking_tabs': booking_tabs,
        'sos_incidents': sos_incidents,
        'sos_markers_data': sos_markers_data,
    }
    return render(request, 'administration/trip_detail.html', context)


@require_http_methods(['GET'])
@login_required
def change_requests_list_view(request):
    qs = (
        ChangeRequest.objects
        .select_related('user', 'vehicle')
        .only(
            'id', 'entity_type', 'status', 'created_at',
            'user__id', 'user__name',
            'vehicle__id', 'vehicle__plate_number',
        )
        .order_by('-created_at')
    )

    status_filter = (request.GET.get('status') or '').strip().upper()
    if status_filter in [ChangeRequest.STATUS_PENDING, ChangeRequest.STATUS_APPROVED, ChangeRequest.STATUS_REJECTED]:
        qs = qs.filter(status=status_filter)
    else:
        status_filter = ''

    entity_filter = (request.GET.get('entity_type') or '').strip().upper()
    if entity_filter in [ChangeRequest.ENTITY_USER_PROFILE, ChangeRequest.ENTITY_VEHICLE]:
        qs = qs.filter(entity_type=entity_filter)
    else:
        entity_filter = ''

    return render(request, 'administration/change_requests_list.html', {
        'change_requests': qs[:300],
        'status_filter': status_filter,
        'entity_filter': entity_filter,
    })


@require_http_methods(['GET', 'POST'])
@csrf_protect
@login_required
def change_request_detail_view(request, change_request_id):
    cr = get_object_or_404(ChangeRequest.objects.select_related('user', 'vehicle'), pk=change_request_id)

    compare_rows = []
    try:
        keys = set()
        keys.update((cr.original_data or {}).keys())
        keys.update((cr.requested_changes or {}).keys())
        for k in sorted(keys):
            compare_rows.append({
                'field': k,
                'old': (cr.original_data or {}).get(k),
                'new': (cr.requested_changes or {}).get(k),
            })
    except Exception:
        compare_rows = []

    error = None
    if request.method == 'POST':
        action = (request.POST.get('action') or '').strip().lower()
        notes = (request.POST.get('review_notes') or '').strip() or None

        if cr.status != ChangeRequest.STATUS_PENDING:
            error = 'This request is already reviewed.'
        elif action not in ['approve', 'reject']:
            error = 'Invalid action.'
        else:
            try:
                if action == 'approve':
                    if cr.entity_type == ChangeRequest.ENTITY_USER_PROFILE:
                        user = cr.user
                        for k, v in (cr.requested_changes or {}).items():
                            setattr(user, k, v)

                        if (getattr(user, 'status', None) or '').strip().upper() == 'VERIFIED':
                            missing = _missing_required_user_verification_fields(user)
                            if missing:
                                raise ValueError('Cannot set user as VERIFIED. Missing required verification fields: ' + ', '.join(missing))

                        user.full_clean()
                        user.save()
                    elif cr.entity_type == ChangeRequest.ENTITY_VEHICLE:
                        vehicle = cr.vehicle
                        if vehicle is None:
                            raise ValueError('Vehicle not found for this change request.')
                        for k, v in (cr.requested_changes or {}).items():
                            setattr(vehicle, k, v)
                        vehicle.full_clean()
                        vehicle.status = Vehicle.STATUS_VERIFIED
                        vehicle.save()
                    else:
                        raise ValueError('Unknown entity type.')

                    cr.status = ChangeRequest.STATUS_APPROVED
                    cr.review_notes = notes
                    cr.reviewed_at = timezone.now()
                    cr.save(update_fields=['status', 'review_notes', 'reviewed_at'])

                    try:
                        payload = {
                            'recipient_id': str(cr.user_id),
                            'user_id': str(cr.user_id),
                            'driver_id': '0',
                            'title': 'Change request approved',
                            'body': 'Your requested changes were approved by admin.',
                            'data': {
                                'type': 'change_request_reviewed',
                                'status': str(cr.status),
                                'change_request_id': str(cr.id),
                                'entity_type': str(cr.entity_type),
                            },
                        }
                        send_ride_notification_async(payload)
                    except Exception:
                        pass

                elif action == 'reject':
                    if cr.entity_type == ChangeRequest.ENTITY_VEHICLE and cr.vehicle is not None:
                        vehicle = cr.vehicle
                        if getattr(vehicle, 'status', None) == Vehicle.STATUS_PENDING:
                            vehicle.status = Vehicle.STATUS_REJECTED
                            vehicle.save(update_fields=['status'])

                    cr.status = ChangeRequest.STATUS_REJECTED
                    cr.review_notes = notes
                    cr.reviewed_at = timezone.now()
                    cr.save(update_fields=['status', 'review_notes', 'reviewed_at'])

                    try:
                        payload = {
                            'recipient_id': str(cr.user_id),
                            'user_id': str(cr.user_id),
                            'driver_id': '0',
                            'title': 'Change request rejected',
                            'body': 'Your requested changes were rejected by admin.',
                            'data': {
                                'type': 'change_request_reviewed',
                                'status': str(cr.status),
                                'change_request_id': str(cr.id),
                                'entity_type': str(cr.entity_type),
                            },
                        }
                        send_ride_notification_async(payload)
                    except Exception:
                        pass

                return redirect('administration:change_request_detail', change_request_id=cr.id)
            except Exception as e:
                error = str(e)

    return render(request, 'administration/change_request_detail.html', {
        'cr': cr,
        'compare_rows': compare_rows,
        'error': error,
    })


@login_required
def admin_booking_map_view(request, booking_pk):
    """Admin page to visualize a single booking on the map with distance and price totals."""
    booking = get_object_or_404(
        Booking.objects.select_related('trip', 'from_stop', 'to_stop', 'passenger'),
        pk=booking_pk,
    )
    trip = booking.trip

    trip_meta_data = {
        'trip_id': trip.trip_id,
        'driver_id': trip.driver_id,
        'driver_name': getattr(getattr(trip, 'driver', None), 'name', None),
        'driver_profile_photo': getattr(getattr(trip, 'driver', None), 'profile_photo_url', None),
    }

    _attach_latest_payments([booking])

    from_order = booking.from_stop.stop_order
    to_order = booking.to_stop.stop_order

    booking_span_data = {
        'from_order': from_order,
        'to_order': to_order,
    }

    booking_meta_data = {
        'booking_id': booking.id,
        'booking_code': getattr(booking, 'booking_id', None),
        'passenger_id': booking.passenger_id,
        'passenger_name': getattr(getattr(booking, 'passenger', None), 'name', None),
        'passenger_profile_photo': getattr(getattr(booking, 'passenger', None), 'profile_photo_url', None),
        'from_stop_name': getattr(getattr(booking, 'from_stop', None), 'stop_name', None),
        'to_stop_name': getattr(getattr(booking, 'to_stop', None), 'stop_name', None),
        'from_stop_lat': float(booking.from_stop.latitude) if (getattr(booking, 'from_stop', None) is not None and getattr(booking.from_stop, 'latitude', None) is not None) else None,
        'from_stop_lng': float(booking.from_stop.longitude) if (getattr(booking, 'from_stop', None) is not None and getattr(booking.from_stop, 'longitude', None) is not None) else None,
        'to_stop_lat': float(booking.to_stop.latitude) if (getattr(booking, 'to_stop', None) is not None and getattr(booking.to_stop, 'latitude', None) is not None) else None,
        'to_stop_lng': float(booking.to_stop.longitude) if (getattr(booking, 'to_stop', None) is not None and getattr(booking.to_stop, 'longitude', None) is not None) else None,
        'passenger_to_driver_rating': float(booking.driver_rating) if getattr(booking, 'driver_rating', None) is not None else None,
        'passenger_to_driver_comment': getattr(booking, 'driver_feedback', None),
        'driver_to_passenger_rating': float(booking.passenger_rating) if getattr(booking, 'passenger_rating', None) is not None else None,
        'driver_to_passenger_comment': getattr(booking, 'passenger_feedback', None),
    }

    segments = (
        TripStopBreakdown.objects
        .filter(trip=trip, from_stop_order__gte=from_order, to_stop_order__lte=to_order)
        .order_by('from_stop_order')
    )

    segments_path_coords_data = []
    for s in segments:
        try:
            if s.from_latitude and s.from_longitude and s.to_latitude and s.to_longitude:
                segments_path_coords_data.append([float(s.from_latitude), float(s.from_longitude)])
                segments_path_coords_data.append([float(s.to_latitude), float(s.to_longitude)])
        except Exception:
            pass

    agg = segments.aggregate(
        total_distance=Sum('distance_km'),
        total_price=Sum('price'),
    )

    # Route stops for this trip (full route, so we can show grey markers outside booking span)
    route_stops = []
    route_stops_data = []
    try:
        route = getattr(trip, 'route', None)
        if route is not None:
            route_stops = list(
                route.route_stops
                .all()
                .order_by('stop_order')
            )
            for rs in route_stops:
                if getattr(rs, 'latitude', None) and getattr(rs, 'longitude', None):
                    route_stops_data.append({
                        'name': rs.stop_name,
                        'order': rs.stop_order,
                        'lat': float(rs.latitude),
                        'lng': float(rs.longitude),
                    })
    except Exception:
        # If for some reason route stops cannot be loaded, fall back gracefully
        route_stops = []
        route_stops_data = []

    # Dense geometry for the whole route, if available
    route_geometry = []
    route_geometry_data = []
    try:
        route = getattr(trip, 'route', None)
        if route is not None:
            route_geometry = route.route_geometry or []
            for p in route_geometry:
                try:
                    if isinstance(p, dict) and 'lat' in p and 'lng' in p:
                        route_geometry_data.append({'lat': float(p['lat']), 'lng': float(p['lng'])})
                except Exception:
                    pass
    except Exception:
        route_geometry = []
        route_geometry_data = []

    context = {
        'booking': booking,
        'trip': trip,
        'trip_meta_data': trip_meta_data,
        'booking_meta_data': booking_meta_data,
        'segments': segments,
        'segments_path_coords_data': segments_path_coords_data,
        'total_distance': agg['total_distance'] or 0,
        'total_price': agg['total_price'] or 0,
        'route_stops': route_stops,
        'route_stops_data': route_stops_data,
        'route_geometry': route_geometry,
        'route_geometry_data': route_geometry_data,
        'booking_from_order': from_order,
        'booking_to_order': to_order,
        'booking_span_data': booking_span_data,
    }

    sos_incidents = (
        SosIncident.objects
        .filter(trip=trip, status='OPEN')
        .select_related('actor', 'booking')
        .order_by('-created_at')
    )
    sos_markers_data = []
    for i in sos_incidents:
        try:
            sos_markers_data.append({
                'id': i.id,
                'lat': float(i.latitude),
                'lng': float(i.longitude),
                'role': i.role,
                'booking_id': i.booking_id,
                'actor_id': i.actor_id,
                'actor_name': getattr(getattr(i, 'actor', None), 'name', None),
                'note': i.note,
                'created_at': i.created_at.isoformat() if getattr(i, 'created_at', None) else None,
            })
        except Exception:
            pass

    context['sos_incidents'] = sos_incidents
    context['sos_markers_data'] = sos_markers_data

    return render(request, 'administration/booking_map.html', context)

@login_required
def api_kpis(request):
    today = timezone.localdate()
    start_7d = today - timedelta(days=6)

    active_users = UsersData.objects.exclude(status='BANNED').count()
    rides_today = Trip.objects.filter(trip_date=today).count()

    cancellations_today = (
        Booking.objects.filter(booking_status='CANCELLED', cancelled_at__date=today).count()
        + Trip.objects.filter(trip_status='CANCELLED', cancelled_at__date=today).count()
    )

    completed_trips_today = Trip.objects.filter(trip_status='COMPLETED', trip_date=today).count()

    avg_wait_duration = (
        Booking.objects
        .filter(pickup_verified_at__isnull=False, booked_at__date__gte=start_7d, booked_at__date__lte=today)
        .aggregate(
            avg=Avg(
                ExpressionWrapper(
                    F('pickup_verified_at') - F('booked_at'),
                    output_field=DurationField(),
                )
            )
        )
        .get('avg')
    )
    avg_wait_minutes = None
    if avg_wait_duration is not None:
        try:
            avg_wait_minutes = round(float(avg_wait_duration.total_seconds()) / 60.0, 2)
        except Exception:
            avg_wait_minutes = None

    data = {
        'active_users': active_users,
        'rides_today': rides_today,
        'cancellations': cancellations_today,
        'avg_wait_minutes': avg_wait_minutes,
        'completed_trips': completed_trips_today,
        'flagged_incidents': SosIncident.objects.filter(status='OPEN').count(),
    }
    return JsonResponse(data)


@login_required
def sos_dashboard_view(request):

    open_incidents = (
        SosIncident.objects
        .select_related('actor', 'trip', 'booking')
        .filter(status='OPEN')
        .order_by('-created_at')[:200]
    )
    resolved_incidents = (
        SosIncident.objects
        .select_related('actor', 'trip', 'booking', 'resolved_by')
        .filter(status='RESOLVED')
        .order_by('-resolved_at', '-created_at')[:100]
    )

    return render(
        request,
        'administration/sos_dashboard.html',
        {
            'open_incidents': open_incidents,
            'resolved_incidents': resolved_incidents,
        },
    )


@login_required
def sos_incident_detail_view(request, incident_id):

    incident = get_object_or_404(
        SosIncident.objects.select_related('actor', 'trip', 'booking', 'resolved_by'),
        pk=incident_id,
    )
    return render(
        request,
        'administration/sos_detail.html',
        {
            'incident': incident,
        },
    )


@require_http_methods(['POST'])
@csrf_protect
@login_required
def sos_incident_resolve_view(request, incident_id):

    incident = get_object_or_404(SosIncident, pk=incident_id)
    if incident.status != SosIncident.STATUS_RESOLVED:
        incident.status = SosIncident.STATUS_RESOLVED
        incident.resolved_at = timezone.now()
        incident.resolved_by = request.user
        note = (request.POST.get('resolved_note') or '').strip()
        incident.resolved_note = note or None
        incident.save()

        trip = getattr(incident, 'trip', None)
        booking = getattr(incident, 'booking', None)
        payload = _build_resolved_sos_snapshot_payload(incident)

        snap, _ = ResolvedSosAuditSnapshot.objects.get_or_create(
            incident_id=incident.id,
            defaults={
                'incident_obj': incident,
                'trip_id': getattr(trip, 'trip_id', None),
                'booking_id': getattr(booking, 'booking_id', None),
                'resolved_at': incident.resolved_at,
                'resolved_by_username': getattr(getattr(incident, 'resolved_by', None), 'username', None),
                'payload': payload,
            },
        )
        snap.incident_obj = incident
        snap.trip_id = getattr(trip, 'trip_id', None)
        snap.booking_id = getattr(booking, 'booking_id', None)
        snap.resolved_at = incident.resolved_at
        snap.resolved_by_username = getattr(getattr(incident, 'resolved_by', None), 'username', None)
        snap.payload = payload
        snap.updated_at = timezone.now()
        snap.save()

    return redirect('administration:sos_incident_detail', incident_id=incident.id)


@require_http_methods(['POST'])
@csrf_protect
@login_required
def resolved_sos_snapshot_regenerate_view(request, incident_id):

    incident = get_object_or_404(
        SosIncident.objects.select_related('trip', 'booking', 'actor', 'resolved_by', 'audit_event'),
        pk=incident_id,
    )

    if incident.status != SosIncident.STATUS_RESOLVED:
        return redirect('administration:sos_incident_detail', incident_id=incident.id)

    payload = _build_resolved_sos_snapshot_payload(incident)

    trip = getattr(incident, 'trip', None)
    booking = getattr(incident, 'booking', None)

    snap, _ = ResolvedSosAuditSnapshot.objects.get_or_create(
        incident_id=incident.id,
        defaults={
            'incident_obj': incident,
        },
    )
    snap.incident_obj = incident
    snap.trip_id = getattr(trip, 'trip_id', None)
    snap.booking_id = getattr(booking, 'booking_id', None)
    snap.resolved_at = incident.resolved_at
    snap.resolved_by_username = getattr(getattr(incident, 'resolved_by', None), 'username', None)
    snap.payload = payload
    snap.updated_at = timezone.now()
    snap.save()

    return redirect('administration:resolved_sos_snapshot_detail', incident_id=incident.id)


@login_required
def resolved_sos_snapshot_detail_view(request, incident_id):

    incident = get_object_or_404(
        SosIncident.objects.select_related('actor', 'trip', 'booking', 'resolved_by'),
        pk=incident_id,
    )
    snapshot = ResolvedSosAuditSnapshot.objects.filter(incident_id=incident.id).first()

    payload_pretty = None
    if snapshot is not None:
        try:
            payload_pretty = json.dumps(snapshot.payload or {}, indent=2, ensure_ascii=False)
        except Exception:
            payload_pretty = str(snapshot.payload)

    return render(
        request,
        'administration/resolved_sos_details.html',
        {
            'incident': incident,
            'snapshot': snapshot,
            'payload_pretty': payload_pretty,
        },
    )

@login_required
def api_chart_data(request):
    today = timezone.localdate()
    days = [today - timedelta(days=i) for i in range(6, -1, -1)]
    day_labels = [d.strftime('%a') for d in days]

    completed_by_day = []
    active_drivers_by_day = []
    active_riders_by_day = []
    avg_wait_by_day = []

    for d in days:
        completed_by_day.append(
            Trip.objects.filter(trip_status='COMPLETED', trip_date=d).count()
        )
        active_drivers_by_day.append(
            Trip.objects.filter(trip_date=d).values('driver_id').distinct().count()
        )
        active_riders_by_day.append(
            Booking.objects.filter(booked_at__date=d).values('passenger_id').distinct().count()
        )

        avg_wait_duration = (
            Booking.objects
            .filter(pickup_verified_at__isnull=False, booked_at__date=d)
            .aggregate(
                avg=Avg(
                    ExpressionWrapper(
                        F('pickup_verified_at') - F('booked_at'),
                        output_field=DurationField(),
                    )
                )
            )
            .get('avg')
        )
        if avg_wait_duration is None:
            avg_wait_by_day.append(None)
        else:
            try:
                avg_wait_by_day.append(round(float(avg_wait_duration.total_seconds()) / 60.0, 2))
            except Exception:
                avg_wait_by_day.append(None)

    # bookings in last 24h bucketed into 4-hour windows
    now = timezone.now()
    since = now - timedelta(hours=24)
    hour_counts = (
        Booking.objects
        .filter(booked_at__gte=since)
        .annotate(h=ExtractHour('booked_at'))
        .values('h')
        .annotate(c=Count('id'))
    )
    hour_map = {row['h']: row['c'] for row in hour_counts if row.get('h') is not None}
    by_hour_labels = ['0h', '4h', '8h', '12h', '16h', '20h', '24h']
    by_hour = [0, 0, 0, 0, 0, 0, 0]
    for h, c in hour_map.items():
        try:
            idx = int(h) // 4
            if idx < 0:
                idx = 0
            if idx > 5:
                idx = 5
            by_hour[idx] += int(c)
        except Exception:
            pass

    # Cancellation breakdown (approximation based on available DB fields)
    cancelled_bookings_7d = Booking.objects.filter(
        booking_status='CANCELLED',
        cancelled_at__date__gte=days[0],
        cancelled_at__date__lte=days[-1],
    ).count()
    cancelled_trips_7d = Trip.objects.filter(
        trip_status='CANCELLED',
        cancelled_at__date__gte=days[0],
        cancelled_at__date__lte=days[-1],
    ).count()
    cancelled_safety_7d = Trip.objects.filter(
        trip_status='CANCELLED',
        cancelled_at__date__gte=days[0],
        cancelled_at__date__lte=days[-1],
        cancellation_reason__icontains='safety',
    ).count()
    other_cancellations_7d = max(cancelled_trips_7d - cancelled_safety_7d, 0)
    cancel_reasons = [
        cancelled_bookings_7d,
        cancelled_trips_7d,
        cancelled_safety_7d,
        other_cancellations_7d,
    ]

    return JsonResponse({
        'labels': day_labels,
        'tsRides': completed_by_day,
        'byHourLabels': by_hour_labels,
        'byHour': by_hour,
        'drivers': active_drivers_by_day,
        'riders': active_riders_by_day,
        'cancelReasons': cancel_reasons,
        'completedTrips': completed_by_day,
        'avgWait': avg_wait_by_day,
    })


@login_required
def user_list_view(request):
    return render(request, 'administration/users_list.html')


def _combine_trip_dt(trip, t):
    try:
        d = getattr(trip, 'trip_date', None)
        if d is None or t is None:
            return None
        dt = datetime.combine(d, t)
        if timezone.is_naive(dt):
            dt = timezone.make_aware(dt)
        return dt
    except Exception:
        return None


def _compute_reached_trigger_dt(trip):
    dep_dt = _combine_trip_dt(trip, getattr(trip, 'departure_time', None))
    arr_dt = _combine_trip_dt(trip, getattr(trip, 'estimated_arrival_time', None))
    if dep_dt is None or arr_dt is None:
        return None, None, None

    if arr_dt <= dep_dt:
        arr_dt = arr_dt + timedelta(days=1)

    planned_hours = (arr_dt - dep_dt).total_seconds() / 3600.0
    if not (planned_hours > 0):
        planned_hours = 2.0

    delay_hours = max(2.0, min(12.0, float(planned_hours)))
    trigger_dt = arr_dt + timedelta(hours=delay_hours)
    return dep_dt, arr_dt, trigger_dt


@login_required
@require_http_methods(['GET'])
def reached_overdue_dashboard_view(request):
    if not getattr(request.user, 'is_staff', False):
        return JsonResponse({'success': False, 'error': 'Forbidden'}, status=403)

    now = timezone.now()
    status_filter = (request.GET.get('status') or '').strip().upper()
    if status_filter not in ['', 'SCHEDULED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED']:
        status_filter = ''

    trips_qs = (
        Trip.objects
        .exclude(trip_status='CANCELLED')
        .select_related('driver', 'route')
        .only(
            'id', 'trip_id', 'trip_date', 'departure_time', 'estimated_arrival_time',
            'trip_status',
            'driver__id', 'driver__name',
            'route__route_name',
        )
        .order_by('-trip_date', '-departure_time')
    )
    if status_filter:
        trips_qs = trips_qs.filter(trip_status=status_filter)

    driver_overdue = []
    passenger_overdue = []

    trips = list(trips_qs[:350])
    for trip in trips:
        dep_dt, arr_dt, trigger_dt = _compute_reached_trigger_dt(trip)
        if trigger_dt is None:
            continue
        if now < trigger_dt:
            continue

        if trip.trip_status != 'COMPLETED':
            driver_overdue.append({
                'trip': trip,
                'departure_dt': dep_dt,
                'arrival_dt': arr_dt,
                'trigger_dt': trigger_dt,
            })

        bookings = (
            Booking.objects
            .filter(trip=trip, booking_status='CONFIRMED')
            .select_related('passenger', 'from_stop', 'to_stop')
            .only(
                'id', 'booking_status', 'ride_status',
                'passenger__id', 'passenger__name',
                'from_stop__stop_name',
                'to_stop__stop_name',
            )
            .order_by('id')
        )
        for b in bookings:
            if getattr(b, 'ride_status', None) == 'DROPPED_OFF':
                continue
            passenger_overdue.append({
                'trip': trip,
                'booking': b,
                'departure_dt': dep_dt,
                'arrival_dt': arr_dt,
                'trigger_dt': trigger_dt,
            })

    return render(
        request,
        'administration/reached_overdue_dashboard.html',
        {
            'now': now,
            'status_filter': status_filter,
            'driver_overdue': driver_overdue,
            'passenger_overdue': passenger_overdue,
        },
    )


@login_required
def api_users(request):
    qs = UsersData.objects.all().values(
        'id','name','email','status','driver_rating','passenger_rating','created_at'
    )
    return JsonResponse({'users': list(qs)})


# --- User vehicles helpers and CRUD ---

def _vehicle_to_dict(v: Vehicle):
    return {
        'id': v.id,
        'model_number': v.model_number,
        'variant': v.variant,
        'company_name': v.company_name,
        'plate_number': v.plate_number,
        'vehicle_type': v.vehicle_type,
        'color': v.color,
        'photo_front_url': v.photo_front_url,
        'photo_back_url': v.photo_back_url,
        'documents_image_url': v.documents_image_url,
        'seats': v.seats,
        'engine_number': v.engine_number,
        'chassis_number': v.chassis_number,
        'fuel_type': v.fuel_type,
        'registration_date': v.registration_date.isoformat() if v.registration_date else None,
        'insurance_expiry': v.insurance_expiry.isoformat() if v.insurance_expiry else None,
        'created_at': v.created_at.isoformat() if getattr(v, 'created_at', None) else None,
        'updated_at': v.updated_at.isoformat() if getattr(v, 'updated_at', None) else None,
    }


@login_required
def api_user_vehicles(request, user_id):
    """Return JSON list of vehicles for a given user (admin view)."""
    user = get_object_or_404(UsersData, pk=user_id)
    vehicles = user.vehicles.all().order_by('-created_at')
    data = [_vehicle_to_dict(v) for v in vehicles]
    return JsonResponse({'user_id': user.id, 'vehicles': data})


@login_required
def user_vehicles_redirect_view(request, user_id):
    """Convenience URL that redirects to the user detail page where vehicles are listed."""
    return redirect('administration:user_detail', user_id=user_id)


@login_required
def user_detail_view(request, user_id):
    # api_user_detail(request, user_id)
    user = get_object_or_404(UsersData, pk=user_id)
    vehicles = user.vehicles.all().order_by('-created_at')
    emergency_contact = EmergencyContact.objects.filter(user=user).first()
    return render(
        request,
        'administration/users_detail.html',
        {
            'user_id': user_id,
            'user': user,
            'vehicles': vehicles,
            'emergency_contact': emergency_contact,
        },
    )


@login_required
def api_user_detail(request, user_id):
    user = get_object_or_404(UsersData, pk=user_id)
    data = {f: getattr(user, f) for f in [
        'id','name','username','email','address','phone_no','status','gender',
        'driver_rating','passenger_rating','cnic_no','driving_license_no',
        'accountno','bankname','iban','created_at','updated_at'
    ]}
    # Expose image URLs stored in UsersData (Supabase Storage paths)
    for img_url_field in [
        'profile_photo_url', 'live_photo_url',
        'cnic_front_image_url', 'cnic_back_image_url',
        'driving_license_front_url', 'driving_license_back_url',
        'accountqr_url',
    ]:
        data[img_url_field] = getattr(user, img_url_field, None)
    return JsonResponse(data)


def _missing_required_user_verification_fields(user):
    missing = []
    if not (getattr(user, 'profile_photo_url', None) or ''):
        missing.append('profile_photo')
    if not (getattr(user, 'live_photo_url', None) or ''):
        missing.append('live_photo')
    if not (getattr(user, 'cnic_no', None) or ''):
        missing.append('cnic_no')
    if not (getattr(user, 'cnic_front_image_url', None) or ''):
        missing.append('cnic_front_image')
    if not (getattr(user, 'cnic_back_image_url', None) or ''):
        missing.append('cnic_back_image')
    return missing


def _user_has_scheduled_confirmed_trips(user_id: int) -> bool:
    try:
        return (
            Booking.objects
            .filter(
                trip__driver_id=user_id,
                trip__trip_status='SCHEDULED',
                booking_status__in=['CONFIRMED'],
            )
            .only('id')
            .exists()
        )
    except Exception:
        return False


# Update status via HTML form
@require_http_methods(['POST'])
@login_required
def update_user_status_view(request, user_id):
    user = get_object_or_404(UsersData, pk=user_id)
    status = request.POST.get('status')
    if status in ['PENDING','VERIFIED','REJECTED','BANNED']:
        current = (getattr(user, 'status', None) or '').strip().upper()
        target = (status or '').strip().upper()
        if target in ['PENDING', 'REJECTED', 'BANNED'] and _user_has_scheduled_confirmed_trips(user.id):
            vehicles = user.vehicles.all().order_by('-created_at')
            emergency_contact = EmergencyContact.objects.filter(user=user).first()
            return render(
                request,
                'administration/users_detail.html',
                {
                    'user_id': user_id,
                    'user': user,
                    'vehicles': vehicles,
                    'emergency_contact': emergency_contact,
                    'error': 'User has scheduled trips with confirmed passengers. Cancel trips first before changing verification status.',
                },
            )
        if status == 'VERIFIED':
            missing = _missing_required_user_verification_fields(user)
            if missing:
                vehicles = user.vehicles.all().order_by('-created_at')
                emergency_contact = EmergencyContact.objects.filter(user=user).first()
                return render(
                    request,
                    'administration/users_detail.html',
                    {
                        'user_id': user_id,
                        'user': user,
                        'vehicles': vehicles,
                        'emergency_contact': emergency_contact,
                        'error': 'Cannot set user as VERIFIED. Missing required verification fields: ' + ', '.join(missing),
                    },
                )
        user.status = status
        if status == 'REJECTED':
            reason = (request.POST.get('rejection_reason') or '').strip()
            user.rejection_reason = reason or None
        else:
            user.rejection_reason = None
        user.save()

        if current != target:
            try:
                title = 'Account status updated'
                body = f"Your account status is now {target}."
                if target == 'VERIFIED':
                    body = 'Your account has been verified.'
                elif target == 'REJECTED':
                    body = 'Your account verification was rejected.'
                elif target == 'BANNED':
                    body = 'Your account was banned. Please contact support.'
                elif target == 'PENDING':
                    body = 'Your account status is pending verification.'

                payload = {
                    'recipient_id': str(user.id),
                    'user_id': str(user.id),
                    'driver_id': '0',
                    'title': title,
                    'body': body,
                    'data': {
                        'type': 'user_status_updated',
                        'status': str(target),
                        'user_id': str(user.id),
                    },
                }
                send_ride_notification_async(payload)
            except Exception:
                pass
    return redirect('administration:user_detail', user_id=user_id)


def _sync_admin_todos(request) -> None:
    """Upsert todos based on current system state.

    This runs on page load to avoid needing Celery/Redis.
    """

    try:
        # 1) User verification todos
        pending_users = UsersData.objects.filter(status='PENDING').only('id', 'name', 'status').order_by('-created_at')[:400]
        pending_user_ids = set()
        for u in pending_users:
            pending_user_ids.add(int(u.id))
            AdminTodoItem.objects.get_or_create(
                source_type=AdminTodoItem.SOURCE_USER_VERIFICATION,
                source_id=int(u.id),
                defaults={
                    'title': f"Verify user: {u.name} (#{u.id})",
                    'details': None,
                    'link_url': reverse('administration:user_detail', kwargs={'user_id': u.id}),
                    'category': AdminTodoItem.CATEGORY_VERIFICATION,
                    'priority': AdminTodoItem.PRIORITY_HIGH,
                    'status': AdminTodoItem.STATUS_PENDING,
                },
            )

        # 2) SOS incidents todos
        open_incidents = SosIncident.objects.filter(status=SosIncident.STATUS_OPEN).only('id', 'status', 'created_at').order_by('-created_at')[:400]
        open_incident_ids = set()
        for i in open_incidents:
            open_incident_ids.add(int(i.id))
            AdminTodoItem.objects.get_or_create(
                source_type=AdminTodoItem.SOURCE_SOS_INCIDENT,
                source_id=int(i.id),
                defaults={
                    'title': f"Resolve SOS incident: #{i.id}",
                    'details': None,
                    'link_url': reverse('administration:sos_incident_detail', kwargs={'incident_id': i.id}),
                    'category': AdminTodoItem.CATEGORY_SOS,
                    'priority': AdminTodoItem.PRIORITY_HIGH,
                    'status': AdminTodoItem.STATUS_PENDING,
                },
            )

        # 3) Change request todos
        pending_crs = ChangeRequest.objects.filter(status=ChangeRequest.STATUS_PENDING).only('id', 'status', 'entity_type', 'created_at').order_by('-created_at')[:400]
        pending_cr_ids = set()
        for cr in pending_crs:
            pending_cr_ids.add(int(cr.id))
            AdminTodoItem.objects.get_or_create(
                source_type=AdminTodoItem.SOURCE_CHANGE_REQUEST,
                source_id=int(cr.id),
                defaults={
                    'title': f"Review change request: #{cr.id} ({cr.entity_type})",
                    'details': None,
                    'link_url': reverse('administration:change_request_detail', kwargs={'change_request_id': cr.id}),
                    'category': AdminTodoItem.CATEGORY_CHANGE_REQUEST,
                    'priority': AdminTodoItem.PRIORITY_MEDIUM,
                    'status': AdminTodoItem.STATUS_PENDING,
                },
            )

        # 4) Support thread todos (only when latest unread sender is USER)
        latest_msg = (
            SupportMessage.objects
            .filter(thread_id=OuterRef('pk'))
            .order_by('-id')
        )
        threads = (
            SupportThread.objects
            .filter(is_closed=False)
            .annotate(latest_message_id=Subquery(latest_msg.values('id')[:1]))
            .annotate(latest_sender_type=Subquery(latest_msg.values('sender_type')[:1]))
            .select_related('user', 'guest')
            .only('id', 'user_id', 'guest_id', 'thread_type', 'is_closed', 'admin_last_seen_id', 'last_message_at', 'updated_at', 'user__id', 'user__name', 'guest__id', 'guest__username')
            .order_by('-last_message_at')[:500]
        )
        pending_thread_ids = set()
        for t in threads:
            try:
                latest_id = int(getattr(t, 'latest_message_id', 0) or 0)
                if latest_id <= int(getattr(t, 'admin_last_seen_id', 0) or 0):
                    continue
                if (getattr(t, 'latest_sender_type', None) or '').upper() != 'USER':
                    continue

                pending_thread_ids.add(int(t.id))
                if t.user_id:
                    title = f"Reply user: {getattr(getattr(t, 'user', None), 'name', '')} (#{t.user_id})"
                    link_url = reverse('administration:user_support_chat', kwargs={'user_id': t.user_id})
                    category = AdminTodoItem.CATEGORY_SUPPORT_USER
                else:
                    title = f"Reply guest: {getattr(getattr(t, 'guest', None), 'username', '')} (#{t.guest_id})"
                    link_url = reverse('administration:guest_support_chat', kwargs={'guest_id': t.guest_id})
                    category = AdminTodoItem.CATEGORY_SUPPORT_GUEST

                AdminTodoItem.objects.get_or_create(
                    source_type=AdminTodoItem.SOURCE_SUPPORT_THREAD,
                    source_id=int(t.id),
                    defaults={
                        'title': title,
                        'details': None,
                        'link_url': link_url,
                        'category': category,
                        'priority': AdminTodoItem.PRIORITY_MEDIUM,
                        'status': AdminTodoItem.STATUS_PENDING,
                    },
                )
            except Exception:
                continue

        # Auto-complete / reopen (unless manually done)
        todo_qs = AdminTodoItem.objects.all().only('id', 'source_type', 'source_id', 'status', 'manual_done', 'done_at')
        for todo in todo_qs[:2000]:
            try:
                st = todo.source_type
                sid = int(todo.source_id)
                resolved = False
                pending = False

                if st == AdminTodoItem.SOURCE_USER_VERIFICATION:
                    pending = sid in pending_user_ids
                    resolved = not pending
                elif st == AdminTodoItem.SOURCE_SOS_INCIDENT:
                    pending = sid in open_incident_ids
                    resolved = not pending
                elif st == AdminTodoItem.SOURCE_CHANGE_REQUEST:
                    pending = sid in pending_cr_ids
                    resolved = not pending
                elif st == AdminTodoItem.SOURCE_SUPPORT_THREAD:
                    pending = sid in pending_thread_ids
                    resolved = not pending

                if resolved and todo.status != AdminTodoItem.STATUS_DONE and not todo.manual_done:
                    todo.mark_done(by_user=None, manual=False)
                if pending and todo.status == AdminTodoItem.STATUS_DONE and not todo.manual_done:
                    todo.reopen()
            except Exception:
                continue
    except Exception:
        return


@require_http_methods(['GET'])
@login_required
def todos_inbox_view(request):
    _sync_admin_todos(request)

    status_filter = (request.GET.get('status') or 'PENDING').strip().upper()
    priority_filter = (request.GET.get('priority') or '').strip().upper()
    category_filter = (request.GET.get('category') or '').strip().upper()
    sort = (request.GET.get('sort') or '').strip().lower()

    qs = AdminTodoItem.objects.all()

    if status_filter in (AdminTodoItem.STATUS_PENDING, AdminTodoItem.STATUS_DONE):
        qs = qs.filter(status=status_filter)
    else:
        status_filter = ''

    if priority_filter in (AdminTodoItem.PRIORITY_LOW, AdminTodoItem.PRIORITY_MEDIUM, AdminTodoItem.PRIORITY_HIGH):
        qs = qs.filter(priority=priority_filter)
    else:
        priority_filter = ''

    if category_filter in {c[0] for c in AdminTodoItem.CATEGORY_CHOICES}:
        qs = qs.filter(category=category_filter)
    else:
        category_filter = ''

    if sort == 'done_desc':
        qs = qs.order_by('-done_at', '-updated_at')
    elif sort == 'priority_desc':
        qs = qs.order_by('-priority', '-created_at')
    elif sort == 'created_asc':
        qs = qs.order_by('created_at')
    else:
        qs = qs.order_by('-created_at')

    embed = (request.GET.get('embed') or '').strip() in {'1', 'true', 'yes'}
    template_name = 'administration/todos_inbox_embed.html' if embed else 'administration/todos_inbox.html'

    return render(request, template_name, {
        'todos': qs[:500],
        'status_filter': status_filter,
        'priority_filter': priority_filter,
        'category_filter': category_filter,
        'sort': sort,
        'category_choices': AdminTodoItem.CATEGORY_CHOICES,
        'priority_choices': AdminTodoItem.PRIORITY_CHOICES,
        'status_choices': AdminTodoItem.STATUS_CHOICES,
    })


@require_http_methods(['POST'])
@csrf_protect
@login_required
def todo_mark_done_view(request, todo_id):
    todo = get_object_or_404(AdminTodoItem, pk=todo_id)
    todo.mark_done(by_user=request.user, manual=True)

    embed = (request.GET.get('embed') or '').strip() in {'1', 'true', 'yes'}
    if embed:
        return redirect(reverse('administration:todos_inbox') + '?embed=1')
    back = request.META.get('HTTP_REFERER')
    if back:
        return redirect(back)
    return redirect('administration:todos_inbox')


@require_http_methods(['POST'])
@csrf_protect
@login_required
def todo_reopen_view(request, todo_id):
    todo = get_object_or_404(AdminTodoItem, pk=todo_id)
    todo.reopen()

    embed = (request.GET.get('embed') or '').strip() in {'1', 'true', 'yes'}
    if embed:
        return redirect(reverse('administration:todos_inbox') + '?embed=1')
    back = request.META.get('HTTP_REFERER')
    if back:
        return redirect(back)
    return redirect('administration:todos_inbox')
# 3) Edit page HTML form
@login_required
def user_edit_view(request, user_id):
    user = get_object_or_404(UsersData, pk=user_id)
    emergency_contact = EmergencyContact.objects.filter(user=user).first()
    return render(
        request,
        'administration/users_edit.html',
        {'user': user, 'user_id': user_id, 'emergency_contact': emergency_contact},
    )
# Handle edit form submission
@require_http_methods(['POST'])
@login_required
def submit_user_edit(request, user_id):
    user = get_object_or_404(UsersData, pk=user_id)
    user.name = request.POST.get('name')
    user.username = request.POST.get('username')
    user.email = request.POST.get('email')
    password = request.POST.get('password')
    if password:
        user.password = make_password(password)
    user.address = request.POST.get('address')
    phone_no = request.POST.get('phone_no')
    # Ensure phone number has + prefix for international format
    if phone_no and not phone_no.startswith('+'):
        phone_no = '+' + phone_no
    user.phone_no = phone_no
    user.gender = request.POST.get('gender')
    user.status = request.POST.get('status')
    user.driver_rating = request.POST.get('driver_rating') or None
    user.passenger_rating = request.POST.get('passenger_rating') or None
    user.cnic_no = request.POST.get('cnic_no')
    user.driving_license_no = (request.POST.get('driving_license_no') or '').strip() or None
    user.accountno = (request.POST.get('accountno') or '').strip() or None
    user.iban = (request.POST.get('iban') or '').strip() or None
    user.bankname = (request.POST.get('bankname') or '').strip() or None

    user_bucket = getattr(settings, 'SUPABASE_USER_BUCKET', 'user-images')
    stamp = int(pytime.time())
    email = (user.email or '').strip()
    if email:
        profile_photo = request.FILES.get('profile_photo')
        live_photo = request.FILES.get('live_photo')
        cnic_front = request.FILES.get('cnic_front_image')
        cnic_back = request.FILES.get('cnic_back_image')
        dl_front = request.FILES.get('driving_license_front')
        dl_back = request.FILES.get('driving_license_back')
        accountqr = request.FILES.get('accountqr')

        if profile_photo:
            ext = (getattr(profile_photo, 'name', '') or 'jpg').rsplit('.', 1)[-1].lower()
            dest = f"users/{email}/profile_photo.{ext}"
            user.profile_photo_url = upload_to_supabase(user_bucket, profile_photo, dest)
        if live_photo:
            ext = (getattr(live_photo, 'name', '') or 'jpg').rsplit('.', 1)[-1].lower()
            dest = f"users/{email}/live_photo.{ext}"
            user.live_photo_url = upload_to_supabase(user_bucket, live_photo, dest)
        if cnic_front:
            ext = (getattr(cnic_front, 'name', '') or 'jpg').rsplit('.', 1)[-1].lower()
            dest = f"users/{email}/cnic_front_{stamp}.{ext}"
            user.cnic_front_image_url = upload_to_supabase(user_bucket, cnic_front, dest)
        if cnic_back:
            ext = (getattr(cnic_back, 'name', '') or 'jpg').rsplit('.', 1)[-1].lower()
            dest = f"users/{email}/cnic_back_{stamp}.{ext}"
            user.cnic_back_image_url = upload_to_supabase(user_bucket, cnic_back, dest)
        if dl_front:
            ext = (getattr(dl_front, 'name', '') or 'jpg').rsplit('.', 1)[-1].lower()
            dest = f"users/{email}/driving_license_front_{stamp}.{ext}"
            user.driving_license_front_url = upload_to_supabase(user_bucket, dl_front, dest)
        if dl_back:
            ext = (getattr(dl_back, 'name', '') or 'jpg').rsplit('.', 1)[-1].lower()
            dest = f"users/{email}/driving_license_back_{stamp}.{ext}"
            user.driving_license_back_url = upload_to_supabase(user_bucket, dl_back, dest)
        if accountqr:
            ext = (getattr(accountqr, 'name', '') or 'png').rsplit('.', 1)[-1].lower()
            dest = f"users/{email}/account_qr_{stamp}.{ext}"
            user.accountqr_url = upload_to_supabase(user_bucket, accountqr, dest)
    try:
        if (getattr(user, 'status', None) or '').strip().upper() in ['PENDING', 'REJECTED', 'BANNED']:
            if _user_has_scheduled_confirmed_trips(user.id):
                raise ValueError('User has scheduled trips with confirmed passengers. Cancel trips first before changing verification status.')

        emergency_name = (request.POST.get('emergency_name') or '').strip()
        emergency_relation = (request.POST.get('emergency_relation') or '').strip()
        emergency_email = (request.POST.get('emergency_email') or '').strip()
        emergency_phone_no = (request.POST.get('emergency_phone_no') or '').strip()
        ec = EmergencyContact.objects.filter(user=user).first()

        if any([emergency_name, emergency_relation, emergency_email, emergency_phone_no]):
            if not all([emergency_name, emergency_relation, emergency_email, emergency_phone_no]):
                raise ValueError('Emergency contact is incomplete. Provide name, relation, email, and phone (or leave all empty).')
            if ec is None:
                ec = EmergencyContact(user=user)
            ec.name = emergency_name
            ec.relation = emergency_relation
            ec.email = emergency_email
            phone_digits = emergency_phone_no[1:] if emergency_phone_no.startswith('+') else emergency_phone_no
            if (not phone_digits.isdigit()) or (len(phone_digits) < 10) or (len(phone_digits) > 15):
                raise ValueError('Emergency phone must be 10-15 digits.')
            ec.phone_no = phone_digits
            ec.full_clean()

        user.full_clean()

        if (getattr(user, 'status', None) or '').strip().upper() == 'VERIFIED':
            missing = _missing_required_user_verification_fields(user)
            if missing:
                raise ValueError('Cannot set user as VERIFIED. Missing required verification fields: ' + ', '.join(missing))

        user.save()

        if any([emergency_name, emergency_relation, emergency_email, emergency_phone_no]):
            ec.save()
        else:
            if ec is not None:
                ec.delete()

        return redirect('administration:user_detail', user_id=user_id)
    except Exception as e:
        emergency_contact = EmergencyContact.objects.filter(user=user).first()
        return render(
            request,
            'administration/users_edit.html',
            {'user': user, 'user_id': user_id, 'error': str(e), 'emergency_contact': emergency_contact},
        )


@login_required
def vehicle_detail_view(request, user_id):
    """Show a dedicated page listing all vehicles for a given user."""
    user = get_object_or_404(UsersData, pk=user_id)
    vehicles = user.vehicles.all().order_by('-created_at')
    return render(
        request,
        'administration/vehicle_detail.html',
        {
            'user': user,
            'vehicles': vehicles,
            'user_id': user_id,
        },
    )


@csrf_protect
@login_required
def vehicle_add_view(request, user_id):
    user = get_object_or_404(UsersData, pk=user_id)
    if request.method == 'POST':
        v = Vehicle(owner=user)
        v.model_number = request.POST.get('model_number') or ''
        v.variant = request.POST.get('variant') or ''
        v.company_name = request.POST.get('company_name') or ''
        v.plate_number = request.POST.get('plate_number') or ''
        v.vehicle_type = request.POST.get('vehicle_type') or Vehicle.TWO_WHEELER
        v.color = request.POST.get('color') or ''
        v.status = Vehicle.STATUS_VERIFIED
        seats_raw = request.POST.get('seats')
        v.seats = int(seats_raw) if seats_raw else None
        v.engine_number = request.POST.get('engine_number') or ''
        v.chassis_number = request.POST.get('chassis_number') or ''
        v.fuel_type = request.POST.get('fuel_type') or ''
        reg_date = request.POST.get('registration_date') or None
        ins_date = request.POST.get('insurance_expiry') or None
        from datetime import datetime
        if reg_date:
            try:
                v.registration_date = datetime.strptime(reg_date, '%Y-%m-%d').date()
            except ValueError:
                pass
        if ins_date:
            try:
                v.insurance_expiry = datetime.strptime(ins_date, '%Y-%m-%d').date()
            except ValueError:
                pass
        try:
            v.full_clean()

            front = request.FILES.get('photo_front')
            back = request.FILES.get('photo_back')
            docs = request.FILES.get('documents_image')

            if front or back or docs:
                vehicle_bucket = getattr(settings, 'SUPABASE_VEHICLE_BUCKET', 'vehicle-images')
                stamp = int(pytime.time())
                plate = (v.plate_number or '').strip().upper().replace(' ', '')

                if front:
                    ext = (getattr(front, 'name', '') or 'jpg').rsplit('.', 1)[-1].lower()
                    dest = f"vehicles/{user.id}/{plate}/front_{stamp}.{ext}"
                    v.photo_front_url = upload_to_supabase(vehicle_bucket, front, dest)
                if back:
                    ext = (getattr(back, 'name', '') or 'jpg').rsplit('.', 1)[-1].lower()
                    dest = f"vehicles/{user.id}/{plate}/back_{stamp}.{ext}"
                    v.photo_back_url = upload_to_supabase(vehicle_bucket, back, dest)
                if docs:
                    ext = (getattr(docs, 'name', '') or 'jpg').rsplit('.', 1)[-1].lower()
                    dest = f"vehicles/{user.id}/{plate}/documents_{stamp}.{ext}"
                    v.documents_image_url = upload_to_supabase(vehicle_bucket, docs, dest)

            v.full_clean()
            v.save()
            return redirect('administration:vehicle_detail', user_id=user_id)
        except Exception as e:
            return render(
                request,
                'administration/vehicle_edit.html',
                {'user': user, 'vehicle': v, 'user_id': user_id, 'error': str(e), 'is_new': True},
            )

    # GET: empty form
    return render(
        request,
        'administration/vehicle_edit.html',
        {'user': user, 'vehicle': None, 'user_id': user_id, 'is_new': True},
    )


@csrf_protect
@login_required
def vehicle_edit_view(request, user_id, vehicle_id):
    user = get_object_or_404(UsersData, pk=user_id)
    vehicle = get_object_or_404(Vehicle, pk=vehicle_id, owner=user)
    if request.method == 'POST':
        vehicle.model_number = request.POST.get('model_number') or ''
        vehicle.variant = request.POST.get('variant') or ''
        vehicle.company_name = request.POST.get('company_name') or ''
        vehicle.plate_number = request.POST.get('plate_number') or ''
        vehicle.vehicle_type = request.POST.get('vehicle_type') or Vehicle.TWO_WHEELER
        vehicle.color = request.POST.get('color') or ''
        seats_raw = request.POST.get('seats')
        vehicle.seats = int(seats_raw) if seats_raw else None
        vehicle.engine_number = request.POST.get('engine_number') or ''
        vehicle.chassis_number = request.POST.get('chassis_number') or ''
        vehicle.fuel_type = request.POST.get('fuel_type') or ''
        reg_date = request.POST.get('registration_date') or None
        ins_date = request.POST.get('insurance_expiry') or None
        from datetime import datetime
        if reg_date:
            try:
                vehicle.registration_date = datetime.strptime(reg_date, '%Y-%m-%d').date()
            except ValueError:
                pass
        if ins_date:
            try:
                vehicle.insurance_expiry = datetime.strptime(ins_date, '%Y-%m-%d').date()
            except ValueError:
                pass
        try:
            vehicle.full_clean()

            front = request.FILES.get('photo_front')
            back = request.FILES.get('photo_back')
            docs = request.FILES.get('documents_image')

            if front or back or docs:
                vehicle_bucket = getattr(settings, 'SUPABASE_VEHICLE_BUCKET', 'vehicle-images')
                stamp = int(pytime.time())
                plate = (vehicle.plate_number or '').strip().upper().replace(' ', '')

                if front:
                    ext = (getattr(front, 'name', '') or 'jpg').rsplit('.', 1)[-1].lower()
                    dest = f"vehicles/{user.id}/{plate}/front_{stamp}.{ext}"
                    vehicle.photo_front_url = upload_to_supabase(vehicle_bucket, front, dest)
                if back:
                    ext = (getattr(back, 'name', '') or 'jpg').rsplit('.', 1)[-1].lower()
                    dest = f"vehicles/{user.id}/{plate}/back_{stamp}.{ext}"
                    vehicle.photo_back_url = upload_to_supabase(vehicle_bucket, back, dest)
                if docs:
                    ext = (getattr(docs, 'name', '') or 'jpg').rsplit('.', 1)[-1].lower()
                    dest = f"vehicles/{user.id}/{plate}/documents_{stamp}.{ext}"
                    vehicle.documents_image_url = upload_to_supabase(vehicle_bucket, docs, dest)

            vehicle.full_clean()
            vehicle.save()
            return redirect('administration:vehicle_detail', user_id=user_id)
        except Exception as e:
            return render(
                request,
                'administration/vehicle_edit.html',
                {'user': user, 'vehicle': vehicle, 'user_id': user_id, 'error': str(e), 'is_new': False},
            )

    # GET: pre-filled form
    return render(
        request,
        'administration/vehicle_edit.html',
        {'user': user, 'vehicle': vehicle, 'user_id': user_id, 'is_new': False},
    )


@require_http_methods(['POST'])
@csrf_protect
@login_required
def vehicle_delete_view(request, user_id, vehicle_id):
    user = get_object_or_404(UsersData, pk=user_id)
    vehicle = get_object_or_404(Vehicle, pk=vehicle_id, owner=user)
    vehicle.delete()
    return redirect('administration:user_detail', user_id=user_id)


@require_http_methods(['POST'])
@csrf_protect
@login_required
def vehicle_update_status_view(request, user_id, vehicle_id):
    user = get_object_or_404(UsersData, pk=user_id)
    vehicle = get_object_or_404(Vehicle, pk=vehicle_id, owner=user)
    status = (request.POST.get('status') or '').strip().upper()
    if status not in [Vehicle.STATUS_PENDING, Vehicle.STATUS_VERIFIED, Vehicle.STATUS_REJECTED]:
        return redirect('administration:vehicle_detail', user_id=user_id)
    vehicle.status = status
    try:
        vehicle.full_clean()
    except Exception:
        pass
    vehicle.save(update_fields=['status', 'updated_at'])
    return redirect('administration:vehicle_detail', user_id=user_id)




@csrf_protect
def login_view(request):
    error_message = ''
    if request.method == 'POST':
        username = request.POST.get('username')
        password = request.POST.get('password')
        user_admin = authenticate(request, username=username, password=password)
        if user_admin is not None:
            login(request, user_admin)
            next_url = (request.POST.get('next') or request.GET.get('next') or '').strip()
            if next_url.startswith('/') and not next_url.startswith('//'):
                return redirect(next_url)
            return redirect('administration:admin_view')
        else:
            error_message = 'Invalid credentials'
    next_url = (request.GET.get('next') or '').strip()
    if not (next_url.startswith('/') and not next_url.startswith('//')):
        next_url = ''
    return render(request, 'administration/login.html', {'error_message': error_message, 'next': next_url})


@login_required
def logout_view(request):
    logout(request)
    return redirect('administration:login_view')

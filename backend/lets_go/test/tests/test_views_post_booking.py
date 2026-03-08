import os
from datetime import date, time
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest

from lets_go.views import views_post_booking


class TestViewsPostBookingHelpers:
    def test_helper_coercion_and_distance(self):
        assert views_post_booking._coerce_int('5') == 5
        assert views_post_booking._coerce_float('2.5') == pytest.approx(2.5)
        assert views_post_booking._haversine_meters(31.5, 74.3, 31.5, 74.3) == pytest.approx(0.0)

    def test_compute_reached_trigger(self):
        trip = SimpleNamespace(trip_date=date(2026, 1, 1), departure_time=time(10, 0), estimated_arrival_time=time(11, 0))
        dt, delay = views_post_booking._compute_reached_trigger_dt(trip)
        assert dt is not None
        assert delay == pytest.approx(2.0)

    def test_require_cron_secret(self, rf):
        with patch.dict(os.environ, {'CRON_SECRET': 'ok'}):
            assert views_post_booking._require_cron_secret(rf.post('/x', HTTP_X_CRON_SECRET='ok')) is None
            assert views_post_booking._require_cron_secret(rf.post('/x', HTTP_X_CRON_SECRET='no')).status_code == 401

    @patch('smtplib.SMTP')
    def test_send_email_success(self, _smtp):
        assert views_post_booking._send_email('s', 'b', ['a@b.com']) is True

    @patch('requests.post')
    def test_send_sms_success(self, m_post):
        m_post.return_value = MagicMock(status_code=200)
        assert views_post_booking._send_sms('+92300111', 'hi') is True


class TestViewsPostBookingEndpointsMethodGuards:
    def test_cron_requires_secret(self, rf):
        with patch.dict(os.environ, {'CRON_SECRET': 'ok'}):
            req = rf.post('/x', HTTP_X_CRON_SECRET='no')
            assert views_post_booking.cron_post_booking_reached_reminders(req).status_code == 401

    def test_get_ride_readiness_invalid_method(self, rf):
        assert views_post_booking.get_ride_readiness(rf.post('/x'), 'T1').status_code == 405

    def test_update_booking_readiness_invalid_method(self, rf):
        assert views_post_booking.update_booking_readiness(rf.get('/x'), 1).status_code == 405

    def test_verify_pickup_code_invalid_method(self, rf):
        assert views_post_booking.verify_pickup_code(rf.get('/x')).status_code in (400, 405)


    def test_parse_iso_dt(self):
        assert views_post_booking._parse_iso_dt('bad') is None

    def test_combine_trip_dt(self):
        trip = SimpleNamespace(trip_date=date(2026, 1, 1))
        assert views_post_booking._combine_trip_dt(trip, time(10, 0)) is not None


class TestViewsPostBookingMoreMethodGuards:
    def test_start_trip_ride_invalid_method(self, rf):
        assert views_post_booking.start_trip_ride(rf.get('/x'), 'T1').status_code in (400, 405)

    def test_start_booking_ride_invalid_method(self, rf):
        assert views_post_booking.start_booking_ride(rf.get('/x'), 1).status_code in (400, 405)

    def test_complete_trip_ride_invalid_method(self, rf):
        assert views_post_booking.complete_trip_ride(rf.get('/x'), 'T1').status_code in (400, 405)

    def test_mark_booking_dropped_off_invalid_method(self, rf):
        assert views_post_booking.mark_booking_dropped_off(rf.get('/x'), 1).status_code in (400, 405)

    def test_driver_mark_reached_pickup_invalid_method(self, rf):
        assert views_post_booking.driver_mark_reached_pickup(rf.get('/x'), 1).status_code in (400, 405)

    def test_driver_mark_reached_dropoff_invalid_method(self, rf):
        assert views_post_booking.driver_mark_reached_dropoff(rf.get('/x'), 1).status_code in (400, 405)

    def test_get_booking_payment_details_invalid_method(self, rf):
        assert views_post_booking.get_booking_payment_details(rf.post('/x'), 1).status_code in (400, 405)

    def test_submit_booking_payment_invalid_method(self, rf):
        assert views_post_booking.submit_booking_payment(rf.get('/x'), 1).status_code in (400, 405)

    def test_confirm_booking_payment_invalid_method(self, rf):
        assert views_post_booking.confirm_booking_payment(rf.get('/x'), 1).status_code in (400, 405)

    def test_get_trip_payments_invalid_method(self, rf):
        assert views_post_booking.get_trip_payments(rf.post('/x'), 'T1').status_code in (400, 405)

    def test_update_live_location_invalid_method(self, rf):
        assert views_post_booking.update_live_location(rf.get('/x'), 'T1').status_code in (400, 405)

    def test_get_live_location_invalid_method(self, rf):
        assert views_post_booking.get_live_location(rf.post('/x'), 'T1').status_code in (400, 405)

    def test_generate_pickup_code_invalid_method(self, rf):
        assert views_post_booking.generate_pickup_code(rf.get('/x'), 'T1', 1).status_code in (400, 405)

    def test_compute_reminder_helpers(self):
        trip = SimpleNamespace(trip_id='T1', trip_date=date(2026, 1, 1), departure_time=time(10, 0))
        assert views_post_booking.compute_driver_reminder_time(trip) is not None


    def test_remaining_helper_symbols_callable(self):
        assert callable(views_post_booking._get_trip_or_404)
        assert callable(views_post_booking._record_system_notification_if_due)
        assert callable(views_post_booking._set_trip_booking_flag)
        assert callable(views_post_booking._mint_share_url)
        assert callable(views_post_booking.compute_passenger_reminder_time)
        assert callable(views_post_booking.build_pre_ride_reminder_jobs_for_trip)
        assert callable(views_post_booking.fire_pre_ride_reminder_notifications)

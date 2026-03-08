from datetime import timedelta
from types import SimpleNamespace
from unittest.mock import patch

from lets_go.utils import auto_archive


class TestAutoArchive:
    def test_auto_archive_for_driver_invalid_driver(self):
        assert auto_archive.auto_archive_for_driver(driver_id=0) == 0

    @patch('lets_go.utils.auto_archive._archive_trip', side_effect=[True, False, True])
    @patch('lets_go.utils.auto_archive.Trip.objects.filter')
    def test_auto_archive_for_driver_limit(self, m_filter, _m_archive):
        trips = [SimpleNamespace(), SimpleNamespace(), SimpleNamespace()]
        m_filter.return_value.select_related.return_value.order_by.return_value.iterator.return_value = trips
        assert auto_archive.auto_archive_for_driver(driver_id=3, limit=2) == 2

    @patch('lets_go.utils.auto_archive._archive_trip', return_value=True)
    @patch('lets_go.utils.auto_archive.Trip.objects.filter')
    def test_auto_archive_global(self, m_filter, _m_archive):
        trips = [SimpleNamespace(), SimpleNamespace()]
        m_filter.return_value.select_related.return_value.order_by.return_value.iterator.return_value = trips
        assert auto_archive.auto_archive_global(limit=5) == 2

    @patch('lets_go.utils.auto_archive.Booking.objects.filter')
    @patch('lets_go.utils.auto_archive.TripPayment.objects.filter')
    @patch('lets_go.utils.auto_archive.timezone.now')
    def test_archive_trip_skips_when_recent(self, m_now, m_pay, m_booking):
        now = __import__('datetime').datetime(2026,1,2,10,0,0)
        m_now.return_value = now
        m_booking.return_value.aggregate.return_value = {'max_dropoff': now, 'max_booking_updated': now, 'max_booking_completed': now}
        m_pay.return_value.aggregate.return_value = {'max_payment_completed': now}
        trip = SimpleNamespace(completed_at=now, cancelled_at=None, updated_at=now, trip_status='COMPLETED')
        assert auto_archive._archive_trip(trip) is False

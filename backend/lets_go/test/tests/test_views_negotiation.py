from types import SimpleNamespace
from datetime import datetime
from unittest.mock import patch

from lets_go.views import views_negotiation


class TestViewsNegotiationHelpers:
    def test_to_int_pkr(self):
        assert views_negotiation._to_int_pkr('22.7') == 23

    def test_serialize_booking_detail(self):
        b = SimpleNamespace(id=1, booking_id='B1', booking_status='PENDING', bargaining_status='PENDING',
                            passenger_offer=100, driver_counter_offer=120, final_agreed_fare=110,
                            number_of_seats=1, male_seats=1, female_seats=0, total_fare=110,
                            original_fare=120, negotiation_notes='n', responded_at=None, created_at=None,
                            negotiated_fare=110,
                            trip_id='T1',
                            trip=SimpleNamespace(trip_id='T1'),
                            passenger_id=2,
                            passenger=SimpleNamespace(id=2, name='P', gender='M', passenger_rating=4.1, profile_photo_url='x'),
                            from_stop_id=1,
                            from_stop=SimpleNamespace(id=1, stop_name='A', stop_order=1),
                            to_stop_id=2,
                            to_stop=SimpleNamespace(id=2, stop_name='B', stop_order=2),
                            booked_at=datetime(2026, 1, 1, 10, 0, 0))
        out = views_negotiation._serialize_booking_detail(b)
        assert out['booking_id'] == 1


class TestViewsNegotiationEndpoints:
    def test_handle_ride_booking_request_invalid_method(self, rf):
        assert views_negotiation.handle_ride_booking_request(rf.get('/x'), 'T1').status_code == 405

    def test_list_pending_requests_invalid_method(self, rf):
        assert views_negotiation.list_pending_requests(rf.post('/x'), 'T1').status_code == 405

    @patch('lets_go.views.views_negotiation.Trip.objects.filter')
    def test_list_pending_requests_not_found(self, m_filter, rf):
        m_filter.return_value.values_list.return_value.first.return_value = None
        assert views_negotiation.list_pending_requests(rf.get('/x'), 'missing').status_code == 404

    def test_booking_request_details_invalid_method(self, rf):
        assert views_negotiation.booking_request_details(rf.post('/x'), 'T1', 1).status_code == 405

    def test_respond_booking_request_invalid_method(self, rf):
        assert views_negotiation.respond_booking_request(rf.get('/x'), 'T1', 1).status_code == 405

    def test_unblock_passenger_for_trip_invalid_method(self, rf):
        assert views_negotiation.unblock_passenger_for_trip(rf.get('/x'), 'T1', 1).status_code == 405

    def test_passenger_respond_booking_invalid_method(self, rf):
        assert views_negotiation.passenger_respond_booking(rf.get('/x'), 'T1', 1).status_code == 405

    def test_get_booking_negotiation_history_invalid_method(self, rf):
        assert views_negotiation.get_booking_negotiation_history(rf.post('/x'), 'T1', 1).status_code == 405

    def test_request_ride_booking_invalid_method(self, rf):
        assert views_negotiation.request_ride_booking(rf.get('/x'), 'T1').status_code == 405

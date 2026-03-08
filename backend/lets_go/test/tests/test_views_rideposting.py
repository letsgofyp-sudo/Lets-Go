from datetime import datetime
from datetime import date, time
from types import SimpleNamespace
from unittest.mock import MagicMock

from lets_go.views import views_rideposting


class TestViewsRidePostingHelpers:
    def test_parse_limit_offset(self, rf):
        req = rf.get('/x?limit=5&offset=2')
        assert views_rideposting._parse_limit_offset(req) == (5, 2)

    def test_is_archived_after_24h(self):
        now = datetime(2026, 1, 2, 10, 0, 0)
        assert views_rideposting._is_archived_after_24h(datetime(2026, 1, 1, 8, 0, 0), now) is True

    def test_to_int_pkr(self):
        assert views_rideposting._to_int_pkr('120.4') == 120
        assert views_rideposting._to_int_pkr('bad', default=9) == 9

    def test_map_trip_status(self):
        assert views_rideposting.map_trip_status_to_frontend('COMPLETED')


class TestViewsRidePostingEndpoints:
    def test_create_trip_invalid_method(self, rf):
        assert views_rideposting.create_trip(rf.get('/x')).status_code == 405

    def test_cancel_booking_invalid_method(self, rf):
        assert views_rideposting.cancel_booking(rf.get('/x'), 1).status_code == 405

    def test_create_route_invalid_method(self, rf):
        assert views_rideposting.create_route(rf.get('/x')).status_code == 400

    def test_get_trip_breakdown_invalid_method(self, rf):
        assert views_rideposting.get_trip_breakdown(rf.post('/x'), 'T1').status_code == 400

    def test_get_user_created_rides_history_invalid_method(self, rf):
        assert views_rideposting.get_user_created_rides_history(rf.post('/x'), 1).status_code == 400

    def test_trigger_auto_archive_for_driver_invalid_method(self, rf):
        assert views_rideposting.trigger_auto_archive_for_driver(rf.put('/x'), 1).status_code == 405

    def test_get_user_booked_rides_history_invalid_method(self, rf):
        assert views_rideposting.get_user_booked_rides_history(rf.post('/x'), 1).status_code == 400

    def test_get_user_rides_invalid_method(self, rf):
        assert views_rideposting.get_user_rides(rf.post('/x'), 1).status_code == 400

    def test_get_trip_details_invalid_method(self, rf):
        assert views_rideposting.get_trip_details(rf.post('/x'), 'T1').status_code == 400

    def test_update_trip_invalid_method(self, rf):
        assert views_rideposting.update_trip(rf.post('/x'), 'T1').status_code == 400

    def test_delete_trip_invalid_method(self, rf):
        assert views_rideposting.delete_trip(rf.post('/x'), 'T1').status_code == 400

    def test_cancel_trip_invalid_method(self, rf):
        assert views_rideposting.cancel_trip(rf.get('/x'), 'T1').status_code == 400

    def test_get_route_details_invalid_method(self, rf):
        assert views_rideposting.get_route_details(rf.post('/x'), 1).status_code == 400

    def test_get_route_statistics_invalid_method(self, rf):
        assert views_rideposting.get_route_statistics(rf.post('/x'), 1).status_code == 400

    def test_search_routes_invalid_method(self, rf):
        assert views_rideposting.search_routes(rf.post('/x')).status_code == 400

    def test_get_available_seats_invalid_method(self, rf):
        assert views_rideposting.get_available_seats(rf.post('/x'), 1).status_code == 400

    def test_create_booking_invalid_method(self, rf):
        assert views_rideposting.create_booking(rf.get('/x')).status_code == 400

    def test_get_user_bookings_invalid_method(self, rf):
        assert views_rideposting.get_user_bookings(rf.post('/x'), 1).status_code == 400

    def test_search_rides_invalid_method(self, rf):
        assert views_rideposting.search_rides(rf.post('/x')).status_code == 400

    def test_cancel_ride_invalid_method(self, rf):
        assert views_rideposting.cancel_ride(rf.post('/x'), 1).status_code == 400


    def test_calculate_distance_helper(self):
        d = views_rideposting._calculate_distance(31.5, 74.3, 31.5, 74.3)
        assert d == 0

    def test_calculate_estimated_arrival(self):
        route = SimpleNamespace(total_distance_km=100)
        out = views_rideposting.calculate_estimated_arrival(time(10, 0), route)
        assert out is not None

    def test_trip_edit_delete_cancel_guards_helpers(self):
        trip_bookings = MagicMock()
        trip_bookings.filter.return_value.exists.return_value = False
        trip = SimpleNamespace(trip_status='SCHEDULED', trip_date=None, departure_time=None, trip_bookings=trip_bookings)
        assert isinstance(views_rideposting.can_edit_trip(trip), bool)
        assert isinstance(views_rideposting.can_delete_trip(trip), bool)
        assert isinstance(views_rideposting.can_cancel_trip(trip), bool)

    def test_update_trip_status_automatically_smoke(self):
        trip = SimpleNamespace(trip_status='SCHEDULED', trip_date=date(2026, 1, 1), departure_time=time(10, 0), save=lambda *a, **k: None)
        result = views_rideposting.update_trip_status_automatically(trip)
        assert result is trip

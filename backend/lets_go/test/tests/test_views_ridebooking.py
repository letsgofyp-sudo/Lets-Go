from lets_go.views import views_ridebooking


class TestViewsRideBooking:
    def test_get_ride_booking_details_invalid_method(self, rf):
        assert views_ridebooking.get_ride_booking_details(rf.post('/x'), 'T1').status_code == 405

    def test_get_confirmed_passengers_invalid_method(self, rf):
        assert views_ridebooking.get_confirmed_passengers(rf.post('/x'), 'T1').status_code == 405

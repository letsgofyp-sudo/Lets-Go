import 'live_tracking_controller.dart';

class PassengerLiveTrackingController extends LiveTrackingController {
  PassengerLiveTrackingController({
    required super.tripId,
    required int passengerId,
    required int bookingId,
  }) : super(
          currentUserId: passengerId,
          bookingId: bookingId,
          isDriver: false,
        );
}

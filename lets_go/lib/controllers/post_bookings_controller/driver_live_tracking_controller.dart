import 'live_tracking_controller.dart';

class DriverLiveTrackingController extends LiveTrackingController {
  DriverLiveTrackingController({
    required super.tripId,
    required int driverId,
  }) : super(
          currentUserId: driverId,
          isDriver: true,
        );
}

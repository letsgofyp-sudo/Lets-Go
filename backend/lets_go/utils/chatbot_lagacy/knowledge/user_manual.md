# LetsGo — User Manual

## 1) What is LetsGo?
LetsGo is a route-based ride sharing app.

- Drivers create trips (rides) on a specific route.
- Passengers search available trips and request seats.
- The app supports chat, fare negotiation, post-booking ride execution (pickup verification, live tracking), manual payments, and SOS/emergency reporting.

## 2) Guest mode vs logged-in
- Guest mode can be used for limited browsing and support chat.
- For personal features (your profile, your bookings, your rides, vehicles, payments, trip chat), you must log in.

## 3) Account status and verification (important)
Your account status can restrict what you’re allowed to do.

- VERIFIED: full access (subject to other rules)
- PENDING / UNDER_REVIEW: waiting for admin verification
- REJECTED: verification rejected (you may need to resubmit)
- BANNED / SUSPENDED: blocked from operations

### 3.1 Booking verification (Passenger)
Before you can book rides, the app may block you if:

- Your account is not VERIFIED.
- Your verification data is incomplete (e.g. required CNIC/photos).
- You have pending profile verification change requests (CNIC/Gender/Profile info).

If booking is blocked, open Profile and complete the missing verification steps, then wait for admin approval.

### 3.2 Creating rides verification (Driver)
Before you can create rides, the app may block you if:

- Your account is not VERIFIED.
- Your driver verification data is incomplete (CNIC + required photos + driving license number + license images).
- Driving license verification is pending.
- The selected vehicle is PENDING or not VERIFIED.

## 4) Profile
Use Profile to view and update:

- Basic info (name, email/phone, address)
- Gender
- Emergency contact
- Verification documents (CNIC, photos, driving license)

Some changes may create a “change request” that needs admin approval.

## 5) Vehicles (Driver)
Drivers add vehicles from Profile/Vehicles.

- A vehicle can have a verification status (e.g. PENDING / VERIFIED).
- If your vehicle is PENDING, you may not be able to create rides using that vehicle.

## 6) Finding rides (Passenger)
To find rides:

1. Go to Find/Search.
2. Select pickup and drop locations (stops).
3. Review available trips and open trip details.

## 7) Booking a ride (Passenger)
To request seats:

1. Open a trip.
2. Choose from/to stop orders (pickup/drop on that route).
3. Select number of seats.
4. Send booking request.

### 7.1 Fare negotiation (if enabled)
Some trips allow price negotiation.

- Passenger can submit an offer (per seat).
- Driver can accept, reject, or counter.
- Negotiation history is visible in the app.

## 8) My Bookings
My Bookings shows your booking list and history.

- You can open booking details to see `booking_id` and `trip_id`.
- Booking status depends on driver/admin decisions and ride execution progress.

## 9) My Rides / Trips (Driver)
Drivers can view trips they created.

- You can view trip details and passenger list.
- Some trips may be auto-archived by the system.

## 10) Chat (Post-booking / Trip chat)
Trip chat allows passengers and drivers to coordinate.

- Messages are associated with a `trip_id`.
- Some views use a polling “updates” API to load new messages.

## 11) Ride execution (after booking)
During ride execution, the system can support:

- Driver “start ride”
- Live location updates and passenger live tracking
- Pickup verification (pickup code)
- Marking reached pickup/dropoff
- Completing ride

## 12) Pickup code (verification)
The app can generate a pickup code for a booking and verify it to start the ride safely.

## 13) Payments (manual)
After ride completion, payments can be handled manually:

- Passenger can pay by CASH, or BANK TRANSFER/QR.
- If bank transfer/QR is used, passenger can upload a receipt.
- Passenger can also rate the driver and leave feedback.
- Driver can confirm payment received and rate the passenger.

## 14) Notifications
The app can send notifications for booking/trip/payment events.

- You can view notifications and unread counts.
- You can mark notifications read or dismiss them.

## 15) SOS / Emergency
If you feel unsafe, use SOS.

- SOS creates an incident and may generate shareable links/tokens.
- You can share live status with trusted contacts (depending on configuration).

## 16) Support chat (Bot + Admin)
Support provides:

- Bot chat for instant help
- Admin chat for human support

The support bot can answer help/manual/FAQ questions and can show some read-only information (for logged-in users), but it should not perform sensitive account-changing actions.

## 17) Troubleshooting
- If the app says verification is pending: complete missing documents in Profile and wait for admin approval.
- If you can’t book/create rides: check your account status (VERIFIED), pending change requests, driving license status, and vehicle verification status.
- If you can’t load trips/messages: check internet and server availability.


# Text-based Flowchart (copy into draw.io manually)

Below is a **pure textual flowchart** (nodes + arrows). You can recreate it in draw.io by making each `[]` a process box, each `< >` a decision diamond, and each `()` a terminator.

I’m giving you:
- **A) Main Post‑Booking Flow (Flutter)**
- **B) SOS Subflow (can happen anytime while tracking active)**
- **C) Public Share / Admin-Web Subflow (small Option B)**

---

## A) Main Post‑Booking Flow (Flutter: Driver + Passenger)

(START)  
→ `[Open Live Tracking Screen (TripId, UserId, Role=Driver/Passenger, BookingId?)]`  
→ [[LiveTrackingController.init()]](cci:1://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/lib/controllers/post_bookings_controller/live_tracking_controller.dart:238:2-260:3)  
→ `[Force stop any old tracking: setSendEnabled(false), BackgroundService.stop()]`  
→ `[Load Trip Layout (best-effort): GET /lets_go/ride-booking/<trip_id>/]`  
→ `[Start Polling Live State loop every 3s: GET /lets_go/trips/<trip_id>/location/?role=...&user_id=...&booking_id=...]`

→ `<Is user Driver?>`

### Driver branch
YES (Driver)  
→ `[User taps "Start Ride"]`  
→ [[Verification Gate check: ApiService.getVerificationGateStatus(userId)]](cci:1://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/lib/services/api_service.dart:569:2-584:3)  
→ `<Gate blocked?>`  
- YES → `[Show message + STOP]` → (END)  
- NO → `[POST Start Trip: POST /lets_go/trips/<trip_id>/start-ride/ {driver_id}]`  
→ `<Start success?>`  
- NO → `[Show error "Unable to start ride"]` → (END or stay on screen)  
- YES → `[Trip status becomes IN_PROGRESS (backend)]`  
→ `[Enable location sending]`  
→ `[Start background foreground-service (Android) OR foreground sender (iOS)]`  
→ `[Immediately send first point: POST /lets_go/trips/<trip_id>/location/update/]`

→ `[LOOP every 3s (Android Background Service OR iOS foreground)]`  
→ `[POST /lets_go/trips/<trip_id>/location/update/ {user_id, role=DRIVER, lat,lng,speed}]`  
→ `<Backend response says ignored/unauthorized?>`  
- YES → `[Stop service + clear queue + end session]` → (END)  
- NO → back to loop

→ `[LOOP every 3s Poll]`  
→ `[GET /lets_go/trips/<trip_id>/location/ (authorized)]`  
→ `<Trip status COMPLETED/CANCELLED?>`  
- YES → `[Stop tracking + stop polling]` → (END)  
- NO → `[Update map: driver marker + driver_path polyline + passenger list]` → back to poll loop

→ `[Optional Driver Actions during IN_PROGRESS]`  
→ `[Driver reached pickup: POST /lets_go/bookings/<booking_id>/driver-reached-pickup/ {driver_id}]`  
→ `[Optional: Generate pickup code: POST /lets_go/trips/<trip_id>/bookings/<booking_id>/pickup-code/ {driver_id,...}]`  
→ `[Driver reached dropoff: POST /lets_go/bookings/<booking_id>/driver-reached-dropoff/ {driver_id}]`  
→ `[Passenger is prompted to pay]`  
→ `[Driver completes trip: POST /lets_go/trips/<trip_id>/complete-ride/ {driver_id}]`  
→ (END)

---

### Passenger branch
NO (Passenger)  
→ `[User taps "Start Ride"]`  
→ [[Verification Gate check: ApiService.getVerificationGateStatus(userId)]](cci:1://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/lib/services/api_service.dart:569:2-584:3)  
→ `<Gate blocked?>`  
- YES → `[Show message + STOP]` → (END)  
- NO → `[POST Start Booking Ride: POST /lets_go/bookings/<booking_id>/start-ride/ {passenger_id}]`  
→ `<Start success?>`  
- NO → `[Show error]` → (END or stay on screen)  
- YES → `[Booking ride_status becomes RIDE_STARTED (backend)]`  
→ `[Enable location sending]`  
→ `[Start background service (Android) OR foreground sender (iOS)]`  
→ `[Immediately send first point: POST /lets_go/trips/<trip_id>/location/update/]`

→ `[LOOP every 3s Send]`  
→ `[POST /lets_go/trips/<trip_id>/location/update/ {user_id, role=PASSENGER, booking_id, lat,lng,speed}]`  
→ `<Backend response says ignored/unauthorized?>`  
- YES → `[Stop service + clear queue + end session]` → (END)  
- NO → back to loop

→ `[LOOP every 3s Poll]`  
→ `[GET /lets_go/trips/<trip_id>/location/ (authorized)]`  
→ `<Booking ride_status DROPPED_OFF / DROPPED_EARLY?>`  
- YES → `[Stop tracking + stop polling]` → `[Go to Payment Screen]`  
- NO → `[Update map: driver marker + driver_path polyline + ETAs]` → back to poll loop

→ `[Optional Passenger Actions]`  
→ `[Verify pickup code (if used): POST /lets_go/pickup-code/verify/ {booking_id, passenger_id, code,...}]`  
→ `[Passenger dropped off: POST /lets_go/bookings/<booking_id>/dropped-off/ {passenger_id}]`  
→ `[Go to Payment Screen]`

→ `[Passenger Payment Screen]`  
→ `[GET payment details: GET /lets_go/bookings/<booking_id>/payment/?role=PASSENGER&user_id=...]`  
→ `<Pay by CASH?>`  
- YES → `[Submit payment (cash): POST multipart /lets_go/bookings/<booking_id>/payment/submit/ (payment_method=CASH, rating, feedback)]`  
- NO → `[Upload receipt + submit: POST multipart /lets_go/bookings/<booking_id>/payment/submit/ (payment_method=BANK_TRANSFER, receipt, rating, feedback)]`  
→ `[Payment status becomes PENDING (backend)]`  
→ `[Wait for driver confirmation (poll/notification)]`  
→ `[Driver confirms payment: POST /lets_go/bookings/<booking_id>/payment/confirm/ {driver_id, received=true, passenger_rating,...}]`  
→ `[Payment status becomes COMPLETED (backend)]`  
→ (END)

---

## B) SOS Subflow (can happen anytime *while tracking session active*)

**Trigger condition in Flutter**  
`<Tracking send enabled AND session exists in SharedPreferences?>`  
- YES → `SOS floating button is visible`

Flow:  
`[User taps SOS]`  
→ `[3-second countdown confirm dialog]`  
→ `<Confirmed?>`  
- NO → `[Cancel]` → return to whatever screen  
- YES → `[Get current location point from controller/session]`  
→ `<Point available?>`  
- NO → `[Show: "Live location not available yet"]` → return  
- YES → `[POST SOS: POST /lets_go/incidents/sos/ {user_id, trip_id, role, booking_id?, lat,lng, note?}]`  
→ `<Success?>`  
- NO → `[Retry loop with backoff OR show error]` → return  
- YES → `[Receive share_url + maps_url + notified flags]`  
→ `[Show dialog: copy/share SOS link]`  
→ return to live tracking

---

## C) Public Share / Admin-Web (small Option B)

### C1) Normal trip share (non-SOS)
`[User generates share link in app]`  
→ `[POST /lets_go/trips/<trip_id>/share/ {role, booking_id?, target=app}]`  
→ `[Receive share_url token link]`  
→ `[Send link to someone (WhatsApp/SMS)]`  
→ `(Receiver opens link in browser)`  
→ `[GET /lets_go/trips/share/<token>/] (renders administration/trip_share_public.html)`  
→ `[Browser polls: GET /lets_go/trips/share/<token>/live/]`  
→ `[Browser shows live marker + driver_path + last seen info]`

### C2) SOS share
`[SOS created]`  
→ `[Backend returns SOS share_url]`  
→ `(Emergency contact opens link)`  
→ `[GET /lets_go/incidents/sos/share/<token>/] (renders administration/sos_share_public.html)`  
→ `[Browser polls: GET /lets_go/incidents/sos/share/<token>/live/]`  
→ `[Browser shows live marker + driver_path + last seen info]`

---

## Completion status
- **Done**: Provided a textual flowchart structure (main flow + SOS subflow + admin/web share subflow) that you can replicate directly in draw.io.
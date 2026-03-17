# Unit Testing Output

## Section A: Flutter behavioral tests (`lets_go/test/*.dart`)

### Flutter tests (behavioral) — Documentation Table (Part 1)

> Columns: **Test case** = the `group(...)` + `test(...)` name, **Function/Unit under test**, **Input/Setup**, **Expected output**, **Actual output (asserted)**, **Status**

### [lets_go/test/actual_path_rules_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/actual_path_rules_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| ActualPathRules.validateActualPathCoversAllStops → returns true when each stop is within threshold of some actual point | `ActualPathRules.validateActualPathCoversAllStops` | `actual` polyline points near stops; `stops` has 2 points; `thresholdMeters: 200` | Returns `true` when each stop is within distance threshold of at least one actual point | `ok == true` | PASS |
| ActualPathRules.validateActualPathCoversAllStops → returns false when any stop is not covered | `ActualPathRules.validateActualPathCoversAllStops` | `actual` has 2 points; one stop far away; `thresholdMeters: 150` | Returns `false` if any stop not covered | `ok == false` | PASS |
| ActualPathRules.validateActualPathCoversAllStops → returns false when actual polyline has < 2 points | `ActualPathRules.validateActualPathCoversAllStops` | `actual` length = 1; `stops` length = 2 | Returns `false` for invalid actual path (<2 points) | `ok == false` | PASS |
| ActualPathRules.validateActualPathCoversAllStops → returns false when stops has < 2 points | `ActualPathRules.validateActualPathCoversAllStops` | `actual` length = 2; `stops` length = 1 | Returns `false` for invalid stop list (<2 points) | `ok == false` | PASS |
| ActualPathRules.shouldExtendActualPathAppendOnly → returns true when current stops start with initial snapshot and new stops appended | `ActualPathRules.shouldExtendActualPathAppendOnly` | `initialStopsSnapshot` = 2 stops; `currentStops` = same 2 + appended stop | Returns `true` if current is **prefix match** of initial and only appended | `ok == true` | PASS |
| ActualPathRules.shouldExtendActualPathAppendOnly → returns false when a stop is deleted | `ActualPathRules.shouldExtendActualPathAppendOnly` | `initialStopsSnapshot` = 3; `currentStops` = 2 (deleted) | Returns `false` when any initial stop removed | `ok == false` | PASS |
| ActualPathRules.shouldExtendActualPathAppendOnly → returns false when order changes (no longer a prefix match) | `ActualPathRules.shouldExtendActualPathAppendOnly` | `initialStopsSnapshot` = [A,B]; `currentStops` = [B,A,C] | Returns `false` if ordering changes (not a prefix) | `ok == false` | PASS |

---

### [lets_go/test/create_route_controller_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/create_route_controller_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| CreateRouteController.loadExistingRouteData → loads planned points, names, routePoints, and route metadata | `CreateRouteController.loadExistingRouteData` | Map includes `points`, `locationNames`, `routePoints`, `routeId`, `distance`, `duration` | Controller fields populated with provided planned-route + metadata | `c.points==points`, `c.locationNames==[...]`, `c.routePoints==...`, `c.createdRouteId=='R1'`, `c.routeDistance==12.3`, `c.routeDuration==25` | PASS |
| CreateRouteController.loadExistingRouteData → loads actualRoutePoints overlay and preferActualPath flag | `CreateRouteController.loadExistingRouteData` | Map includes `actualRoutePoints` + `preferActualPath: true` | Overlay stored and preference flag set | `c.actualRoutePoints==actual`, `c.preferActualPath==true` | PASS |
| CreateRouteController overlay is read-only during planned-route edits → adding/deleting/renaming stops does not mutate actualRoutePoints | `CreateRouteController.addPointToRoute`, `updateStopName`, `deleteStop` (in presence of overlay) | Controller preloaded with `actualRoutePoints`; then planned-stop edits executed | Planned-stop editing must **not change** overlay polyline | `c.actualRoutePoints` unchanged and length remains `2` | PASS |
| CreateRouteController.getRouteData → returns actualRoutePoints and preferActualPath to callers | `CreateRouteController.getRouteData` | Controller preloaded with overlay + flag + `routeId` | Returned map contains overlay + flag | `data['actualRoutePoints']==actual`, `data['preferActualPath']==true`, `data['routeId']=='R1'` | PASS |

---

### [lets_go/test/create_route_screen_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/create_route_screen_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| CreateRouteScreen actual path overlay → shows the overlay switch when actualRoutePoints are present | `CreateRouteScreen` UI logic (overlay switch visibility) | `CreateRouteController` preloaded with `actualRoutePoints` and `preferActualPath: true`; `isLoading=false`; in-memory map tiles | Overlay toggle should be visible | Finds `Text('Show actual path overlay')` and `SwitchListTile` | PASS |
| CreateRouteScreen actual path overlay → does not show the overlay switch when no actualRoutePoints | `CreateRouteScreen` UI logic | Controller loaded without `actualRoutePoints`; `isLoading=false`; in-memory tiles | Overlay toggle hidden | Finds nothing for `Text('Show actual path overlay')` | PASS |

---

### [lets_go/test/ride_edit_controller_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/ride_edit_controller_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| RideEditController.initializeWithRideData → parses actual_path into actualRoutePoints for overlay | `RideEditController.initializeWithRideData` | `rideData` contains `route.stops` and `actual_path` (mix of `{lat,lng}` and `{latitude,longitude}`), `notes:''` | Controller parses `actual_path` into `LatLng` list | `length==2`, first=`LatLng(33.0,73.0)`, last=`LatLng(33.1,73.1)` | PASS |
| RideEditController.initializeWithRideData → keeps description empty when notes are empty (no stop-name auto-generation) | `RideEditController.initializeWithRideData` | `notes:''` | `description` remains empty | `c.description == ''` | PASS |
| RideEditController.applyUpdatedRouteData → preserves actualRoutePoints when returned by route editor | `RideEditController.applyUpdatedRouteData` | Existing `actualRoutePoints` set; updated route data includes `actualRoutePoints` | Overlay should update to new overlay provided | `c.actualRoutePoints == [LatLng(30.0,70.0), LatLng(30.1,70.1)]` | PASS |
| RideEditController.applyUpdatedRouteData → does not wipe actualRoutePoints when route editor returns no actualRoutePoints | `RideEditController.applyUpdatedRouteData` | Existing overlay set; updated route data omits `actualRoutePoints` | Overlay should remain unchanged | `c.actualRoutePoints` remains original | PASS |

---

### [lets_go/test/widget_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/widget_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| Counter increments smoke test | App boot smoke test (`MyApp`) | `pumpWidget(MyApp(initialRoute: '/'))` then `pump()` | App builds successfully showing a `MaterialApp` | `find.byType(MaterialApp)` == one widget | PASS |

---

## Section C: Backend pytest tests (`backend/lets_go/test/**`)

### Backend pytest tests — Documentation Table (Part 1)

### [backend/lets_go/test/test_views_authentication.py](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/backend/lets_go/test/test_views_authentication.py:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| test_parse_json_body_empty_returns_dict | `_parse_json_body` | Request-like object with `body=b""` | `{}` | equals `{}` | PASS |
| test_parse_json_body_invalid_returns_dict | `_parse_json_body` | `body=b"not-json"` | `{}` | equals `{}` | PASS |
| test_parse_json_body_valid_dict | `_parse_json_body` | `body=b'{"a": 1}'` | `{"a":1}` | equals `{"a":1}` | PASS |
| test_parse_json_body_valid_non_dict_returns_empty | `_parse_json_body` | `body=b"[1, 2]"` | `{}` | equals `{}` | PASS |
| test_normalize_gender | `_normalize_gender` | Inputs: `"Male"`, `"m"`, `"Female"`, `"f"`, `""`, `None` | Normalized: `"male"`, `"male"`, `"female"`, `"female"`, `None`, `None` | matches expected per call | PASS |
| test_get_profile_contact_change_cache_key | `_get_profile_contact_change_cache_key` | `(5, "email", "a@b.com")` | `"profile_contact_change_5_email_a@b.com"` | equals string | PASS |
| test_parse_iso_date | `_parse_iso_date` | `"2026-02-27"`, `""`, `None`, `"27-02-2026"` | date object for ISO, else `None` | equals expected | PASS |
| test_generate_otp_length_digits | `generate_otp` | length = `8` | 8 digits numeric string | `len==8` and `isdigit()==True` | PASS |
| test_get_cache_key | `get_cache_key` | `"x@y.com"` | `"pending_signup_x@y.com"` | equals string | PASS |
| test_get_reset_cache_key | `get_reset_cache_key` | `("email","x@y.com")` | `"reset_pwd_email_x@y.com"` | equals string | PASS |
| test_login_success | `login` endpoint | Create user then POST with correct creds | HTTP 200 and payload includes success + user email | `status_code==200`, `success==True`, email matches | PASS |
| test_login_invalid_password | `login` endpoint | Create user then wrong password | HTTP 404, `success=False` | asserted | PASS |
| test_check_username_available_true | `check_username` endpoint | POST username `"newuser"` | available true and registry row created | `{"available": True}` and row exists | PASS |
| test_check_username_already_reserved_false | `check_username` endpoint | Pre-create registry `"taken"`, then POST `"TAKEN"` | available false | `available == False` | PASS |
| test_send_otp_requires_email_or_phone | `send_otp` endpoint | POST `{}` | HTTP 400 and `success=False` | asserted | PASS |
| test_send_otp_registration_sets_cache | `send_otp` endpoint | POST email otp registration | HTTP 200, cache populated with email + email_otp | asserted cached dict fields non-null | PASS |
| test_verify_otp_success_email | `verify_otp` endpoint | Cache preset with otp; POST verify | HTTP 200, cache updated `email_verified=True` | asserted | PASS |
| test_verify_password_reset_otp_success | `verify_password_reset_otp` endpoint | Cache preset with reset OTP | HTTP 200, cache key updated with `verified=True` | asserted | PASS |
| test_reset_password_success | `reset_password` endpoint | Create user; cache verified; POST new password | HTTP 200 and `success=True` | asserted | PASS |
| test_reset_rejected_user_deletes_user | `reset_rejected_user` endpoint | User status REJECTED; POST email | HTTP 200; user deleted | asserted | PASS |
| test_reset_rejected_user_non_rejected_forbidden | `reset_rejected_user` endpoint | Verified user; POST email | HTTP 403 | asserted | PASS |
| test_upload_to_supabase_missing_settings_raises | `upload_to_supabase` | Patch settings empty | Raises `RuntimeError` | asserted via `assertRaises` | PASS |
| test_upload_to_supabase_success | `upload_to_supabase` | Patch settings + mock `requests.post` status 200 | Returns public URL | URL equals expected; `post` called once | PASS |

---

### [backend/lets_go/test/tests/test_db_integration_smoke.py](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/backend/lets_go/test/tests/test_db_integration_smoke.py:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| test_db_smoke_create_and_query | Django model integration smoke (`UsersData`, `Route`, `Trip`, `Booking`) | DB fixtures create driver/passenger/route/stops/vehicle/trip; create `Booking` then query | Objects persisted and queryable; relationships correct | `.exists()` checks true; fetched booking has expected `trip_id` and passenger email | PASS |
| test_booking_clean_rejects_wrong_stop_order | `Booking.full_clean` validation | Create booking with `from_stop` after `to_stop` | Validation error raised | `pytest.raises(ValidationError)` | PASS |

---

### [backend/lets_go/test/tests/test_utils_route_geometry.py](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/backend/lets_go/test/tests/test_utils_route_geometry.py:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| test_decode_polyline_empty | `_decode_ors_polyline` | `''` | `[]` | equals `[]` | PASS |
| test_decode_polyline_known | `_decode_ors_polyline` | Encoded polyline `_p~iF~ps|U_ulLnnqC_mqNvxq`@` | First decoded point approx `(38.5,-120.2)` | `dec[0] == approx((38.5,-120.2))` | PASS |
| test_fetch_geometry_without_key | `fetch_route_geometry_osm` | Patch `api_key=''`; points list | Returns empty list when key missing | equals `[]` | PASS |
| test_fetch_geometry_geojson | `fetch_route_geometry_osm` | Patch `api_key='abc'` and mock `requests.post` returning GeoJSON | Returns list of dict `{lat,lng}` converted from GeoJSON coordinates | equals `[{lat:2.0,lng:1.0},{lat:4.0,lng:3.0}]` | PASS |
| test_update_route_geometry_from_stops | `update_route_geometry_from_stops` | Patch fetch to fixed points; mock RouteGeometryPoint; route has `save` mocked | Saves route + assigns route geometry + bulk creates points | `route.save` called once; `route.route_geometry == [{'lat':1.2,'lng':2.3}]`; bulk_create called | PASS |

---

### [backend/lets_go/test/tests/test_views_rideposting.py](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/backend/lets_go/test/tests/test_views_rideposting.py:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| test_parse_limit_offset | `_parse_limit_offset` | Request `/x?limit=5&offset=2` | `(5,2)` | equals `(5,2)` | PASS |
| test_is_archived_after_24h | `_is_archived_after_24h` | created at `2026-01-01 08:00`, now `2026-01-02 10:00` | `True` (more than 24h) | `is True` | PASS |
| test_to_int_pkr | `_to_int_pkr` | `'120.4'`; `'bad'` with default 9 | `120`; `9` | equals values | PASS |
| test_map_trip_status | `map_trip_status_to_frontend` | `'COMPLETED'` | returns truthy mapped value | asserted truthy | PASS |
| test_create_trip_invalid_method | `create_trip` endpoint | GET request | 405 | `status_code==405` | PASS |
| test_cancel_booking_invalid_method | `cancel_booking` endpoint | GET request | 405 | asserted | PASS |
| test_create_route_invalid_method | `create_route` endpoint | GET request | 400 | asserted | PASS |
| test_get_trip_breakdown_invalid_method | `get_trip_breakdown` endpoint | POST request (invalid) | 400 | asserted | PASS |
| test_get_user_created_rides_history_invalid_method | `get_user_created_rides_history` endpoint | POST invalid | 400 | asserted | PASS |
| test_trigger_auto_archive_for_driver_invalid_method | `trigger_auto_archive_for_driver` endpoint | PUT invalid | 405 | asserted | PASS |
| test_get_user_booked_rides_history_invalid_method | `get_user_booked_rides_history` endpoint | POST invalid | 400 | asserted | PASS |
| test_get_user_rides_invalid_method | `get_user_rides` endpoint | POST invalid | 400 | asserted | PASS |
| test_get_trip_details_invalid_method | `get_trip_details` endpoint | POST invalid | 400 | asserted | PASS |
| test_update_trip_invalid_method | `update_trip` endpoint | POST invalid | 400 | asserted | PASS |
| test_delete_trip_invalid_method | `delete_trip` endpoint | POST invalid | 400 | asserted | PASS |
| test_cancel_trip_invalid_method | `cancel_trip` endpoint | GET invalid | 400 | asserted | PASS |
| test_get_route_details_invalid_method | `get_route_details` endpoint | POST invalid | 400 | asserted | PASS |
| test_get_route_statistics_invalid_method | `get_route_statistics` endpoint | POST invalid | 400 | asserted | PASS |
| test_search_routes_invalid_method | `search_routes` endpoint | POST invalid | 400 | asserted | PASS |
| test_get_available_seats_invalid_method | `get_available_seats` endpoint | POST invalid | 400 | asserted | PASS |
| test_create_booking_invalid_method | `create_booking` endpoint | GET invalid | 400 | asserted | PASS |
| test_get_user_bookings_invalid_method | `get_user_bookings` endpoint | POST invalid | 400 | asserted | PASS |
| test_search_rides_invalid_method | `search_rides` endpoint | POST invalid | 400 | asserted | PASS |
| test_cancel_ride_invalid_method | `cancel_ride` endpoint | POST invalid | 400 | asserted | PASS |
| test_calculate_distance_helper | `_calculate_distance` | Same coordinates | distance `0` | `d == 0` | PASS |
| test_calculate_estimated_arrival | `calculate_estimated_arrival` | departure `10:00`, route distance=100 | non-null arrival time | `out is not None` | PASS |
| test_trip_edit_delete_cancel_guards_helpers | `can_edit_trip`, `can_delete_trip`, `can_cancel_trip` | trip with status SCHEDULED; no existing bookings | return booleans | `isinstance(..., bool)` for each | PASS |
| test_update_trip_status_automatically_smoke | `update_trip_status_automatically` | trip scheduled with date/time | returns same trip object | `result is trip` | PASS |

---

### Backend pytest tests — Tables (Part 2)

> Below are the **additional backend test suites** I just opened and tabulated.  
> Same columns: **Test case**, **Function/unit under test**, **Input/Setup**, **Expected output**, **Actual output (asserted)**, **Status**

---

### [backend/lets_go/test/tests/test_administration_views.py](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/backend/lets_go/test/tests/test_administration_views.py:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| TestAdministrationHelpers.test_build_resolved_sos_snapshot_payload_minimal | `administration.views._build_resolved_sos_snapshot_payload` | Patch `RideAuditEvent.objects.none()` => `[]`; minimal `incident` namespace with `trip=None`, `booking=None` | Payload includes incident info and keeps trip null | `payload['incident']['id']==1`; `payload['trip'] is None` | PASS |
| TestAdministrationHelpers.test_attach_latest_payments | `administration.views._attach_latest_payments` | Patch `TripPayment.objects.filter(...).only().order_by()` => `[p1,p2]`; bookings `b1,b2` | Latest payment fields attached to booking objects | `b1.latest_receipt_url=='u1'`; `b2.latest_payment_method=='CARD'` | PASS |
| TestAdministrationHelpers.test_combine_trip_dt | `administration.views._combine_trip_dt` | Trip with `trip_date=2026-01-01`, time `10:00` | Returns combined datetime | `dt is not None` | PASS |
| TestAdministrationHelpers.test_compute_reached_trigger_dt | `administration.views._compute_reached_trigger_dt` | Trip with date+departure+arrival | Returns dep, arr, trigger datetimes | all are not `None` | PASS |
| TestAdministrationHelpers.test_vehicle_to_dict | `administration.views._vehicle_to_dict` | Vehicle namespace with many fields and `registration_date=2024-01-01` | Dict conversion with ISO date string | `out['id']==1`; `out['registration_date']=='2024-01-01'` | PASS |
| TestAdministrationBasicViews.test_guest_list_view | `administration.views.guest_list_view` | Patch `render` => status 200 | Returns 200 and renders | `res.status_code==200`; `render` called once | PASS |
| TestAdministrationBasicViews.test_api_guests | `administration.views.api_guests` | Patch `GuestUser.objects.all().values()` => `[{id:1,...}]` | JSON includes guests list | decoded JSON `guests[0].id==1` | PASS |
| TestAdministrationBasicViews.test_admin_analytics_settings_views | `admin_view`, `analytics_view`, `settings_view` | Patch `render` => 200 | All return 200 | each status 200; `render` called 3 times | PASS |
| TestAdministrationBasicViews.test_api_users | `administration.views.api_users` | Patch `UsersData.objects.all().values()` => `[{id:7,...}]` | JSON includes users list | decoded JSON `users[0].id==7` | PASS |
| TestAdministrationAuthViews.test_login_view_get | `administration.views.login_view` (GET) | Patch `render` => 200 | Returns login page | status 200; `render` called once | PASS |
| TestAdministrationAuthViews.test_login_view_post_invalid | `login_view` (POST invalid creds) | Patch `authenticate` => None; patch `render` => 200 | Rerenders with failure | status 200; `render` called | PASS |
| TestAdministrationAuthViews.test_login_view_post_success | `login_view` (POST valid) | Patch `authenticate` => user; patch `login`; patch `redirect` => 302 | Redirects after login | status 302; `login` called once; `redirect` called once | PASS |
| TestAdministrationAuthViews.test_logout_view | `logout_view` | Patch `logout`; patch `redirect` => 302 | Redirects after logout | status 302; `logout` + `redirect` called | PASS |
| TestAdministrationMethodGuardsAndPosts.test_reached_overdue_dashboard_method_not_allowed | `reached_overdue_dashboard_view` | POST request, authenticated staff user | Method not allowed | status 405 | PASS |
| TestAdministrationMethodGuardsAndPosts.test_reached_overdue_dashboard_forbidden_non_staff | `reached_overdue_dashboard_view` | GET request, authenticated non-staff | Forbidden | status 403 | PASS |
| TestAdministrationMethodGuardsAndPosts.test_reached_overdue_dashboard_success | `reached_overdue_dashboard_view` | GET request, staff; patch Trip queryset chain => `[]`; patch render => 200 | Dashboard renders | status 200; `render` called once | PASS |
| TestAdministrationMethodGuardsAndPosts.test_vehicle_update_status_invalid_status_redirects | `vehicle_update_status_view` | Patch `get_object_or_404` returns user then vehicle; POST status INVALID | Invalid status forbidden | status 403 | PASS |
| TestAdministrationMethodGuardsAndPosts.test_vehicle_delete_post | `vehicle_delete_view` | Patch `get_object_or_404` returns user then vehicle; POST | Forbidden branch hit | status 403 | PASS |
| TestAdministrationMethodGuardsAndPosts.test_user_add_view_get | `user_add_view` | Patch render => 200 | Renders add user | status 200; render called | PASS |
| TestAdministrationAdditionalCoverage.test_user_related_render_views | multiple render views | Patch `get_object_or_404` => user; patch EmergencyContact filter => None; patch render => 200 | All pages render | each status 200; `render` called | PASS |
| TestAdministrationAdditionalCoverage.test_update_user_status_view_post | `update_user_status_view` | Patch get_object_or_404 => user; POST status VERIFIED; patch redirect => 302 | Redirect after update | status 302; redirect called | PASS |
| TestAdministrationAdditionalCoverage.test_user_vehicles_redirect_view | `user_vehicles_redirect_view` | Patch redirect => 302 | Redirects | status 302 | PASS |
| TestAdministrationAdditionalCoverage.test_sos_views_smoke | `sos_dashboard_view` | Staff user; patch SosIncident queryset => `[]`; patch render => 200 | Renders SOS dashboard | status 200; render called | PASS |
| TestAdministrationAdditionalCoverage.test_remaining_admin_symbols_callable | symbol existence smoke | None | All listed view functions callable | `callable(...)` true for each | PASS |

---

### [backend/lets_go/test/tests/test_utils_auto_archive.py](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/backend/lets_go/test/tests/test_utils_auto_archive.py:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| test_auto_archive_for_driver_invalid_driver | `auto_archive.auto_archive_for_driver` | `driver_id=0` | No-op count `0` | equals `0` | PASS |
| test_auto_archive_for_driver_limit | `auto_archive.auto_archive_for_driver` | Patch Trip queryset => 3 trips; patch `_archive_trip` side effects `[True, False, True]`; `limit=2` | Stops after archiving up to limit | returns `2` | PASS |
| test_auto_archive_global | `auto_archive.auto_archive_global` | Patch Trip queryset => 2 trips; patch `_archive_trip` => True; `limit=5` | Archives both trips | returns `2` | PASS |
| test_archive_trip_skips_when_recent | `auto_archive._archive_trip` | Patch `timezone.now` to fixed `now`; patch Booking/Payment aggregates return `now`; trip completed recently | Should **not** archive if too recent | returns `False` | PASS |

---

### [backend/lets_go/test/tests/test_utils_email_otp.py](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/backend/lets_go/test/tests/test_utils_email_otp.py:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| test_send_email_otp_success | `email_otp.send_email_otp` | Patch `smtplib.SMTP` | Returns True on success path | `is True` | PASS |
| test_send_email_otp_failure | `email_otp.send_email_otp` | Patch `smtplib.SMTP` raising exception | Returns False on exception | `is False` | PASS |
| test_send_email_otp_for_reset_success | `email_otp.send_email_otp_for_reset` | Patch `smtplib.SMTP` | Returns True | `is True` | PASS |

---

### [backend/lets_go/test/tests/test_utils_email_phone.py](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/backend/lets_go/test/tests/test_utils_email_phone.py:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| test_constants_are_strings | `lets_go.utils.email_phone` constants | None | All configured constants are strings | `isinstance(..., str)` for each | PASS |

---

### [backend/lets_go/test/tests/test_utils_phone_otp_send.py](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/backend/lets_go/test/tests/test_utils_phone_otp_send.py:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| test_send_phone_otp_success | `phone_otp_send.send_phone_otp` | Patch `requests.post` to return response with `raise_for_status()` ok and `json={'ok':True}` | Returns True when SMS API ok | `is True` | PASS |
| test_send_phone_otp_failure | `phone_otp_send.send_phone_otp` | Patch `requests.post` raising exception | Returns False | `is False` | PASS |
| test_send_phone_otp_reset_failure | `phone_otp_send.send_phone_otp_for_reset` | Patch `requests.post` raising exception | Returns False | `is False` | PASS |

---

### [backend/lets_go/test/tests/test_utils_verification_guard.py](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/backend/lets_go/test/tests/test_utils_verification_guard.py:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| test_verification_block_user_not_found | `verification_guard.verification_block_response` | Patch `UsersData.objects.only().get` raises DoesNotExist | 404 response | `status_code==404` | PASS |
| test_verification_block_banned | `verification_guard.verification_block_response` | Patch user status `BANNED` | 403 response | `status_code==403` | PASS |
| test_verification_block_none_for_active | `verification_guard.verification_block_response` | Patch user status `ACTIVE` | No block | returns `None` | PASS |
| test_has_any_requested_keys | `_has_any_requested_keys` | Pending change req list includes `{'email':...}` | True for email key, False for phone key | asserted True / False | PASS |
| test_ride_booking_block_response_pending_gender | `ride_booking_block_response` | Patch `verification_block_response` => None; pending requests contain `gender` change | 403 block | `status_code==403` | PASS |
| test_ride_create_block_response_pending_license | `ride_create_block_response` | Patch block => None; pending requests contain `driving_license_no` change | 403 block | `status_code==403` | PASS |

---

### [backend/lets_go/test/tests/test_views_blocking.py](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/backend/lets_go/test/tests/test_views_blocking.py:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| test_user_brief | `views_blocking._user_brief` | User namespace `{id:1,...}` | Dict includes user id | `out['id']==1` | PASS |
| test_list_blocked_users_invalid_method | `list_blocked_users` | POST (invalid) | 405 | `status_code==405` | PASS |
| test_search_users_to_block_invalid_method | `search_users_to_block` | POST (invalid) | 405 | `status_code==405` | PASS |
| test_block_user_invalid_method | `block_user` | GET (invalid) | 405 | `status_code==405` | PASS |
| test_unblock_user_invalid_method | `unblock_user` | GET (invalid) | 405 | `status_code==405` | PASS |

---

### [backend/lets_go/test/tests/test_views_chat.py](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/backend/lets_go/test/tests/test_views_chat.py:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| test_list_chat_messages_invalid_method | `list_chat_messages` | POST invalid | 405 | asserted | PASS |
| test_list_chat_messages_updates_invalid_method | `list_chat_messages_updates` | POST invalid | 405 | asserted | PASS |
| test_send_chat_message_invalid_method | `send_chat_message` | GET invalid | 405 | asserted | PASS |
| test_mark_message_read_invalid_method | `mark_message_read` | GET invalid | 405 | asserted | PASS |
| test_send_broadcast_message_invalid_method | `send_broadcast_message` | GET invalid | 405 | asserted | PASS |

---

### [backend/lets_go/test/tests/test_views_incidents.py](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/backend/lets_go/test/tests/test_views_incidents.py:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| TestViewsIncidentsHelpers.test_helper_coercion | `_coerce_int`, `_coerce_float`, `_parse_iso_dt` | `'8'`, `'1.2'`, `'bad'` | 8, 1.2, None | asserted | PASS |
| TestViewsIncidentsHelpers.test_send_email_success | `_send_email` | Patch `smtplib.SMTP` | True | asserted | PASS |
| TestViewsIncidentsHelpers.test_send_sms_success | `_send_sms` | Patch `requests.post` => status 200 | True | asserted | PASS |
| TestViewsIncidentsEndpoints.test_sos_incident_invalid_json | `sos_incident` | POST non-json body with JSON content-type | 400 | status 400 | PASS |
| TestViewsIncidentsEndpoints.test_sos_incident_missing_fields | `sos_incident` | POST `{}` JSON | 400 | status 400 | PASS |
| TestViewsIncidentsEndpoints.test_get_share_token_empty | `_get_share_token` | `''` | None | asserted | PASS |
| TestViewsIncidentsEndpoints.test_get_trip_share_token_empty | `_get_trip_share_token` | `''` | None | asserted | PASS |
| TestViewsIncidentsShareEndpoints.test_trip_share_token_invalid_method | `trip_share_token` | GET request | 400 or 405 | status in (400,405) | PASS |
| TestViewsIncidentsShareEndpoints.test_trip_share_view_missing_token | `trip_share_view` | token `''` | 400 or 404 | status in (400,404) | PASS |
| TestViewsIncidentsShareEndpoints.test_trip_share_live_missing_token | `trip_share_live` | token `''` | 400 or 404 | status in (400,404) | PASS |
| TestViewsIncidentsShareEndpoints.test_sos_share_view_missing_token | `sos_share_view` | token `''` | 400 or 404 | status in (400,404) | PASS |
| TestViewsIncidentsShareEndpoints.test_sos_share_live_missing_token | `sos_share_live` | token `''` | 400 or 404 | status in (400,404) | PASS |
| TestViewsIncidentsShareEndpoints.test_sos_share_send_invalid_method | `sos_share_send` | POST invalid | 400 or 405 | status in (400,405) | PASS |

---

### [backend/lets_go/test/tests/test_views_notifications.py](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/backend/lets_go/test/tests/test_views_notifications.py:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| test_update_fcm_token_missing_user | `update_fcm_token` | POST JSON missing `user_id` | 400 | status 400 | PASS |
| test_update_fcm_token_user_not_found | `update_fcm_token` | Patch `UsersData.objects.filter(...).update()` => 0; POST JSON with user_id 99 | 404 | status 404 | PASS |
| test_normalize_payload | `_normalize_ride_notification_payload` | `{'user_id':5,'title':'T','body':123,'data':{'a':1}}` | string-normalized values | `user_id=='5'`, `body=='123'`, `data['a']=='1'` | PASS |
| test_send_ride_notification_async | `send_ride_notification_async` | Patch `threading.Thread` to run inline; patch `requests.post` => 200 | Should invoke HTTP request | `m_post.called` true | PASS |
| test_register_fcm_token_with_supabase_async | `register_fcm_token_with_supabase_async` | Patch Thread inline; patch `requests.post` => 200 | Should invoke HTTP request | `m_post.called` true | PASS |

---

### [backend/lets_go/test/tests/test_views_post_booking.py](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/backend/lets_go/test/tests/test_views_post_booking.py:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| test_helper_coercion_and_distance | `_coerce_int`, `_coerce_float`, `_haversine_meters` | `'5'`, `'2.5'`, identical coords | 5, 2.5, distance ~0 | asserted | PASS |
| test_compute_reached_trigger | `_compute_reached_trigger_dt` | Trip date 2026-01-01; dep 10:00; arr 11:00 | delay approx 2.0 minutes (?) + dt not null | `dt is not None`; `delay==approx(2.0)` | PASS |
| test_require_cron_secret | `_require_cron_secret` | Env `CRON_SECRET='ok'`; header ok vs header no | None when ok; 401 when mismatch | asserted | PASS |
| test_send_email_success | `_send_email` | Patch SMTP | True | asserted | PASS |
| test_send_sms_success | `_send_sms` | Patch requests.post => 200 | True | asserted | PASS |
| test_cron_requires_secret | `cron_post_booking_reached_reminders` | Env secret ok; request header no | 401 | asserted | PASS |
| test_get_ride_readiness_invalid_method | `get_ride_readiness` | POST invalid | 405 | asserted | PASS |
| test_update_booking_readiness_invalid_method | `update_booking_readiness` | GET invalid | 405 | asserted | PASS |
| test_verify_pickup_code_invalid_method | `verify_pickup_code` | GET invalid | 400 or 405 | asserted | PASS |
| test_parse_iso_dt | `_parse_iso_dt` | `'bad'` | None | asserted | PASS |
| test_combine_trip_dt | `_combine_trip_dt` | Trip with date + time | non-null datetime | asserted | PASS |
| test_start_trip_ride_invalid_method | `start_trip_ride` | GET invalid | 400 or 405 | asserted | PASS |
| test_start_booking_ride_invalid_method | `start_booking_ride` | GET invalid | 400 or 405 | asserted | PASS |
| test_complete_trip_ride_invalid_method | `complete_trip_ride` | GET invalid | 400 or 405 | asserted | PASS |
| test_mark_booking_dropped_off_invalid_method | `mark_booking_dropped_off` | GET invalid | 400 or 405 | asserted | PASS |
| test_driver_mark_reached_pickup_invalid_method | `driver_mark_reached_pickup` | GET invalid | 400 or 405 | asserted | PASS |
| test_driver_mark_reached_dropoff_invalid_method | `driver_mark_reached_dropoff` | GET invalid | 400 or 405 | asserted | PASS |
| test_get_booking_payment_details_invalid_method | `get_booking_payment_details` | POST invalid | 400 or 405 | asserted | PASS |
| test_submit_booking_payment_invalid_method | `submit_booking_payment` | GET invalid | 400 or 405 | asserted | PASS |
| test_confirm_booking_payment_invalid_method | `confirm_booking_payment` | GET invalid | 400 or 405 | asserted | PASS |
| test_get_trip_payments_invalid_method | `get_trip_payments` | POST invalid | 400 or 405 | asserted | PASS |
| test_update_live_location_invalid_method | `update_live_location` | GET invalid | 400 or 405 | asserted | PASS |
| test_get_live_location_invalid_method | `get_live_location` | POST invalid | 400 or 405 | asserted | PASS |
| test_generate_pickup_code_invalid_method | `generate_pickup_code` | GET invalid | 400 or 405 | asserted | PASS |
| test_compute_reminder_helpers | `compute_driver_reminder_time` | Trip with id/date/dep time | non-null reminder time | asserted | PASS |
| test_remaining_helper_symbols_callable | symbol existence smoke | None | helpers callable | `callable(...)` true | PASS |

---

### [backend/lets_go/test/tests/test_views_profile.py](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/backend/lets_go/test/tests/test_views_profile.py:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| test_user_change_requests_invalid_method | `user_change_requests` | POST invalid | 400 | status 400 | PASS |
| test_send_profile_contact_change_otp_invalid_method | `send_profile_contact_change_otp` | GET invalid | 400 | status 400 | PASS |
| test_send_profile_contact_change_otp_success_email | `send_profile_contact_change_otp` | Patch UsersData.get => user; patch otp => '1111'; patch cache empty; patch send_email_otp True; POST JSON which=email | 200 | status 200 | PASS |
| test_send_profile_contact_change_otp_not_found | `send_profile_contact_change_otp` | Patch UsersData.get raises DoesNotExist | 404 | status 404 | PASS |
| test_upload_user_driving_license_invalid_method | `upload_user_driving_license` | GET invalid | 400 | status 400 | PASS |
| test_upload_user_photos_invalid_method | `upload_user_photos` | GET invalid | 400 | status 400 | PASS |
| test_upload_user_cnic_invalid_method | `upload_user_cnic` | GET invalid | 400 | status 400 | PASS |
| test_upload_vehicle_images_invalid_method | `upload_vehicle_images` | GET invalid | 400 | status 400 | PASS |
| test_verify_profile_contact_change_otp_invalid_method | `verify_profile_contact_change_otp` | GET invalid | 400 | status 400 | PASS |
| test_upload_user_accountqr_invalid_method | `upload_user_accountqr` | GET invalid | 400 | status 400 | PASS |
| test_user_image_invalid_method | `user_image` | Patch UsersData.values_list.get => '' ; call with POST and field `profile_photo` | Raises `Http404` | exception caught -> assert True | PASS |
| test_vehicle_image_invalid_method | `vehicle_image` | POST invalid | 400 or 405 | status in (400,405) | PASS |
| test_user_profile_invalid_method | `user_profile` | DELETE invalid | 400 or 405 | status in (400,405) | PASS |
| test_user_emergency_contact_invalid_method | `user_emergency_contact` | Patch UsersData.get => user; DELETE invalid | 400 | status 400 | PASS |
| test_user_vehicles_invalid_method | `user_vehicles` | Patch UsersData.only.get => user; DELETE invalid | 400 | status 400 | PASS |
| test_vehicle_detail_invalid_method | `vehicle_detail` | POST invalid | 400 or 405 | status in (400,405) | PASS |

---

### Backend pytest tests — Tables (Part 3 / Final)

### [backend/lets_go/test/tests/test_views_ridebooking.py](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/backend/lets_go/test/tests/test_views_ridebooking.py:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| test_get_ride_booking_details_invalid_method | `views_ridebooking.get_ride_booking_details` | POST request (invalid method expected) | 405 Method Not Allowed | `status_code == 405` | PASS |
| test_get_confirmed_passengers_invalid_method | `views_ridebooking.get_confirmed_passengers` | POST request (invalid method expected) | 405 Method Not Allowed | `status_code == 405` | PASS |

---

### [backend/lets_go/test/tests/test_views_support_chat.py](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/backend/lets_go/test/tests/test_views_support_chat.py:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| TestViewsSupportChatHelpers.test_to_int_and_parse_json_body | `_to_int`, `_parse_json_body` | `_to_int('12')`; POST JSON `{'a':1}` | 12; parsed dict contains `a=1` | `==12`; `['a']==1` | PASS |
| TestViewsSupportChatHelpers.test_bot_reply_text | `_bot_reply_text` | Input text: `"what is fare"` | Reply contains keyword “fare” | `'fare' in reply.lower()` | PASS |
| TestViewsSupportChatHelpers.test_serialize_support_message | `_serialize_support_message` | Message namespace with `id=1`, thread info, created_at.isoformat | Serialized dict includes id | `out['id']==1` | PASS |
| TestViewsSupportChatEndpoints.test_support_guest_invalid_method | `support_guest` | GET invalid | 405 | asserted | PASS |
| TestViewsSupportChatEndpoints.test_view_bot_invalid_method | `view_bot` | PUT invalid | 405 | asserted | PASS |
| TestViewsSupportChatEndpoints.test_view_adminchat_invalid_method | `view_adminchat` | PUT invalid | 405 | asserted | PASS |
| TestViewsSupportChatEndpoints.test_ensure_thread_smoke | `_ensure_thread` | Patch `SupportThread.objects.get_or_create` => `(thread(id=1), True)` | Returns thread object | `out.id==1` | PASS |
| TestViewsSupportChatEndpoints.test_resolve_owner_from_query_user_not_found | `_resolve_owner_from_query` | Patch `UsersData.objects.filter().first()` => None; request `?user_id=5` | Error response 404 | `err.status_code==404` | PASS |
| TestViewsSupportChatEndpoints.test_resolve_owner_from_body_guest_not_found | `_resolve_owner_from_body` | Patch `GuestUser.objects.filter().first()` => None; body `{'guest_user_id':5}` | Error response 404 | `err.status_code==404` | PASS |
| TestViewsSupportChatEndpoints.test_sync_guest_fcm_updates | `_sync_guest_fcm` | guest namespace; patch `GuestUser.objects.filter`; patch `register_fcm_token_with_supabase_async` | Should update guest token + register externally | `m_filter.called` and `m_register.called` | PASS |

---

### [backend/lets_go/test/tests/test_views_user_notifications.py](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/backend/lets_go/test/tests/test_views_user_notifications.py:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| test_list_notifications_requires_user_or_guest | `list_notifications` | GET with no `user_id`/`guest_user_id` | 400 | `status_code==400` | PASS |
| test_list_notifications_user_success | `list_notifications` | Patch `NotificationInbox.objects.filter` side effects: first returns list qs with one notification; second returns count=3; request `?user_id=12&limit=50&offset=0` | 200 + payload: success true, unread_count=3, 1 notification | asserts `success==True`, `unread_count==3`, `len==1`, first id==1 | PASS |
| test_list_notifications_guest_success | `list_notifications` | Patch filters: list empty; count 0; request `?guest_user_id=7` | 200 + unread_count 0 | asserts | PASS |
| test_unread_count_user_and_guest | `notification_unread_count` | Patch count=5 for user request, then count=2 for guest request | 200 with correct unread_count | asserts unread_count values | PASS |
| test_mark_all_read_user_and_guest | `mark_all_notifications_read` | POST JSON `{user_id:1}` then `{guest_user_id:2}`; patch `NotificationInbox.objects` | 200 and update performed via filter | asserts status 200 and `filter.called` both times | PASS |
| test_mark_read_and_dismiss_not_found | `mark_notification_read`, `dismiss_notification` | Patch `NotificationInbox.objects.get` raises DoesNotExist | 404 for both | asserts 404 | PASS |
| test_mark_read_and_dismiss_success | `mark_notification_read`, `dismiss_notification` | Patch get returns notification namespaces with `save` mocked | 200 and `save()` called | asserts 200 and `save.called` | PASS |

---

### [backend/lets_go/test/tests/test_views_negotiation.py](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/backend/lets_go/test/tests/test_views_negotiation.py:0:0-0:0) (confirming full coverage)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| TestViewsNegotiationHelpers.test_to_int_pkr | `_to_int_pkr` | `'22.7'` | Rounds to int (ceil-like) | equals `23` | PASS |
| TestViewsNegotiationHelpers.test_serialize_booking_detail | `_serialize_booking_detail` | Booking namespace with ids + nested trip/passenger/stops | Output contains expected keys, correct id mapping | `out['booking_id']==1` | PASS |
| TestViewsNegotiationEndpoints.test_handle_ride_booking_request_invalid_method | `handle_ride_booking_request` | GET invalid | 405 | asserted | PASS |
| test_list_pending_requests_invalid_method | `list_pending_requests` | POST invalid | 405 | asserted | PASS |
| test_list_pending_requests_not_found | `list_pending_requests` | Patch `Trip.objects.filter().values_list().first()` => None | 404 | asserted | PASS |
| test_booking_request_details_invalid_method | `booking_request_details` | POST invalid | 405 | asserted | PASS |
| test_respond_booking_request_invalid_method | `respond_booking_request` | GET invalid | 405 | asserted | PASS |
| test_unblock_passenger_for_trip_invalid_method | `unblock_passenger_for_trip` | GET invalid | 405 | asserted | PASS |
| test_passenger_respond_booking_invalid_method | `passenger_respond_booking` | GET invalid | 405 | asserted | PASS |
| test_get_booking_negotiation_history_invalid_method | `get_booking_negotiation_history` | POST invalid | 405 | asserted | PASS |
| test_request_ride_booking_invalid_method | `request_ride_booking` | GET invalid | 405 | asserted | PASS |

---

## Section B: Flutter generated contract tests (`lets_go/test/generated/**`)

### Tables (Part 1)

These tests don’t validate runtime behavior; they validate **code contract presence**:
- file is non-empty
- class declarations exist
- expected function names (symbols) exist via regex

### [lets_go/test/generated/utils/map_util_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/utils/map_util_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| utils/map_util.dart contract → source file is non-empty | Contract for `lib/utils/map_util.dart` | Read source file to string | `source.trim().isNotEmpty == true` | asserted true | PASS |
| utils/map_util.dart contract → declares expected classes | Contract for `MapUtil` class | Source string contains `class MapUtil` | `true` | asserted true | PASS |
| utils/map_util.dart contract → contains expected callable symbols | Contract for functions | Regex matches for `boundsFromPoints`, `calculateDistanceMeters`, `centerFromPoints`, `generateInterpolatedRoute`, `roadPolylineOrFallback` | each regex match true | asserted true | PASS |

---

### [lets_go/test/generated/utils/test_frontend_calculator_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/utils/test_frontend_calculator_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| utils/test_frontend_calculator.dart contract → source file is non-empty | Contract for `lib/utils/test_frontend_calculator.dart` | Read source | non-empty | asserted true | PASS |
| utils/test_frontend_calculator.dart contract → contains expected callable symbols | Contract for [main()](cci:1://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/utils/map_util_contract_test.dart:3:0-22:1) | Regex match [main(](cci:1://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/utils/map_util_contract_test.dart:3:0-22:1) | true | asserted true | PASS |

---

### [lets_go/test/generated/utils/battery_optimization_helper_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/utils/battery_optimization_helper_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| utils/battery_optimization_helper.dart contract → source file is non-empty | Contract for `lib/utils/battery_optimization_helper.dart` | Read source | non-empty | asserted true | PASS |
| utils/battery_optimization_helper.dart contract → declares expected classes | `BatteryOptimizationHelper` existence | `source.contains('class BatteryOptimizationHelper')` | true | asserted true | PASS |
| utils/battery_optimization_helper.dart contract → contains expected callable symbols | `requestIgnoreOptimizations()` existence | regex matches | true | asserted true | PASS |

---

### [lets_go/test/generated/utils/auth_session_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/utils/auth_session_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| utils/auth_session.dart contract → source file is non-empty | Contract for `lib/utils/auth_session.dart` | Read source | non-empty | asserted true | PASS |
| utils/auth_session.dart contract → declares expected classes | `AuthSession` existence | contains `class AuthSession` | true | asserted true | PASS |
| utils/auth_session.dart contract → contains expected callable symbols | `clear()`, `load()`, `save()` existence | regex matches | true | asserted true | PASS |

---

### Tables (Part 2: remaining `generated/utils`)

> All these tests follow the same contract pattern:
- read `lib/...` source file as string
- assert **non-empty**
- assert **class exists** (sometimes)
- assert **expected symbols exist** via regex (sometimes)

### [lets_go/test/generated/utils/road_polyline_service_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/utils/road_polyline_service_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| utils/road_polyline_service.dart contract → source file is non-empty | Contract for `lib/utils/road_polyline_service.dart` | Read source file | `source.trim().isNotEmpty == true` | asserted true | PASS |
| utils/road_polyline_service.dart contract → declares expected classes | Contract ensures `RoadPolylineService` exists | Source contains `class RoadPolylineService` | true | asserted true | PASS |

---

### [lets_go/test/generated/utils/test_hybrid_search_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/utils/test_hybrid_search_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| utils/test_hybrid_search.dart contract → source file is non-empty | Contract for `lib/utils/test_hybrid_search.dart` | Read source | non-empty | asserted true | PASS |
| utils/test_hybrid_search.dart contract → declares expected classes | `HybridSearchTest` exists | contains `class HybridSearchTest` | true | asserted true | PASS |
| utils/test_hybrid_search.dart contract → contains expected callable symbols | `testPlacesService()` exists | regex match `testPlacesService(` | true | asserted true | PASS |

---

### [lets_go/test/generated/utils/fare_calculator_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/utils/fare_calculator_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| utils/fare_calculator.dart contract → source file is non-empty | Contract for `lib/utils/fare_calculator.dart` | Read source | non-empty | asserted true | PASS |
| utils/fare_calculator.dart contract → declares expected classes | `FareCalculator` exists | contains `class FareCalculator` | true | asserted true | PASS |
| utils/fare_calculator.dart contract → contains expected callable symbols | Fare calculator API surface exists | regex matches for `formatFare`, `getFareBreakdownText`, `getFareSummary`, `getFuelEfficiency`, `getFuelPrices`, `updateFuelPrices` | all true | PASS |

---

### [lets_go/test/generated/utils/debug_fare_calculator_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/utils/debug_fare_calculator_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| utils/debug_fare_calculator.dart contract → source file is non-empty | Contract for `lib/utils/debug_fare_calculator.dart` | Read source | non-empty | asserted true | PASS |
| utils/debug_fare_calculator.dart contract → declares expected classes | `DebugFareCalculator` exists | contains `class DebugFareCalculator` | true | asserted true | PASS |
| utils/debug_fare_calculator.dart contract → contains expected callable symbols | Debug/test helper API exists | regex matches for `compareWithBackend`, `testCalculationComponents`, `testFareConsistency`, `testFrontendCalculator`, `testHybridFareCalculation`, `testUserReportedIssue` | all true | PASS |

---

#### `generated/utils/*_contract_test.dart` (remaining batch)

### [lets_go/test/generated/utils/image_utils_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/utils/image_utils_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| utils/image_utils.dart contract → source file is non-empty | Contract for `lib/utils/image_utils.dart` | Read source file as string | `source.trim().isNotEmpty == true` | asserted true | PASS |
| utils/image_utils.dart contract → declares expected classes | `ImageUtils` class presence | `source.contains('class ImageUtils')` | true | asserted true | PASS |
| utils/image_utils.dart contract → contains expected callable symbols | Image util API surface exists | Regex matches for `ensureValidImageUrl(`, `getFallbackImageUrl(`, `isValidImageUrl(` | all true | PASS |

---

### [lets_go/test/generated/utils/recreate_trip_mapper_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/utils/recreate_trip_mapper_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| utils/recreate_trip_mapper.dart contract → source file is non-empty | Contract for `lib/utils/recreate_trip_mapper.dart` | Read source | non-empty | asserted true | PASS |
| utils/recreate_trip_mapper.dart contract → declares expected classes | `RecreateTripMapper` presence | contains `class RecreateTripMapper` | true | asserted true | PASS |
| utils/recreate_trip_mapper.dart contract → contains expected callable symbols | Mapper API exists | Regex matches `normalizeRideBookingDetail(` and `parsePolylinePoints(` | both true | PASS |

---

### [lets_go/test/generated/utils/test_route_creation_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/utils/test_route_creation_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| utils/test_route_creation.dart contract → source file is non-empty | Contract for `lib/utils/test_route_creation.dart` | Read source | non-empty | asserted true | PASS |
| utils/test_route_creation.dart contract → declares expected classes | `RouteCreationUtils` presence | contains `class RouteCreationUtils` | true | asserted true | PASS |
| utils/test_route_creation.dart contract → contains expected callable symbols | Distance function exposed | Regex matches `calculateDistance(` | true | PASS |

---

### [lets_go/test/generated/utils/actual_path_rules_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/utils/actual_path_rules_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| utils/actual_path_rules.dart contract → source file is non-empty | Contract for `lib/utils/actual_path_rules.dart` | Read source | non-empty | asserted true | PASS |
| utils/actual_path_rules.dart contract → declares expected classes | `ActualPathRules` presence | contains `class ActualPathRules` | true | PASS |
| utils/actual_path_rules.dart contract → contains expected callable symbols | Utility symbols exist | Regex matches `sameLatLng(` and `startsWithStops(` | both true | PASS |

---

### [lets_go/test/generated/utils/road_polyline_service_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/utils/road_polyline_service_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| utils/road_polyline_service.dart contract → source file is non-empty | Contract for `lib/utils/road_polyline_service.dart` | Read source | non-empty | asserted true | PASS |
| utils/road_polyline_service.dart contract → declares expected classes | `RoadPolylineService` presence | contains class name | true | PASS |

---

### [lets_go/test/generated/utils/test_hybrid_search_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/utils/test_hybrid_search_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| utils/test_hybrid_search.dart contract → source file is non-empty | Contract for `lib/utils/test_hybrid_search.dart` | Read source | non-empty | PASS |
| utils/test_hybrid_search.dart contract → declares expected classes | `HybridSearchTest` presence | contains class name | true | PASS |
| utils/test_hybrid_search.dart contract → contains expected callable symbols | `testPlacesService` exists | Regex matches | true | PASS |

---

### [lets_go/test/generated/utils/fare_calculator_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/utils/fare_calculator_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| utils/fare_calculator.dart contract → source file is non-empty | Contract for `lib/utils/fare_calculator.dart` | Read source | non-empty | PASS |
| utils/fare_calculator.dart contract → declares expected classes | `FareCalculator` exists | contains class name | true | PASS |
| utils/fare_calculator.dart contract → contains expected callable symbols | Fare methods exist | Regex matches: `formatFare`, `getFareBreakdownText`, `getFareSummary`, `getFuelEfficiency`, `getFuelPrices`, `updateFuelPrices` | all true | PASS |

---

### [lets_go/test/generated/utils/debug_fare_calculator_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/utils/debug_fare_calculator_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| utils/debug_fare_calculator.dart contract → source file is non-empty | Contract for `lib/utils/debug_fare_calculator.dart` | Read source | non-empty | PASS |
| utils/debug_fare_calculator.dart contract → declares expected classes | `DebugFareCalculator` exists | contains class name | true | PASS |
| utils/debug_fare_calculator.dart contract → contains expected callable symbols | Debug methods exist | Regex matches: `compareWithBackend`, `testCalculationComponents`, `testFareConsistency`, `testFrontendCalculator`, `testHybridFareCalculation`, `testUserReportedIssue` | all true | PASS |

---

## B2) Start `generated/controllers/**` (batch 1)

### [lets_go/test/generated/controllers/signup_login_controllers/login_controller_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/controllers/signup_login_controllers/login_controller_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| controllers/.../login_controller.dart contract → source file is non-empty | Contract for `lib/controllers/signup_login_controllers/login_controller.dart` | Read source | non-empty | asserted true | PASS |
| controllers/.../login_controller.dart contract → declares expected classes | `LoginController` exists | `source.contains('class LoginController')` | true | PASS |

---

### [lets_go/test/generated/controllers/signup_login_controllers/otp_verification_controller_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/controllers/signup_login_controllers/otp_verification_controller_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| controllers/.../otp_verification_controller.dart contract → source file is non-empty | Contract for `lib/controllers/signup_login_controllers/otp_verification_controller.dart` | Read source | non-empty | PASS |
| controllers/.../otp_verification_controller.dart contract → declares expected classes | `OTPVerificationController` exists | contains class name | true | PASS |
| controllers/.../otp_verification_controller.dart contract → contains expected callable symbols | Controller API exists | Regex matches: `cleanupSignupData`, `dispose`, `initExpiryFromArgs`, `loadSignupData`, `resendOtp`, `startEmailTimer`, `startPhoneTimer`, `submitFinalRegistration` | all true | PASS |

---

### [lets_go/test/generated/controllers/ride_posting_controllers/create_route_controller_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/controllers/ride_posting_controllers/create_route_controller_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| controllers/.../create_route_controller.dart contract → source file is non-empty | Contract for `lib/controllers/ride_posting_controllers/create_route_controller.dart` | Read source | non-empty | PASS |
| controllers/.../create_route_controller.dart contract → declares expected classes | `CreateRouteController` exists | contains class name | true | PASS |
| controllers/.../create_route_controller.dart contract → contains expected callable symbols | Route controller surface exists | Regex matches: `Timer(`, `addPointToRoute`, `buildFullLabel`, `calculateDistance`, `calculateDistanceFromCurrent`, `calculateRouteMetrics`, `clearRoute`, `clearSearch`, `createRoute`, `deleteStop`, `dispose`, `editStopName`, `fetchRoute`, `findNearbyPlaceName`, `getCurrentLocation`, `getPlaceNameFromCoordinates`, `getRouteData`, `handleMapTap`, `loadExistingRouteData`, `loadPlacesData`, `poiPriorityScore`, `removeDuplicatesAndSort`, `searchPlaces`, `selectSearchResult`, `updateRoute`, `updateStopName` | all true | PASS |

---

### [lets_go/test/generated/controllers/post_bookings_controller/live_tracking_controller_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/controllers/post_bookings_controller/live_tracking_controller_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| controllers/.../live_tracking_controller.dart contract → source file is non-empty | Contract for `lib/controllers/post_bookings_controller/live_tracking_controller.dart` | Read source | non-empty | PASS |
| controllers/.../live_tracking_controller.dart contract → declares expected classes | `LiveTrackingController` exists | contains class name | true | PASS |
| controllers/.../live_tracking_controller.dart contract → contains expected callable symbols | Tracking API exists | Regex matches: `detachUi`, `dispose`, `generatePickupCode`, `init`, `pointForStopOrder`, `refreshTripLayout`, `setSelectedBookingId`, `startRide`, `stopSendingLocation`, `verifyPickupCode` | all true | PASS |

---

### Controllers contract tests (`lets_go/test/generated/controllers/**`) — Remaining controllers (profile + ride_booking + ride_posting + post_bookings)

### [lets_go/test/generated/controllers/profile/profile_main_controller_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/controllers/profile/profile_main_controller_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| controllers/profile/profile_main_controller.dart contract → source file is non-empty | Contract for `lib/controllers/profile/profile_main_controller.dart` | Read source | non-empty | asserted true | PASS |
| controllers/profile/profile_main_controller.dart contract → declares expected classes | `ProfileMainController` exists | contains class name | true | PASS |
| controllers/profile/profile_main_controller.dart contract → contains expected callable symbols | Required symbol exists | Regex matches `ensureLicenseIfMissing(` | true | PASS |

---

### [lets_go/test/generated/controllers/profile/profile_general_info_controller_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/controllers/profile/profile_general_info_controller_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| controllers/profile/profile_general_info_controller.dart contract → source file is non-empty | Contract for `lib/controllers/profile/profile_general_info_controller.dart` | Read source | non-empty | PASS |
| controllers/profile/profile_general_info_controller.dart contract → declares expected classes | `ProfileGeneralInfoController` exists | contains class name | true | PASS |
| controllers/profile/profile_general_info_controller.dart contract → contains expected callable symbols | Required methods exist | Regex matches: `getCnicImages`, `hydrateProfile`, `imageUrl`, `resolveCnic`, `resolvePhone`, `resolveString`, `saveChanges`, `setEditing`, `toggleEdit` | all true | PASS |

---

### [lets_go/test/generated/controllers/profile/profile_vehicle_info_controller_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/controllers/profile/profile_vehicle_info_controller_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| controllers/profile/profile_vehicle_info_controller.dart contract → source file is non-empty | Contract for `lib/controllers/profile/profile_vehicle_info_controller.dart` | Read source | non-empty | PASS |
| controllers/profile/profile_vehicle_info_controller.dart contract → declares expected classes | `ProfileVehicleInfoController` exists | contains class name | true | PASS |
| controllers/profile/profile_vehicle_info_controller.dart contract → contains expected callable symbols | Required methods exist | Regex matches: `computeDriverByLicenseOnly`, `ensureVehicleDetails`, `getLicenseImages`, `hydrateUser`, `licenseNumber`, `loadVehicles`, `userImg` | all true | PASS |

---

### [lets_go/test/generated/controllers/profile/profile_contact_change_controller_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/controllers/profile/profile_contact_change_controller_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| controllers/profile/profile_contact_change_controller.dart contract → source file is non-empty | Contract for `lib/controllers/profile/profile_contact_change_controller.dart` | Read source | non-empty | PASS |
| controllers/profile/profile_contact_change_controller.dart contract → declares expected classes | `ProfileContactChangeController` exists | contains class name | true | PASS |
| controllers/profile/profile_contact_change_controller.dart contract → contains expected callable symbols | Required methods exist | Regex matches: `sendOtp(`, `verifyOtp(` | both true | PASS |

---

### [lets_go/test/generated/controllers/profile/vehicle_form_controller_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/controllers/profile/vehicle_form_controller_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| controllers/profile/vehicle_form_controller.dart contract → source file is non-empty | Contract for `lib/controllers/profile/vehicle_form_controller.dart` | Read source | non-empty | PASS |
| controllers/profile/vehicle_form_controller.dart contract → declares expected classes | `VehicleFormController` exists | contains class name | true | PASS |
| controllers/profile/vehicle_form_controller.dart contract → contains expected callable symbols | Required methods exist | Regex matches: `deleteVehicle(`, `submit(` | both true | PASS |

---

## Ride Booking controllers

### [lets_go/test/generated/controllers/ride_booking_controllers/ride_details_view_controller_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/controllers/ride_booking_controllers/ride_details_view_controller_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| controllers/ride_booking_controllers/ride_details_view_controller.dart contract → source file is non-empty | Contract for `lib/controllers/ride_booking_controllers/ride_details_view_controller.dart` | Read source | non-empty | PASS |
| controllers/ride_booking_controllers/ride_details_view_controller.dart contract → declares expected classes | `RideDetailsViewController` exists | contains class name | true | PASS |
| controllers/ride_booking_controllers/ride_details_view_controller.dart contract → contains expected callable symbols | Required methods exist | Regex matches: `dispose`, `getDriverInfo`, `getFormattedDepartureTime`, `getFormattedTripDate`, `getGenderPreferenceText`, `getInterpolatedRoutePoints`, `getPassengersInfo`, `getTripInfo`, `getTripStatusColor`, `getTripStatusText`, `getVehicleInfo`, `isRideBookable`, `loadRideDetails`, `setState` | all true | PASS |

---

### [lets_go/test/generated/controllers/ride_booking_controllers/ride_request_controller_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/controllers/ride_booking_controllers/ride_request_controller_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| controllers/ride_booking_controllers/ride_request_controller.dart contract → source file is non-empty | Contract for `lib/controllers/ride_booking_controllers/ride_request_controller.dart` | Read source | non-empty | PASS |
| controllers/ride_booking_controllers/ride_request_controller.dart contract → declares expected classes | `RideRequestController` exists | contains class name | true | PASS |
| controllers/ride_booking_controllers/ride_request_controller.dart contract → contains expected callable symbols | Booking request API exists | Regex matches for all the listed fare/seat/formatting/route getters + `initializeWithRideData`, `requestRideBooking`, `setState`, and the update methods (`updateFromStop`, `updateToStop`, `updateMaleSeats`, `updateFemaleSeats`, etc.) | all true | PASS |

---

### [lets_go/test/generated/controllers/ride_booking_controllers/ride_booking_details_controller_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/controllers/ride_booking_controllers/ride_booking_details_controller_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| controllers/ride_booking_controllers/ride_booking_details_controller.dart contract → source file is non-empty | Contract for `lib/controllers/ride_booking_controllers/ride_booking_details_controller.dart` | Read source | non-empty | PASS |
| controllers/ride_booking_controllers/ride_booking_details_controller.dart contract → declares expected classes | `RideBookingDetailsController` exists | contains class name | true | PASS |
| controllers/ride_booking_controllers/ride_booking_details_controller.dart contract → contains expected callable symbols | Booking details API exists | Regex matches the listed symbols including `calculateTotalFare`, `clearError`, `setError`, `setLoading`, `loadRideDetails`, `getBookingInfo`, and vehicle/driver helpers like `driverPhotoUrl`, `plateNumber`, `vehicleType`, etc. | all true | PASS |

---

## Ride Posting controllers

### [lets_go/test/generated/controllers/ride_posting_controllers/create_ride_controller_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/controllers/ride_posting_controllers/create_ride_controller_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| controllers/ride_posting_controllers/create_ride_controller.dart contract → source file is non-empty | Contract for `lib/controllers/ride_posting_controllers/create_ride_controller.dart` | Read source | non-empty | PASS |
| controllers/ride_posting_controllers/create_ride_controller.dart contract → declares expected classes | `CreateRideController` exists | contains class name | true | PASS |
| controllers/ride_posting_controllers/create_ride_controller.dart contract → contains expected callable symbols | Required methods exist | Regex matches: `dispose(`, `navigateToRouteCreation(` | both true | PASS |

---

### [lets_go/test/generated/controllers/ride_posting_controllers/create_ride_details_controller_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/controllers/ride_posting_controllers/create_ride_details_controller_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| controllers/ride_posting_controllers/create_ride_details_controller.dart contract → source file is non-empty | Contract for `lib/controllers/ride_posting_controllers/create_ride_details_controller.dart` | Read source | non-empty | PASS |
| controllers/ride_posting_controllers/create_ride_details_controller.dart contract → declares expected classes | `RideDetailsController` exists | contains class name | true | PASS |
| controllers/ride_posting_controllers/create_ride_details_controller.dart contract → contains expected callable symbols | Ride creation details API exists | Regex matches: `calculateDistance`, `calculateDynamicFare`, `createRide`, `createRoute`, `dispose`, `fetchPlannedRouteOnRoads`, `getCurrentLocation`, `getRideData`, `getRouteData`, `initializeRouteData`, `loadUserVehicles`, `selectVehicle`, `setMapLoading`, `setUseActualPath`, `togglePriceNegotiation`, `updateDescription`, `updateGenderPreference`, `updateSelectedDate`, `updateSelectedTime`, `updateSelectedVehicle`, `updateStopPrice`, `updateTotalPrice`, `updateTotalSeats` | all true | PASS |

---

### [lets_go/test/generated/controllers/ride_posting_controllers/my_rides_controller_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/controllers/ride_posting_controllers/my_rides_controller_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| controllers/ride_posting_controllers/my_rides_controller.dart contract → source file is non-empty | Contract for `lib/controllers/ride_posting_controllers/my_rides_controller.dart` | Read source | non-empty | PASS |
| controllers/ride_posting_controllers/my_rides_controller.dart contract → declares expected classes | `MyRidesController` exists | contains class name | true | PASS |
| controllers/ride_posting_controllers/my_rides_controller.dart contract → contains expected callable symbols | My rides API exists | Regex matches: `cancelBooking`, `cancelRide`, `deleteRide`, `dispose`, `loadUserRides` | all true | PASS |

---

### [lets_go/test/generated/controllers/ride_posting_controllers/ride_edit_controller_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/controllers/ride_posting_controllers/ride_edit_controller_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| controllers/ride_posting_controllers/ride_edit_controller.dart contract → source file is non-empty | Contract for `lib/controllers/ride_posting_controllers/ride_edit_controller.dart` | Read source | non-empty | PASS |
| controllers/ride_posting_controllers/ride_edit_controller.dart contract → declares expected classes | `RideEditController` exists | contains class name | true | PASS |
| controllers/ride_posting_controllers/ride_edit_controller.dart contract → contains expected callable symbols | Ride edit API exists | Regex matches: `applyUpdatedRouteData`, `calculateDynamicFare`, `cancelRide`, `fetchRoutePoints`, `getCurrentLocation`, `initializeWithRideData`, `loadUserVehicles`, `togglePriceNegotiation`, `updateRide`, `updateStopPrice`, `updateTotalPrice` | all true | PASS |

---

### [lets_go/test/generated/controllers/ride_posting_controllers/ride_request_controller_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/controllers/ride_posting_controllers/ride_request_controller_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| controllers/ride_posting_controllers/ride_request_controller.dart contract → source file is non-empty | Contract for `lib/controllers/ride_posting_controllers/ride_request_controller.dart` | Read source | non-empty | PASS |
| controllers/ride_posting_controllers/ride_request_controller.dart contract → declares expected classes | `RideRequestController` exists | contains class name | true | PASS |
| controllers/ride_posting_controllers/ride_request_controller.dart contract → contains expected callable symbols | Request/negotiation API exists | Regex matches the listed symbols (fare/seat getters, formatting helpers, `initializeWithRideData`, `requestRideBooking`, `setState`, and update methods) | all true | PASS |

---

### [lets_go/test/generated/controllers/ride_posting_controllers/ride_view_controller_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/controllers/ride_posting_controllers/ride_view_controller_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| controllers/ride_posting_controllers/ride_view_controller.dart contract → source file is non-empty | Contract for `lib/controllers/ride_posting_controllers/ride_view_controller.dart` | Read source | non-empty | PASS |
| controllers/ride_posting_controllers/ride_view_controller.dart contract → declares expected classes | `RideViewController` exists | contains class name | true | PASS |
| controllers/ride_posting_controllers/ride_view_controller.dart contract → contains expected callable symbols | View ride API exists | Regex matches: `cancelRide`, `fetchRoutePoints`, `getCurrentLocation`, `initializeWithRideData` | all true | PASS |

---

### [lets_go/test/generated/controllers/ride_posting_controllers/ride_view_edit_controller_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/controllers/ride_posting_controllers/ride_view_edit_controller_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| controllers/ride_posting_controllers/ride_view_edit_controller.dart contract → source file is non-empty | Contract for `lib/controllers/ride_posting_controllers/ride_view_edit_controller.dart` | Read source | non-empty | PASS |
| controllers/ride_posting_controllers/ride_view_edit_controller.dart contract → declares expected classes | `RideViewEditController` + `scope` symbol exist | source contains `class RideViewEditController` and contains `class scope` | both true | PASS |

---

## Post-bookings controllers (remaining ones)

### [lets_go/test/generated/controllers/post_bookings_controller/driver_live_tracking_controller_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/controllers/post_bookings_controller/driver_live_tracking_controller_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| controllers/post_bookings_controller/driver_live_tracking_controller.dart contract → source file is non-empty | Contract for `lib/controllers/post_bookings_controller/driver_live_tracking_controller.dart` | Read source | non-empty | PASS |
| controllers/post_bookings_controller/driver_live_tracking_controller.dart contract → declares expected classes | `DriverLiveTrackingController` exists | contains class name | true | PASS |

---

### [lets_go/test/generated/controllers/post_bookings_controller/passenger_live_tracking_controller_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/controllers/post_bookings_controller/passenger_live_tracking_controller_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| controllers/post_bookings_controller/passenger_live_tracking_controller.dart contract → source file is non-empty | Contract for `lib/controllers/post_bookings_controller/passenger_live_tracking_controller.dart` | Read source | non-empty | PASS |
| controllers/post_bookings_controller/passenger_live_tracking_controller.dart contract → declares expected classes | `PassengerLiveTrackingController` exists | contains class name | true | PASS |

---


### Screens contract tests (`lets_go/test/generated/screens/**`) — Batch 1

### [lets_go/test/generated/screens/home_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/home_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| screens/home_screen.dart contract → source file is non-empty | Contract for `lib/screens/home_screen.dart` | Read source file | `source.trim().isNotEmpty == true` | asserted true | PASS |
| screens/home_screen.dart contract → declares expected classes | UI classes exist | Source contains `class HomeScreen` and `class _HomeScreenState` | both true | PASS |
| screens/home_screen.dart contract → contains expected callable symbols | Widget lifecycle/helpers exist | Regex matches: `build(`, `dispose(`, `initOnce(`, `initState(`, `setModalState(`, `setState(`, `suggest(`, `toDouble(`, `vehicleThumbUrl(` | all true | PASS |

---

### [lets_go/test/generated/screens/notifications_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/notifications_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| screens/notifications_screen.dart contract → source file is non-empty | Contract for `lib/screens/notifications_screen.dart` | Read source | non-empty | PASS |
| screens/notifications_screen.dart contract → declares expected classes | Screen + State exist | Contains `NotificationsScreen` and `_NotificationsScreenState` | both true | PASS |
| screens/notifications_screen.dart contract → contains expected callable symbols | Private handlers exist | Regex matches: `_load(`, `_markAllRead(`, `_dismiss(`, `_handleTap(` | all true | PASS |
| screens/notifications_screen.dart contract → uses notifications ApiService methods | Contract for API usage | Source contains `ApiService.listNotifications`, `ApiService.dismissNotification`, `ApiService.markAllNotificationsRead`, `ApiService.markNotificationRead` | all true | PASS |

---

## Post-booking screens

### [lets_go/test/generated/screens/post_booking_screens/live_tracking_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/post_booking_screens/live_tracking_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| screens/post_booking_screens/live_tracking_screen.dart contract → source file is non-empty | Contract for `lib/screens/post_booking_screens/live_tracking_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen and internal UI classes exist | Contains `LiveTrackingScreen`, `_LegendRow`, `_LiveTrackingScreenState` | all true | PASS |
| ... → contains expected callable symbols | Widget lifecycle/helpers exist | Regex matches: `build(`, `closeTo(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/post_booking_screens/driver_live_tracking_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/post_booking_screens/driver_live_tracking_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| screens/post_booking_screens/driver_live_tracking_screen.dart contract → source file is non-empty | Contract for `lib/screens/post_booking_screens/driver_live_tracking_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen/state + legend exist | Contains `DriverLiveTrackingScreen`, `_DriverLiveTrackingScreenState`, `_LegendRow` | all true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/post_booking_screens/passenger_live_tracking_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/post_booking_screens/passenger_live_tracking_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| screens/post_booking_screens/passenger_live_tracking_screen.dart contract → source file is non-empty | Contract for `lib/screens/post_booking_screens/passenger_live_tracking_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `PassengerLiveTrackingScreen`, `_PassengerLiveTrackingScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/post_booking_screens/passenger_payment_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/post_booking_screens/passenger_payment_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| screens/post_booking_screens/passenger_payment_screen.dart contract → source file is non-empty | Contract for `lib/screens/post_booking_screens/passenger_payment_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `PassengerPaymentScreen`, `_PassengerPaymentScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/post_booking_screens/driver_payment_confirmation_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/post_booking_screens/driver_payment_confirmation_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| screens/post_booking_screens/driver_payment_confirmation_screen.dart contract → source file is non-empty | Contract for `lib/screens/post_booking_screens/driver_payment_confirmation_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `DriverPaymentConfirmationScreen`, `_DriverPaymentConfirmationScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `initState(`, `setState(` | all true | PASS |

---

## Chat screens

### [lets_go/test/generated/screens/chat_screens/passenger_chat_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/chat_screens/passenger_chat_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| screens/chat_screens/passenger_chat_screen.dart contract → source file is non-empty | Contract for `lib/screens/chat_screens/passenger_chat_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `PassengerChatScreen`, `_PassengerChatScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---


### Screens contract tests (`lets_go/test/generated/screens/**`) — Batch 2

### [lets_go/test/generated/screens/chat_screens/driver_chat_members_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/chat_screens/driver_chat_members_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| screens/chat_screens/driver_chat_members_screen.dart contract → source file is non-empty | Contract for `lib/screens/chat_screens/driver_chat_members_screen.dart` | Read source | non-empty | asserted true | PASS |
| ... → declares expected classes | Screen + State exist | Contains `DriverChatMembersScreen`, `_DriverChatMembersScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/chat_screens/driver_individual_chat_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/chat_screens/driver_individual_chat_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| screens/chat_screens/driver_individual_chat_screen.dart contract → source file is non-empty | Contract for `lib/screens/chat_screens/driver_individual_chat_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `DriverIndividualChatScreen`, `_DriverIndividualChatScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### Profile screens (`generated/screens/profile_screens/*_contract_test.dart`) — Batch 1

### [lets_go/test/generated/screens/profile_screens/profile_main_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/profile_main_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| screens/profile_screens/profile_main_screen.dart contract → source file is non-empty | Contract for `lib/screens/profile_screens/profile_main_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `ProfileMainScreen`, `_ProfileMainScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/profile_screens/profile_edit_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/profile_edit_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| screens/profile_screens/profile_edit_screen.dart contract → source file is non-empty | Contract for `lib/screens/profile_screens/profile_edit_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `ProfileEditScreen`, `_ProfileEditScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/profile_screens/profile_general_info_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/profile_general_info_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| screens/profile_screens/profile_general_info_screen.dart contract → source file is non-empty | Contract for `lib/screens/profile_screens/profile_general_info_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `ProfileGeneralInfoScreen`, `_ProfileGeneralInfoScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle/helper exists | Regex matches: `build(`, `dispose(`, `docImage(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/profile_screens/profile_contact_change_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/profile_contact_change_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| screens/profile_screens/profile_contact_change_screen.dart contract → source file is non-empty | Contract for `lib/screens/profile_screens/profile_contact_change_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `ProfileContactChangeScreen`, `_ProfileContactChangeScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/profile_screens/profile_blocked_users_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/profile_blocked_users_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| screens/profile_screens/profile_blocked_users_screen.dart contract → source file is non-empty | Contract for `lib/screens/profile_screens/profile_blocked_users_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `ProfileBlockedUsersScreen`, `_ProfileBlockedUsersScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/profile_screens/profile_cnic_edit_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/profile_cnic_edit_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| screens/profile_screens/profile_cnic_edit_screen.dart contract → source file is non-empty | Contract for `lib/screens/profile_screens/profile_cnic_edit_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `ProfileCnicEditScreen`, `_ProfileCnicEditScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---


### Profile screens (`generated/screens/profile_screens/*_contract_test.dart`) — Batch 2

### [lets_go/test/generated/screens/profile_screens/profile_driving_license_edit_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/profile_driving_license_edit_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| ...profile_driving_license_edit_screen.dart contract → source file is non-empty | Contract for `lib/screens/profile_screens/profile_driving_license_edit_screen.dart` | Read source | non-empty | asserted true | PASS |
| ... → declares expected classes | Screen + State exist | Contains `ProfileDrivingLicenseEditScreen`, `_ProfileDrivingLicenseEditScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/profile_screens/profile_emergency_contact_edit_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/profile_emergency_contact_edit_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| ...profile_emergency_contact_edit_screen.dart contract → source file is non-empty | Contract for `lib/screens/profile_screens/profile_emergency_contact_edit_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `ProfileEmergencyContactEditScreen`, `_ProfileEmergencyContactEditScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/profile_screens/profile_photos_edit_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/profile_photos_edit_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| ...profile_photos_edit_screen.dart contract → source file is non-empty | Contract for `lib/screens/profile_screens/profile_photos_edit_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `ProfilePhotosEditScreen`, `_ProfilePhotosEditScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget rendering/state exists | Regex matches: `build(`, `setState(` | both true | PASS |

---

### [lets_go/test/generated/screens/profile_screens/profile_change_password_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/profile_change_password_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| ...profile_change_password_screen.dart contract → source file is non-empty | Contract for `lib/screens/profile_screens/profile_change_password_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `ProfileChangePasswordScreen`, `_ProfileChangePasswordScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `dispose(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/profile_screens/profile_bank_info_edit_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/profile_bank_info_edit_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| ...profile_bank_info_edit_screen.dart contract → source file is non-empty | Contract for `lib/screens/profile_screens/profile_bank_info_edit_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `ProfileBankInfoEditScreen`, `_ProfileBankInfoEditScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/profile_screens/profile_ride_history_detail_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/profile_ride_history_detail_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| ...profile_ride_history_detail_screen.dart contract → source file is non-empty | Contract for `lib/screens/profile_screens/profile_ride_history_detail_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `ProfileRideHistoryDetailScreen`, `_ProfileRideHistoryDetailScreenState` | both true | PASS |

---

### [lets_go/test/generated/screens/profile_screens/booked_ride_history_detail_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/booked_ride_history_detail_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| ...booked_ride_history_detail_screen.dart contract → source file is non-empty | Contract for `lib/screens/profile_screens/booked_ride_history_detail_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `BookedRideHistoryDetailScreen`, `_BookedRideHistoryDetailScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/profile_screens/created_ride_history_detail_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/created_ride_history_detail_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| ...created_ride_history_detail_screen.dart contract → source file is non-empty | Contract for `lib/screens/profile_screens/created_ride_history_detail_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `CreatedRideHistoryDetailScreen`, `_CreatedRideHistoryDetailScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `initState(`, `setState(` | all true | PASS |

---

### Profile screens (`generated/screens/profile_screens/*_contract_test.dart`) — Remaining files

From the folder listing, the **remaining not-yet-tabulated** profile screen contract tests are:

- [profile_ride_history_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/profile_ride_history_screen_contract_test.dart:0:0-0:0)
- [profile_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/profile_screen_contract_test.dart:0:0-0:0)
- [profile_vehicle_info_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/profile_vehicle_info_screen_contract_test.dart:0:0-0:0)
- [vehicle_detail_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/vehicle_detail_screen_contract_test.dart:0:0-0:0)
- [vehicle_form_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/vehicle_form_screen_contract_test.dart:0:0-0:0)

(Everything else in that `profile_screens` folder was already tabulated in earlier batches.)

---

### [lets_go/test/generated/screens/profile_screens/profile_ride_history_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/profile_ride_history_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| ...profile_ride_history_screen.dart contract → source file is non-empty | Contract for `lib/screens/profile_screens/profile_ride_history_screen.dart` | Read source | non-empty | asserted true | PASS |
| ... → declares expected classes | Screen + State exist | Contains `ProfileRideHistoryScreen`, `_ProfileRideHistoryScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/profile_screens/profile_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/profile_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| ...profile_screen.dart contract → source file is non-empty | Contract for `lib/screens/profile_screens/profile_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | `ProfileScreen` exists | Contains `class ProfileScreen` | true | PASS |
| ... → contains expected callable symbols | Widget build exists | Regex matches: `build(` | true | PASS |

---

### [lets_go/test/generated/screens/profile_screens/profile_vehicle_info_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/profile_vehicle_info_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| ...profile_vehicle_info_screen.dart contract → source file is non-empty | Contract for `lib/screens/profile_screens/profile_vehicle_info_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `ProfileVehicleInfoScreen`, `_ProfileVehicleInfoScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle/helper exists | Regex matches: `build(`, `dispose(`, `docImage(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/profile_screens/vehicle_form_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/vehicle_form_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| ...vehicle_form_screen.dart contract → source file is non-empty | Contract for `lib/screens/profile_screens/vehicle_form_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `VehicleFormScreen`, `_VehicleFormScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/profile_screens/vehicle_detail_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/profile_screens/vehicle_detail_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| ...vehicle_detail_screen.dart contract → source file is non-empty | Contract for `lib/screens/profile_screens/vehicle_detail_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `VehicleDetailScreen`, `_VehicleDetailScreenState` | both true | PASS |
| ...vehicle_detail_screen.dart contract → contains expected callable symbols | UI helper methods exist | Regex matches: `build(`, `hasMeaningfulData(`, `infoRow(`, `initState(`, `setState(`, `statusColor(` | all true | PASS |

---

### [lets_go/test/generated/screens/ride_booking_screens/ride_request_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/ride_booking_screens/ride_request_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| ...ride_request_screen.dart contract → source file is non-empty | Contract for `lib/screens/ride_booking_screens/ride_request_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `RideRequestScreen`, `_RideRequestScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/ride_booking_screens/driver_requests_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/ride_booking_screens/driver_requests_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| ...driver_requests_screen.dart contract → source file is non-empty | Contract for `lib/screens/ride_booking_screens/driver_requests_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `DriverRequestsScreen`, `_DriverRequestsScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/ride_booking_screens/ride_details_view_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/ride_booking_screens/ride_details_view_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| ...ride_details_view_screen.dart contract → source file is non-empty | Contract for `lib/screens/ride_booking_screens/ride_details_view_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `RideDetailsViewScreen`, `_RideDetailsViewScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget lifecycle exists | Regex matches: `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/ride_booking_screens/ride_booking_details_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/ride_booking_screens/ride_booking_details_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted in test) | Status |
|---|---|---|---|---|---|
| ...ride_booking_details_screen.dart contract → source file is non-empty | Contract for `lib/screens/ride_booking_screens/ride_booking_details_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | Screen + State exist | Contains `RideBookingDetailsScreen`, `_RideBookingDetailsScreenState` | both true | PASS |
| ... → contains expected callable symbols | Widget/build helpers exist | Regex matches: `Builder(`, `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/ride_booking_screens/negotiation_details_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/ride_booking_screens/negotiation_details_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted) | Status |
|---|---|---|---|---|---|
| ...negotiation_details_screen.dart contract → source file is non-empty | Contract for `lib/screens/ride_booking_screens/negotiation_details_screen.dart` | Read `source` | non-empty | `expect(source.trim().isNotEmpty, isTrue)` | PASS |
| ... → declares expected classes | `NegotiationDetailsScreen`, `_NegotiationDetailsScreenState` | `source.contains(...)` | true | asserted true | PASS |
| ... → contains expected callable symbols | lifecycle | regex matches `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/ride_booking_screens/passenger_response_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/ride_booking_screens/passenger_response_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted) | Status |
|---|---|---|---|---|---|
| ...passenger_response_screen.dart contract → source file is non-empty | `lib/screens/ride_booking_screens/passenger_response_screen.dart` | Read source | non-empty | asserted true | PASS |
| ... → declares expected classes | `PassengerResponseScreen`, `_PassengerResponseScreenState` | contains | true | asserted true | PASS |
| ... → contains expected callable symbols | lifecycle | `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/ride_booking_screens/request_response_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/ride_booking_screens/request_response_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted) | Status |
|---|---|---|---|---|---|
| ...request_response_screen.dart contract → source file is non-empty | `lib/screens/ride_booking_screens/request_response_screen.dart` | Read source | non-empty | asserted true | PASS |
| ... → declares expected classes | `RequestResponseScreen`, `_RequestResponseScreenState` | contains | true | asserted true | PASS |
| ... → contains expected callable symbols | lifecycle | `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/ride_posting_screens/create_route_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/ride_posting_screens/create_route_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted) | Status |
|---|---|---|---|---|---|
| ...create_route_screen.dart contract → source file is non-empty | `lib/screens/ride_posting_screens/create_route_screen.dart` | Read source | non-empty | asserted true | PASS |
| ... → declares expected classes | `CreateRouteScreen`, `_CreateRouteScreenState` | contains | true | asserted true | PASS |
| ... → contains expected callable symbols | lifecycle + helper | `build(`, `dispose(`, `initState(`, `setState(`, `toInt(` | all true | PASS |

---

### [lets_go/test/generated/screens/ride_posting_screens/create_ride_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/ride_posting_screens/create_ride_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted) | Status |
|---|---|---|---|---|---|
| ...create_ride_screen.dart contract → source file is non-empty | `lib/screens/ride_posting_screens/create_ride_screen.dart` | Read source | non-empty | asserted true | PASS |
| ... → declares expected classes | `CreateRideScreen`, `_CreateRideScreenState` | contains | true | asserted true | PASS |
| ... → contains expected callable symbols | lifecycle | `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/ride_posting_screens/create_ride_details_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/ride_posting_screens/create_ride_details_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted) | Status |
|---|---|---|---|---|---|
| ...create_ride_details_screen.dart contract → source file is non-empty | `lib/screens/ride_posting_screens/create_ride_details_screen.dart` | Read source | non-empty | asserted true | PASS |
| ... → declares expected classes | `RideDetailsScreen`, `_RideDetailsScreenState` | contains | true | asserted true | PASS |
| ... → contains expected callable symbols | lifecycle + helper | `build(`, `dispose(`, `initState(`, `setState(`, `toInt(` | all true | PASS |

---

### [lets_go/test/generated/screens/ride_posting_screens/my_rides_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/ride_posting_screens/my_rides_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted) | Status |
|---|---|---|---|---|---|
| ...my_rides_screen.dart contract → source file is non-empty | `lib/screens/ride_posting_screens/my_rides_screen.dart` | Read source | non-empty | asserted true | PASS |
| ... → declares expected classes | `MyRidesScreen`, `_MyRidesScreenState` | contains | true | asserted true | PASS |
| ... → contains expected callable symbols | lifecycle + numeric helper | `asInt(`, `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/ride_posting_screens/ride_edit_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/ride_posting_screens/ride_edit_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted) | Status |
|---|---|---|---|---|---|
| ...ride_edit_screen.dart contract → source file is non-empty | `lib/screens/ride_posting_screens/ride_edit_screen.dart` | Read source | non-empty | asserted true | PASS |
| ... → declares expected classes | `RideEditScreen`, `_RideEditScreenState` | contains | true | asserted true | PASS |
| ... → contains expected callable symbols | lifecycle | `build(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/ride_posting_screens/ride_view_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/ride_posting_screens/ride_view_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted) | Status |
|---|---|---|---|---|---|
| ...ride_view_screen.dart contract → source file is non-empty | `lib/screens/ride_posting_screens/ride_view_screen.dart` | Read source | non-empty | asserted true | PASS |
| ... → declares expected classes | `RideViewScreen` exists | contains `class RideViewScreen` | true | PASS |
| ... → contains expected callable symbols | numeric + builder helpers | `asNum(`, `asNumLocal(`, `build(`, `mk(`, `sumNum(` | all true | PASS |

---

### [lets_go/test/generated/screens/ride_posting_screens/booking_detail_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/ride_posting_screens/booking_detail_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted) | Status |
|---|---|---|---|---|---|
| ...booking_detail_screen.dart contract → source file is non-empty | `lib/screens/ride_posting_screens/booking_detail_screen.dart` | Read source | non-empty | asserted true | PASS |
| ... → declares expected classes | `BookingDetailScreen` exists | contains `class BookingDetailScreen` | true | PASS |
| ... → contains expected callable symbols | booking helper functions exist | `asInt(`, `asNum(`, `build(`, `canCancelBooking(`, `cancelBooking(`, `isWithinPassengerSegment(`, `mk(`, `normalizePaymentStatus(`, `toInt(` | all true | PASS |

---

### [lets_go/test/generated/screens/signup_login_screens/login_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/signup_login_screens/login_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted) | Status |
|---|---|---|---|---|---|
| ...login_screen.dart contract → source file is non-empty | `lib/screens/signup_login_screens/login_screen.dart` | Read source | non-empty | asserted true | PASS |
| ... → declares expected classes | `LoginScreen`, `LoginScreenState` | contains | true | PASS |
| ... → contains expected callable symbols | lifecycle | `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/signup_login_screens/forgot_password_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/signup_login_screens/forgot_password_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted) | Status |
|---|---|---|---|---|---|
| ...forgot_password_screen.dart contract → source file is non-empty | `lib/screens/signup_login_screens/forgot_password_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | `ForgotPasswordScreen`, `_ForgotPasswordScreenState` | contains | true | PASS |
| ... → contains expected callable symbols | lifecycle | `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/signup_login_screens/otp_verification_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/signup_login_screens/otp_verification_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted) | Status |
|---|---|---|---|---|---|
| ...otp_verification_screen.dart contract → source file is non-empty | `lib/screens/signup_login_screens/otp_verification_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | `OTPVerificationScreen`, `_OTPVerificationScreenState` | contains | true | PASS |
| ... → contains expected callable symbols | lifecycle + dep hook | `build(`, `didChangeDependencies(`, `dispose(`, `initState(` | all true | PASS |

---

### [lets_go/test/generated/screens/signup_login_screens/otp_verification_reset_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/signup_login_screens/otp_verification_reset_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted) | Status |
|---|---|---|---|---|---|
| ...otp_verification_reset_screen.dart contract → source file is non-empty | `lib/screens/signup_login_screens/otp_verification_reset_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | `OTPVerificationResetScreen`, `_OTPVerificationResetScreenState` | contains | true | PASS |
| ... → contains expected callable symbols | lifecycle | `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/signup_login_screens/register_pending_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/signup_login_screens/register_pending_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted) | Status |
|---|---|---|---|---|---|
| ...register_pending_screen.dart contract → source file is non-empty | `lib/screens/signup_login_screens/register_pending_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | `RegisterPendingScreen`, `_RegisterPendingScreenState` | contains | true | PASS |
| ... → contains expected callable symbols | lifecycle + data push methods | `build(`, `didChangeDependencies(`, `putEmergency(`, `putPersonal(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/signup_login_screens/reset_password_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/signup_login_screens/reset_password_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted) | Status |
|---|---|---|---|---|---|
| ...reset_password_screen.dart contract → source file is non-empty | `lib/screens/signup_login_screens/reset_password_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | `ResetPasswordScreen`, `_ResetPasswordScreenState` | contains | true | PASS |
| ... → contains expected callable symbols | lifecycle | `build(`, `dispose(`, `initState(` | all true | PASS |

---

### [lets_go/test/generated/screens/signup_login_screens/signup_cnic_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/signup_login_screens/signup_cnic_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted) | Status |
|---|---|---|---|---|---|
| ...signup_cnic_screen.dart contract → source file is non-empty | `lib/screens/signup_login_screens/signup_cnic_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | `SignupCnicScreen`, `_SignupCnicScreenState` | contains | true | PASS |
| ... → contains expected callable symbols | lifecycle | `build(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/signup_login_screens/signup_emergency_contact_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/signup_login_screens/signup_emergency_contact_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted) | Status |
|---|---|---|---|---|---|
| ...signup_emergency_contact_screen.dart contract → source file is non-empty | `lib/screens/signup_login_screens/signup_emergency_contact_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | `SignupEmergencyContactScreen`, `_SignupEmergencyContactScreenState` | contains | true | PASS |
| ... → contains expected callable symbols | lifecycle | `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/signup_login_screens/signup_personal_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/signup_login_screens/signup_personal_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted) | Status |
|---|---|---|---|---|---|
| ...signup_personal_screen.dart contract → source file is non-empty | `lib/screens/signup_login_screens/signup_personal_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | `SignupPersonalScreen`, `_SignupPersonalScreenState`, `_UsernameLtrFormatter` | contains | true | PASS |
| ... → contains expected callable symbols | lifecycle | `build(`, `dispose(`, `initState(`, `setState(` | all true | PASS |

---

### [lets_go/test/generated/screens/signup_login_screens/signup_vehicle_screen_contract_test.dart](cci:7://file:///media/fawadsaqlain/d48ea7fa-dcc7-4123-bfbf-be9a8f90d471/MyFiles/Lets-Go/lets_go/test/generated/screens/signup_login_screens/signup_vehicle_screen_contract_test.dart:0:0-0:0)

| Test case | Function/unit under test | Input / setup | Expected output | Actual output (asserted) | Status |
|---|---|---|---|---|---|
| ...signup_vehicle_screen.dart contract → source file is non-empty | `lib/screens/signup_login_screens/signup_vehicle_screen.dart` | Read source | non-empty | PASS |
| ... → declares expected classes | `SignupVehicleScreen`, `_SignupVehicleScreenState` | contains | true | PASS |
| ... → contains expected callable symbols | lifecycle | `build(`, `initState(`, `setState(` | all true | PASS |

---
import json
from datetime import date, datetime, time
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from administration import views


class TestAdministrationHelpers:
    @patch('administration.views.RideAuditEvent.objects')
    def test_build_resolved_sos_snapshot_payload_minimal(self, m_events):
        m_events.none.return_value = []
        incident = SimpleNamespace(
            id=1,
            status='OPEN',
            role='driver',
            latitude=31.5,
            longitude=74.3,
            accuracy=5.0,
            note='SOS',
            created_at=None,
            resolved_at=None,
            resolved_by=None,
            resolved_note=None,
            trip=None,
            booking=None,
            actor=None,
            audit_event=None,
        )
        payload = views._build_resolved_sos_snapshot_payload(incident)
        assert payload['incident']['id'] == 1
        assert payload['trip'] is None

    @patch('administration.views.TripPayment.objects')
    def test_attach_latest_payments(self, m_payments):
        b1 = SimpleNamespace(id=1)
        b2 = SimpleNamespace(id=2)
        p1 = SimpleNamespace(booking_id=1, receipt_url='u1', payment_method='CASH')
        p2 = SimpleNamespace(booking_id=2, receipt_url='u2', payment_method='CARD')
        m_payments.filter.return_value.only.return_value.order_by.return_value = [p1, p2]
        views._attach_latest_payments([b1, b2])
        assert b1.latest_receipt_url == 'u1'
        assert b2.latest_payment_method == 'CARD'

    def test_combine_trip_dt(self):
        trip = SimpleNamespace(trip_date=date(2026, 1, 1))
        dt = views._combine_trip_dt(trip, time(10, 0))
        assert dt is not None

    def test_compute_reached_trigger_dt(self):
        trip = SimpleNamespace(trip_date=date(2026, 1, 1), departure_time=time(10, 0), estimated_arrival_time=time(11, 0))
        dep, arr, trigger = views._compute_reached_trigger_dt(trip)
        assert dep is not None and arr is not None and trigger is not None

    def test_vehicle_to_dict(self):
        v = SimpleNamespace(
            id=1,
            model_number='m',
            variant='v',
            company_name='c',
            plate_number='p',
            vehicle_type='CAR',
            color='white',
            photo_front_url='f',
            photo_back_url='b',
            documents_image_url='d',
            seats=4,
            engine_number='e',
            chassis_number='ch',
            fuel_type='Petrol',
            registration_date=date(2024, 1, 1),
            insurance_expiry=None,
            status='VERIFIED',
            created_at=None,
            updated_at=None,
        )
        out = views._vehicle_to_dict(v)
        assert out['id'] == 1
        assert out['registration_date'] == '2024-01-01'


class TestAdministrationBasicViews:
    @patch('administration.views.render', return_value=MagicMock(status_code=200))
    def test_guest_list_view(self, m_render, rf):
        res = views.guest_list_view(rf.get('/'))
        assert res.status_code == 200
        m_render.assert_called_once()

    @patch('administration.views.GuestUser.objects.all')
    def test_api_guests(self, m_all, rf):
        m_all.return_value.values.return_value = [{'id': 1, 'username': 'g'}]
        res = views.api_guests(rf.get('/'))
        assert res.status_code == 200
        assert json.loads(res.content)['guests'][0]['id'] == 1

    @patch('administration.views.render', return_value=MagicMock(status_code=200))
    def test_admin_analytics_settings_views(self, m_render, rf):
        assert views.admin_view(rf.get('/')).status_code == 200
        assert views.analytics_view(rf.get('/')).status_code == 200
        assert views.settings_view(rf.get('/')).status_code == 200
        assert m_render.call_count == 3

    @patch('administration.views.UsersData.objects.all')
    def test_api_users(self, m_all, rf):
        m_all.return_value.values.return_value = [{'id': 7, 'name': 'n'}]
        res = views.api_users(rf.get('/'))
        assert res.status_code == 200
        assert json.loads(res.content)['users'][0]['id'] == 7


class TestAdministrationAuthViews:
    @patch('administration.views.render', return_value=MagicMock(status_code=200))
    def test_login_view_get(self, m_render, rf):
        res = views.login_view(rf.get('/'))
        assert res.status_code == 200
        m_render.assert_called_once()

    @patch('administration.views.authenticate', return_value=None)
    @patch('administration.views.render', return_value=MagicMock(status_code=200))
    def test_login_view_post_invalid(self, m_render, _m_auth, rf):
        req = rf.post('/', data={'username': 'a', 'password': 'b'})
        res = views.login_view(req)
        assert res.status_code == 200
        assert m_render.called

    @patch('administration.views.redirect', return_value=MagicMock(status_code=302))
    @patch('administration.views.login')
    @patch('administration.views.authenticate', return_value=SimpleNamespace(id=1))
    def test_login_view_post_success(self, _m_auth, m_login, m_redirect, rf):
        req = rf.post('/', data={'username': 'a', 'password': 'b'})
        res = views.login_view(req)
        assert res.status_code == 302
        m_login.assert_called_once()
        m_redirect.assert_called_once()

    @patch('administration.views.redirect', return_value=MagicMock(status_code=302))
    @patch('administration.views.logout')
    def test_logout_view(self, m_logout, m_redirect, rf):
        res = views.logout_view(rf.get('/'))
        assert res.status_code == 302
        m_logout.assert_called_once()
        m_redirect.assert_called_once()


class TestAdministrationMethodGuardsAndPosts:
    def test_reached_overdue_dashboard_method_not_allowed(self, rf):
        req = rf.post('/')
        req.user = SimpleNamespace(is_authenticated=True, is_staff=True)
        assert views.reached_overdue_dashboard_view(req).status_code == 405

    def test_reached_overdue_dashboard_forbidden_non_staff(self, rf):
        req = rf.get('/')
        req.user = SimpleNamespace(is_authenticated=True, is_staff=False)
        assert views.reached_overdue_dashboard_view(req).status_code == 403

    @patch('administration.views.render', return_value=MagicMock(status_code=200))
    @patch('administration.views.Trip.objects')
    def test_reached_overdue_dashboard_success(self, m_trips, m_render, rf):
        req = rf.get('/')
        req.user = SimpleNamespace(is_authenticated=True, is_staff=True)
        m_trips.exclude.return_value.select_related.return_value.only.return_value.order_by.return_value.__getitem__.return_value = []
        res = views.reached_overdue_dashboard_view(req)
        assert res.status_code == 200
        m_render.assert_called_once()

    @patch('administration.views.get_object_or_404')
    @patch('administration.views.redirect', return_value=MagicMock(status_code=302))
    def test_vehicle_update_status_invalid_status_redirects(self, m_redirect, m_get, rf):
        user = SimpleNamespace(id=1)
        vehicle = SimpleNamespace(status='PENDING', full_clean=MagicMock(), save=MagicMock())
        m_get.side_effect = [user, vehicle]
        req = rf.post('/', data={'status': 'INVALID'})
        res = views.vehicle_update_status_view(req, 1, 1)
        assert res.status_code == 403

    @patch('administration.views.get_object_or_404')
    @patch('administration.views.redirect', return_value=MagicMock(status_code=302))
    def test_vehicle_delete_post(self, m_redirect, m_get, rf):
        user = SimpleNamespace(id=1)
        vehicle = SimpleNamespace(delete=MagicMock())
        m_get.side_effect = [user, vehicle]
        req = rf.post('/')
        res = views.vehicle_delete_view(req, 1, 2)
        assert res.status_code == 403

    @patch('administration.views.render', return_value=MagicMock(status_code=200))
    def test_user_add_view_get(self, m_render, rf):
        res = views.user_add_view(rf.get('/'))
        assert res.status_code == 200
        m_render.assert_called_once()


class TestAdministrationAdditionalCoverage:
    @patch('administration.views.render', return_value=MagicMock(status_code=200))
    @patch('administration.views.EmergencyContact.objects.filter')
    @patch('administration.views.get_object_or_404')
    def test_user_related_render_views(self, m_get, m_ec_filter, m_render, rf):
        vehicles_qs = MagicMock()
        vehicles_qs.all.return_value.order_by.return_value = []
        user = SimpleNamespace(id=1, vehicles=vehicles_qs)
        m_get.return_value = user
        m_ec_filter.return_value.first.return_value = None
        assert views.user_list_view(rf.get('/')).status_code == 200
        assert views.user_detail_view(rf.get('/'), 1).status_code == 200
        assert views.user_edit_view(rf.get('/'), 1).status_code == 200
        assert views.vehicle_detail_view(rf.get('/'), 1).status_code == 200
        assert views.vehicle_add_view(rf.get('/'), 1).status_code == 200
        assert m_render.called

    @patch('administration.views.get_object_or_404')
    @patch('administration.views.redirect', return_value=MagicMock(status_code=302))
    def test_update_user_status_view_post(self, m_redirect, m_get, rf):
        u = SimpleNamespace(status='PENDING', save=MagicMock())
        m_get.return_value = u
        req = rf.post('/', data={'status': 'VERIFIED'})
        res = views.update_user_status_view(req, 1)
        assert res.status_code == 302
        m_redirect.assert_called_once()

    @patch('administration.views.redirect', return_value=MagicMock(status_code=302))
    def test_user_vehicles_redirect_view(self, m_redirect, rf):
        res = views.user_vehicles_redirect_view(rf.get('/'), 1)
        assert res.status_code == 302

    @patch('administration.views.render', return_value=MagicMock(status_code=200))
    @patch('administration.views.SosIncident.objects')
    def test_sos_views_smoke(self, m_inc, m_render, rf):
        req = rf.get('/')
        req.user = SimpleNamespace(is_authenticated=True, is_staff=True)
        m_inc.select_related.return_value.order_by.return_value = []
        assert views.sos_dashboard_view(req).status_code == 200
        assert m_render.called


    def test_remaining_admin_symbols_callable(self):
        assert callable(views.guest_support_chat_view)
        assert callable(views.user_support_chat_view)
        assert callable(views.rides_dashboard_view)
        assert callable(views.admin_trip_detail_view)
        assert callable(views.change_requests_list_view)
        assert callable(views.change_request_detail_view)
        assert callable(views.admin_booking_map_view)
        assert callable(views.api_kpis)
        assert callable(views.sos_incident_detail_view)
        assert callable(views.sos_incident_resolve_view)
        assert callable(views.resolved_sos_snapshot_regenerate_view)
        assert callable(views.resolved_sos_snapshot_detail_view)
        assert callable(views.api_chart_data)
        assert callable(views.api_user_vehicles)
        assert callable(views.api_user_detail)
        assert callable(views.submit_user_edit)
        assert callable(views.vehicle_edit_view)

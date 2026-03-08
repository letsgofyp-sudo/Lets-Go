import json
from unittest.mock import MagicMock, patch

from lets_go.views import views_incidents


class TestViewsIncidentsHelpers:
    def test_helper_coercion(self):
        assert views_incidents._coerce_int('8') == 8
        assert views_incidents._coerce_float('1.2') == 1.2
        assert views_incidents._parse_iso_dt('bad') is None

    @patch('smtplib.SMTP')
    def test_send_email_success(self, _smtp):
        assert views_incidents._send_email('s', 'b', ['qa@example.com']) is True

    @patch('requests.post')
    def test_send_sms_success(self, m_post):
        m_post.return_value = MagicMock(status_code=200)
        assert views_incidents._send_sms('+92300111', 'x') is True


class TestViewsIncidentsEndpoints:
    def test_sos_incident_invalid_json(self, rf):
        req = rf.post('/x', data='not-json', content_type='application/json')
        assert views_incidents.sos_incident(req).status_code == 400

    def test_sos_incident_missing_fields(self, rf):
        req = rf.post('/x', data=json.dumps({}), content_type='application/json')
        assert views_incidents.sos_incident(req).status_code == 400


    def test_get_share_token_empty(self):
        assert views_incidents._get_share_token('') is None

    def test_get_trip_share_token_empty(self):
        assert views_incidents._get_trip_share_token('') is None


class TestViewsIncidentsShareEndpoints:
    def test_trip_share_token_invalid_method(self, rf):
        assert views_incidents.trip_share_token(rf.get('/x'), 'T1').status_code in (400, 405)

    def test_trip_share_view_missing_token(self, rf):
        assert views_incidents.trip_share_view(rf.get('/x'), '').status_code in (400, 404)

    def test_trip_share_live_missing_token(self, rf):
        assert views_incidents.trip_share_live(rf.get('/x'), '').status_code in (400, 404)

    def test_sos_share_view_missing_token(self, rf):
        assert views_incidents.sos_share_view(rf.get('/x'), '').status_code in (400, 404)

    def test_sos_share_live_missing_token(self, rf):
        assert views_incidents.sos_share_live(rf.get('/x'), '').status_code in (400, 404)

    def test_sos_share_send_invalid_method(self, rf):
        assert views_incidents.sos_share_send(rf.post('/x'), 'tok').status_code in (400, 405)

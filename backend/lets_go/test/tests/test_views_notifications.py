import json
from unittest.mock import MagicMock, patch

from lets_go.views import views_notifications


class DummyThread:
    def __init__(self, target=None, daemon=None):
        self.target = target

    def start(self):
        if self.target:
            self.target()


class TestViewsNotifications:
    def test_update_fcm_token_missing_user(self, rf):
        req = rf.post('/x', data=json.dumps({'fcm_token': 'abc'}), content_type='application/json')
        assert views_notifications.update_fcm_token(req).status_code == 400

    @patch('lets_go.views.views_notifications.UsersData.objects.filter')
    def test_update_fcm_token_user_not_found(self, m_filter, rf):
        m_filter.return_value.exclude.return_value.update.return_value = 0
        m_filter.return_value.update.return_value = 0
        req = rf.post('/x', data=json.dumps({'user_id': 99, 'fcm_token': 'abc'}), content_type='application/json')
        assert views_notifications.update_fcm_token(req).status_code == 404

    def test_normalize_payload(self):
        p = views_notifications._normalize_ride_notification_payload({'user_id': 5, 'title': 'T', 'body': 123, 'data': {'a': 1}})
        assert p['user_id'] == '5'
        assert p['body'] == '123'
        assert p['data']['a'] == '1'

    @patch('lets_go.views.views_notifications.threading.Thread', DummyThread)
    @patch('lets_go.views.views_notifications.requests.post')
    @patch('lets_go.views.views_notifications.SUPABASE_FN_API_KEY', 'k')
    @patch('lets_go.views.views_notifications.close_old_connections', lambda: None)
    def test_send_ride_notification_async(self, m_post):
        m_post.return_value = MagicMock(status_code=200, text='ok')
        views_notifications.send_ride_notification_async({'user_id': 1, 'title': 'a', 'body': 'b', 'data': {}})
        assert m_post.called

    @patch('lets_go.views.views_notifications.threading.Thread', DummyThread)
    @patch('lets_go.views.views_notifications.requests.post')
    @patch('lets_go.views.views_notifications.SUPABASE_FN_API_KEY', 'k')
    @patch('lets_go.views.views_notifications.close_old_connections', lambda: None)
    def test_register_fcm_token_with_supabase_async(self, m_post):
        m_post.return_value = MagicMock(status_code=200, text='ok')
        views_notifications.register_fcm_token_with_supabase_async('user:1', 'tok')
        assert m_post.called

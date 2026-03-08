import json
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from django.utils import timezone

from lets_go.views import views_user_notifications


class TestViewsUserNotifications:
    def test_list_notifications_requires_user_or_guest(self, rf):
        resp = views_user_notifications.list_notifications(rf.get('/x'))
        assert resp.status_code == 400

    @patch('lets_go.views.views_user_notifications.NotificationInbox.objects')
    def test_list_notifications_user_success(self, m_objects, rf):
        n1 = SimpleNamespace(
            id=1,
            notification_type='ride_request',
            title='t',
            body='b',
            data={'type': 'ride_request'},
            is_read=False,
            is_dismissed=False,
            created_at=timezone.now(),
        )

        qs = MagicMock()
        qs.__getitem__.return_value = [n1]

        m_filter_for_list = MagicMock()
        m_filter_for_list.order_by.return_value = qs

        m_filter_for_count = MagicMock()
        m_filter_for_count.count.return_value = 3

        # first call: list filter(...)
        # second call: unread count filter(...)
        m_objects.filter.side_effect = [m_filter_for_list, m_filter_for_count]

        req = rf.get('/x?user_id=12&limit=50&offset=0')
        resp = views_user_notifications.list_notifications(req)
        assert resp.status_code == 200

        payload = json.loads(resp.content)
        assert payload['success'] is True
        assert payload['unread_count'] == 3
        assert len(payload['notifications']) == 1
        assert payload['notifications'][0]['id'] == 1

    @patch('lets_go.views.views_user_notifications.NotificationInbox.objects')
    def test_list_notifications_guest_success(self, m_objects, rf):
        qs = MagicMock()
        qs.__getitem__.return_value = []

        m_filter_for_list = MagicMock()
        m_filter_for_list.order_by.return_value = qs

        m_filter_for_count = MagicMock()
        m_filter_for_count.count.return_value = 0

        m_objects.filter.side_effect = [m_filter_for_list, m_filter_for_count]

        req = rf.get('/x?guest_user_id=7')
        resp = views_user_notifications.list_notifications(req)
        assert resp.status_code == 200

        payload = json.loads(resp.content)
        assert payload['success'] is True
        assert payload['unread_count'] == 0

    @patch('lets_go.views.views_user_notifications.NotificationInbox.objects')
    def test_unread_count_user_and_guest(self, m_objects, rf):
        m_objects.filter.return_value.count.return_value = 5
        resp = views_user_notifications.notification_unread_count(rf.get('/x?user_id=1'))
        assert resp.status_code == 200
        assert json.loads(resp.content)['unread_count'] == 5

        m_objects.filter.return_value.count.return_value = 2
        resp2 = views_user_notifications.notification_unread_count(rf.get('/x?guest_user_id=9'))
        assert resp2.status_code == 200
        assert json.loads(resp2.content)['unread_count'] == 2

    @patch('lets_go.views.views_user_notifications.NotificationInbox.objects')
    def test_mark_all_read_user_and_guest(self, m_objects, rf):
        req = rf.post('/x', data=json.dumps({'user_id': 1}), content_type='application/json')
        resp = views_user_notifications.mark_all_notifications_read(req)
        assert resp.status_code == 200
        assert m_objects.filter.called

        m_objects.filter.reset_mock()
        req2 = rf.post('/x', data=json.dumps({'guest_user_id': 2}), content_type='application/json')
        resp2 = views_user_notifications.mark_all_notifications_read(req2)
        assert resp2.status_code == 200
        assert m_objects.filter.called

    @patch('lets_go.views.views_user_notifications.NotificationInbox.objects')
    def test_mark_read_and_dismiss_not_found(self, m_objects, rf):
        m_objects.get.side_effect = views_user_notifications.NotificationInbox.DoesNotExist()
        assert views_user_notifications.mark_notification_read(rf.post('/x'), 123).status_code == 404
        assert views_user_notifications.dismiss_notification(rf.post('/x'), 123).status_code == 404

    @patch('lets_go.views.views_user_notifications.NotificationInbox.objects')
    def test_mark_read_and_dismiss_success(self, m_objects, rf):
        n = SimpleNamespace(
            id=1,
            is_read=False,
            is_dismissed=False,
            save=MagicMock(),
        )
        m_objects.get.return_value = n
        assert views_user_notifications.mark_notification_read(rf.post('/x'), 1).status_code == 200
        assert n.save.called

        n2 = SimpleNamespace(
            id=2,
            is_read=True,
            is_dismissed=False,
            save=MagicMock(),
        )
        m_objects.get.return_value = n2
        assert views_user_notifications.dismiss_notification(rf.post('/x'), 2).status_code == 200
        assert n2.save.called

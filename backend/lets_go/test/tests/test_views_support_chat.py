import json
from types import SimpleNamespace
from unittest.mock import patch

from lets_go.views import views_support_chat


class TestViewsSupportChatHelpers:
    def test_to_int_and_parse_json_body(self, rf):
        assert views_support_chat._to_int('12') == 12
        req = rf.post('/x', data=json.dumps({'a': 1}), content_type='application/json')
        assert views_support_chat._parse_json_body(req)['a'] == 1

    def test_bot_reply_text(self):
        assert 'fare' in views_support_chat._bot_reply_text('what is fare').lower()

    def test_serialize_support_message(self):
        msg = SimpleNamespace(id=1, sender_type='USER', sender_user_id=2, message_text='hi',
                              thread_id=10,
                              thread=SimpleNamespace(thread_type='ADMIN', admin_last_seen_id=0),
                              created_at=SimpleNamespace(isoformat=lambda: '2026-01-01T10:00:00'))
        out = views_support_chat._serialize_support_message(msg)
        assert out['id'] == 1


class TestViewsSupportChatEndpoints:
    def test_support_guest_invalid_method(self, rf):
        assert views_support_chat.support_guest(rf.get('/x')).status_code == 405

    def test_view_bot_invalid_method(self, rf):
        assert views_support_chat.view_bot(rf.put('/x')).status_code == 405

    def test_view_adminchat_invalid_method(self, rf):
        assert views_support_chat.view_adminchat(rf.put('/x')).status_code == 405


    @patch('lets_go.views.views_support_chat.SupportThread.objects')
    def test_ensure_thread_smoke(self, m_threads):
        th = SimpleNamespace(id=1)
        m_threads.get_or_create.return_value = (th, True)
        out = views_support_chat._ensure_thread(None, SimpleNamespace(id=1), 'ADMIN')
        assert out.id == 1

    @patch('lets_go.views.views_support_chat.UsersData.objects.filter')
    def test_resolve_owner_from_query_user_not_found(self, m_filter, rf):
        m_filter.return_value.first.return_value = None
        req = rf.get('/x?user_id=5')
        _, _, err = views_support_chat._resolve_owner_from_query(req)
        assert err.status_code == 404

    @patch('lets_go.views.views_support_chat.GuestUser.objects.filter')
    def test_resolve_owner_from_body_guest_not_found(self, m_filter):
        m_filter.return_value.first.return_value = None
        _, _, err = views_support_chat._resolve_owner_from_body({'guest_user_id': 5})
        assert err.status_code == 404

    @patch('lets_go.views.views_support_chat.register_fcm_token_with_supabase_async')
    @patch('lets_go.views.views_support_chat.GuestUser.objects.filter')
    def test_sync_guest_fcm_updates(self, m_filter, m_register):
        guest = SimpleNamespace(id=1, fcm_token='old', username='g1')
        views_support_chat._sync_guest_fcm(guest, 'new-token')
        assert m_filter.called
        assert m_register.called

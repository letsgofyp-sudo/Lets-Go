from lets_go.views import views_chat


class TestViewsChat:
    def test_list_chat_messages_invalid_method(self, rf):
        assert views_chat.list_chat_messages(rf.post('/x'), 'T1').status_code == 405

    def test_list_chat_messages_updates_invalid_method(self, rf):
        assert views_chat.list_chat_messages_updates(rf.post('/x'), 'T1').status_code == 405

    def test_send_chat_message_invalid_method(self, rf):
        assert views_chat.send_chat_message(rf.get('/x'), 'T1').status_code == 405

    def test_mark_message_read_invalid_method(self, rf):
        assert views_chat.mark_message_read(rf.get('/x'), 1).status_code == 405

    def test_send_broadcast_message_invalid_method(self, rf):
        assert views_chat.send_broadcast_message(rf.get('/x'), 'T1').status_code == 405

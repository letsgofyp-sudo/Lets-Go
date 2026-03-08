from types import SimpleNamespace

from lets_go.views import views_blocking


class TestViewsBlocking:
    def test_user_brief(self):
        out = views_blocking._user_brief(SimpleNamespace(id=1, name='A', username='a', profile_photo_url='u'))
        assert out['id'] == 1

    def test_list_blocked_users_invalid_method(self, rf):
        assert views_blocking.list_blocked_users(rf.post('/x'), 1).status_code == 405

    def test_search_users_to_block_invalid_method(self, rf):
        assert views_blocking.search_users_to_block(rf.post('/x'), 1).status_code == 405

    def test_block_user_invalid_method(self, rf):
        assert views_blocking.block_user(rf.get('/x'), 1).status_code == 405

    def test_unblock_user_invalid_method(self, rf):
        assert views_blocking.unblock_user(rf.get('/x'), 1, 2).status_code == 405

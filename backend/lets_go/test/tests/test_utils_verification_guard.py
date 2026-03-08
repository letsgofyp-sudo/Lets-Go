from types import SimpleNamespace
from unittest.mock import patch

from lets_go.utils import verification_guard


class TestVerificationGuard:
    @patch('lets_go.utils.verification_guard.UsersData.objects.only')
    def test_verification_block_user_not_found(self, m_only):
        m_only.return_value.get.side_effect = verification_guard.UsersData.DoesNotExist
        assert verification_guard.verification_block_response(1).status_code == 404

    @patch('lets_go.utils.verification_guard.UsersData.objects.only')
    def test_verification_block_banned(self, m_only):
        m_only.return_value.get.return_value = SimpleNamespace(status='BANNED')
        assert verification_guard.verification_block_response(1).status_code == 403

    @patch('lets_go.utils.verification_guard.UsersData.objects.only')
    def test_verification_block_none_for_active(self, m_only):
        m_only.return_value.get.return_value = SimpleNamespace(status='ACTIVE')
        assert verification_guard.verification_block_response(1) is None

    def test_has_any_requested_keys(self):
        crs = [SimpleNamespace(requested_changes={'email': 'x@y.com'})]
        assert verification_guard._has_any_requested_keys(crs, ['email']) is True
        assert verification_guard._has_any_requested_keys(crs, ['phone']) is False

    @patch('lets_go.utils.verification_guard.verification_block_response', return_value=None)
    @patch('lets_go.utils.verification_guard._pending_user_profile_change_requests')
    def test_ride_booking_block_response_pending_gender(self, m_pending, _m_block):
        m_pending.return_value = [SimpleNamespace(requested_changes={'gender': 'F'})]
        assert verification_guard.ride_booking_block_response(1).status_code == 403

    @patch('lets_go.utils.verification_guard.verification_block_response', return_value=None)
    @patch('lets_go.utils.verification_guard._pending_user_profile_change_requests')
    def test_ride_create_block_response_pending_license(self, m_pending, _m_block):
        m_pending.return_value = [SimpleNamespace(requested_changes={'driving_license_no': '123'})]
        assert verification_guard.ride_create_block_response(1).status_code == 403

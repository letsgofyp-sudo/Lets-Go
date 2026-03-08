from unittest.mock import MagicMock, patch

from lets_go.utils import phone_otp_send


class TestPhoneOtp:
    @patch('requests.post')
    def test_send_phone_otp_success(self, m_post):
        resp = MagicMock()
        resp.raise_for_status.return_value = None
        resp.json.return_value = {'ok': True}
        m_post.return_value = resp
        assert phone_otp_send.send_phone_otp('+923001112233', '8888') is True

    @patch('requests.post', side_effect=Exception('down'))
    def test_send_phone_otp_failure(self, _m_post):
        assert phone_otp_send.send_phone_otp('+923001112233', '8888') is False

    @patch('requests.post', side_effect=Exception('down'))
    def test_send_phone_otp_reset_failure(self, _m_post):
        assert phone_otp_send.send_phone_otp_for_reset('+923001112233', '8888') is False

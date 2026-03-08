from unittest.mock import patch

from lets_go.utils import email_otp


class TestEmailOtp:
    @patch('smtplib.SMTP')
    def test_send_email_otp_success(self, _smtp):
        assert email_otp.send_email_otp('qa@example.com', '1234') is True

    @patch('smtplib.SMTP', side_effect=Exception('smtp down'))
    def test_send_email_otp_failure(self, _smtp):
        assert email_otp.send_email_otp('qa@example.com', '1234') is False

    @patch('smtplib.SMTP')
    def test_send_email_otp_for_reset_success(self, _smtp):
        assert email_otp.send_email_otp_for_reset('qa@example.com', '1234') is True

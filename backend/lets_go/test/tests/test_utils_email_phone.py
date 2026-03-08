from lets_go.utils import email_phone


class TestEmailPhoneConstants:
    def test_constants_are_strings(self):
        assert isinstance(email_phone.BASE_URL, str)
        assert isinstance(email_phone.API_KEY, str)
        assert isinstance(email_phone.DEVICE_ID, str)
        assert isinstance(email_phone.email, str)
        assert isinstance(email_phone.email_password, str)

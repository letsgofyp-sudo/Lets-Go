from datetime import date
from unittest.mock import MagicMock, patch

from django.core.cache import cache
from django.test import TestCase
from django.urls import reverse

from lets_go.models import UsersData, UsernameRegistry
from lets_go.views import views_authentication


class AuthenticationHelpersTests(TestCase):
    def test_parse_json_body_empty_returns_dict(self):
        class R:
            body = b""

        self.assertEqual(views_authentication._parse_json_body(R()), {})

    def test_parse_json_body_invalid_returns_dict(self):
        class R:
            body = b"not-json"

        self.assertEqual(views_authentication._parse_json_body(R()), {})

    def test_parse_json_body_valid_dict(self):
        class R:
            body = b"{\"a\": 1}"

        self.assertEqual(views_authentication._parse_json_body(R()), {"a": 1})

    def test_parse_json_body_valid_non_dict_returns_empty(self):
        class R:
            body = b"[1, 2]"

        self.assertEqual(views_authentication._parse_json_body(R()), {})

    def test_normalize_gender(self):
        self.assertEqual(views_authentication._normalize_gender("Male"), "male")
        self.assertEqual(views_authentication._normalize_gender("m"), "male")
        self.assertEqual(views_authentication._normalize_gender("Female"), "female")
        self.assertEqual(views_authentication._normalize_gender("f"), "female")
        self.assertIsNone(views_authentication._normalize_gender(""))
        self.assertIsNone(views_authentication._normalize_gender(None))

    def test_get_profile_contact_change_cache_key(self):
        k = views_authentication._get_profile_contact_change_cache_key(5, "email", "a@b.com")
        self.assertEqual(k, "profile_contact_change_5_email_a@b.com")

    def test_parse_iso_date(self):
        self.assertEqual(views_authentication._parse_iso_date("2026-02-27"), date(2026, 2, 27))
        self.assertIsNone(views_authentication._parse_iso_date(""))
        self.assertIsNone(views_authentication._parse_iso_date(None))
        self.assertIsNone(views_authentication._parse_iso_date("27-02-2026"))

    def test_generate_otp_length_digits(self):
        otp = views_authentication.generate_otp(8)
        self.assertEqual(len(otp), 8)
        self.assertTrue(otp.isdigit())

    def test_get_cache_key(self):
        self.assertEqual(views_authentication.get_cache_key("x@y.com"), "pending_signup_x@y.com")

    def test_get_reset_cache_key(self):
        self.assertEqual(
            views_authentication.get_reset_cache_key("email", "x@y.com"),
            "reset_pwd_email_x@y.com",
        )


class AuthenticationEndpointsTests(TestCase):
    def setUp(self):
        cache.clear()

    def _create_user(self, **overrides):
        data = {
            "name": "Test User",
            "username": "testuser",
            "email": "test@example.com",
            "password": "Password@123",
            "address": "Test Address",
            "phone_no": "+923001234567",
            "cnic_no": "36603-0269853-9",
            "gender": "male",
            "status": "VERIFIED",
        }
        data.update(overrides)
        user = UsersData(**data)
        user.full_clean()
        user.password = views_authentication.make_password(data["password"])
        user.save()
        return user

    def test_login_success(self):
        self._create_user()
        resp = self.client.post(
            reverse("login"),
            data={"email": "test@example.com", "password": "Password@123"},
        )
        self.assertEqual(resp.status_code, 200)
        payload = resp.json()
        self.assertTrue(payload.get("success"))
        self.assertIn("UsersData", payload)
        self.assertEqual(payload["UsersData"][0]["email"], "test@example.com")

    def test_login_invalid_password(self):
        self._create_user()
        resp = self.client.post(
            reverse("login"),
            data={"email": "test@example.com", "password": "WrongPass@123"},
        )
        self.assertEqual(resp.status_code, 404)
        self.assertFalse(resp.json().get("success"))

    def test_check_username_available_true(self):
        resp = self.client.post(reverse("check_username"), data={"username": "newuser"})
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json(), {"available": True})
        self.assertTrue(UsernameRegistry.objects.filter(username__iexact="newuser").exists())

    def test_check_username_already_reserved_false(self):
        UsernameRegistry.objects.create(username="taken")
        resp = self.client.post(reverse("check_username"), data={"username": "TAKEN"})
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json().get("available"), False)

    def test_send_otp_requires_email_or_phone(self):
        resp = self.client.post(reverse("send_otp"), data={})
        self.assertEqual(resp.status_code, 400)
        self.assertFalse(resp.json().get("success"))

    def test_send_otp_registration_sets_cache(self):
        resp = self.client.post(
            reverse("send_otp"),
            data={"email": "otp@example.com", "otp_for": "registration", "resend": "email"},
        )
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.json().get("success"))
        ck = views_authentication.get_cache_key("otp@example.com")
        cached = cache.get(ck)
        self.assertIsNotNone(cached)
        self.assertEqual(cached.get("email"), "otp@example.com")
        self.assertIsNotNone(cached.get("email_otp"))

    def test_verify_otp_success_email(self):
        ck = views_authentication.get_cache_key("otp@example.com")
        cache.set(
            ck,
            {
                "email": "otp@example.com",
                "phone_no": "",
                "otp_for": "registration",
                "email_otp": "123456",
                "email_expiry": 9999999999,
                "email_verified": False,
            },
            timeout=300,
        )
        resp = self.client.post(
            reverse("verify_otp"),
            data={"email": "otp@example.com", "otp": "123456", "which": "email"},
        )
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.json().get("success"))
        cached = cache.get(ck)
        self.assertTrue(cached.get("email_verified"))

    def test_verify_password_reset_otp_success(self):
        ck = views_authentication.get_reset_cache_key("email", "reset@example.com")
        cache.set(
            ck,
            {
                "email_otp": "654321",
                "email_expiry": 1111111111,
            },
            timeout=300,
        )
        resp = self.client.post(
            reverse("verify_password_reset_otp"),
            data={"method": "email", "value": "reset@example.com", "otp": "654321"},
        )
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.json().get("success"))
        cached = cache.get(ck)
        self.assertTrue(cached.get("verified"))

    def test_reset_password_success(self):
        self._create_user(email="reset@example.com", username="resetuser")
        ck = views_authentication.get_reset_cache_key("email", "reset@example.com")
        cache.set(ck, {"verified": True}, timeout=300)
        resp = self.client.post(
            reverse("reset_password"),
            data={"method": "email", "value": "reset@example.com", "new_password": "NewPass@123"},
        )
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.json().get("success"))

    def test_reset_rejected_user_deletes_user(self):
        user = self._create_user(status="REJECTED", username="rejuser", email="rej@example.com")
        UsernameRegistry.objects.create(username="rejuser")
        resp = self.client.post(reverse("reset_rejected_user"), data={"email": "rej@example.com"})
        self.assertEqual(resp.status_code, 200, msg=getattr(resp, "content", b"").decode("utf-8", errors="ignore"))
        self.assertTrue(resp.json().get("success"))
        self.assertFalse(UsersData.objects.filter(id=user.id).exists())

    def test_reset_rejected_user_non_rejected_forbidden(self):
        self._create_user(status="VERIFIED", username="okuser", email="ok@example.com")
        resp = self.client.post(reverse("reset_rejected_user"), data={"email": "ok@example.com"})
        self.assertEqual(resp.status_code, 403)

    def test_upload_to_supabase_missing_settings_raises(self):
        file_obj = MagicMock()
        file_obj.read.return_value = b"abc"

        with patch.object(views_authentication.settings, "SUPABASE_URL", ""):
            with patch.object(views_authentication.settings, "SUPABASE_SERVICE_KEY", ""):
                with self.assertRaises(RuntimeError):
                    views_authentication.upload_to_supabase("bucket", file_obj, "dest")

    def test_upload_to_supabase_success(self):
        file_obj = MagicMock()
        file_obj.read.return_value = b"abc"
        file_obj.content_type = "image/jpeg"

        mocked_resp = MagicMock()
        mocked_resp.status_code = 200
        mocked_resp.text = "ok"

        with patch.object(views_authentication.settings, "SUPABASE_URL", "https://example.supabase.co"):
            with patch.object(views_authentication.settings, "SUPABASE_SERVICE_KEY", "KEY"):
                with patch("lets_go.views.views_authentication.requests.post", return_value=mocked_resp) as post:
                    url = views_authentication.upload_to_supabase("bucket", file_obj, "a/b.jpg")

        self.assertEqual(url, "https://example.supabase.co/storage/v1/object/public/bucket/a/b.jpg")
        post.assert_called_once()

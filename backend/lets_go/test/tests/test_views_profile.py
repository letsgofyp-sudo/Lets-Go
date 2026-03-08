import json
from types import SimpleNamespace
from unittest.mock import patch

from lets_go.views import views_profile


class TestViewsProfile:
    def test_user_change_requests_invalid_method(self, rf):
        assert views_profile.user_change_requests(rf.post('/x'), 1).status_code == 400

    def test_send_profile_contact_change_otp_invalid_method(self, rf):
        assert views_profile.send_profile_contact_change_otp(rf.get('/x'), 1).status_code == 400

    @patch('lets_go.views.views_profile.UsersData.objects.only')
    @patch('lets_go.views.views_profile.generate_otp', return_value='1111')
    @patch('lets_go.views.views_profile.cache')
    @patch('lets_go.views.views_profile.send_email_otp', return_value=True)
    def test_send_profile_contact_change_otp_success_email(self, _m_send, m_cache, _m_otp, m_only, rf):
        m_only.return_value.get.return_value = SimpleNamespace(id=1, email='u@x.com', phone_no='+92300')
        m_cache.get.return_value = None
        req = rf.post('/x', data=json.dumps({'which': 'email', 'value': 'qa@example.com'}), content_type='application/json')
        assert views_profile.send_profile_contact_change_otp(req, 1).status_code == 200

    @patch('lets_go.views.views_profile.UsersData.objects.only')
    def test_send_profile_contact_change_otp_not_found(self, m_only, rf):
        m_only.return_value.get.side_effect = views_profile.UsersData.DoesNotExist
        req = rf.post('/x', data=json.dumps({'which': 'email', 'value': 'qa@example.com'}), content_type='application/json')
        assert views_profile.send_profile_contact_change_otp(req, 99).status_code == 404

    def test_upload_user_driving_license_invalid_method(self, rf):
        assert views_profile.upload_user_driving_license(rf.get('/x'), 1).status_code == 400

    def test_upload_user_photos_invalid_method(self, rf):
        assert views_profile.upload_user_photos(rf.get('/x'), 1).status_code == 400

    def test_upload_user_cnic_invalid_method(self, rf):
        assert views_profile.upload_user_cnic(rf.get('/x'), 1).status_code == 400

    def test_upload_vehicle_images_invalid_method(self, rf):
        assert views_profile.upload_vehicle_images(rf.get('/x'), 1).status_code == 400

    def test_verify_profile_contact_change_otp_invalid_method(self, rf):
        assert views_profile.verify_profile_contact_change_otp(rf.get('/x'), 1).status_code == 400

    def test_upload_user_accountqr_invalid_method(self, rf):
        assert views_profile.upload_user_accountqr(rf.get('/x'), 1).status_code == 400

    def test_user_image_invalid_method(self, rf):
        with patch('lets_go.views.views_profile.UsersData.objects.only') as m_only:
            m_only.return_value.values_list.return_value.get.return_value = ''
            try:
                views_profile.user_image(rf.post('/x'), 1, 'profile_photo')
                assert False, 'expected Http404'
            except views_profile.Http404:
                assert True

    def test_vehicle_image_invalid_method(self, rf):
        res = views_profile.vehicle_image(rf.post('/x'), 1, 'photo_front')
        assert res.status_code in (400, 405)


    def test_user_profile_invalid_method(self, rf):
        assert views_profile.user_profile(rf.delete('/x'), 1).status_code in (400, 405)

    def test_user_emergency_contact_invalid_method(self, rf):
        with patch('lets_go.views.views_profile.UsersData.objects.get') as m_get:
            m_get.return_value = SimpleNamespace(id=1)
            assert views_profile.user_emergency_contact(rf.delete('/x'), 1).status_code == 400

    def test_user_vehicles_invalid_method(self, rf):
        with patch('lets_go.views.views_profile.UsersData.objects.only') as m_only:
            m_only.return_value.get.return_value = SimpleNamespace(id=1)
            assert views_profile.user_vehicles(rf.delete('/x'), 1).status_code == 400

    def test_vehicle_detail_invalid_method(self, rf):
        assert views_profile.vehicle_detail(rf.post('/x'), 1).status_code in (400, 405)

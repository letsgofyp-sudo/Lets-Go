// lib/controllers/signup_controller.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../constants.dart';

class SignupController {static Future<Map<String, dynamic>> signup(
    Map<String, String> fields,
    Map<String, File?> images,
) async {
    final urlEndpoint = Uri.parse('$url/lets_go/send_otp/');
    final request = http.MultipartRequest('POST', urlEndpoint);

    // Only send email and phone for OTP
    if (fields.containsKey('email')) request.fields['email'] = fields['email']!;
    if (fields.containsKey('phone_no')) request.fields['phone_no'] = fields['phone_no']!;
    request.fields['otp_for'] = 'registration';

    try {
      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final data = jsonDecode(responseData);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'message': data['message'],
          'email_expiry': data['email_expiry'],
          'phone_expiry': data['phone_expiry'],
        };
      } else {
        return {'success': false, 'message': data['error'] ?? 'Signup failed.'};
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Signup failed. Try again later. due to $e',
      };
    }
}}

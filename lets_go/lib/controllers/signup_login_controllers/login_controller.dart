// lib/controllers/login_controller.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../constants.dart';

class LoginController {
  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final urlEndpoint = Uri.parse('$url/lets_go/login/');
    debugPrint('🔍 LOGIN DEBUG: Attempting login to: $urlEndpoint');
    debugPrint('🔍 LOGIN DEBUG: Email: $email');
    
    try {
      final response = await http.post(
        urlEndpoint,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'email': email, 'password': password},
      );
      
      debugPrint('🔍 LOGIN DEBUG: Response status: ${response.statusCode}');
      debugPrint('🔍 LOGIN DEBUG: Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('🔍 LOGIN DEBUG: Login successful!');
        return {
          'success': true,
          'message': data['message'],
          'UsersData': data['UsersData'],
        };
      } else {
        debugPrint('🔍 LOGIN DEBUG: Login failed with status ${response.statusCode}');
        try {
          final error = jsonDecode(response.body);
          return {'success': false, 'message': error['error']};
        } catch (e) {
          return {'success': false, 'message': 'Server error: ${response.statusCode}'};
        }
      }
    } catch (e) {
      debugPrint('🔍 LOGIN DEBUG: Exception occurred: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
}

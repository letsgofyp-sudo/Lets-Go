// lib/screens/login_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';

import '../../constants.dart';
import '../../controllers/signup_login_controllers/login_controller.dart';
import '../../controllers/signup_login_controllers/navigation_controller.dart';
import '../../services/notification_service.dart';
import '../../services/api_service.dart';
import '../../utils/auth_session.dart';
import '../support_chat_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  final AppLinks _appLinks = AppLinks();

  StreamSubscription? _tripShareLinkSub;
  bool _didCheckInitialTripShareLink = false;

  @override
  void initState() {
    super.initState();
    _listenForTripShareLinks();
    _tryAutoLogin();
  }

  @override
  void dispose() {
    _tripShareLinkSub?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _extractTripShareToken(Uri uri) {
    try {
      final seg = uri.pathSegments;
      final i = seg.indexOf('share');
      if (i >= 0 && i + 1 < seg.length && seg.contains('trips')) {
        final token = seg[i + 1].trim();
        if (token.isNotEmpty) return token;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _storePendingTripShareToken(String token) async {
    try {
      final t = token.trim();
      if (t.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_trip_share_token', t);
    } catch (_) {
      // ignore
    }
  }

  void _listenForTripShareLinks() {
    if (_tripShareLinkSub != null) return;

    () async {
      if (_didCheckInitialTripShareLink) return;
      _didCheckInitialTripShareLink = true;
      try {
        final initial = await _appLinks.getInitialLink();
        if (!mounted) return;
        if (initial != null) {
          final token = _extractTripShareToken(initial);
          if (token != null) {
            await _storePendingTripShareToken(token);
          }
        }
      } catch (_) {
        // ignore
      }
    }();

    _tripShareLinkSub = _appLinks.uriLinkStream.listen(
      (uri) async {
        final token = _extractTripShareToken(uri);
        if (token == null) return;
        await _storePendingTripShareToken(token);
      },
      onError: (_) {},
    );
  }

  Future<void> _openGuestSupportChat() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingGuestId = int.tryParse((prefs.getString('guest_user_id') ?? '').toString()) ?? 0;
      final rawToken = prefs.getString('fcm_token');
      final fcmToken = rawToken == null || rawToken.isEmpty ? null : rawToken;

      final resp = await ApiService.createGuestSupportUser(
        existingGuestUserId: existingGuestId > 0 ? existingGuestId : null,
        fcmToken: fcmToken,
      );

      if (resp['success'] == true) {
        final gid = int.tryParse((resp['guest_user_id'] ?? '').toString()) ?? 0;
        if (gid > 0) {
          await prefs.setString('guest_user_id', gid.toString());
        }

        // Ensure guest record is updated with the current device token (so guest can receive notifications).
        // ignore: discarded_futures
        NotificationService.trySyncGuestFcmTokenNow();

        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SupportChatScreen(
              userData: <String, dynamic>{
                'guest_user_id': gid,
              },
            ),
          ),
        );
      } else {
        final msg = (resp['error'] ?? resp['message'] ?? 'Failed to open support chat.').toString();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open support chat: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startOrResumeSignup() async {
    final prefs = await SharedPreferences.getInstance();

    // If a signup is currently locked (user is in OTP flow), always resume OTP
    final locked = prefs.getBool('signup_locked') == true;
    if (locked) {
      if (!mounted) return;
      Navigator.pushNamed(context, '/otp_verification');
      return;
    }

    final step = prefs.getString('signup_step');
    String route;
    switch (step) {
      case 'emergency':
        route = '/signup_emergency';
        break;
      case 'cnic':
        route = '/signup_cnic';
        break;
      case 'vehicle':
        route = '/signup_vehicle';
        break;
      case 'otp':
        route = '/otp_verification';
        break;
      case 'personal':
      default:
        // Default to starting from personal info if no step recorded
        route = '/signup_personal';
        break;
    }

    if (!mounted) return;
    Navigator.pushNamed(context, route);
  }

  Future<void> _tryAutoLogin() async {
    try {
      final sessionUser = await AuthSession.load();
      if (sessionUser == null) {
        debugPrint('🔐 Auto-login: no stored session');
        return;
      }
      if (!mounted) return;
      debugPrint('🔐 Auto-login: session found for user ${sessionUser['id']}');

      // Refresh user status from backend so routing matches manual login.
      // This prevents stale local session data from sending VERIFIED users to Pending screen.
      Map<String, dynamic> userData = Map<String, dynamic>.from(sessionUser);
      final idRaw = sessionUser['id'];
      final id = idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '');
      if (id != null) {
        try {
          final fresh = await ApiService.getUserProfile(id);
          userData = {
            ...userData,
            ...fresh,
          };
          await AuthSession.save(userData);
        } catch (e) {
          debugPrint('⚠️ Auto-login: failed to refresh profile: $e');
        }
      }

      // Restore logged_in_user_id for backend-managed FCM registration
      final userId = userData['id']?.toString();
      if (userId != null && userId.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('logged_in_user_id', userId);
      }
      // Navigate using the same controller logic
      if (!mounted) return;
      NavigationController.navigateAfterLogin(context, userData);
    } catch (e) {
      debugPrint('❌ Auto-login error: $e');
    }
  }

  void _login() async {
    if (_formKey.currentState!.validate()) {
      debugPrint('🔍 UI DEBUG: Starting login process...');
      setState(() => _isLoading = true);
      
      final result = await LoginController.login(
        _emailController.text,
        _passwordController.text,
      );
      
      debugPrint('🔍 UI DEBUG: Login result received: $result');
      setState(() => _isLoading = false);
      
      if (!mounted) return;
      
      if (result['success']) {
        debugPrint('🔍 UI DEBUG: Login successful, processing user data...');
        final userData = result['UsersData'] is List && result['UsersData'].isNotEmpty
            ? result['UsersData'][0] as Map<String, dynamic>
            : result['UsersData'] as Map<String, dynamic>;
        
        debugPrint('🔍 UI DEBUG: User data: $userData');
        // Save session for auto-login
        try {
          await AuthSession.save(userData);
          debugPrint('🔐 Session saved for auto-login');
        } catch (e) {
          debugPrint('⚠️ Failed to save session: $e');
        }
        // Cache logged-in user id for backend-managed FCM registration
        try {
          final userId = userData['id']?.toString();
          if (userId != null && userId.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('logged_in_user_id', userId);
          }
        } catch (e) {
          debugPrint('⚠️ Failed to cache logged_in_user_id post-login: $e');
        }
        // After explicit login, always attempt to register FCM token with backend
        try {
          final userId = userData['id']?.toString();
          if (userId != null && userId.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            final rawToken = prefs.getString('fcm_token');
            // DEBUG: log what we read from SharedPreferences
            // ignore: avoid_print
            debugPrint('[LoginScreen] raw fcm_token from SharedPreferences: $rawToken');
            final fcmToken = rawToken == null || rawToken.isEmpty ? null : rawToken;

            final uri = Uri.parse('$url/lets_go/update_fcm_token/');
            final payload = jsonEncode({
              'user_id': int.tryParse(userId) ?? userId,
              'fcm_token': fcmToken,
            });
            final resp = await http.post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: payload,
            );

            if (mounted) {
              final bool isPlaceholder = fcmToken == null;
              final String tokenPreview = isPlaceholder
                  ? 'NO_FCM_TOKEN'
                  : (fcmToken.length > 12 ? '${fcmToken.substring(0, 12)}...' : fcmToken);
              final String statusLabel = resp.statusCode == 200 ? 'ok' : 'error';
              // Include rawToken debug info so we can see if anything is stored locally
              final String rawInfo = rawToken == null
                  ? 'raw=null'
                  : 'raw_len=${rawToken.length}';
              final String message = isPlaceholder
                  ? 'FCM sync: $statusLabel (no real token on device yet, $rawInfo)'
                  : 'FCM sync: $statusLabel (token: $tokenPreview, $rawInfo)';

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(message),
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('FCM sync failed: $e'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
        debugPrint('🔍 UI DEBUG: Navigating after login...');
        
        // Use NavigationController to determine where to navigate based on user status
        if (!mounted) return;
        NavigationController.navigateAfterLogin(context, userData);
      } else {
        debugPrint('🔍 UI DEBUG: Login failed: ${result['message']}');
        setState(() => _errorMessage = result['message']);
      }
    } else {
      debugPrint('🔍 UI DEBUG: Form validation failed');
    }
  }

  Future<void> _launchUri(Uri uri, {String? failMessage}) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failMessage ?? 'Unable to open')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failMessage ?? 'Unable to open')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const supportPhone = '+923228730277';
    const supportEmail = 'letsgofyp@gmail.com';

    String digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');
    final phoneDial = digitsOnly(supportPhone);

    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: FloatingActionButton(
        heroTag: 'support_fab_login',
        onPressed: _openGuestSupportChat,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        child: const Icon(Icons.support_agent),
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F766E),
                  Color(0xFF14B8A6),
                  Color(0xFF99F6E4),
                ],
              ),
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            child: Column(
              children: [
                const SizedBox(height: 6),
                Center(
                  child: Column(
                    children: [
                      Image.asset(
                        'assets/images/app_logo.png',
                        width: 160,
                        height: 160,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Lets Go',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sign in to continue',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Welcome back',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Enter your credentials to access your account.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _emailController,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.left,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                            labelText: 'User name or email',
                            prefixIcon: const Icon(Icons.person_outline),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (value) => value!.isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordController,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          obscureText: _obscurePassword,
                          validator: (value) {
                            if (value == null || value.isEmpty) return 'Required';
                            if (value.length < 8) return 'Min 8 characters';
                            if (!RegExp(r'[A-Z]').hasMatch(value)) return 'Must have uppercase';
                            if (!RegExp(r'[a-z]').hasMatch(value)) return 'Must have lowercase';
                            if (!RegExp(r'\d').hasMatch(value)) return 'Must have digit';
                            if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(value)) return 'Must have special char';
                            return null;
                          },
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              Navigator.pushNamed(context, '/forgot_password');
                            },
                            child: const Text('Forgot Password?'),
                          ),
                        ),
                        if (_errorMessage != null)
                          ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.shade100),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline, color: Colors.red.shade600, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: TextStyle(color: Colors.red.shade700),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F766E),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Sign in', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: _startOrResumeSignup,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF0F766E),
                              side: const BorderSide(color: Color(0xFF0F766E)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('New user? Create an account'),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.support_agent, size: 18, color: Color(0xFF0F766E)),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Customer Support',
                                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      tooltip: 'Call',
                                      onPressed: () => _launchUri(
                                        Uri(scheme: 'tel', path: phoneDial),
                                        failMessage: 'Could not open dialer',
                                      ),
                                      icon: const Icon(Icons.call_outlined),
                                    ),
                                    IconButton(
                                      tooltip: 'Email',
                                      onPressed: () => _launchUri(
                                        Uri(
                                          scheme: 'mailto',
                                          path: supportEmail,
                                          query: 'subject=Lets%20Go%20Support',
                                        ),
                                        failMessage: 'Could not open email app',
                                      ),
                                      icon: const Icon(Icons.email_outlined),
                                    ),
                                    IconButton(
                                      tooltip: 'WhatsApp',
                                      onPressed: () => _launchUri(
                                        Uri.parse('https://wa.me/${phoneDial.replaceAll('+', '')}'),
                                        failMessage: 'Could not open WhatsApp',
                                      ),
                                      icon: const Icon(Icons.chat_outlined),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ],
      ),
    );
  }
}

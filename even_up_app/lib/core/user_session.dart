import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:even_up_app/core/config.dart';

/// Singleton that holds the currently logged-in user's session.
/// All API callers should use [UserSession.instance.authHeaders] for requests.
class UserSession extends ChangeNotifier {
  static final UserSession instance = UserSession._();
  UserSession._();

  String? _token;
  String? _userId;
  String? _name;
  String? _email;
  int? _pendingRequestCount = 0;
  Timer? _pollingTimer;

  int get pendingRequestCount => _pendingRequestCount ?? 0;

  bool get isLoggedIn => _token != null;
  String get userId => _userId ?? 'local-user-123';
  String get name => _name ?? 'You';
  String get email => _email ?? '';

  Map<String, String> get authHeaders => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  void login({
    required String token,
    required String userId,
    required String name,
    required String email,
  }) {
    _token = token;
    _userId = userId;
    _name = name;
    _email = email;
    _startPolling();
    refreshPendingRequestCount();
    notifyListeners();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      refreshPendingRequestCount();
    });
  }

  Future<void> refreshPendingRequestCount() async {
    if (!isLoggedIn) return;
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/friend-requests'),
        headers: authHeaders,
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setPendingRequestCount(data.length);
      }
    } catch (e) {
      debugPrint('Error polling requests: $e');
    }
  }

  void setPendingRequestCount(int count) {
    _pendingRequestCount = count;
    notifyListeners();
  }

  void logout() {
    _token = null;
    _userId = null;
    _name = null;
    _email = null;
    _pendingRequestCount = 0;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    notifyListeners();
  }
}

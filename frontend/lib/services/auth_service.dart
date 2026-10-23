import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'session_storage.dart';

class AuthService extends ChangeNotifier {
  static final AuthService instance = AuthService._();
  AuthService._();

  static const String _baseUrl = 'https://auto.zksms.online/api';
  static const String _tokenKey = 'autoke_auth_token';
  static const String _userKey = 'autoke_auth_user';

  String? _token;
  Map<String, dynamic>? _currentUser;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  bool get isAuthenticated => _token != null && _currentUser != null;

  String? get token => _token;
  Map<String, dynamic>? get currentUser => _currentUser;

  String get role => (_currentUser?['role'] ?? 'MECHANIC').toString().toUpperCase();
  String get userName => (_currentUser?['name'] ?? 'User').toString();
  String get userEmail => (_currentUser?['email'] ?? '').toString();
  String get userId => (_currentUser?['id'] ?? '').toString();

  bool get isOwner => role == 'OWNER' || role == 'SUPER_ADMIN' || role == 'ADMIN';
  bool get isManager => role == 'MANAGER' || isOwner;
  bool get isStorekeeper => role == 'STOREKEEPER' || role == 'INVENTORY_MANAGER';
  bool get isMechanic => role == 'MECHANIC';
  bool get isAdvisor => role == 'ADVISOR';

  Map<String, String> get authHeaders => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
        'x-user-role': role,
        'x-user-name': userName,
      };

  Future<void> init() async {
    try {
      _token = await SessionStorage.getString(_tokenKey);
      final userRaw = await SessionStorage.getString(_userKey);
      if (userRaw != null && userRaw.isNotEmpty) {
        _currentUser = json.decode(userRaw);
      }
      if (_token != null) {
        _verifySession();
      }
    } catch (e) {
      debugPrint('AuthService init error: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> _verifySession() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/auth/me'),
        headers: authHeaders,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['user'] != null) {
          _currentUser = Map<String, dynamic>.from(data['user']);
          try {
            await SessionStorage.setString(_userKey, json.encode(_currentUser));
          } catch (_) {}
          notifyListeners();
        }
      } else if (res.statusCode == 401 || res.statusCode == 403) {
        await logout();
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>> login(String identifier, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'identifier': identifier.trim(),
          'password': password,
        }),
      );

      final data = json.decode(res.body);
      if (res.statusCode == 200 && data['token'] != null) {
        _token = data['token'];
        _currentUser = Map<String, dynamic>.from(data['user']);

        // Persist session safely (never allow a storage error to abort login)
        try {
          await SessionStorage.setString(_tokenKey, _token!);
          await SessionStorage.setString(_userKey, json.encode(_currentUser));
        } catch (storageErr) {
          debugPrint('Session storage write error (ignoring): $storageErr');
        }

        notifyListeners();
        return {'success': true};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Login failed. Please check your credentials.'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: Unable to connect to workshop server ($e)'};
    }
  }

  Future<void> logout() async {
    try {
      if (_token != null) {
        try {
          await http.post(
            Uri.parse('$_baseUrl/auth/logout'),
            headers: authHeaders,
          );
        } catch (_) {}
      }
      try {
        await SessionStorage.remove(_tokenKey);
        await SessionStorage.remove(_userKey);
      } catch (_) {}
    } catch (e) {
      debugPrint('Logout error: $e');
    } finally {
      _token = null;
      _currentUser = null;
      notifyListeners();
    }
  }
}

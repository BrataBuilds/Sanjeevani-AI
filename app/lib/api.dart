import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Thin HTTP client for the Sanjeevani backend.
///
/// The backend is token-based (no cookies): every call carries the JWT in an
/// Authorization header. Responses stay as maps and lists — there is no model
/// codegen here on purpose, the payloads move faster than generated classes would.
class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

String _defaultBaseUrl() {
  // An Android emulator reaches the host machine at 10.0.2.2, not localhost.
  if (kIsWeb) return 'http://localhost:4000';
  if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:4000';
  return 'http://localhost:4000';
}

class Api {
  Api._();
  static final Api instance = Api._();

  /// Override for a real device or a deployed API:
  ///   flutter run --dart-define=API_URL=http://192.168.1.20:4000
  static const String _override = String.fromEnvironment('API_URL');
  static final String baseUrl = _override.isEmpty ? _defaultBaseUrl() : _override;

  static const _tokenKey = 'sanjeevani.token';
  String? _token;
  String? get token => _token;

  Future<void> loadToken() async {
    _token = (await SharedPreferences.getInstance()).getString(_tokenKey);
  }

  Future<void> setToken(String? value) async {
    _token = value;
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, value);
    }
  }

  Map<String, String> _headers({bool json = false}) => {
        if (json) 'content-type': 'application/json',
        if (_token != null) 'authorization': 'Bearer $_token',
      };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query?.isEmpty ?? true ? null : query);

  dynamic _decode(http.Response res) {
    dynamic body;
    if (res.body.isNotEmpty) {
      try {
        body = jsonDecode(res.body);
      } catch (_) {
        body = {'error': res.body};
      }
    }
    if (res.statusCode >= 400) {
      final message = body is Map && body['error'] is String
          ? body['error'] as String
          : 'request failed (${res.statusCode})';
      throw ApiException(res.statusCode, message);
    }
    return body;
  }

  Future<dynamic> get(String path, [Map<String, String>? query]) async =>
      _decode(await http.get(_uri(path, query), headers: _headers()));

  Future<dynamic> post(String path, [Object? body]) async => _decode(await http.post(
        _uri(path),
        headers: _headers(json: body != null),
        body: body == null ? null : jsonEncode(body),
      ));

  Future<dynamic> put(String path, Object body) async => _decode(await http.put(
        _uri(path),
        headers: _headers(json: true),
        body: jsonEncode(body),
      ));

  Future<dynamic> delete(String path) async =>
      _decode(await http.delete(_uri(path), headers: _headers()));

  /// Multipart upload. Files are stored as bytea in Postgres, so the bytes go
  /// straight up in one request.
  Future<dynamic> upload(
    String path, {
    required Uint8List bytes,
    required String filename,
    Map<String, String> fields = const {},
  }) async {
    final request = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(_headers())
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await request.send();
    return _decode(await http.Response.fromStream(streamed));
  }

  /// Stored files need the auth header, so an Image.network would 401.
  Future<Uint8List> fileBytes(String path) async {
    final res = await http.get(_uri(path), headers: _headers());
    if (res.statusCode >= 400) throw ApiException(res.statusCode, 'could not load file');
    return res.bodyBytes;
  }

  // ----------------------------------------------------------------- auth

  /// Which sign-in methods this server will actually accept. Asked once at boot
  /// so the login screen never offers a button the backend would reject.
  Future<Map<String, bool>> authConfig() async {
    try {
      final cfg = await get('/auth/config');
      return {
        'google': cfg['google_enabled'] == true,
        'firebase': cfg['firebase_enabled'] == true,
      };
    } catch (_) {
      return const {'google': false, 'firebase': false};
    }
  }

  Future<Map<String, dynamic>> register(String email, String password, String fullName) async =>
      (await post('/auth/register', {'email': email, 'password': password, 'full_name': fullName}))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> login(String email, String password) async =>
      (await post('/auth/login', {'email': email, 'password': password})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> loginWithGoogle(String idToken) async =>
      (await post('/auth/google', {'id_token': idToken})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> loginWithFirebase(String idToken) async =>
      (await post('/auth/firebase', {'id_token': idToken})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> me() async => (await get('/auth/me')) as Map<String, dynamic>;

  Future<void> setAppLock(String pin) => post('/auth/app-lock', {'pin': pin});

  Future<bool> verifyAppLock(String pin) async =>
      ((await post('/auth/app-lock/verify', {'pin': pin})) as Map)['ok'] == true;

  // -------------------------------------------------------------- profile

  Future<Map<String, dynamic>> profile() async =>
      (await get('/me/profile')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> saveProfile(Map<String, dynamic> patch) async =>
      (await put('/me/profile', patch)) as Map<String, dynamic>;

  Future<Map<String, dynamic>> uploadProfilePhoto(Uint8List bytes, String filename) async =>
      (await upload('/me/profile/photo', bytes: bytes, filename: filename)) as Map<String, dynamic>;

  Future<List> conditions() async => (await get('/me/conditions')) as List;
  Future<void> addCondition(String kind, String label, String? notes) =>
      post('/me/conditions', {'kind': kind, 'label': label, 'notes': ?notes});
  Future<void> deleteCondition(String id) => delete('/me/conditions/$id');

  Future<List> relatives() async => (await get('/me/relatives')) as List;
  Future<void> addRelative(String name, String contact, String relation) =>
      post('/me/relatives', {'name': name, 'contact': contact, 'relation': relation});
  Future<void> deleteRelative(String id) => delete('/me/relatives/$id');

  Future<List> setPreferredHospitals(List<String> ids) async =>
      (await put('/me/preferred-hospitals', {'hospital_ids': ids})) as List;

  Future<List> documents() async => (await get('/me/documents')) as List;
  Future<Map<String, dynamic>> uploadDocument(
    Uint8List bytes,
    String filename,
    String label,
    String? description,
  ) async =>
      (await upload('/me/documents',
          bytes: bytes,
          filename: filename,
          fields: {'label': label, 'description': ?description}))
          as Map<String, dynamic>;
  Future<void> deleteDocument(String id) => delete('/me/documents/$id');

  Future<Map<String, dynamic>> verifyAadhaar(String number) async =>
      (await post('/me/aadhaar/verify', {'aadhaar_number': number})) as Map<String, dynamic>;

  Future<List> visits() async => (await get('/me/visits')) as List;
  Future<Map<String, dynamic>> bills() async => (await get('/me/bills')) as Map<String, dynamic>;

  // ------------------------------------------------------------ hospitals

  Future<List> hospitals({double? lat, double? lng}) async => (await get('/hospitals', {
        if (lat != null) 'lat': '$lat',
        if (lng != null) 'lng': '$lng',
      })) as List;

  // ----------------------------------------------------------------- chat

  Future<List> conversations({String? kind}) async =>
      (await get('/conversations', kind == null ? null : {'kind': kind})) as List;

  /// [forceNew] starts a separate consultation instead of continuing the last
  /// one. Without it the server hands back an untouched thread if there is one,
  /// so opening the app repeatedly does not pile up empty consultations.
  Future<Map<String, dynamic>> openAiThread({bool forceNew = false}) async =>
      (await post('/conversations', {
        'kind': 'ai',
        if (forceNew) 'force_new': true,
      })) as Map<String, dynamic>;

  Future<Map<String, dynamic>> openCareTeamThread(String hospitalId) async =>
      (await post('/conversations', {'kind': 'care_team', 'hospital_id': hospitalId}))
          as Map<String, dynamic>;

  /// `after` is the newest timestamp already held, for incremental polling.
  /// [after]/[afterId] are one keyset cursor — send both or neither. They are the
  /// created_at and id of the newest message already held.
  Future<Map<String, dynamic>> messages(String conversationId,
          {String? after, String? afterId}) async =>
      (await get('/conversations/$conversationId/messages',
          {'after': ?after, 'after_id': ?afterId})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> sendMessage(String conversationId, String body,
          {String? language}) async =>
      (await post('/conversations/$conversationId/messages',
          {'body': body, 'language': ?language})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> sendAttachment(
    String conversationId,
    Uint8List bytes,
    String filename, {
    String? caption,
  }) async =>
      (await upload('/conversations/$conversationId/attachments',
          bytes: bytes,
          filename: filename,
          fields: {'body': ?caption})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> answerMcq(
    String conversationId,
    String messageId,
    Map<String, dynamic> answers,
  ) async =>
      (await post('/conversations/$conversationId/mcq-answer',
          {'message_id': messageId, 'answers': answers})) as Map<String, dynamic>;
}

/// A visit only carries a token once a doctor has called the patient in, so a
/// null token is "not issued yet", never "Token #null".
String visitHeadline(Map v) {
  final token = v['token_no'];
  final hospital = v['hospital_name'] ?? 'Hospital';
  return token == null ? 'Awaiting review · $hospital' : 'Token #$token · $hospital';
}

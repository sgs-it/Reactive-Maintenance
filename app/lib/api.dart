import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

typedef Data = Map<String, dynamic>;

class ApiException implements Exception {
  const ApiException(this.message, this.status);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class Api {
  static const configuredOrigin = String.fromEnvironment('RMCS_API_ORIGIN');
  static const demo = bool.fromEnvironment('RMCS_DEMO');
  static bool get needsOrigin => !kIsWeb && configuredOrigin.isEmpty;
  final http.Client _http = http.Client();
  String? token;
  Uri? origin;

  Uri _uri(String path) {
    if (configuredOrigin.isNotEmpty) {
      return Uri.parse(configuredOrigin).resolve(path);
    }
    if (kIsWeb) return Uri.base.resolve(path);
    if (origin != null) return origin!.resolve(path);
    throw const ApiException('Enter your company’s RMCS server address.', 0);
  }

  Map<String, String> get _headers => {
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<http.Response> _send(
    String path, {
    Data? body,
    Uint8List? image,
    String? mime,
    String? requestId,
  }) async {
    final uri = _uri('/api/$path');
    try {
      final headers = {
        ..._headers,
        if (body != null) 'Content-Type': 'application/json',
        'Content-Type': ?mime,
        'Idempotency-Key': ?requestId,
      };
      final response =
          await (body == null && image == null
                  ? _http.get(uri, headers: headers)
                  : _http.post(
                      uri,
                      headers: headers,
                      body: image ?? jsonEncode(body),
                    ))
              .timeout(const Duration(seconds: 70));
      if (response.statusCode >= 400) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Data;
        throw ApiException(data['error'] as String, response.statusCode);
      }
      return response;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        'Could not reach RMCS. Check your connection and try again.',
        0,
      );
    }
  }

  Future<Data> get(String path) async =>
      jsonDecode(utf8.decode((await _send(path)).bodyBytes)) as Data;

  Future<Data> post(String path, Data data) async =>
      jsonDecode(utf8.decode((await _send(path, body: data)).bodyBytes))
          as Data;

  Future<Uint8List> photo(String id) async =>
      (await _send('photos/$id/image')).bodyBytes;

  Future<({Uint8List bytes, String filename})> report(
    String format,
    Map<String, String> filters,
  ) async {
    final query = Uri(queryParameters: filters).query;
    final response = await _send('reports/complaints.$format?$query');
    final filename = RegExp(
      r'filename="([A-Za-z0-9._-]+)"',
    ).firstMatch(response.headers['content-disposition'] ?? '')?.group(1);
    return (
      bytes: response.bodyBytes,
      filename: filename ?? 'RMCS-service-requests.$format',
    );
  }

  Future<void> upload(
    String id,
    String stage,
    Uint8List bytes,
    String mime,
    String requestId,
  ) async {
    await _send(
      'complaints/$id/photos/$stage',
      image: bytes,
      mime: mime,
      requestId: requestId,
    );
  }

  Future<Data> login(String email, String password) async {
    final data = await post('login', {'email': email, 'password': password});
    token = data['token'] as String;
    return data['user'] as Data;
  }
}

Uri? companyOrigin(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    return null;
  }
  return uri;
}

String textOf(Data data, String key, [String fallback = '']) =>
    data[key]?.toString() ?? fallback;
List<Data> records(Data data, String key) =>
    List<Data>.from(data[key] as List? ?? const []);

const roleLabels = {
  'foreman': 'Team Leader / Foreman',
  'supervisor': 'Supervisor',
  'engineer': 'Engineer',
  'manager': 'Manager',
  'client': 'Client',
};
const statusLabels = {
  'open': 'Open',
  'assigned': 'Assigned',
  'in_progress': 'In Progress',
  'on_hold': 'On Hold',
  'pending': 'Pending',
  'verification': 'Pending Verification',
  'rework': 'Rework Required',
  'engineer_review': 'Pending Engineer Review',
  'closed': 'Closed',
  'solved': 'Closed',
};
bool resolved(Data row) => ['closed', 'solved'].contains(row['status']);

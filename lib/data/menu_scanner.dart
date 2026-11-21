import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../domain/scanned_menu.dart';

/// Exception thrown when menu scanning fails.
class MenuScanException implements Exception {
  const MenuScanException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Abstract contract for scanning menu photographs.
///
/// Implementations can call a local development proxy, a cloud endpoint,
/// or a mock service for automated testing.
abstract class MenuScanner {
  Future<MenuScanResult> scanMenu({
    required List<int> imageBytes,
    required String filename,
    required String mimeType,
  });
}

/// Default local development scanner that connects to the Node.js proxy
/// running at `http://127.0.0.1:8787`.
class LocalGeminiMenuScanner implements MenuScanner {
  LocalGeminiMenuScanner({this.baseUrl = defaultBaseUrl, http.Client? client})
    : _client = client ?? http.Client();

  static const defaultBaseUrl = 'http://127.0.0.1:8787';

  final String baseUrl;
  final http.Client _client;

  @override
  Future<MenuScanResult> scanMenu({
    required List<int> imageBytes,
    required String filename,
    required String mimeType,
  }) async {
    final uri = Uri.parse('$baseUrl/api/menu/scan');

    final request = http.MultipartRequest('POST', uri);

    MediaType? parsedContentType;
    try {
      final parts = mimeType.split('/');
      if (parts.length == 2) {
        parsedContentType = MediaType(parts[0], parts[1]);
      }
    } catch (_) {
      parsedContentType = MediaType('image', 'jpeg');
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: filename,
        contentType: parsedContentType,
      ),
    );

    http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await _client.send(request);
    } catch (e) {
      throw MenuScanException(
        'Could not connect to scanner proxy at $baseUrl. '
        'Is the proxy running? (Error: $e)',
      );
    }

    final response = await http.Response.fromStream(streamedResponse);
    final statusCode = response.statusCode;

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw MenuScanException(
        'Invalid response from scanner server (HTTP $statusCode): ${response.body}',
        statusCode: statusCode,
      );
    }

    if (statusCode == 200 &&
        body['success'] == true &&
        body['data'] is Map<String, dynamic>) {
      return MenuScanResult.fromJson(body['data'] as Map<String, dynamic>);
    }

    final errorMessage =
        body['error']?.toString() ??
        'Server returned HTTP $statusCode without error details.';
    throw MenuScanException(errorMessage, statusCode: statusCode);
  }
}

/// Configurable development API base URL. Can be overridden in tests or settings.
final menuScannerBaseUrlProvider = Provider<String>(
  (ref) => LocalGeminiMenuScanner.defaultBaseUrl,
);

/// Riverpod provider for the active [MenuScanner].
final menuScannerProvider = Provider<MenuScanner>((ref) {
  final baseUrl = ref.watch(menuScannerBaseUrlProvider);
  return LocalGeminiMenuScanner(baseUrl: baseUrl);
});

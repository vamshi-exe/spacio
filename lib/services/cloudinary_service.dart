import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config/app_config.dart';

class CloudinaryException implements Exception {
  final String message;
  CloudinaryException(this.message);
  @override
  String toString() => message;
}

/// Uploads images to Cloudinary using an **unsigned** upload preset, so no
/// API secret is needed in the app. Returns the hosted `secure_url`.
class CloudinaryService {
  CloudinaryService._();
  static final instance = CloudinaryService._();

  Uri get _endpoint => _endpointFor('image');

  Uri _endpointFor(String resourceType) => Uri.parse(
        'https://api.cloudinary.com/v1_1/${AppConfig.cloudinaryCloudName}'
        '/$resourceType/upload',
      );

  /// Upload a local file (room / tile photo). Returns the hosted URL.
  Future<String> uploadFile(File file, {String folder = 'tiles_ai'}) {
    return _send(() async {
      final request = http.MultipartRequest('POST', _endpoint)
        ..fields['upload_preset'] = AppConfig.cloudinaryUploadPreset
        ..fields['folder'] = folder;
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      return request;
    });
  }

  /// Upload raw bytes (e.g. the base64 result returned by OpenAI).
  Future<String> uploadBytes(
    Uint8List bytes, {
    String folder = 'tiles_ai',
    String filename = 'result.png',
  }) {
    return _send(() async {
      final request = http.MultipartRequest('POST', _endpoint)
        ..fields['upload_preset'] = AppConfig.cloudinaryUploadPreset
        ..fields['folder'] = folder;
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: MediaType('image', 'png'),
        ),
      );
      return request;
    });
  }

  /// Upload a PDF (e.g. a quotation) and return a public URL WhatsApp/clients
  /// can fetch. Uses the `auto` resource type so Cloudinary serves it correctly.
  Future<String> uploadPdfBytes(
    Uint8List bytes, {
    String folder = 'spacio/quotations',
    String filename = 'quotation.pdf',
  }) {
    return _send(() async {
      final request = http.MultipartRequest('POST', _endpointFor('auto'))
        ..fields['upload_preset'] = AppConfig.cloudinaryUploadPreset
        ..fields['folder'] = folder;
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: MediaType('application', 'pdf'),
        ),
      );
      return request;
    });
  }

  /// Send the upload, retrying transient failures (corrupted TLS records,
  /// dropped connections, timeouts, 5xx/429) with a short backoff. The request
  /// is rebuilt each attempt because its file streams can only be sent once.
  Future<String> _send(Future<http.MultipartRequest> Function() build) async {
    const maxAttempts = 3;
    const timeout = Duration(seconds: 60);
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final request = await build();
        final streamed = await request.send().timeout(timeout);
        final res = await http.Response.fromStream(streamed);

        if (res.statusCode == 200) {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          final url = body['secure_url'] as String?;
          if (url == null || url.isEmpty) {
            throw CloudinaryException('Cloudinary did not return a URL.');
          }
          return url;
        }

        final err = CloudinaryException(
          'Cloudinary upload failed (${res.statusCode}): ${res.body}',
        );
        final retryable = res.statusCode == 429 || res.statusCode >= 500;
        if (!retryable || attempt == maxAttempts) throw err;
        lastError = err;
      } on CloudinaryException {
        rethrow;
      } on TlsException catch (e) {
        lastError = e;
        if (attempt == maxAttempts) {
          throw CloudinaryException(
            'Secure connection to Cloudinary failed ($e). Check your '
            'connection and try again.',
          );
        }
      } on SocketException catch (e) {
        lastError = e;
        if (attempt == maxAttempts) {
          throw CloudinaryException(
            'Network error reaching Cloudinary ($e). Check your connection '
            'and try again.',
          );
        }
      } on http.ClientException catch (e) {
        lastError = e;
        if (attempt == maxAttempts) {
          throw CloudinaryException(
            'Connection to Cloudinary was interrupted ($e).',
          );
        }
      } on TimeoutException catch (e) {
        lastError = e;
        if (attempt == maxAttempts) {
          throw CloudinaryException('Cloudinary upload timed out.');
        }
      }

      log('Cloudinary upload attempt $attempt failed, retrying: $lastError');
      await Future.delayed(Duration(seconds: attempt * 2));
    }

    throw CloudinaryException('Cloudinary upload failed after retries.');
  }
}

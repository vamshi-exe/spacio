import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/tile_option.dart';

class OpenAiApiException implements Exception {
  final String message;
  OpenAiApiException(this.message);
  @override
  String toString() => message;
}

class GenerationUsage {
  final int textInputTokens;
  final int imageInputTokens;
  final int outputTokens;
  final double usd;

  const GenerationUsage({
    required this.textInputTokens,
    required this.imageInputTokens,
    required this.outputTokens,
    required this.usd,
  });
}

class TileGenerationResult {
  final List<GeneratedResult> images;
  final GenerationUsage? usage;

  const TileGenerationResult({required this.images, this.usage});
}

class OpenAIService {
  static const _baseUrl = 'https://api.openai.com/v1';
  static const _imageModel = 'gpt-image-1';

  // gpt-image-1 pricing (USD per token).
  static const _textInputUsdPerToken = 5 / 1000000;
  static const _imageInputUsdPerToken = 10 / 1000000;
  static const _outputUsdPerToken = 40 / 1000000;

  final String apiKey;

  OpenAIService(this.apiKey);

  Future<TileGenerationResult> generateTileVisualization({
    required File roomImage,
    required TileOption tile,
    int count = 1,
  }) async {
    final notes = tile.additionalNotes.trim();
    final notesLine = notes.isEmpty
        ? ''
        : '\n\nAdditional client notes (apply only if they do not conflict '
              'with the rules above): $notes.';
    final surface = tile.surface.label;

    final prompt =
        'Photorealistic architectural visualization task.\n'
        'Image 1 is a real photograph of an existing interior. '
        'Image 2 is a tile sample showing the exact color, pattern, finish, '
        'and format to install.\n\n'
        'Task: re-surface ONLY the $surface in Image 1 using the tile from '
        'Image 2. Treat the output as a documentation photo of the same room, '
        'taken from the same camera, after a professional tiler has finished '
        'installation. This is NOT a redesign and NOT a new space.\n\n'
        'Hard preservation rules — these must remain pixel-faithful to Image 1:\n'
        '- Camera position, focal length, perspective, framing, and crop.\n'
        '- Room dimensions, wall geometry, staircase treads and risers, '
        'landings, ceiling height, window and door positions, railings, '
        'mouldings, and floor.\n'
        '- All existing fixtures, electrical outlets, switches, sconces, '
        'furniture, plants, and decor. Do not add, remove, relocate, or '
        'restyle any object.\n'
        '- Original lighting direction, color temperature, exposure, '
        'shadows, highlights, and ambient reflections.\n'
        '- Any surface that is NOT the $surface stays exactly as in Image 1.\n\n'
        'Tile application rules for the $surface:\n'
        '- Use the tile in Image 2 as a single physical tile at its real '
        'installed size; scale it proportionally to the wall, do not stretch '
        'or zoom the texture.\n'
        '- Keep grout lines straight, uniform in width, and aligned with the '
        'wall planes and corners.\n'
        '- Follow the surface perspective; wrap tiles around corners and '
        'cuts the way a real tiler would.\n'
        '- Reproduce the tile color, veining, pattern variation, sheen, and '
        'finish exactly as in Image 2. Do not recolor, restyle, age, or '
        'distress it.\n'
        'If there are existing obstacles in the main object surface then remove it accordingly'
        '- Do not invent damaged plaster, exposed brick, decorative panels, '
        'mirrors, or any feature not present in Image 1.\n\n'
        'Output must be indistinguishable from a real post-installation '
        'photograph: no 3D-render look, no illustration, no concept art, no '
        'stylization.$notesLine';

    final size = await _pickSize(roomImage);
    log(prompt);

    final res = await _sendImageEdit(
      roomImage: roomImage,
      tileImage: tile.tileImage,
      prompt: prompt,
      size: size,
      count: count,
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final imgs = (data['data'] as List).cast<Map<String, dynamic>>();
    final results = imgs
        .map((m) {
          final b64 = m['b64_json'] as String?;
          final url = m['url'] as String?;
          final imageUrl = b64 != null && b64.isNotEmpty
              ? 'data:image/png;base64,$b64'
              : (url ?? '');
          return GeneratedResult(
            imageUrl: imageUrl,
            revisedPrompt: m['revised_prompt'] as String? ?? prompt,
          );
        })
        .where((r) => r.imageUrl.isNotEmpty)
        .toList();

    return TileGenerationResult(
      images: results,
      usage: _parseUsage(data['usage']),
    );
  }

  /// POST the image edit, retrying transient failures (dropped connections,
  /// timeouts, rate limits, 5xx) with a short backoff. The multipart request is
  /// rebuilt on each attempt because its file streams can only be sent once.
  Future<http.Response> _sendImageEdit({
    required File roomImage,
    required File tileImage,
    required String prompt,
    required String size,
    required int count,
  }) async {
    const maxAttempts = 3;
    const timeout = Duration(seconds: 120);
    OpenAiApiException? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$_baseUrl/images/edits'),
        );
        request.headers['Authorization'] = 'Bearer $apiKey';
        request.fields['model'] = _imageModel;
        request.fields['prompt'] = prompt;
        request.fields['quality'] = 'medium';
        request.fields['size'] = size;
        request.fields['input_fidelity'] = 'low';
        request.fields['n'] = '$count';
        request.files.add(
          await http.MultipartFile.fromPath(
            'image[]',
            roomImage.path,
            contentType: _mediaTypeFor(roomImage.path),
          ),
        );
        request.files.add(
          await http.MultipartFile.fromPath(
            'image[]',
            tileImage.path,
            contentType: _mediaTypeFor(tileImage.path),
          ),
        );

        final streamed = await request.send().timeout(timeout);
        final res = await http.Response.fromStream(streamed);

        if (res.statusCode == 200) return res;

        // Retry rate-limits and server errors; fail fast on client errors.
        final retryable = res.statusCode == 429 || res.statusCode >= 500;
        lastError = OpenAiApiException(
          _apiErrorMessage(res.statusCode, res.body),
        );
        if (!retryable || attempt == maxAttempts) throw lastError;
      } on OpenAiApiException {
        rethrow;
      } on TimeoutException {
        lastError = OpenAiApiException(
          'The request to OpenAI timed out. Check your connection and try '
          'again.',
        );
        if (attempt == maxAttempts) throw lastError;
      } on TlsException catch (e) {
        lastError = OpenAiApiException(
          'Secure connection to OpenAI failed (${e.message}). Check your '
          'connection and try again.',
        );
        if (attempt == maxAttempts) throw lastError;
      } on SocketException catch (e) {
        lastError = OpenAiApiException(
          'Network error reaching OpenAI (${e.osError?.message ?? e.message}). '
          'Check your connection and try again.',
        );
        if (attempt == maxAttempts) throw lastError;
      } on http.ClientException catch (e) {
        lastError = OpenAiApiException(
          'Connection to OpenAI was interrupted (${e.message}). Check your '
          'connection and try again.',
        );
        if (attempt == maxAttempts) throw lastError;
      }

      log('Image edit attempt $attempt failed, retrying: ${lastError.message}');
      await Future.delayed(Duration(seconds: attempt * 2));
    }

    throw lastError ?? OpenAiApiException('Image generation failed.');
  }

  /// Pull a human-readable message out of an OpenAI error body when possible.
  String _apiErrorMessage(int status, String body) {
    var detail = body;
    try {
      final m = jsonDecode(body);
      if (m is Map && m['error'] is Map && m['error']['message'] is String) {
        detail = m['error']['message'] as String;
      }
    } catch (_) {}
    return 'OpenAI image API error ($status): $detail';
  }

  GenerationUsage? _parseUsage(dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;
    final outputTokens = (raw['output_tokens'] as num?)?.toInt() ?? 0;
    final details = raw['input_tokens_details'];
    int textTokens = 0;
    int imageTokens = 0;
    if (details is Map<String, dynamic>) {
      textTokens = (details['text_tokens'] as num?)?.toInt() ?? 0;
      imageTokens = (details['image_tokens'] as num?)?.toInt() ?? 0;
    }
    final usd =
        textTokens * _textInputUsdPerToken +
        imageTokens * _imageInputUsdPerToken +
        outputTokens * _outputUsdPerToken;
    return GenerationUsage(
      textInputTokens: textTokens,
      imageInputTokens: imageTokens,
      outputTokens: outputTokens,
      usd: usd,
    );
  }

  MediaType _mediaTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    return MediaType('image', 'jpeg');
  }

  Future<String> _pickSize(File image) async {
    try {
      final bytes = await image.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      frame.image.dispose();
      return w >= h ? '1536x1024' : '1024x1536';
    } catch (_) {
      return '1536x1024';
    }
  }
}

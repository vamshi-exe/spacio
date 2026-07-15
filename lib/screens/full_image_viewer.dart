import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Open a project's result image full-screen, or show a hint if it's missing.
void openProjectImage(
  BuildContext context, {
  required String? imageUrl,
  String? title,
}) {
  if (imageUrl == null || imageUrl.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No image saved for this visualization yet.'),
      ),
    );
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FullImageViewer(imageUrl: imageUrl, title: title),
    ),
  );
}

/// Full-screen, pinch-to-zoom image viewer with a save-to-gallery action.
/// Handles both network URLs and base64 `data:` URLs.
class FullImageViewer extends StatefulWidget {
  final String imageUrl;
  final String? title;

  const FullImageViewer({super.key, required this.imageUrl, this.title});

  @override
  State<FullImageViewer> createState() => _FullImageViewerState();
}

class _FullImageViewerState extends State<FullImageViewer> {
  bool _saving = false;
  bool _sharing = false;

  /// Decode a `data:` URL or download a network image into bytes.
  Future<Uint8List> _fetchBytes() async {
    final url = widget.imageUrl;
    if (url.startsWith('data:')) {
      final comma = url.indexOf(',');
      if (comma == -1) throw Exception('Malformed image data.');
      return base64Decode(url.substring(comma + 1));
    }
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      throw Exception('Download failed (HTTP ${res.statusCode}).');
    }
    return res.bodyBytes;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) throw Exception('Gallery permission denied.');
      }
      final bytes = await _fetchBytes();
      final name = 'spacio_${DateTime.now().millisecondsSinceEpoch}';
      await Gal.putImageBytes(bytes, album: 'Spacio', name: name);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Saved to gallery (Spacio album).')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save image: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    // Anchor rect for the iPad share popover (ignored on phones).
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    try {
      final bytes = await _fetchBytes();
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/spacio_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes);
      final caption = widget.title == null
          ? 'Tile visualization — created with Spacio'
          : '${widget.title} — visualized with Spacio';
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: caption,
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not share image: $e')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: widget.title == null
            ? null
            : Text(
                widget.title!,
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
        actions: [
          IconButton(
            tooltip: 'Share',
            onPressed: _sharing ? null : _share,
            icon: _sharing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.share_rounded),
          ),
          IconButton(
            tooltip: 'Save to gallery',
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(minScale: 1, maxScale: 5, child: _image()),
      ),
    );
  }

  Widget _image() {
    final url = widget.imageUrl;
    if (url.startsWith('data:')) {
      try {
        final comma = url.indexOf(',');
        final bytes = base64Decode(url.substring(comma + 1));
        return Image.memory(bytes, fit: BoxFit.contain);
      } catch (_) {
        return _broken();
      }
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : const Center(child: CircularProgressIndicator(color: Colors.white)),
      errorBuilder: (_, _, _) => _broken(),
    );
  }

  Widget _broken() => const Center(
    child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 56),
  );
}

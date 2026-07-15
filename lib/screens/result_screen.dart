import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../config/app_config.dart';
import '../models/client.dart';
import '../models/estimate.dart';
import '../models/tile_option.dart';
import '../services/openai_service.dart';
import '../services/cloudinary_service.dart';
import '../services/email_service.dart';
import '../services/quotation_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shimmer_loading.dart';
import 'auth/auth_widgets.dart';

/// Lifecycle of the automatic quotation email sent after a successful render.
enum _AutoEmail { idle, sending, sent, failed }

class ResultScreen extends StatefulWidget {
  final File image;
  final TileOption tile;
  final Client? client;
  final String clientName;
  final String? clientPhone;
  final String? clientEmail;

  /// Area in sq ft captured on the tile screen. When present alongside a
  /// client email and a tile price, the quotation is emailed automatically
  /// once generation succeeds.
  final double? initialArea;

  const ResultScreen({
    super.key,
    required this.image,
    required this.tile,
    this.client,
    required this.clientName,
    this.clientPhone,
    this.clientEmail,
    this.initialArea,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  String _status = 'Generating tile visualization...';
  List<GeneratedResult> _results = const [];
  GenerationUsage? _usage;
  String? _error;
  bool _loading = true;
  final Set<int> _downloading = {};

  // Persistence state (Cloudinary upload + Supabase save).
  bool _saving = false;
  bool _saved = false;
  String? _saveError;
  String? _saveWarning;

  // Auto-email state: the quotation is mailed to the client automatically once
  // generation succeeds, when an area + client email + tile price are all set.
  _AutoEmail _autoEmail = _AutoEmail.idle;
  String? _autoEmailError;

  Future<void> _download(int index, String url) async {
    if (_downloading.contains(index)) return;
    setState(() => _downloading.add(index));
    final messenger = ScaffoldMessenger.of(context);
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          throw Exception('Gallery permission denied.');
        }
      }
      Uint8List bytes;
      if (url.startsWith('data:')) {
        final comma = url.indexOf(',');
        if (comma == -1) {
          throw Exception('Malformed data URL.');
        }
        bytes = base64Decode(url.substring(comma + 1));
      } else {
        final res = await http.get(Uri.parse(url));
        if (res.statusCode != 200) {
          throw Exception('Download failed (HTTP ${res.statusCode}).');
        }
        bytes = res.bodyBytes;
      }
      final name = 'spacio_${DateTime.now().millisecondsSinceEpoch}';
      await Gal.putImageBytes(bytes, album: 'Spacio', name: name);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Saved to gallery (Spacio album).')),
      );
    } catch (e) {
      print('Error saving image: $e');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save image: $e')),
      );
    } finally {
      if (mounted) setState(() => _downloading.remove(index));
    }
  }

  @override
  void initState() {
    super.initState();
    _run();
  }

  /// Re-attempt generation after an error, without leaving the screen.
  void _retry() {
    setState(() {
      _error = null;
      _loading = true;
      _status = 'Generating tile visualization...';
    });
    _run();
  }

  Future<void> _run() async {
    try {
      // Pre-flight: block generation if the user is out of credits. If the
      // balance can't be read (e.g. offline), proceed rather than hard-fail.
      try {
        final profile = await SupabaseService.instance.fetchProfile();
        if (profile.totalRendersLeft <= 0) {
          if (!mounted) return;
          setState(() {
            _error =
                "You're out of render credits.\n"
                'Upgrade your plan to keep generating visualizations.';
            _loading = false;
          });
          return;
        }
      } catch (_) {
        // Couldn't verify credits — continue.
      }

      final svc = OpenAIService(ApiConfig.openAiApiKey);

      setState(() => _status = 'Generating tile visualization...');
      final out = await svc.generateTileVisualization(
        roomImage: widget.image,
        tile: widget.tile,
      );

      if (!mounted) return;
      setState(() {
        _results = out.images;
        _usage = out.usage;
        _loading = false;
      });

      // Upload + save in the background; results are already on screen.
      _persist();

      // Fire the automatic quotation email (no-op unless area + email + price
      // are all available). Runs independently of the Supabase save.
      _maybeAutoEmail();
    } on OpenAiApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Unexpected error: $e';
        _loading = false;
      });
    }
  }

  /// Save the visualization to Supabase, uploading images to Cloudinary along
  /// the way. Each step degrades independently: a failed image upload still
  /// saves the project (with whatever uploaded), and the client is saved even
  /// if everything else fails — so a Cloudinary outage never loses the record.
  Future<void> _persist() async {
    if (_results.isEmpty || !AppConfig.isConfigured) return;
    setState(() {
      _saving = true;
      _saveError = null;
      _saveWarning = null;
    });

    // 1. Resolve the client (the critical CRM write). Reuse the one the tile
    //    screen already saved when available.
    final Client client;
    try {
      client =
          widget.client ??
          await SupabaseService.instance.findOrCreateClient(
            name: widget.clientName,
            phone: widget.clientPhone,
            email: widget.clientEmail,
          );
    } catch (e) {
      log('Client save failed: $e');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'Could not save the client: $e';
      });
      return;
    }

    // 2. Upload images independently. A failure leaves that URL null and bumps
    //    the counter rather than aborting the whole save.
    final cloud = CloudinaryService.instance;
    var failedUploads = 0;
    Future<String?> tryUpload(
      String label,
      Future<String> Function() up,
    ) async {
      try {
        return await up();
      } catch (e) {
        failedUploads++;
        log('$label upload failed: $e');
        return null;
      }
    }

    final roomUrl = await tryUpload(
      'Room',
      () => cloud.uploadFile(widget.image, folder: 'tiles_ai/rooms'),
    );
    final tileUrl = await tryUpload(
      'Tile',
      () => cloud.uploadFile(widget.tile.tileImage, folder: 'tiles_ai/tiles'),
    );

    String? resultUrl;
    final first = _results.first.imageUrl;
    final bytes = _bytesFor(first);
    if (bytes != null) {
      resultUrl = await tryUpload(
        'Result',
        () => cloud.uploadBytes(bytes, folder: 'tiles_ai/results'),
      );
    } else if (first.startsWith('http')) {
      resultUrl = first;
    }

    // 3. Save the project row (the record that links client ↔ visualization).
    try {
      await SupabaseService.instance.createProject(
        name: widget.clientName,
        surface: widget.tile.surface.label,
        clientId: client.id,
        roomImageUrl: roomUrl,
        tileImageUrl: tileUrl,
        resultImageUrl: resultUrl,
        notes: widget.tile.additionalNotes,
        tileName: widget.tile.tileName,
        tileWidth: widget.tile.tileWidth,
        tileHeight: widget.tile.tileHeight,
        tileSizeUnit: widget.tile.tileSizeUnit,
        pricePerSqFt: widget.tile.pricePerSqFt,
        cartageFee: widget.tile.cartageFee,
        gstPercent: widget.tile.gstPercent,
        areaSqFt: widget.initialArea,
      );
    } catch (e) {
      log('Project save failed: $e');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = "Saved the client, but the project didn't sync: $e";
      });
      return;
    }

    // 4. The render was generated (cost incurred), so spend the credit even if
    //    image hosting failed. A failure here is non-fatal — the project saved.
    try {
      await SupabaseService.instance.consumeRender();
    } catch (e) {
      log('consumeRender failed: $e');
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = true;
      if (failedUploads > 0) {
        _saveWarning =
            'Saved — but $failedUploads image${failedUploads == 1 ? '' : 's'} '
            "couldn't upload. Check your Cloudinary upload preset.";
      }
    });
  }

  /// Decode a `data:` URL into bytes; returns null for plain http(s) URLs.
  Uint8List? _bytesFor(String url) {
    if (!url.startsWith('data:')) return null;
    final comma = url.indexOf(',');
    if (comma == -1) return null;
    try {
      return base64Decode(url.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  /// Email the quotation to the client automatically once a render succeeds.
  /// Silently no-ops unless everything needed for a complete quote is present:
  /// backend configured, a client email, an area, and a tile price.
  Future<void> _maybeAutoEmail() async {
    if (!AppConfig.isConfigured) return;
    final email = widget.clientEmail?.trim();
    final area = widget.initialArea;
    final price = widget.tile.pricePerSqFt;
    if (email == null || email.isEmpty) return;
    if (area == null || area <= 0) return;
    if (price == null || price <= 0) return;

    setState(() {
      _autoEmail = _AutoEmail.sending;
      _autoEmailError = null;
    });
    try {
      final withGst = Estimate(
        areaSqFt: area,
        pricePerSqFt: price,
        cartageFee: widget.tile.cartageFee ?? 0,
        gstPercent: widget.tile.gstPercent,
        tileAreaSqFt: widget.tile.tileAreaSqFt,
      );
      String? preparedBy;
      if (AppConfig.isConfigured) {
        preparedBy = SupabaseService.instance.currentEmail;
      }
      final renderImageUrl = _results.isEmpty ? null : _results.first.imageUrl;
      // Attach both the with-GST and without-GST quotations.
      final attachments = <QuotationAttachment>[];
      for (final estimate in [withGst, withGst.withGst(0)]) {
        final pdf = await QuotationService.instance.buildQuotationPdf(
          tileName: widget.tile.tileName,
          tileSizeLabel: widget.tile.tileSizeLabel,
          surfaceLabel: widget.tile.surface.label,
          estimate: estimate,
          clientName: widget.clientName,
          clientPhone: widget.clientPhone,
          clientEmail: widget.clientEmail,
          preparedBy: preparedBy,
          renderImageUrl: renderImageUrl,
          date: DateTime.now(),
        );
        attachments.add(
          QuotationAttachment(
            bytes: pdf,
            filename: QuotationService.quotationFilename(
              widget.clientName,
              estimate,
            ),
          ),
        );
      }
      await EmailService.instance.sendQuotation(
        attachments: attachments,
        toEmail: email,
        clientName: widget.clientName,
        summary: 'Total ${Estimate.formatCurrency(withGst.totalWithGst)}',
      );
      if (!mounted) return;
      setState(() => _autoEmail = _AutoEmail.sent);
    } catch (e) {
      log('Auto-email failed: $e');
      if (!mounted) return;
      setState(() {
        _autoEmail = _AutoEmail.failed;
        _autoEmailError = '$e';
      });
    }
  }

  /// Pop the whole capture → tiles → result stack and land back on Home.
  void _goHome() => Navigator.of(context).popUntil((route) => route.isFirst);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Once a visualization exists, back returns to Home rather than to
        // the tile/photo screens; while loading or on error, step back one.
        if (_results.isNotEmpty) {
          _goHome();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Visualizations'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () =>
                _results.isNotEmpty ? _goHome() : Navigator.of(context).pop(),
          ),
        ),
        body: _loading
            ? _GeneratingView(status: _status)
            : _error != null
            ? _errorView(_error!)
            : _resultsView(),
      ),
    );
  }

  Widget _usageCard(GenerationUsage usage) {
    print(usage.imageInputTokens);
    print(usage.outputTokens);
    print(usage.textInputTokens);
    print(usage.usd);
    final usd = usage.usd.toStringAsFixed(4);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Generation cost: \$$usd',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Text in: ${usage.textInputTokens} tok · '
              'Image in: ${usage.imageInputTokens} tok · '
              'Output: ${usage.outputTokens} tok',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultImage(String url) {
    if (url.startsWith('data:')) {
      try {
        final comma = url.indexOf(',');
        final bytes = base64Decode(url.substring(comma + 1));
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) =>
              const Center(child: Icon(Icons.broken_image_outlined, size: 48)),
        );
      } catch (_) {
        return const Center(child: Icon(Icons.broken_image_outlined, size: 48));
      }
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (_, child, p) =>
          p == null ? child : const AppShimmer(child: ShimmerBox(radius: 0)),
      errorBuilder: (ctx, err, stack) =>
          const Center(child: Icon(Icons.broken_image_outlined, size: 48)),
    );
  }

  Widget _errorView(String message) {
    log(message);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 56,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Go back'),
          ),
        ],
      ),
    );
  }

  Widget _saveStatusBanner() {
    IconData icon;
    String text;
    Color color;
    if (_saving) {
      icon = Icons.cloud_upload_outlined;
      text = 'Saving to your projects…';
      color = Theme.of(context).colorScheme.primary;
    } else if (_saveError != null) {
      icon = Icons.cloud_off_outlined;
      text = _saveError!;
      color = Theme.of(context).colorScheme.error;
    } else if (_saved && _saveWarning != null) {
      icon = Icons.warning_amber_rounded;
      text = _saveWarning!;
      color = Colors.orange;
    } else if (_saved) {
      icon = Icons.cloud_done_outlined;
      text = 'Saved to your projects';
      color = Colors.green;
    } else {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (_saving)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _autoEmailBanner() {
    IconData icon;
    String text;
    Color color;
    switch (_autoEmail) {
      case _AutoEmail.idle:
        return const SizedBox.shrink();
      case _AutoEmail.sending:
        icon = Icons.mark_email_read_outlined;
        text = 'Emailing the quotation to ${widget.clientEmail}…';
        color = Theme.of(context).colorScheme.primary;
      case _AutoEmail.sent:
        icon = Icons.mark_email_read_outlined;
        text = 'Quotation emailed to ${widget.clientEmail}';
        color = Colors.green;
      case _AutoEmail.failed:
        icon = Icons.error_outline_rounded;
        text =
            "Couldn't auto-email the quotation"
            "${_autoEmailError == null ? '' : ': $_autoEmailError'}. "
            'Use “Email to client” below to retry.';
        color = Theme.of(context).colorScheme.error;
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (_autoEmail == _AutoEmail.sending)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _resultsView() {
    if (_results.isEmpty) {
      return const Center(child: Text('No images returned.'));
    }
    final usage = _usage;
    final headerCount = usage == null ? 0 : 1;
    return Column(
      children: [
        _saveStatusBanner(),
        _autoEmailBanner(),
        Expanded(child: _resultsList(headerCount, usage)),
      ],
    );
  }

  Widget _resultsList(int headerCount, GenerationUsage? usage) {
    // One extra trailing item: the estimate / quotation card.
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _results.length + headerCount + 1,
      itemBuilder: (context, rawIndex) {
        if (headerCount == 1 && rawIndex == 0) {
          return _usageCard(usage!);
        }
        final i = rawIndex - headerCount;
        if (i == _results.length) {
          return _EstimateCard(
            tile: widget.tile,
            clientName: widget.clientName,
            clientPhone: widget.clientPhone,
            clientEmail: widget.clientEmail,
            renderImageUrl: _results.isEmpty ? null : _results.first.imageUrl,
            initialArea: widget.initialArea,
          );
        }
        final r = _results[i];
        final busy = _downloading.contains(i);
        return Card(
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: _buildResultImage(r.imageUrl),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: 'Save to gallery',
                        color: Colors.white,
                        icon: busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.download_rounded),
                        onPressed: busy ? null : () => _download(i, r.imageUrl),
                      ),
                    ),
                  ),
                ],
              ),
              // Padding(
              //   padding: const EdgeInsets.all(12),
              //   child: Text(
              //     r.revisedPrompt,
              //     style: Theme.of(context).textTheme.bodySmall,
              //   ),
              // ),
            ],
          ),
        );
      },
    );
  }
}

/// Shown beneath the generated visualizations. Displays the tile's catalogue
/// details, takes an area in sq ft, and computes the material + approx total
/// cost — then offers a downloadable PDF quotation.
class _EstimateCard extends StatefulWidget {
  final TileOption tile;
  final String clientName;
  final String? clientPhone;
  final String? clientEmail;
  final String? renderImageUrl;
  final double? initialArea;

  const _EstimateCard({
    required this.tile,
    required this.clientName,
    required this.clientPhone,
    required this.clientEmail,
    required this.renderImageUrl,
    this.initialArea,
  });

  @override
  State<_EstimateCard> createState() => _EstimateCardState();
}

class _EstimateCardState extends State<_EstimateCard> {
  final _area = TextEditingController();
  Estimate? _estimate;
  String? _areaError;

  @override
  void initState() {
    super.initState();
    // Prefill the area captured on the tile screen (the one auto-emailed) so
    // the on-screen estimate matches, and compute it right away when valid.
    final area = widget.initialArea;
    if (area != null && area > 0) {
      _area.text = _numStr(area);
      if (_hasPrice) {
        _estimate = Estimate(
          areaSqFt: area,
          pricePerSqFt: _price!,
          cartageFee: _cartageFee,
          gstPercent: _gstPercent,
          tileAreaSqFt: widget.tile.tileAreaSqFt,
        );
      }
    }
  }

  static String _numStr(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  /// Which share is in flight: 'gst', 'plain', or null.
  String? _sharingTag;

  /// True while the quotation is being emailed to the client server-side.
  bool _emailing = false;

  double? get _price => widget.tile.pricePerSqFt;
  bool get _hasPrice => _price != null && _price! > 0;
  double get _cartageFee => widget.tile.cartageFee ?? 0;
  double get _gstPercent => widget.tile.gstPercent;

  @override
  void dispose() {
    _area.dispose();
    super.dispose();
  }

  void _generate() {
    final area = double.tryParse(_area.text.trim());
    if (area == null || area <= 0) {
      setState(() {
        _areaError = 'Enter a valid area in sq ft.';
        _estimate = null;
      });
      return;
    }
    if (!_hasPrice) return;
    setState(() {
      _areaError = null;
      _estimate = Estimate(
        areaSqFt: area,
        pricePerSqFt: _price!,
        cartageFee: _cartageFee,
        gstPercent: _gstPercent,
        tileAreaSqFt: widget.tile.tileAreaSqFt,
      );
    });
  }

  /// Open the system share sheet with the quotation PDF. The user picks the
  /// destination — Mail, WhatsApp, save to files, etc. — so a single flow
  /// covers every channel instead of a dedicated per-app button.
  Future<void> _sharePdf({required bool withGst}) async {
    final base = _estimate;
    if (base == null || _sharingTag != null) return;
    final estimate = withGst ? base : base.withGst(0);
    setState(() => _sharingTag = withGst ? 'gst' : 'plain');
    final messenger = ScaffoldMessenger.of(context);
    try {
      String? preparedBy;
      if (AppConfig.isConfigured) {
        preparedBy = SupabaseService.instance.currentEmail;
      }
      await QuotationService.instance.shareQuotation(
        tileName: widget.tile.tileName,
        tileSizeLabel: widget.tile.tileSizeLabel,
        surfaceLabel: widget.tile.surface.label,
        estimate: estimate,
        clientName: widget.clientName,
        clientPhone: widget.clientPhone,
        clientEmail: widget.clientEmail,
        preparedBy: preparedBy,
        renderImageUrl: widget.renderImageUrl,
        date: DateTime.now(),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not create PDF: $e')),
      );
    } finally {
      if (mounted) setState(() => _sharingTag = null);
    }
  }

  /// Email the quotation (both with-GST and without-GST copies) straight to the
  /// client's stored address via the send-quotation-email Edge Function — no
  /// share sheet or manual compose.
  Future<void> _emailToClient() async {
    final base = _estimate;
    final email = widget.clientEmail;
    if (base == null || _emailing) return;
    if (email == null || email.trim().isEmpty) {
      _toast('No client email to send to.');
      return;
    }
    setState(() => _emailing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      String? preparedBy;
      if (AppConfig.isConfigured) {
        preparedBy = SupabaseService.instance.currentEmail;
      }
      // Attach both the with-GST and without-GST quotations.
      final attachments = <QuotationAttachment>[];
      for (final estimate in [base, base.withGst(0)]) {
        final pdf = await QuotationService.instance.buildQuotationPdf(
          tileName: widget.tile.tileName,
          tileSizeLabel: widget.tile.tileSizeLabel,
          surfaceLabel: widget.tile.surface.label,
          estimate: estimate,
          clientName: widget.clientName,
          clientPhone: widget.clientPhone,
          clientEmail: widget.clientEmail,
          preparedBy: preparedBy,
          renderImageUrl: widget.renderImageUrl,
          date: DateTime.now(),
        );
        attachments.add(
          QuotationAttachment(
            bytes: pdf,
            filename: QuotationService.quotationFilename(
              widget.clientName,
              estimate,
            ),
          ),
        );
      }
      await EmailService.instance.sendQuotation(
        attachments: attachments,
        toEmail: email,
        clientName: widget.clientName,
        summary: 'Total ${Estimate.formatCurrency(base.totalWithGst)}',
      );
      messenger.showSnackBar(
        SnackBar(content: Text('Quotation emailed to $email.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not email the quotation: $e')),
      );
    } finally {
      if (mounted) setState(() => _emailing = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final tile = widget.tile;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calculate_outlined,
                size: 20,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                'Estimate',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontSize: 17),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _detail('Tile name', tile.tileName.isEmpty ? '—' : tile.tileName),
          _detail(
            'Tile size',
            tile.tileSizeLabel.isEmpty ? '—' : tile.tileSizeLabel,
          ),
          _detail(
            'Price / sq ft',
            _hasPrice ? Estimate.formatCurrency(_price!) : 'Not set',
          ),
          _detail('GST slab', '${_gstPercent.toStringAsFixed(0)}%'),
          const SizedBox(height: 16),
          AuthField(
            controller: _area,
            label: 'Area (sq ft) *',
            hint: 'e.g. 120',
            icon: Icons.straighten_rounded,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
          ),
          if (_areaError != null) ...[
            const SizedBox(height: 6),
            Text(
              _areaError!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
          if (!_hasPrice) ...[
            const SizedBox(height: 10),
            Text(
              'Add a price per sq ft on the tile screen to estimate costs.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          AuthButton(
            label: 'Generate Estimate',
            loading: false,
            onPressed: _hasPrice ? _generate : null,
          ),
          if (_estimate != null) ...[
            const SizedBox(height: 18),
            if (_estimate!.tilesNeeded != null) ...[
              _infoRow('Tiles needed', '${_estimate!.tilesNeeded} pcs'),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: AppColors.border, height: 1),
              ),
            ],
            _resultRow('Material cost', _estimate!.materialCost),
            const SizedBox(height: 8),
            _resultRow('Cartage fee', _estimate!.cartageFee, muted: true),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(color: AppColors.border, height: 1),
            ),
            _resultRow(
              'Approx. Total (excl. GST)',
              _estimate!.approxTotalCost,
              emphasize: true,
            ),
            const SizedBox(height: 8),
            _resultRow(
              'GST (${_estimate!.gstPercent.toStringAsFixed(0)}%)',
              _estimate!.gstAmount,
              muted: true,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(color: AppColors.border, height: 1),
            ),
            _resultRow(
              'Total incl. GST',
              _estimate!.totalWithGst,
              emphasize: true,
            ),
            const SizedBox(height: 18),
            _shareButton(
              label: 'Share with GST',
              tag: 'gst',
              filled: true,
              onPressed: () => _sharePdf(withGst: true),
            ),
            const SizedBox(height: 10),
            _shareButton(
              label: 'Share without GST',
              tag: 'plain',
              filled: false,
              onPressed: () => _sharePdf(withGst: false),
            ),
            const SizedBox(height: 8),
            const Text(
              'Opens your share sheet — send by email, WhatsApp, or save the PDF.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (_emailing || _sharingTag != null)
                    ? null
                    : _emailToClient,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _emailing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textPrimary,
                        ),
                      )
                    : const Icon(Icons.mail_outline_rounded, size: 20),
                label: Text(
                  _emailing ? 'Sending…' : 'Email to client',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if ((widget.clientEmail ?? '').trim().isEmpty) ...[
              const SizedBox(height: 6),
              const Text(
                'Add a client email to send the quotation directly.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _shareButton({
    required String label,
    required String tag,
    required bool filled,
    required VoidCallback onPressed,
  }) {
    final busy = _sharingTag == tag;
    final anyBusy = _sharingTag != null;
    final spinnerColor = filled ? AppColors.onCream : AppColors.textPrimary;
    final icon = busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: spinnerColor,
            ),
          )
        : const Icon(Icons.ios_share_rounded, size: 20);
    final text = Text(
      busy ? 'Preparing…' : label,
      style: const TextStyle(fontWeight: FontWeight.w700),
    );

    return SizedBox(
      height: 50,
      width: double.infinity,
      child: filled
          ? FilledButton.icon(
              onPressed: anyBusy ? null : onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.cream,
                foregroundColor: AppColors.onCream,
                disabledBackgroundColor: AppColors.cream.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: icon,
              label: text,
            )
          : OutlinedButton.icon(
              onPressed: anyBusy ? null : onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: icon,
              label: text,
            ),
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A non-currency label/value row (e.g. tile count).
  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _resultRow(
    String label,
    double amount, {
    bool emphasize = false,
    bool muted = false,
  }) {
    final labelColor = muted ? AppColors.textMuted : AppColors.textSecondary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: emphasize ? AppColors.textPrimary : labelColor,
            fontSize: emphasize ? 15 : 13.5,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        Text(
          Estimate.formatCurrency(amount),
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: emphasize ? 18 : 14,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Shimmer skeleton shown while the visualization is generating: a square
/// image card and an estimate card, with the live status line on top.
class _GeneratingView extends StatelessWidget {
  final String status;
  const _GeneratingView({required this.status});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          status,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        const AppShimmer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(aspectRatio: 1, child: ShimmerBox()),
              SizedBox(height: 16),
              ShimmerBox(height: 220),
            ],
          ),
        ),
      ],
    );
  }
}

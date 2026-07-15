import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../models/client.dart';
import '../models/estimate.dart';
import '../models/project.dart';
import '../services/email_service.dart';
import '../services/quotation_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'auth/auth_widgets.dart';
import 'client_detail_screen.dart';
import 'full_image_viewer.dart';

/// Read-only view of a saved visualization: result image, surface, date,
/// notes, linked client, and the original room/tile photos.
class ProjectDetailScreen extends StatefulWidget {
  final Project project;
  const ProjectDetailScreen({super.key, required this.project});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  Client? _client;
  bool _loadingClient = false;

  late final _areaCtrl = TextEditingController(
    text: _project.areaSqFt == null ? '' : _numStr(_project.areaSqFt!),
  );
  late final _priceCtrl = TextEditingController(
    text: _project.pricePerSqFt == null ? '' : _numStr(_project.pricePerSqFt!),
  );
  late final _cartageCtrl = TextEditingController(
    text: _project.cartageFee == null ? '' : _numStr(_project.cartageFee!),
  );

  /// Which quotation share is in flight: 'gst', 'plain', or null.
  String? _sharingTag;
  bool _emailing = false;

  Project get _project => widget.project;

  @override
  void initState() {
    super.initState();
    _loadClient();
  }

  @override
  void dispose() {
    _areaCtrl.dispose();
    _priceCtrl.dispose();
    _cartageCtrl.dispose();
    super.dispose();
  }

  static String _numStr(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  /// Estimate built from the current area/price fields, or null when either
  /// is missing or invalid.
  Estimate? get _estimate {
    final area = double.tryParse(_areaCtrl.text.trim());
    final price = double.tryParse(_priceCtrl.text.trim());
    if (area == null || area <= 0 || price == null || price <= 0) return null;
    return Estimate(
      areaSqFt: area,
      pricePerSqFt: price,
      cartageFee: double.tryParse(_cartageCtrl.text.trim()) ?? 0,
      gstPercent: _project.gstPercent,
      tileAreaSqFt: _project.tileAreaSqFt,
    );
  }

  String get _quotationClientName => _client?.name ?? _project.name;

  /// Open the system share/save sheet with the quotation PDF — the user can
  /// send it anywhere or save it as a download.
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
        tileName: _project.tileName,
        tileSizeLabel: _project.tileSizeLabel,
        surfaceLabel: _project.surface,
        estimate: estimate,
        clientName: _quotationClientName,
        clientPhone: _client?.phone,
        clientEmail: _client?.email,
        preparedBy: preparedBy,
        renderImageUrl: _project.resultImageUrl,
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

  /// Email both the with-GST and without-GST quotations to the client's
  /// stored address via the send-quotation-email Edge Function.
  Future<void> _emailToClient() async {
    final base = _estimate;
    final email = _client?.email;
    if (base == null || _emailing) return;
    if (email == null || email.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No client email to send to.')),
      );
      return;
    }
    setState(() => _emailing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      String? preparedBy;
      if (AppConfig.isConfigured) {
        preparedBy = SupabaseService.instance.currentEmail;
      }
      final attachments = <QuotationAttachment>[];
      for (final estimate in [base, base.withGst(0)]) {
        final pdf = await QuotationService.instance.buildQuotationPdf(
          tileName: _project.tileName,
          tileSizeLabel: _project.tileSizeLabel,
          surfaceLabel: _project.surface,
          estimate: estimate,
          clientName: _quotationClientName,
          clientPhone: _client?.phone,
          clientEmail: email,
          preparedBy: preparedBy,
          renderImageUrl: _project.resultImageUrl,
          date: DateTime.now(),
        );
        attachments.add(
          QuotationAttachment(
            bytes: pdf,
            filename: QuotationService.quotationFilename(
              _quotationClientName,
              estimate,
            ),
          ),
        );
      }
      await EmailService.instance.sendQuotation(
        attachments: attachments,
        toEmail: email,
        clientName: _quotationClientName,
        summary: 'Total ${Estimate.formatCurrency(base.totalWithGst)}',
      );
      print(email.toString());

      messenger.showSnackBar(
        SnackBar(content: Text('Quotation emailed to $email.')),
      );
    } catch (e) {
      print(e.toString());
      messenger.showSnackBar(
        SnackBar(content: Text('Could not email the quotation: $e')),
      );
    } finally {
      if (mounted) setState(() => _emailing = false);
    }
  }

  Future<void> _loadClient() async {
    final clientId = _project.clientId;
    if (clientId == null) return;
    setState(() => _loadingClient = true);
    try {
      final client = await SupabaseService.instance.getClient(clientId);
      if (!mounted) return;
      setState(() {
        _client = client;
        _loadingClient = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingClient = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            _header(context),
            const SizedBox(height: 16),
            _resultImage(context),
            const SizedBox(height: 16),
            _detailsCard(),
            if (_project.notes.isNotEmpty) ...[
              const SizedBox(height: 16),
              _notesCard(),
            ],
            if (_project.clientId != null) ...[
              const SizedBox(height: 16),
              _clientCard(context),
            ],
            const SizedBox(height: 28),
            Text(
              'Quotation',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontSize: 17),
            ),
            const SizedBox(height: 14),
            _quotationCard(context),
            if (_project.roomImageUrl != null ||
                _project.tileImageUrl != null) ...[
              const SizedBox(height: 28),
              Text(
                'Source images',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontSize: 17),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  if (_project.roomImageUrl != null)
                    Expanded(
                      child: _SourceImage(
                        label: 'Room',
                        imageUrl: _project.roomImageUrl!,
                        title: '${_project.name} — Room',
                      ),
                    ),
                  if (_project.roomImageUrl != null &&
                      _project.tileImageUrl != null)
                    const SizedBox(width: 12),
                  if (_project.tileImageUrl != null)
                    Expanded(
                      child: _SourceImage(
                        label: 'Tile',
                        imageUrl: _project.tileImageUrl!,
                        title: '${_project.name} — Tile',
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _project.name,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _project.timeAgo,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }

  Widget _resultImage(BuildContext context) {
    return GestureDetector(
      onTap: () => openProjectImage(
        context,
        imageUrl: _project.resultImageUrl,
        title: _project.name,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: _project.resultImageUrl != null
            ? AspectRatio(
                aspectRatio: 16 / 10,
                child: Image.network(
                  _project.resultImageUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, p) => p == null
                      ? child
                      : Container(
                          color: AppColors.surface,
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.cream,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                  errorBuilder: (_, _, _) => Container(
                    color: AppColors.surface,
                    child: const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              )
            : const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Text(
                    'No result image saved yet.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _detailsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _detailRow(
            'Surface',
            _project.surface.isEmpty ? 'Not specified' : _project.surface,
          ),
          if (_project.tileName.isNotEmpty) ...[
            const SizedBox(height: 12),
            _detailRow('Tile', _project.tileName),
          ],
          if (_project.tileSizeLabel.isNotEmpty) ...[
            const SizedBox(height: 12),
            _detailRow('Tile size', _project.tileSizeLabel),
          ],
          const SizedBox(height: 12),
          _detailRow('Created', _formatDate(_project.createdAt)),
        ],
      ),
    );
  }

  Widget _quotationCard(BuildContext context) {
    final estimate = _estimate;
    final clientEmail = (_client?.email ?? '').trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AuthField(
                  controller: _areaCtrl,
                  label: 'Area (sq ft)',
                  hint: 'e.g. 120',
                  icon: Icons.straighten_rounded,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AuthField(
                  controller: _priceCtrl,
                  label: 'Price / sq ft (₹)',
                  hint: 'e.g. 85',
                  icon: Icons.currency_rupee_rounded,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AuthField(
            controller: _cartageCtrl,
            label: 'Cartage fee (₹)',
            hint: 'e.g. 500',
            icon: Icons.local_shipping_outlined,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
          ),
          if (estimate == null) ...[
            const SizedBox(height: 10),
            const Text(
              'Enter the area and price per sq ft to generate a quotation.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ] else ...[
            const SizedBox(height: 16),
            _amountRow('Approx. Total (excl. GST)', estimate.approxTotalCost),
            const SizedBox(height: 6),
            _amountRow(
              'Total incl. GST (${estimate.gstPercent.toStringAsFixed(0)}%)',
              estimate.totalWithGst,
            ),
            const SizedBox(height: 16),
            _quotationButton(
              label: 'Download / Share with GST',
              tag: 'gst',
              filled: true,
              onPressed: () => _sharePdf(withGst: true),
            ),
            const SizedBox(height: 10),
            _quotationButton(
              label: 'Download / Share without GST',
              tag: 'plain',
              filled: false,
              onPressed: () => _sharePdf(withGst: false),
            ),
            const SizedBox(height: 8),
            const Text(
              'Opens your share sheet — save the PDF or send it by email, '
              'WhatsApp, etc.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed:
                    (_emailing || _sharingTag != null || clientEmail.isEmpty)
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
            if (clientEmail.isEmpty) ...[
              const SizedBox(height: 6),
              const Text(
                'Add an email to this client to send the quotation directly.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _amountRow(String label, double amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13.5,
          ),
        ),
        Text(
          Estimate.formatCurrency(amount),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _quotationButton({
    required String label,
    required String tag,
    required bool filled,
    required VoidCallback onPressed,
  }) {
    final busy = _sharingTag == tag;
    final anyBusy = _sharingTag != null || _emailing;
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

  Widget _detailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13.5,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _notesCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NOTES',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _project.notes,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _clientCard(BuildContext context) {
    final client = _client;
    return GestureDetector(
      onTap: client == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ClientDetailScreen(client: client),
              ),
            ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                client?.initials ?? '?',
                style: const TextStyle(
                  color: AppColors.onCream,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CLIENT',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _loadingClient
                        ? 'Loading…'
                        : client?.name ?? 'Client not found',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (client != null)
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textMuted,
              ),
          ],
        ),
      ),
    );
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _formatDate(DateTime d) {
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    final period = d.hour < 12 ? 'AM' : 'PM';
    return '${d.day} ${_months[d.month - 1]} ${d.year}, $hour12:$minute $period';
  }
}

class _SourceImage extends StatelessWidget {
  final String label;
  final String imageUrl;
  final String title;

  const _SourceImage({
    required this.label,
    required this.imageUrl,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openProjectImage(context, imageUrl: imageUrl, title: title),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, p) => p == null
                    ? child
                    : const ColoredBox(color: AppColors.surface),
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: AppColors.surface,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/estimate.dart';

/// Builds and shares a one-page tiling quotation PDF.
///
/// Currency in the PDF uses `Rs.` rather than ₹ because the bundled PDF font
/// (Helvetica) has no rupee glyph — on-screen UI still shows ₹.
class QuotationService {
  QuotationService._();
  static final instance = QuotationService._();

  /// Open the system share/save sheet with the generated quotation.
  Future<void> shareQuotation({
    required String tileName,
    required String tileSizeLabel,
    required String surfaceLabel,
    required Estimate estimate,
    required String clientName,
    String? clientPhone,
    String? clientEmail,
    String? preparedBy,
    String? renderImageUrl,
    required DateTime date,
  }) async {
    final bytes = await buildQuotationPdf(
      tileName: tileName,
      tileSizeLabel: tileSizeLabel,
      surfaceLabel: surfaceLabel,
      estimate: estimate,
      clientName: clientName,
      clientPhone: clientPhone,
      clientEmail: clientEmail,
      preparedBy: preparedBy,
      renderImageUrl: renderImageUrl,
      date: date,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: quotationFilename(clientName, estimate),
    );
  }

  /// Build the quotation PDF and return its bytes (used by share & WhatsApp).
  Future<Uint8List> buildQuotationPdf({
    required String tileName,
    required String tileSizeLabel,
    required String surfaceLabel,
    required Estimate estimate,
    required String clientName,
    String? clientPhone,
    String? clientEmail,
    String? preparedBy,
    String? renderImageUrl,
    required DateTime date,
  }) async {
    final preview = await _imageBytes(renderImageUrl);
    return _build(
      tileName: tileName,
      tileSizeLabel: tileSizeLabel,
      surfaceLabel: surfaceLabel,
      estimate: estimate,
      clientName: clientName,
      clientPhone: clientPhone,
      clientEmail: clientEmail,
      preparedBy: preparedBy,
      date: date,
      preview: preview,
    );
  }

  /// Stable, filesystem-safe filename for a quotation, e.g.
  /// "Quotation_Anjali_Mehta_GST.pdf".
  static String quotationFilename(String clientName, Estimate estimate) {
    final safeName = clientName.trim().isEmpty
        ? 'client'
        : clientName.trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final tag = estimate.hasGst ? 'GST' : 'NoGST';
    return 'Quotation_${safeName}_$tag.pdf';
  }

  Future<Uint8List> _build({
    required String tileName,
    required String tileSizeLabel,
    required String surfaceLabel,
    required Estimate estimate,
    required String clientName,
    String? clientPhone,
    String? clientEmail,
    String? preparedBy,
    required DateTime date,
    Uint8List? preview,
  }) async {
    final doc = pw.Document();
    final accent = PdfColor.fromInt(0xFF111112);
    final muted = PdfColor.fromInt(0xFF6B6B70);
    final line = PdfColor.fromInt(0xFFDDDDD8);
    final cream = PdfColor.fromInt(0xFFF6F4EC);

    String money(double v) => Estimate.formatCurrency(v, symbol: 'Rs. ');

    final previewImage = preview == null ? null : pw.MemoryImage(preview);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'SPACIO',
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 1,
                          color: accent,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        estimate.hasGst
                            ? 'Tile Quotation (incl. GST)'
                            : 'Tile Quotation (without GST)',
                        style: pw.TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Date',
                        style: pw.TextStyle(fontSize: 9, color: muted),
                      ),
                      pw.Text(
                        _formatDate(date),
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 14),
              pw.Divider(color: line, thickness: 1),
              pw.SizedBox(height: 14),

              // ── Prepared for + tile details + preview ──────────────────
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('PREPARED FOR'),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          clientName.isEmpty ? 'Client' : clientName,
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        if ((clientPhone ?? '').isNotEmpty)
                          pw.Text(
                            clientPhone!,
                            style: pw.TextStyle(color: muted, fontSize: 10),
                          ),
                        if ((clientEmail ?? '').isNotEmpty)
                          pw.Text(
                            clientEmail!,
                            style: pw.TextStyle(color: muted, fontSize: 10),
                          ),
                        pw.SizedBox(height: 18),
                        _sectionLabel('TILE'),
                        pw.SizedBox(height: 4),
                        _detailRow('Name', tileName.isEmpty ? '—' : tileName),
                        _detailRow(
                          'Size',
                          tileSizeLabel.isEmpty ? '—' : tileSizeLabel,
                        ),
                        _detailRow(
                          'Applied to',
                          surfaceLabel.isEmpty ? '—' : surfaceLabel,
                        ),
                        _detailRow(
                          'Price / sq ft',
                          money(estimate.pricePerSqFt),
                        ),
                      ],
                    ),
                  ),
                  if (previewImage != null) ...[
                    pw.SizedBox(width: 16),
                    pw.ClipRRect(
                      horizontalRadius: 8,
                      verticalRadius: 8,
                      child: pw.Image(
                        previewImage,
                        width: 300,
                        height: 300,
                        fit: pw.BoxFit.cover,
                      ),
                    ),
                  ],
                ],
              ),
              pw.SizedBox(height: 24),

              // ── Estimate table ──────────────────────────────────────────
              _sectionLabel('ESTIMATE'),
              pw.SizedBox(height: 8),
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: line),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  children: [
                    _estimateRow(
                      'Area',
                      '${_trimNum(estimate.areaSqFt)} sq ft',
                      line: line,
                    ),
                    if (estimate.tilesNeeded != null)
                      _estimateRow(
                        'Tiles needed',
                        '${estimate.tilesNeeded} pcs',
                        line: line,
                      ),
                    _estimateRow(
                      'Material cost  (${_trimNum(estimate.areaSqFt)} × ${money(estimate.pricePerSqFt)})',
                      money(estimate.materialCost),
                      line: line,
                    ),
                    _estimateRow(
                      'Cartage fee',
                      money(estimate.cartageFee),
                      line: line,
                    ),
                    if (estimate.hasGst) ...[
                      _estimateRow(
                        'Subtotal (excl. GST)',
                        money(estimate.approxTotalCost),
                        line: line,
                      ),
                      _estimateRow(
                        'GST (${_trimNum(estimate.gstPercent)}%)',
                        money(estimate.gstAmount),
                        line: line,
                      ),
                    ],
                    pw.Container(
                      color: cream,
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            estimate.hasGst
                                ? 'Total (incl. GST)'
                                : 'Approx. Total Cost',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          pw.Text(
                            money(
                              estimate.hasGst
                                  ? estimate.totalWithGst
                                  : estimate.approxTotalCost,
                            ),
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              pw.Spacer(),
              pw.Divider(color: line, thickness: 1),
              pw.SizedBox(height: 6),
              pw.Text(
                'This is an approximate estimate covering tile material and '
                'cartage'
                '${estimate.hasGst ? ' with ${_trimNum(estimate.gstPercent)}% GST' : ' (GST not included)'}. '
                'Final cost may vary with site conditions, layout, grouting and '
                'labour.',
                style: pw.TextStyle(fontSize: 8.5, color: muted),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                preparedBy == null || preparedBy.isEmpty
                    ? 'Generated by Spacio'
                    : 'Prepared by $preparedBy · Generated by Spacio',
                style: pw.TextStyle(fontSize: 8.5, color: muted),
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _sectionLabel(String text) => pw.Text(
    text,
    style: pw.TextStyle(
      fontSize: 9,
      letterSpacing: 1.2,
      fontWeight: pw.FontWeight.bold,
      color: PdfColor.fromInt(0xFF9A9A9F),
    ),
  );

  static pw.Widget _detailRow(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(
      children: [
        pw.SizedBox(
          width: 80,
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfColor.fromInt(0xFF6B6B70),
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
        ),
      ],
    ),
  );

  static pw.Widget _estimateRow(
    String label,
    String value, {
    required PdfColor line,
  }) => pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: line)),
    ),
    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(
          child: pw.Text(label, style: const pw.TextStyle(fontSize: 10.5)),
        ),
        pw.SizedBox(width: 12),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );

  /// Drop a trailing `.0` so 120.0 prints as "120" but 12.5 stays "12.5".
  static String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  static String _formatDate(DateTime d) {
    const months = [
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
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  /// Decode a `data:` URL or download an http(s) image; null on any failure.
  Future<Uint8List?> _imageBytes(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      if (url.startsWith('data:')) {
        final comma = url.indexOf(',');
        if (comma == -1) return null;
        return base64Decode(url.substring(comma + 1));
      }
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return null;
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }
}

import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One PDF to attach to a quotation email (e.g. the with-GST and without-GST
/// copies).
class QuotationAttachment {
  final Uint8List bytes;
  final String filename;
  const QuotationAttachment({required this.bytes, required this.filename});
}

/// Emails quotation PDFs to a client via the `send-quotation-email` Supabase
/// Edge Function (Resend).
///
/// The PDF bytes are sent inline (base64) to the Edge Function — which holds
/// the email API key server-side — so nothing needs to be publicly hosted, and
/// the client gets a single email with every attachment.
class EmailService {
  EmailService._();
  static final instance = EmailService._();

  static const _functionName = 'send-quotation-email';

  Future<void> sendQuotation({
    required List<QuotationAttachment> attachments,
    required String toEmail,
    required String clientName,
    String? summary,
  }) async {
    if (attachments.isEmpty) {
      throw ArgumentError('At least one attachment is required.');
    }

    final encoded = attachments
        .map((a) => {'filename': a.filename, 'content': base64Encode(a.bytes)})
        .toList();

    final res = await Supabase.instance.client.functions.invoke(
      _functionName,
      body: {
        'toEmail': toEmail,
        'clientName': clientName,
        'attachments': encoded,
        'summary': ?summary,
      },
    );

    if (res.status != 200) {
      final data = res.data;
      final detail = data is Map && data['error'] != null
          ? data['error']
          : 'status ${res.status}';
      throw Exception('Email send failed: $detail');
    }
  }
}

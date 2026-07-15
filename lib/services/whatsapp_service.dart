import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cloudinary_service.dart';

/// Sends a quotation PDF to a client over WhatsApp via the
/// `send-whatsapp-quotation` Supabase Edge Function (Meta Cloud API).
///
/// The PDF is hosted on Cloudinary first (WhatsApp needs a public URL), then
/// the Edge Function — which holds the WhatsApp token server-side — delivers it.
class WhatsappService {
  WhatsappService._();
  static final instance = WhatsappService._();

  static const _functionName = 'send-whatsapp-quotation';

  Future<void> sendQuotation({
    required Uint8List pdfBytes,
    required String toPhone,
    required String clientName,
    required String filename,
    String? summary,
  }) async {
    // 1. Host the PDF so WhatsApp's servers can fetch it.
    final pdfUrl = await CloudinaryService.instance.uploadPdfBytes(
      pdfBytes,
      filename: filename,
    );

    // 2. Ask the Edge Function to send it.
    final res = await Supabase.instance.client.functions.invoke(
      _functionName,
      body: {
        'toPhone': toPhone,
        'clientName': clientName,
        'pdfUrl': pdfUrl,
        'filename': filename,
        'summary': ?summary,
      },
    );

    if (res.status != 200) {
      final data = res.data;
      final detail = data is Map && data['error'] != null
          ? data['error']
          : 'status ${res.status}';
      throw Exception('WhatsApp send failed: $detail');
    }
  }
}

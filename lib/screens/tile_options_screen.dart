import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';
import '../models/catalogue_item.dart';
import '../models/client.dart';
import '../models/estimate.dart';
import '../models/tile_option.dart';
import '../services/supabase_service.dart';
import 'catalogue_picker_screen.dart';
import 'result_screen.dart';

class TileOptionsScreen extends StatefulWidget {
  final File image;
  const TileOptionsScreen({super.key, required this.image});

  @override
  State<TileOptionsScreen> createState() => _TileOptionsScreenState();
}

class _TileOptionsScreenState extends State<TileOptionsScreen> {
  final _picker = ImagePicker();
  File? _tileImage;
  RoomSurface _surface = RoomSurface.livingRoomWall;
  double _gstPercent = 18;
  final _clientName = TextEditingController();
  final _clientPhone = TextEditingController();
  final _clientEmail = TextEditingController();
  final _notes = TextEditingController();
  final _tileName = TextEditingController();
  final _tileWidth = TextEditingController();
  final _tileHeight = TextEditingController();
  final _tilePrice = TextEditingController();
  final _cartageFee = TextEditingController();
  final _area = TextEditingController();
  LengthUnit _sizeUnit = LengthUnit.mm;
  bool _submitting = false;

  /// Name of the catalogue product currently applied (null when a photo was
  /// taken manually), plus a flag while its hosted image downloads.
  String? _selectedCatalogueName;
  bool _applyingCatalogue = false;

  @override
  void dispose() {
    _clientName.dispose();
    _clientPhone.dispose();
    _clientEmail.dispose();
    _notes.dispose();
    _tileName.dispose();
    _tileWidth.dispose();
    _tileHeight.dispose();
    _tilePrice.dispose();
    _cartageFee.dispose();
    _area.dispose();
    super.dispose();
  }

  String? _trimmedOrNull(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _pickTile(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 1400,
    );
    if (picked == null) return;
    setState(() {
      _tileImage = File(picked.path);
      // A manually-taken photo is no longer "from the catalogue".
      _selectedCatalogueName = null;
    });
  }

  /// Pick a saved product from the catalogue instead of taking a photo. The
  /// hosted image is downloaded to a temp file so the rest of the generate
  /// pipeline (which expects a [File]) is unchanged, and the product's details
  /// prefill the tile fields below.
  Future<void> _pickFromCatalogue() async {
    if (_applyingCatalogue) return;
    final item = await Navigator.of(context).push<CatalogueItem>(
      MaterialPageRoute(builder: (_) => const CataloguePickerScreen()),
    );
    if (item == null || !mounted) return;
    setState(() => _applyingCatalogue = true);
    try {
      final file = await _downloadToFile(item.imageUrl);
      if (!mounted) return;
      setState(() {
        _tileImage = file;
        _selectedCatalogueName = item.name;
        _tileName.text = item.name;
        _tileWidth.text = _numStr(item.width);
        _tileHeight.text = _numStr(item.height);
        _tilePrice.text = _numStr(item.pricePerSqFt);
        _sizeUnit = item.sizeUnit;
        if (Estimate.gstSlabs.contains(item.gstPercent)) {
          _gstPercent = item.gstPercent;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load the catalogue image: $e')),
      );
    } finally {
      if (mounted) setState(() => _applyingCatalogue = false);
    }
  }

  /// Download a hosted image to a temp file, preserving its extension so the
  /// OpenAI upload sends the right content type.
  Future<File> _downloadToFile(String url) async {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/catalogue_$stamp${_extFor(url)}');
    await file.writeAsBytes(res.bodyBytes);
    return file;
  }

  String _extFor(String url) {
    final path = Uri.parse(url).path.toLowerCase();
    if (path.endsWith('.png')) return '.png';
    if (path.endsWith('.webp')) return '.webp';
    return '.jpg';
  }

  static String _numStr(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  }

  Future<void> _generate() async {
    if (_submitting || _tileImage == null) return;
    final clientName = _clientName.text.trim();
    if (clientName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter the client's name to continue.")),
      );
      return;
    }
    final clientPhone = _clientPhone.text.trim();
    if (clientPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter the client's contact number.")),
      );
      return;
    }
    final tile = TileOption(
      tileImage: _tileImage!,
      surface: _surface,
      additionalNotes: _notes.text,
      tileName: _tileName.text.trim(),
      tileWidth: double.tryParse(_tileWidth.text.trim()),
      tileHeight: double.tryParse(_tileHeight.text.trim()),
      tileSizeUnit: _sizeUnit,
      pricePerSqFt: double.tryParse(_tilePrice.text.trim()),
      cartageFee: double.tryParse(_cartageFee.text.trim()),
      gstPercent: _gstPercent,
    );

    // Save the contact to the CRM up front so it shows in Clients even if the
    // render or the Cloudinary upload later fails. Best-effort: a failure here
    // never blocks the visualization — _persist() retries when saving.
    setState(() => _submitting = true);
    Client? client;
    if (AppConfig.isConfigured) {
      try {
        client = await SupabaseService.instance.findOrCreateClient(
          name: clientName,
          phone: clientPhone,
          email: _trimmedOrNull(_clientEmail),
        );
      } catch (_) {
        // Ignore — the render flow continues and persistence is retried later.
      }
    }
    if (!mounted) return;
    setState(() => _submitting = false);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          image: widget.image,
          tile: tile,
          client: client,
          clientName: clientName,
          clientPhone: clientPhone,
          clientEmail: _trimmedOrNull(_clientEmail),
          initialArea: double.tryParse(_area.text.trim()),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tile reference')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _label('Client name *'),
          TextField(
            controller: _clientName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'e.g. Anjali Mehta',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          _label('Contact number *'),
          TextField(
            controller: _clientPhone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              hintText: '+91 98765 43210',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          _label('Email'),
          TextField(
            controller: _clientEmail,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              hintText: 'client@email.com',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          _label('Client wall (Image 2)'),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              widget.image,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 24),
          _label('Tile photo (Image 1)'),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _applyingCatalogue ? null : _pickFromCatalogue,
              icon: _applyingCatalogue
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.grid_view_rounded),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _applyingCatalogue ? 'Loading…' : 'Choose from catalogue',
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'or upload a photo',
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: _tileImage == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.photo_size_select_actual_outlined,
                            size: 48,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 8),
                          const Text('Upload a clear close-up of the tile'),
                        ],
                      ),
                    )
                  : Image.file(_tileImage!, fit: BoxFit.cover),
            ),
          ),
          if (_selectedCatalogueName != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 15,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'From catalogue: ${_selectedCatalogueName!}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickTile(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('Gallery'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickTile(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('Camera'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _label('Tile name'),
          TextField(
            controller: _tileName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'e.g. Carrara Marble Gloss',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          _label('Tile size'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tileWidth,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: 'Width',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('×', style: TextStyle(fontSize: 18)),
              ),
              Expanded(
                child: TextField(
                  controller: _tileHeight,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: 'Height',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 92,
                child: DropdownButtonFormField<LengthUnit>(
                  initialValue: _sizeUnit,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(border: OutlineInputBorder()),
                  items: LengthUnit.values
                      .map((u) => DropdownMenuItem<LengthUnit>(
                            value: u,
                            child: Text(u.label),
                          ))
                      .toList(),
                  onChanged: (u) => setState(() => _sizeUnit = u ?? _sizeUnit),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _label('Price / sq ft (₹)'),
          TextField(
            controller: _tilePrice,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              hintText: '85',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          _label('Cartage fee (₹)'),
          TextField(
            controller: _cartageFee,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              hintText: 'e.g. 500',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Flat transport/delivery charge added to the quotation total.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          _label('Area (sq ft)'),
          TextField(
            controller: _area,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              hintText: 'e.g. 120',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Enter the area and a client email to auto-send the quotation once '
            'the visualization is ready.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          _label('GST slab'),
          DropdownButtonFormField<double>(
            initialValue: _gstPercent,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: Estimate.gstSlabs
                .map((v) => DropdownMenuItem<double>(
                      value: v,
                      child: Text('${v.toStringAsFixed(0)}%'),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _gstPercent = v ?? _gstPercent),
          ),
          const SizedBox(height: 6),
          Text(
            'Applied only to the "with GST" quotation. A non-GST copy is also '
            'available.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 24),
          _label('Apply tiles to'),
          DropdownButtonFormField<RoomSurface>(
            initialValue: _surface,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: RoomSurface.values
                .map((v) => DropdownMenuItem<RoomSurface>(
                      value: v,
                      child: Text(v.label),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _surface = v!),
          ),
          const SizedBox(height: 16),
          _label('Extra notes (optional)'),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'e.g. diagonal layout, dark grout, match daylight',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _tileImage == null || _submitting ? null : _generate,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _submitting ? 'Saving client…' : 'Generate visualizations',
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_tileImage == null)
            Text(
              'Upload a tile photo to continue.',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge),
      );
}

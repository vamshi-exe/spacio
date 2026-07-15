import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_config.dart';
import '../models/catalogue_item.dart';
import '../models/estimate.dart';
import '../models/tile_option.dart';
import '../services/cloudinary_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/catalogue_widgets.dart';
import 'auth/auth_widgets.dart';

/// Add a new catalogue product or edit an existing one. Returns `true` via
/// [Navigator.pop] when something changed, so the caller can refresh its list.
class CatalogueItemFormScreen extends StatefulWidget {
  /// Section to preselect when adding a brand-new item.
  final TileCategory category;
  final CatalogueItem? item;

  const CatalogueItemFormScreen({
    super.key,
    this.category = TileCategory.tiles,
    this.item,
  });

  bool get isEditing => item != null;

  @override
  State<CatalogueItemFormScreen> createState() =>
      _CatalogueItemFormScreenState();
}

class _CatalogueItemFormScreenState extends State<CatalogueItemFormScreen> {
  final _picker = ImagePicker();

  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _width = TextEditingController(text: _num(widget.item?.width));
  late final _height = TextEditingController(text: _num(widget.item?.height));
  late final _price =
      TextEditingController(text: _num(widget.item?.pricePerSqFt));
  final _customTag = TextEditingController();

  late TileCategory _category = widget.item?.category ?? widget.category;
  late LengthUnit _sizeUnit = widget.item?.sizeUnit ?? LengthUnit.mm;
  late double _gstPercent = widget.item?.gstPercent ?? 18;
  late final Set<String> _tags = {...?widget.item?.tags};

  /// A freshly-picked local image (replaces the existing one on save).
  File? _pickedImage;

  /// The already-hosted image URL when editing (kept if no new image is picked).
  late final String? _existingUrl = widget.item?.imageUrl;

  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _width.dispose();
    _height.dispose();
    _price.dispose();
    _customTag.dispose();
    super.dispose();
  }

  static String _num(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  }

  bool get _hasImage => _pickedImage != null || (_existingUrl?.isNotEmpty ?? false);

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 1400,
    );
    if (picked == null) return;
    setState(() => _pickedImage = File(picked.path));
  }

  void _addCustomTag() {
    final t = _customTag.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _tags.add(t);
      _customTag.clear();
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      _toast('Enter the product name.');
      return;
    }
    if (!_hasImage) {
      _toast('Add a photo of the tile or marble.');
      return;
    }
    if (_pickedImage != null && !AppConfig.isCloudinaryConfigured) {
      _toast('Image hosting is not configured yet.');
      return;
    }

    setState(() => _saving = true);
    try {
      // Only upload when a new image was picked; otherwise keep the hosted one.
      var imageUrl = _existingUrl ?? '';
      if (_pickedImage != null) {
        imageUrl = await CloudinaryService.instance
            .uploadFile(_pickedImage!, folder: 'tiles_ai/catalogue');
      }

      final svc = SupabaseService.instance;
      final tags = _tags.toList();
      final width = double.tryParse(_width.text.trim());
      final height = double.tryParse(_height.text.trim());
      final price = double.tryParse(_price.text.trim());

      if (widget.isEditing) {
        await svc.updateCatalogueItem(
          id: widget.item!.id,
          category: _category,
          name: name,
          imageUrl: imageUrl,
          width: width,
          height: height,
          sizeUnit: _sizeUnit,
          pricePerSqFt: price,
          gstPercent: _gstPercent,
          tags: tags,
        );
      } else {
        await svc.createCatalogueItem(
          category: _category,
          name: name,
          imageUrl: imageUrl,
          width: width,
          height: height,
          sizeUnit: _sizeUnit,
          pricePerSqFt: price,
          gstPercent: _gstPercent,
          tags: tags,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save: $e');
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Delete product?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Remove ${widget.item!.name} from your catalogue? This can\'t be '
          'undone.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _saving = true);
    try {
      await SupabaseService.instance.deleteCatalogueItem(widget.item!.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not delete: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    // Merge presets with any custom tags already on the item so all show up.
    final tagOptions = <String>[
      ...CatalogueItem.suggestedTags,
      ..._tags.where((t) => !CatalogueItem.suggestedTags.contains(t)),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.isEditing ? 'Edit product' : 'New product'),
        actions: [
          if (widget.isEditing)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            _label('Section'),
            CategorySelector(
              selected: _category,
              onChanged: (c) => setState(() => _category = c),
            ),
            const SizedBox(height: 20),

            _label('Product photo *'),
            _imagePicker(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text('Gallery'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined, size: 18),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text('Camera'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            AuthField(
              controller: _name,
              label: 'Product name *',
              hint: 'e.g. Carrara Marble Gloss',
              icon: Icons.label_outline_rounded,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 20),

            _label('Tile size'),
            _sizeRow(),
            const SizedBox(height: 20),

            AuthField(
              controller: _price,
              label: 'Price / sq ft (₹)',
              hint: 'e.g. 85',
              icon: Icons.currency_rupee_rounded,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 20),

            _label('GST slab'),
            DropdownButtonFormField<double>(
              initialValue: _gstPercent,
              isExpanded: true,
              dropdownColor: AppColors.card,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
              decoration: _dec(''),
              items: Estimate.gstSlabs
                  .map((v) => DropdownMenuItem<double>(
                        value: v,
                        child: Text('${v.toStringAsFixed(0)}%'),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _gstPercent = v ?? _gstPercent),
            ),
            const SizedBox(height: 20),

            _label('Tags'),
            const SizedBox(height: 2),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tagOptions.map(_tagToggle).toList(),
            ),
            const SizedBox(height: 12),
            _customTagField(),
            const SizedBox(height: 28),

            AuthButton(
              label: widget.isEditing ? 'Save changes' : 'Add to catalogue',
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePicker() {
    Widget child;
    if (_pickedImage != null) {
      child = Image.file(_pickedImage!, fit: BoxFit.cover);
    } else if (_existingUrl?.isNotEmpty ?? false) {
      child = Image.network(
        _existingUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _imagePlaceholder(),
      );
    } else {
      child = _imagePlaceholder();
    }
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(color: AppColors.card, child: child),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.photo_size_select_actual_outlined,
            size: 40,
            color: AppColors.textSecondary,
          ),
          SizedBox(height: 8),
          Text(
            'Add a clear close-up of the surface',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _sizeRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _width,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: _dec('Width'),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text('×', style: TextStyle(color: AppColors.textSecondary)),
        ),
        Expanded(
          child: TextField(
            controller: _height,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: _dec('Height'),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 92,
          child: DropdownButtonFormField<LengthUnit>(
            initialValue: _sizeUnit,
            isExpanded: true,
            dropdownColor: AppColors.card,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
            decoration: _dec(''),
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
    );
  }

  Widget _tagToggle(String tag) {
    final active = _tags.contains(tag);
    return GestureDetector(
      onTap: () => setState(() {
        active ? _tags.remove(tag) : _tags.add(tag);
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? AppColors.cream : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.cream : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active) ...[
              const Icon(Icons.check_rounded, size: 14, color: AppColors.onCream),
              const SizedBox(width: 5),
            ],
            Text(
              tag,
              style: TextStyle(
                color: active ? AppColors.onCream : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customTagField() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _customTag,
            style: const TextStyle(color: AppColors.textPrimary),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _addCustomTag(),
            decoration: _dec('Add a custom tag'),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 52,
          child: OutlinedButton(
            onPressed: _addCustomTag,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Icon(Icons.add_rounded, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        filled: true,
        fillColor: AppColors.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppColors.textSecondary, width: 1.4),
        ),
      );
}

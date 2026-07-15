import 'package:flutter/material.dart';
import '../models/catalogue_item.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/catalogue_widgets.dart';
import 'catalogue_item_form_screen.dart';

/// Browse the merchant's catalogue and pick a product for a visualization.
/// Pops the chosen [CatalogueItem] back to the tile screen.
class CataloguePickerScreen extends StatefulWidget {
  const CataloguePickerScreen({super.key});

  @override
  State<CataloguePickerScreen> createState() => _CataloguePickerScreenState();
}

class _CataloguePickerScreenState extends State<CataloguePickerScreen> {
  final _search = TextEditingController();
  List<CatalogueItem> _all = const [];
  TileCategory _category = TileCategory.tiles;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await SupabaseService.instance.listCatalogueItems();
      if (!mounted) return;
      setState(() {
        _all = items;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your catalogue.';
        _loading = false;
      });
    }
  }

  Future<void> _addNew() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CatalogueItemFormScreen(category: _category),
      ),
    );
    if (added == true) _load();
  }

  List<CatalogueItem> get _visible {
    final q = _search.text.trim().toLowerCase();
    return _all
        .where((i) => i.category == _category)
        .where((i) => q.isEmpty || i.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Choose from catalogue'),
        actions: [
          IconButton(
            tooltip: 'Add product',
            icon: const Icon(Icons.add_rounded),
            onPressed: _addNew,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: CategorySelector(
                selected: _category,
                onChanged: (c) => setState(() => _category = c),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search ${_category.label.toLowerCase()}…',
                  hintStyle:
                      const TextStyle(color: AppColors.textMuted, fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 20, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.card,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: AppColors.textSecondary, width: 1.4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(child: _body(items)),
          ],
        ),
      ),
    );
  }

  Widget _body(List<CatalogueItem> items) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.cream),
      );
    }
    if (_error != null) {
      return Center(
        child: Text(_error!,
            style: const TextStyle(color: AppColors.textSecondary)),
      );
    }
    if (items.isEmpty) {
      return _EmptyCatalogue(category: _category, onAdd: _addNew);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _PickerCard(
        item: items[i],
        onTap: () => Navigator.of(context).pop(items[i]),
      ),
    );
  }
}

class _PickerCard extends StatelessWidget {
  final CatalogueItem item;
  final VoidCallback onTap;

  const _PickerCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 64,
                height: 64,
                child: item.imageUrl.isEmpty
                    ? const ColoredBox(
                        color: AppColors.surface,
                        child: Icon(Icons.grid_view_rounded,
                            size: 22, color: AppColors.textSecondary),
                      )
                    : Image.network(
                        item.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: AppColors.surface,
                          child: Icon(Icons.broken_image_outlined,
                              size: 22, color: AppColors.textSecondary),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.detailLine.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.detailLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  if (item.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children:
                          item.tags.take(3).map((t) => TagChip(t)).toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _EmptyCatalogue extends StatelessWidget {
  final TileCategory category;
  final VoidCallback onAdd;

  const _EmptyCatalogue({required this.category, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.grid_view_rounded,
                size: 34, color: AppColors.textSecondary),
            const SizedBox(height: 14),
            Text(
              'No ${category.label.toLowerCase()} saved yet',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add ${category.label.toLowerCase()} to your catalogue to reuse '
              'them without taking a photo.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAdd,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.cream,
                foregroundColor: AppColors.onCream,
              ),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add product'),
            ),
          ],
        ),
      ),
    );
  }
}

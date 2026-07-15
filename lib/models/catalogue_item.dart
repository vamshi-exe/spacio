import 'tile_option.dart';

/// The two sections a merchant organises catalogue products into.
enum TileCategory {
  tiles('Tiles'),
  marbles('Marbles');

  final String label;
  const TileCategory(this.label);

  /// Parse the value stored in the `category` column back to an enum.
  static TileCategory fromName(String? name) => TileCategory.values.firstWhere(
        (c) => c.name == name,
        orElse: () => TileCategory.tiles,
      );
}

/// A product saved to the merchant's catalogue. Reused on the tile screen so a
/// rep can pick a tile or marble without photographing it — the stored image
/// and its details (size, price, GST) prefill the visualization and estimate.
class CatalogueItem {
  final String id;
  final TileCategory category;
  final String name;
  final String imageUrl;
  final double? width;
  final double? height;
  final LengthUnit sizeUnit;
  final double? pricePerSqFt;

  /// GST slab to apply on the "with GST" quotation (e.g. 18 for tiles).
  final double gstPercent;

  /// Merchant-defined highlight labels, e.g. "Hot Selling", "Top Picks".
  final List<String> tags;
  final DateTime createdAt;

  const CatalogueItem({
    required this.id,
    required this.category,
    required this.name,
    required this.imageUrl,
    this.width,
    this.height,
    this.sizeUnit = LengthUnit.mm,
    this.pricePerSqFt,
    this.gstPercent = 18,
    this.tags = const [],
    required this.createdAt,
  });

  /// Common presets offered in the form; merchants can also add their own.
  static const suggestedTags = [
    'Hot Selling',
    'Top Picks',
    'New Arrival',
    'Best Value',
    'Premium',
    'On Offer',
  ];

  factory CatalogueItem.fromMap(Map<String, dynamic> map) {
    return CatalogueItem(
      id: map['id'] as String,
      category: TileCategory.fromName(map['category'] as String?),
      name: (map['name'] as String?) ?? 'Untitled',
      imageUrl: (map['image_url'] as String?) ?? '',
      width: (map['width'] as num?)?.toDouble(),
      height: (map['height'] as num?)?.toDouble(),
      sizeUnit: LengthUnit.values.firstWhere(
        (u) => u.name == map['size_unit'],
        orElse: () => LengthUnit.mm,
      ),
      pricePerSqFt: (map['price_per_sqft'] as num?)?.toDouble(),
      gstPercent: (map['gst_percent'] as num?)?.toDouble() ?? 18,
      tags:
          (map['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }

  /// Human-readable size, e.g. "600 × 600 mm" — empty when incomplete.
  String get sizeLabel {
    final w = width, h = height;
    if (w == null || h == null) return '';
    return '${_trim(w)} × ${_trim(h)} ${sizeUnit.label}';
  }

  bool get hasPrice => pricePerSqFt != null && pricePerSqFt! > 0;

  /// Compact "size · ₹price" subtitle used on cards — empty when nothing is set.
  String get detailLine {
    final parts = <String>[];
    if (sizeLabel.isNotEmpty) parts.add(sizeLabel);
    if (hasPrice) parts.add('₹${_trim(pricePerSqFt!)}/sqft');
    return parts.join('  ·  ');
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

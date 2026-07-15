import 'tile_option.dart';

/// A saved visualization row from the `projects` table.
class Project {
  final String id;
  final String name;
  final String surface;
  final String? clientId;
  final String? roomImageUrl;
  final String? tileImageUrl;
  final String? resultImageUrl;
  final String notes;
  final DateTime createdAt;

  /// Tile & estimate details captured at creation so a quotation PDF can be
  /// regenerated later. All optional — older rows predate these columns.
  final String tileName;
  final double? tileWidth;
  final double? tileHeight;
  final LengthUnit tileSizeUnit;
  final double? pricePerSqFt;
  final double? cartageFee;
  final double gstPercent;
  final double? areaSqFt;

  const Project({
    required this.id,
    required this.name,
    required this.surface,
    required this.clientId,
    required this.roomImageUrl,
    required this.tileImageUrl,
    required this.resultImageUrl,
    required this.notes,
    required this.createdAt,
    this.tileName = '',
    this.tileWidth,
    this.tileHeight,
    this.tileSizeUnit = LengthUnit.mm,
    this.pricePerSqFt,
    this.cartageFee,
    this.gstPercent = 18,
    this.areaSqFt,
  });

  factory Project.fromMap(Map<String, dynamic> map) {
    return Project(
      id: map['id'] as String,
      name: (map['name'] as String?) ?? 'Untitled',
      surface: (map['surface'] as String?) ?? '',
      clientId: map['client_id'] as String?,
      roomImageUrl: map['room_image_url'] as String?,
      tileImageUrl: map['tile_image_url'] as String?,
      resultImageUrl: map['result_image_url'] as String?,
      notes: (map['notes'] as String?) ?? '',
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
      tileName: (map['tile_name'] as String?) ?? '',
      tileWidth: (map['tile_width'] as num?)?.toDouble(),
      tileHeight: (map['tile_height'] as num?)?.toDouble(),
      tileSizeUnit: LengthUnit.values.asNameMap()[map['size_unit']] ??
          LengthUnit.mm,
      pricePerSqFt: (map['price_per_sqft'] as num?)?.toDouble(),
      cartageFee: (map['cartage_fee'] as num?)?.toDouble(),
      gstPercent: (map['gst_percent'] as num?)?.toDouble() ?? 18,
      areaSqFt: (map['area_sqft'] as num?)?.toDouble(),
    );
  }

  /// Human-readable tile size, e.g. "600 × 600 mm" — empty when not saved.
  String get tileSizeLabel {
    final w = tileWidth, h = tileHeight;
    if (w == null || h == null) return '';
    return '${_trim(w)} × ${_trim(h)} ${tileSizeUnit.label}';
  }

  /// Area of one tile in square feet, or null when the size is incomplete.
  double? get tileAreaSqFt {
    final w = tileWidth, h = tileHeight;
    if (w == null || h == null) return null;
    final area = tileSizeUnit.toFeet(w) * tileSizeUnit.toFeet(h);
    return area > 0 ? area : null;
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  /// Relative timestamp like "12 min ago" / "Yesterday".
  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h hr${h == 1 ? '' : 's'} ago';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    final weeks = (diff.inDays / 7).floor();
    return '$weeks wk${weeks == 1 ? '' : 's'} ago';
  }
}

import 'dart:io';

enum RoomSurface {
  livingRoomWall('Living room wall'),
  livingRoomFloor('Living room floor'),
  kitchenBacksplash('Kitchen backsplash'),
  kitchenFloor('Kitchen floor'),
  bathroomWall('Bathroom wall'),
  bathroomFloor('Bathroom floor'),
  bedroomFloor('Bedroom floor'),
  staircaseSteps('Staircase steps'),
  staircaseWall('Staircase wall'),
  exteriorWall('Exterior wall'),
  exteriorFloor('Exterior / patio floor');

  final String label;
  const RoomSurface(this.label);
}

/// Units a tile's dimensions can be entered in. [perFoot] is how many of this
/// unit make one foot, used to convert dimensions to square feet.
enum LengthUnit {
  mm('mm', 304.8),
  cm('cm', 30.48),
  inch('in', 12),
  ft('ft', 1);

  final String label;
  final double perFoot;
  const LengthUnit(this.label, this.perFoot);

  /// Convert a value in this unit to feet.
  double toFeet(double value) => value / perFoot;
}

class TileOption {
  final File tileImage;
  final RoomSurface surface;
  final String additionalNotes;

  /// Catalogue details used by the estimate / quotation. All optional so the
  /// visualization still works when the rep skips them.
  final String tileName;
  final double? tileWidth;
  final double? tileHeight;
  final LengthUnit tileSizeUnit;
  final double? pricePerSqFt;

  /// Flat cartage (transport) fee in rupees, added to the estimate total.
  final double? cartageFee;

  /// GST slab to apply on the "with GST" quotation (e.g. 18 for tiles).
  final double gstPercent;

  const TileOption({
    required this.tileImage,
    required this.surface,
    this.additionalNotes = '',
    this.tileName = '',
    this.tileWidth,
    this.tileHeight,
    this.tileSizeUnit = LengthUnit.mm,
    this.pricePerSqFt,
    this.cartageFee,
    this.gstPercent = 18,
  });

  /// Human-readable size, e.g. "600 × 600 mm" — empty when not provided.
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
}

class GeneratedResult {
  final String imageUrl;
  final String revisedPrompt;

  const GeneratedResult({
    required this.imageUrl,
    required this.revisedPrompt,
  });
}

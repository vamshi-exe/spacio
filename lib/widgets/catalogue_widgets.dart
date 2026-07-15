import 'package:flutter/material.dart';
import '../models/catalogue_item.dart';
import '../theme/app_theme.dart';

/// Two-pill segmented control to switch between the Tiles and Marbles sections.
/// Shared by the home catalogue section, the add/edit form and the picker.
class CategorySelector extends StatelessWidget {
  final TileCategory selected;
  final ValueChanged<TileCategory> onChanged;

  const CategorySelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: TileCategory.values.map((c) {
          final active = c == selected;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? AppColors.cream : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  c.label,
                  style: TextStyle(
                    color: active ? AppColors.onCream : AppColors.textSecondary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Small highlight pill used to render a catalogue item's tags.
class TagChip extends StatelessWidget {
  final String label;
  final bool small;

  const TagChip(this.label, {super.key, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 7 : 10,
        vertical: small ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: AppColors.cream.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cream.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: small ? 9.5 : 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

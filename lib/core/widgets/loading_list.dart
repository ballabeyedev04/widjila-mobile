import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_colors.dart';

/// Squelette de chargement pour les listes (chantiers, réserves...) —
/// équivalent de `admin/src/components/... shimmer`. Évite un écran blanc/
/// spinner isolé pendant le premier chargement d'une liste paginée.
class LoadingList extends StatelessWidget {
  final int itemCount;
  final double itemHeight;

  const LoadingList({super.key, this.itemCount = 6, this.itemHeight = 88});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.border,
      highlightColor: AppColors.background,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, _) => Container(
          height: itemHeight,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}

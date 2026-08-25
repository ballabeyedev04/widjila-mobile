import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Teinte sémantique — miroir de `admin/src/utils/constants.js` (STATUTS_*,
/// `tone: 'primary'|'info'|'success'|'warning'|'danger'|'neutral'`) pour que
/// les statuts (chantier, réserve, inspection...) s'affichent de façon
/// cohérente entre web et mobile.
enum BadgeTone { primary, info, success, warning, danger, neutral }

/// Couleurs d'une teinte — publiques car les cartes riches (sélecteur de
/// chantier, fiche d'intervenant) reprennent la MÊME teinte que la pastille
/// pour leur liseré et leur icône : sans cela, chaque écran redéfinirait sa
/// propre correspondance statut → couleur et elles finiraient par diverger.
extension BadgeToneColors on BadgeTone {
  Color get fg {
    switch (this) {
      case BadgeTone.primary:
        return AppColors.primary;
      case BadgeTone.info:
        return AppColors.info;
      case BadgeTone.success:
        return AppColors.success;
      case BadgeTone.warning:
        return AppColors.warning;
      case BadgeTone.danger:
        return AppColors.danger;
      case BadgeTone.neutral:
        return AppColors.neutral;
    }
  }

  Color get bg {
    switch (this) {
      case BadgeTone.primary:
        return AppColors.primary.withValues(alpha: 0.12);
      case BadgeTone.info:
        return AppColors.infoBg;
      case BadgeTone.success:
        return AppColors.successBg;
      case BadgeTone.warning:
        return AppColors.warningBg;
      case BadgeTone.danger:
        return AppColors.dangerBg;
      case BadgeTone.neutral:
        return AppColors.neutralBg;
    }
  }
}

/// Pastille de statut — équivalent de `admin/src/components/Badge.jsx`.
class StatusBadge extends StatelessWidget {
  final String label;
  final BadgeTone tone;

  const StatusBadge({super.key, required this.label, this.tone = BadgeTone.neutral});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: TextStyle(color: tone.fg, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

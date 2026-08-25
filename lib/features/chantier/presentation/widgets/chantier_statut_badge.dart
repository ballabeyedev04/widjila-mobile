import 'package:flutter/material.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/chantier.dart';

/// Teintes alignées sur `admin/src/utils/constants.js#STATUTS_CHANTIER`.
///
/// Exposée en fonction libre — et non enfermée dans le widget — parce que le
/// sélecteur de chantier colore aussi le liseré et l'icône de ses cartes avec
/// cette teinte : une seule table de correspondance, donc pas de dérive
/// possible entre la pastille et le reste de la carte.
BadgeTone toneStatutChantier(ChantierStatut statut) {
  switch (statut) {
    case ChantierStatut.enPreparation:
      return BadgeTone.info;
    case ChantierStatut.enCours:
      return BadgeTone.success;
    case ChantierStatut.enPause:
      return BadgeTone.warning;
    case ChantierStatut.archive:
      return BadgeTone.neutral;
    case ChantierStatut.cloture:
      return BadgeTone.danger;
  }
}

/// Icône par statut — donne à chaque état une silhouette reconnaissable dans
/// les puces de filtre et sur la tuile des cartes, là où la seule couleur ne
/// suffirait pas (et ne dirait rien à un daltonien).
IconData iconeStatutChantier(ChantierStatut statut) {
  switch (statut) {
    case ChantierStatut.enPreparation:
      return Icons.pending_actions_rounded;
    case ChantierStatut.enCours:
      return Icons.construction_rounded;
    case ChantierStatut.enPause:
      return Icons.pause_circle_outline_rounded;
    case ChantierStatut.archive:
      return Icons.inventory_2_outlined;
    case ChantierStatut.cloture:
      return Icons.task_alt_rounded;
  }
}

class ChantierStatutBadge extends StatelessWidget {
  final ChantierStatut statut;
  const ChantierStatutBadge({super.key, required this.statut});

  @override
  Widget build(BuildContext context) =>
      StatusBadge(label: statut.label(context.l10n), tone: toneStatutChantier(statut));
}

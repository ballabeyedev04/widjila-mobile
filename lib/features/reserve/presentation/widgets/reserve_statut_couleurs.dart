import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/reserve.dart';

/// Couleur d'un statut dans les GRAPHIQUES (donut, légendes, courbes).
///
/// Les badges partagent un ton par famille (trois statuts « danger », quatre
/// « warning »…) : lisible sur une carte, illisible sur un disque où deux
/// parts de la même couleur ne se distinguent plus. Chaque statut reçoit donc
/// ici SA teinte, la même partout où il est dessiné — la légende d'à côté
/// n'a de sens que si elle utilise exactement les couleurs du disque.
///
/// Les statuts du client reprennent les couleurs de son ancien outil, qu'il
/// connaît : en retard rouge, à surveiller orange, à échéance bleu, traitée
/// violet, refusée noir, levée gris.
Color couleurStatutGraphique(ReserveStatut s) {
  switch (s) {
    case ReserveStatut.creee:
      return AppColors.neutral;
    case ReserveStatut.affectee:
      return const Color(0xFF60A5FA);
    case ReserveStatut.priseEnCharge:
      return const Color(0xFF0EA5E9);
    case ReserveStatut.enCours:
      return AppColors.warning;
    case ReserveStatut.aSurveiller:
      return const Color(0xFFF97316);
    case ReserveStatut.aEcheance:
      return AppColors.info;
    case ReserveStatut.corrigee:
      return AppColors.primary;
    case ReserveStatut.traitee:
      return const Color(0xFF7C3AED);
    case ReserveStatut.aVerifier:
      return AppColors.accent;
    case ReserveStatut.validee:
      return AppColors.success;
    case ReserveStatut.levee:
      return const Color(0xFF9CA3AF);
    case ReserveStatut.refusee:
      return const Color(0xFF111827);
    case ReserveStatut.rouverte:
      return const Color(0xFFE11D48);
    case ReserveStatut.enRetard:
      return AppColors.danger;
    case ReserveStatut.cloturee:
      return const Color(0xFF475569);
  }
}

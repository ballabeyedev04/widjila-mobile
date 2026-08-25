import 'package:flutter/material.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/reserve.dart';

/// Teintes alignées sur `admin/src/utils/constants.js#STATUTS_RESERVE`.
class ReserveStatutBadge extends StatelessWidget {
  final ReserveStatut statut;
  const ReserveStatutBadge({super.key, required this.statut});

  BadgeTone get _tone {
    switch (statut) {
      case ReserveStatut.creee:
        return BadgeTone.neutral;
      case ReserveStatut.affectee:
        return BadgeTone.info;
      case ReserveStatut.priseEnCharge:
        return BadgeTone.info;
      case ReserveStatut.enCours:
        return BadgeTone.warning;
      case ReserveStatut.corrigee:
        return BadgeTone.primary;
      case ReserveStatut.aVerifier:
        return BadgeTone.warning;
      case ReserveStatut.validee:
        return BadgeTone.success;
      case ReserveStatut.refusee:
        return BadgeTone.danger;
      case ReserveStatut.rouverte:
        return BadgeTone.danger;
      case ReserveStatut.enRetard:
        return BadgeTone.danger;
      case ReserveStatut.cloturee:
        return BadgeTone.neutral;
    }
  }

  @override
  Widget build(BuildContext context) => StatusBadge(label: statut.label(context.l10n), tone: _tone);
}

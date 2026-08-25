import '../../../core/config/user_role.dart';
import 'entities/reserve.dart';

/// Statuts « verdict » — miroir de `STATUTS_CONTROLE` côté back
/// (`reserve.service.js`). Prononcer un verdict est réservé aux rôles de
/// pilotage ([UserRoleX.peutPiloter]) ; les proposer à un autre rôle ne
/// ferait qu'offrir un bouton que le serveur refusera systématiquement.
const _statutsVerdict = {
  ReserveStatut.validee,
  ReserveStatut.refusee,
  ReserveStatut.cloturee,
  ReserveStatut.rouverte,
};

/// Statuts qu'un sous-traitant peut lui-même déclarer — miroir de
/// `STATUTS_SOUS_TRAITANT` côté back (`reserve.service.js`).
const _statutsSousTraitant = {
  ReserveStatut.priseEnCharge,
  ReserveStatut.enCours,
  ReserveStatut.corrigee,
};

/// Statuts proposables depuis l'écran de détail, compte tenu du rôle courant
/// et du statut actuel de la réserve.
///
/// Fonction PURE (aucune dépendance Flutter/BLoC) — reflète côté client la
/// même politique que `ReserveService.changerStatut` côté back, pour éviter
/// de proposer une action que le serveur refusera systématiquement. Le
/// serveur reste la seule autorité réelle : cette fonction n'est qu'un
/// filtre d'affichage, jamais un contrôle de sécurité.
List<ReserveStatut> statutsProposables({
  required ReserveStatut statutActuel,
  required UserRole role,
  required bool estAssigneAMoi,
}) {
  final autres = ReserveStatut.values.where((s) => s != statutActuel);

  if (role == UserRole.sousTraitant) {
    if (!estAssigneAMoi) return const [];
    return autres.where(_statutsSousTraitant.contains).toList();
  }

  if (!role.peutPiloter) {
    return autres.where((s) => !_statutsVerdict.contains(s)).toList();
  }

  return autres.toList();
}

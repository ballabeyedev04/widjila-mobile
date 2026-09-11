import '../../../core/config/user_role.dart';
import 'entities/reserve.dart';

/// Statuts « verdict » — miroir de `STATUTS_CONTROLE` côté back
/// (`reserve.service.js:38`). Prononcer un verdict est réservé aux rôles de
/// pilotage ([UserRoleX.peutPiloter]) ; les proposer à un autre rôle ne
/// ferait qu'offrir un bouton que le serveur refusera systématiquement.
const _statutsVerdict = {
  ReserveStatut.validee,
  ReserveStatut.refusee,
  ReserveStatut.cloturee,
  ReserveStatut.rouverte,
};

/// Statuts qu'un sous-traitant peut lui-même déclarer — miroir de
/// `STATUTS_SOUS_TRAITANT` côté back (`reserve.service.js:22`).
const _statutsSousTraitant = {
  ReserveStatut.priseEnCharge,
  ReserveStatut.enCours,
  ReserveStatut.corrigee,
};

/// Matrice des transitions autorisées — miroir EXACT de `TRANSITIONS`
/// (`backend/src/modules/reserve/service/reserve.service.js:44-60`).
///
/// ── Pourquoi la dupliquer ici ─────────────────────────────────────────────
///
/// Sans elle, l'écran proposait TOUS les statuts sauf l'actuel, filtrés par le
/// seul rôle. Sur une réserve « créée », il en offrait sept que le serveur
/// refuse un par un : chaque choix coûtait un aller-retour pour obtenir
/// « Transition impossible : creee → validee ». Une réserve CLÔTURÉE — état
/// terminal côté serveur, `cloturee: []` — paraissait même entièrement
/// rouvrable.
///
/// Le serveur reste la seule autorité : cette table ne garde rien, elle évite
/// seulement de PROPOSER ce qui sera refusé. Toute modification de la matrice
/// serveur doit être reportée ici — `reserve_statut_policy_test.dart` et
/// `reserve.changerStatut.roles.test.js` se répondent case par case.
///
/// `enRetard` n'apparaît volontairement dans AUCUNE liste de destination :
/// c'est le traitement automatique des échéances qui le pose, jamais un
/// utilisateur. Il n'est donc jamais proposé, exactement comme côté serveur.
const _transitions = <ReserveStatut, Set<ReserveStatut>>{
  ReserveStatut.creee: {
    ReserveStatut.affectee,
    ReserveStatut.enCours,
    ReserveStatut.rouverte,
  },
  ReserveStatut.affectee: {
    ReserveStatut.priseEnCharge,
    ReserveStatut.enCours,
    ReserveStatut.corrigee,
    ReserveStatut.rouverte,
  },
  ReserveStatut.priseEnCharge: {
    ReserveStatut.enCours,
    ReserveStatut.corrigee,
    ReserveStatut.rouverte,
  },
  ReserveStatut.enCours: {
    ReserveStatut.corrigee,
    ReserveStatut.aVerifier,
    ReserveStatut.rouverte,
  },
  ReserveStatut.corrigee: {
    ReserveStatut.aVerifier,
    ReserveStatut.validee,
    ReserveStatut.refusee,
    ReserveStatut.rouverte,
  },
  ReserveStatut.aVerifier: {
    ReserveStatut.validee,
    ReserveStatut.refusee,
    ReserveStatut.enCours,
    ReserveStatut.rouverte,
  },
  ReserveStatut.validee: {
    ReserveStatut.cloturee,
    ReserveStatut.rouverte,
  },
  ReserveStatut.refusee: {
    ReserveStatut.enCours,
    ReserveStatut.corrigee,
    ReserveStatut.rouverte,
  },
  ReserveStatut.rouverte: {
    ReserveStatut.affectee,
    ReserveStatut.priseEnCharge,
    ReserveStatut.enCours,
    ReserveStatut.corrigee,
    ReserveStatut.aVerifier,
  },
  // Posé automatiquement par le traitement des échéances ; la reprise du
  // cycle normal reste ouverte — mais SANS verdict direct : la réserve en
  // retard n'a pas encore été déclarée corrigée, elle repasse par
  // `corrigee` / `a_verifier` (miroir du serveur).
  ReserveStatut.enRetard: {
    ReserveStatut.affectee,
    ReserveStatut.priseEnCharge,
    ReserveStatut.enCours,
    ReserveStatut.corrigee,
    ReserveStatut.aVerifier,
    ReserveStatut.rouverte,
  },
  // ÉTAT TERMINAL. Le serveur n'autorise aucune sortie (`cloturee: []`).
  ReserveStatut.cloturee: <ReserveStatut>{},
};

/// Statuts proposables depuis l'écran de détail, compte tenu de l'état actuel
/// de la réserve, du rôle courant et des preuves déjà jointes.
///
/// Fonction PURE (aucune dépendance Flutter/BLoC). Elle applique les QUATRE
/// règles que `ReserveService.changerStatut` applique côté serveur, dans le
/// même ordre :
///
///   1. transition autorisée depuis le statut actuel (`TRANSITIONS`) ;
///   2. verdict réservé aux rôles de pilotage (`STATUTS_CONTROLE`) ;
///   3. sous-traitant : uniquement sa propre progression, et seulement sur une
///      réserve qui lui est assignée (`STATUTS_SOUS_TRAITANT`) ;
///   4. `validee` exige des preuves de correction (`Media.count > 0`).
///
/// Le serveur reste la seule autorité réelle : cette fonction n'est qu'un
/// filtre d'affichage, jamais un contrôle de sécurité.
///
/// [estAssigneAMoi] doit tenir compte de l'affectation PRINCIPALE **et** des
/// affectations secondaires : le serveur accepte les deux
/// (`reserve.service.js:1021-1023`).
///
/// [aDesPreuves] : vrai dès qu'au moins un média est joint à la réserve. Sans
/// preuve, `validee` est retiré — le serveur le refuse
/// (`reserve.service.js:1041-1046`).
List<ReserveStatut> statutsProposables({
  required ReserveStatut statutActuel,
  required UserRole role,
  required bool estAssigneAMoi,
  required bool aDesPreuves,
}) {
  // 0. La ROUTE elle-même : `PATCH /reserves/:id/statut` n'est ouverte qu'aux
  //    intervenants sur les réserves et au sous-traitant (`reserve.route.js`).
  //    Un client, par exemple, recevait des statuts « non verdict » à
  //    proposer — et un 403 à l'appui sur le bouton.
  if (role != UserRole.sousTraitant && !role.peutIntervenirSurReserves) return const [];

  // 1. Ce que la matrice autorise depuis l'état courant. Un statut absent de
  //    cette table (valeur inconnue reçue du serveur) ne propose rien plutôt
  //    que de tout proposer.
  final autorises = _transitions[statutActuel] ?? const <ReserveStatut>{};
  Iterable<ReserveStatut> candidats = autorises.where((s) => s != statutActuel);

  // 4. `validee` sans preuve de correction est refusé par le serveur.
  if (!aDesPreuves) {
    candidats = candidats.where((s) => s != ReserveStatut.validee);
  }

  // 3. Sous-traitant : sa progression, et seulement s'il est assigné.
  if (role == UserRole.sousTraitant) {
    if (!estAssigneAMoi) return const [];
    return candidats.where(_statutsSousTraitant.contains).toList();
  }

  // 2. Verdict réservé au pilotage.
  if (!role.peutPiloter) {
    return candidats.where((s) => !_statutsVerdict.contains(s)).toList();
  }

  return candidats.toList();
}

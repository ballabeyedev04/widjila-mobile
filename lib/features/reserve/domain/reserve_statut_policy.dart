import '../../../core/config/user_role.dart';
import 'entities/reserve.dart';

/// Statuts « verdict » — miroir de `STATUTS_CONTROLE` côté back
/// (`reserve.service.js`). Prononcer un verdict est réservé aux rôles de
/// pilotage ([UserRoleX.peutPiloter]) ; les proposer à un autre rôle ne
/// ferait qu'offrir un bouton que le serveur refusera systématiquement.
///
/// `levee` est un verdict au même titre que `validee` : le mot du client pour
/// la même décision.
const _statutsVerdict = {
  ReserveStatut.validee,
  ReserveStatut.levee,
  ReserveStatut.refusee,
  ReserveStatut.cloturee,
  ReserveStatut.rouverte,
};

/// Statuts qu'un sous-traitant peut lui-même déclarer — miroir de
/// `STATUTS_SOUS_TRAITANT` côté back. `traitee` : même déclaration que
/// `corrigee`, dans le vocabulaire du client.
const _statutsSousTraitant = {
  ReserveStatut.priseEnCharge,
  ReserveStatut.enCours,
  ReserveStatut.corrigee,
  ReserveStatut.traitee,
};

/// Destinations autorisées depuis un statut — miroir EXACT de `TRANSITIONS`
/// (`backend/src/modules/reserve/service/reserve.service.js`).
///
/// ── Décision client (après recette) : le choix du statut est LIBRE ────────
///
/// L'ancienne matrice n'autorisait que l'étape suivante du cycle : depuis
/// « créée », l'écran n'offrait que trois statuts, et le client — qui suit
/// ses réserves par état (en retard, à surveiller, à échéance, traitée,
/// refusée, levée…) — ne retrouvait pas les siens. Toute réserve EN COURS DE
/// VIE peut désormais recevoir n'importe quel statut.
///
/// Ce qui reste gardé, parce que ce sont des règles d'intégrité et non de
/// parcours (mêmes règles que le serveur, dans le même ordre) :
///   - `creee` n'est jamais une destination : c'est l'état initial ;
///   - `cloturee` est TERMINAL, et n'est atteignable qu'après un verdict
///     positif (`validee` / `levee`) ;
///   - un verdict positif ne se défait que par une RÉOUVERTURE explicite.
///
/// Le serveur reste la seule autorité : cette table ne garde rien, elle évite
/// seulement de PROPOSER ce qui sera refusé. `reserve_statut_policy_test.dart`
/// et `reserve.statutsClient.test.js` (backend) se répondent case par case.
///
/// `enRetard` est posé chaque soir par le traitement des échéances, mais le
/// client peut aussi le choisir à la main : il fait partie des destinations.
Set<ReserveStatut> _destinationsDepuis(ReserveStatut depuis) {
  switch (depuis) {
    case ReserveStatut.cloturee:
      return const <ReserveStatut>{};
    case ReserveStatut.validee:
      return const {ReserveStatut.levee, ReserveStatut.cloturee, ReserveStatut.rouverte};
    case ReserveStatut.levee:
      return const {ReserveStatut.cloturee, ReserveStatut.rouverte};
    default:
      return {
        for (final s in ReserveStatut.values)
          if (s != depuis && s != ReserveStatut.creee && s != ReserveStatut.cloturee) s,
      };
  }
}

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
///   4. `validee` et `levee` exigent des preuves de correction
///      (`Media.count > 0`).
///
/// Le serveur reste la seule autorité réelle : cette fonction n'est qu'un
/// filtre d'affichage, jamais un contrôle de sécurité.
///
/// [estAssigneAMoi] doit tenir compte de l'affectation PRINCIPALE **et** des
/// affectations secondaires : le serveur accepte les deux.
///
/// [aDesPreuves] : vrai dès qu'au moins un média est joint à la réserve. Sans
/// preuve, les verdicts positifs sont retirés — le serveur les refuse.
///
/// Le résultat suit l'ordre du cycle de vie (celui de l'enum), pour que la
/// feuille de choix se lise comme un parcours.
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

  // 1. Ce que la matrice autorise depuis l'état courant.
  final autorises = _destinationsDepuis(statutActuel);
  Iterable<ReserveStatut> candidats = ReserveStatut.values.where(autorises.contains);

  // 4. Un verdict positif sans preuve de correction est refusé par le serveur.
  if (!aDesPreuves) {
    candidats = candidats.where((s) => !s.estLevee);
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

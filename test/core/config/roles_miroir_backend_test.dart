import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/features/organisation/presentation/pages/intervenants_list_page.dart';

/// Crible complet : chaque filtre de rôle du mobile contre le groupe qui garde
/// la route correspondante dans `backend/src/config/roles.js`.
///
/// ## Pourquoi ce fichier existe
///
/// Un bouton conditionné à un rôle PLUS ÉTROIT que la route qu'il appelle est
/// invisible pour des gens qui y ont pourtant droit — et invisible sans
/// erreur, sans message, sans rien. C'est arrivé : l'écran Plans gardait
/// « Ajouter des plans » derrière `estOperationnelOuControle` alors que le
/// serveur ouvre la route à `DEPOSANT`. Une entreprise avait le droit de
/// déposer et n'avait aucun bouton pour le faire. Le défaut a survécu à
/// plusieurs relectures parce qu'il n'était visible ni dans le code de
/// l'écran, ni dans le code du serveur — seulement dans l'ÉCART entre les
/// deux.
///
/// L'inverse (filtre plus LARGE que la route) est moins grave — l'utilisateur
/// reçoit un 403 lisible — mais reste une promesse non tenue.
///
/// Les listes ci-dessous sont recopiées telles quelles depuis le serveur. Le
/// rôle `Admin` en est retiré : le mobile ne le modélise pas (voir la doc de
/// [UserRole]), un compte Admin y est traité comme `inconnu`.
void main() {
  // ── Les groupes du serveur, verbatim ───────────────────────────────────────
  const operationnel = {
    UserRole.chefProjet,
    UserRole.conducteurTravaux,
    UserRole.maitreOeuvre,
  };
  const operationnelControle = {...operationnel, UserRole.bureauControle};
  const pilotage = {...operationnelControle, UserRole.maitreOuvrage};
  const gestion = {UserRole.chefProjet, UserRole.maitreOuvrage};
  const gestionMembres = {...gestion, UserRole.entreprise};
  const deposant = {
    ...operationnel,
    UserRole.entreprise,
    UserRole.bureauControle,
    UserRole.maitreOuvrage,
  };
  const reserveIntervenants = {...pilotage, UserRole.entreprise, UserRole.pilote};
  // `partenaire.route.js` liste ses rôles en clair, sans passer par un groupe.
  const partenaires = {
    UserRole.chefProjet,
    UserRole.conducteurTravaux,
    UserRole.maitreOuvrage,
    UserRole.maitreOeuvre,
  };

  /// Vérifie un prédicat pour les DIX rôles, pas seulement pour ceux qu'on
  /// soupçonne : c'est un rôle auquel personne ne pensait qui a été oublié.
  void crible(
    String nom,
    Set<UserRole> attendus,
    bool Function(UserRole) predicat,
    String routes,
  ) {
    group('$nom  ↔  $routes', () {
      for (final role in UserRole.values) {
        final attendu = attendus.contains(role);
        test('${role.name} : ${attendu ? "autorisé" : "refusé"}', () {
          expect(predicat(role), attendu);
        });
      }
    });
  }

  crible('estOperationnel', operationnel, (r) => r.estOperationnel,
      'OPERATIONNEL — archivage documents/plans, suppression réserve');
  crible('estOperationnelOuControle', operationnelControle, (r) => r.estOperationnelOuControle,
      'OPERATIONNEL_CONTROLE — dépôt document, modification réserve, inspections');
  crible('peutPiloter', pilotage, (r) => r.peutPiloter, 'PILOTAGE — génération de rapports');
  crible('peutGererOrganisation', gestion, (r) => r.peutGererOrganisation,
      'GESTION — organisation, filiales, équipes, validation de chantier');
  crible('peutGererMembres', gestionMembres, (r) => r.peutGererMembres,
      'GESTION_MEMBRES — liste et ajout de membres');
  crible('peutDeposerPlans', deposant, (r) => r.peutDeposerPlans,
      'DEPOSANT — POST /chantiers/:id/plans, POST /chantiers');
  crible('peutIntervenirSurReserves', reserveIntervenants, (r) => r.peutIntervenirSurReserves,
      'RESERVE_INTERVENANTS — création de réserve, pièces, affectations');
  crible('peutGererPartenaires', partenaires, (r) => peutGererPartenaires(r),
      'partenaire.route.js — POST/PUT partenaires');

  test('peutGererPartenaires refuse un rôle absent', () {
    // Signature nullable : l'appelant lit `b.state.utilisateur?.role`.
    expect(peutGererPartenaires(null), isFalse);
  });

  group('le cas qui avait échappé', () {
    test('Entreprise peut déposer des plans mais n’est pas opérationnelle', () {
      // L'écart exact qui cachait le bouton « Ajouter des plans ».
      expect(UserRole.entreprise.peutDeposerPlans, isTrue);
      expect(UserRole.entreprise.estOperationnelOuControle, isFalse);
    });

    test('MaitreOuvrage aussi — il était perdu par le même filtre', () {
      expect(UserRole.maitreOuvrage.peutDeposerPlans, isTrue);
      expect(UserRole.maitreOuvrage.estOperationnelOuControle, isFalse);
    });

    test('le « + » des réserves, lui, s’affichait bien pour une entreprise', () {
      // Ce qui rendait le symptôme déroutant : un bouton visible, l'autre non,
      // sur le même écran et pour le même compte.
      expect(UserRole.entreprise.peutIntervenirSurReserves, isTrue);
    });
  });
}

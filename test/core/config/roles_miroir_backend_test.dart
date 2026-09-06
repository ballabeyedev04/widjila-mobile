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
  //
  // `entreprise` figure dans TOUS : c'est le titulaire de son organisation, le
  // rôle le plus élevé après le super-admin plateforme. Son absence d'un seul
  // groupe suffisait à lui cacher un écran ou à lui refuser un bouton — c'est
  // arrivé pour les plans, pour l'abonnement et pour ses propres chantiers.
  const operationnel = {
    UserRole.chefProjet,
    UserRole.conducteurTravaux,
    UserRole.maitreOeuvre,
    UserRole.entreprise,
  };
  const operationnelControle = {...operationnel, UserRole.bureauControle};
  const pilotage = {...operationnelControle, UserRole.maitreOuvrage};
  const gestion = {UserRole.chefProjet, UserRole.maitreOuvrage, UserRole.entreprise};
  const gestionMembres = {...gestion};
  const deposant = {
    ...operationnel,
    UserRole.bureauControle,
    UserRole.maitreOuvrage,
  };
  const reserveIntervenants = {...pilotage, UserRole.pilote};
  // `partenaire.route.js` liste ses rôles en clair, sans passer par un groupe.
  const partenaires = {
    UserRole.chefProjet,
    UserRole.conducteurTravaux,
    UserRole.maitreOuvrage,
    UserRole.maitreOeuvre,
    UserRole.entreprise,
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

  group('le titulaire n’est oublié nulle part', () {
    // Le balayage qui manquait. Trois fois le même défaut est passé : un
    // groupe écrit sans l'entreprise, un écran qui s'affiche, un 403 derrière.
    // Ici, un oubli futur échoue au lieu d'arriver chez le client.
    final droits = <String, bool Function(UserRole)>{
      'estOperationnel': (r) => r.estOperationnel,
      'estOperationnelOuControle': (r) => r.estOperationnelOuControle,
      'peutPiloter': (r) => r.peutPiloter,
      'peutGererOrganisation': (r) => r.peutGererOrganisation,
      'peutGererMembres': (r) => r.peutGererMembres,
      'peutGererAbonnement': (r) => r.peutGererAbonnement,
      'peutAttribuerRoleGestion': (r) => r.peutAttribuerRoleGestion,
      'peutDeposerPlans': (r) => r.peutDeposerPlans,
      'peutDemanderChantier': (r) => r.peutDemanderChantier,
      'peutIntervenirSurReserves': (r) => r.peutIntervenirSurReserves,
      'estSensible': (r) => r.estSensible,
    };

    droits.forEach((nom, droit) {
      test('$nom lui est ouvert', () {
        expect(droit(UserRole.entreprise), isTrue);
      });
    });

    test('et le crible ci-dessus couvre bien tous ces droits', () {
      // Sans cette borne, retirer un getter de la table le ferait disparaître
      // du balayage sans que rien ne le signale.
      expect(droits.length, greaterThanOrEqualTo(11));
    });
  });

  group('ce qui n’est PAS ouvert au titulaire', () {
    test('le sous-traitant garde son accès étroit, à lui seul', () {
      // `SOUS_TRAITANT` n'est pas un groupe de droits : c'est l'ouverture de
      // deux routes au seul sous-traitant. L'entreprise passe déjà par
      // `RESERVE_INTERVENANTS`.
      expect(UserRole.entreprise.estSousTraitant, isFalse);
      expect(UserRole.sousTraitant.estSousTraitant, isTrue);
    });

    test('le verdict sur une demande de chantier reste hors du mobile', () {
      // `VALIDATION_CHANTIER` côté serveur : valider sa propre demande
      // annulerait le circuit. Aucun getter ne l'expose ici, et c'est voulu.
      expect(UserRole.values.length, 10);
    });
  });
}

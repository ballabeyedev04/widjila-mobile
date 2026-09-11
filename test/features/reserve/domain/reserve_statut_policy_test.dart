import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/reserve_statut_policy.dart';

// Miroir client de ReserveService.changerStatut (backend) — chaque cas ici a
// son pendant exact dans reserve.changerStatut.roles.test.js (backend). Les
// deux suites doivent rester synchronisées : un statut ajouté d'un côté sans
// l'autre est le genre d'écart qu'aucun des deux tests ne détecte seul.
void main() {
  group('statutsProposables — matrice de transitions', () {
    test('depuis « créée », seuls les trois statuts de la matrice sont proposés', () {
      // `TRANSITIONS.creee = ['affectee', 'en_cours', 'rouverte']`.
      // L'écran proposait auparavant TOUS les autres statuts : sept d'entre
      // eux ne pouvaient qu'échouer sur « Transition impossible ».
      final statuts = statutsProposables(
        statutActuel: ReserveStatut.creee,
        role: UserRole.chefProjet,
        estAssigneAMoi: false,
        aDesPreuves: true,
      );

      expect(statuts, unorderedEquals([
        ReserveStatut.affectee,
        ReserveStatut.enCours,
        ReserveStatut.rouverte,
      ]));
    });

    test('« clôturée » est un état TERMINAL — rien n’est proposé', () {
      // `TRANSITIONS.cloturee = []`. L'écran offrait dix choix sur un objet
      // que le serveur déclare définitivement figé.
      final statuts = statutsProposables(
        statutActuel: ReserveStatut.cloturee,
        role: UserRole.chefProjet,
        estAssigneAMoi: false,
        aDesPreuves: true,
      );

      expect(statuts, isEmpty);
    });

    test('« en retard » n’est JAMAIS une destination proposable', () {
      // Il est posé par le traitement automatique des échéances : il
      // n'apparaît dans aucune liste de destination de la matrice serveur.
      for (final depart in ReserveStatut.values) {
        final statuts = statutsProposables(
          statutActuel: depart,
          role: UserRole.chefProjet,
          estAssigneAMoi: true,
          aDesPreuves: true,
        );
        expect(statuts, isNot(contains(ReserveStatut.enRetard)),
            reason: 'proposé depuis $depart');
      }
    });

    test('depuis « en retard », la reprise du cycle normal reste ouverte', () {
      final statuts = statutsProposables(
        statutActuel: ReserveStatut.enRetard,
        role: UserRole.chefProjet,
        estAssigneAMoi: false,
        aDesPreuves: true,
      );

      expect(statuts, contains(ReserveStatut.enCours));
      expect(statuts, contains(ReserveStatut.corrigee));
    });

    test('depuis « en retard », AUCUN verdict direct (miroir du serveur)', () {
      // Une réserve en retard n'a pas été déclarée corrigée : la valider ou la
      // refuser d'emblée court-circuitait le contrôle. Le serveur le refuse.
      final statuts = statutsProposables(
        statutActuel: ReserveStatut.enRetard,
        role: UserRole.chefProjet,
        estAssigneAMoi: false,
        aDesPreuves: true,
      );

      expect(statuts, isNot(contains(ReserveStatut.validee)));
      expect(statuts, isNot(contains(ReserveStatut.refusee)));
    });

    test('aucun statut ne se propose lui-même', () {
      for (final depart in ReserveStatut.values) {
        final statuts = statutsProposables(
          statutActuel: depart,
          role: UserRole.chefProjet,
          estAssigneAMoi: true,
          aDesPreuves: true,
        );
        expect(statuts, isNot(contains(depart)), reason: 'depuis $depart');
      }
    });
  });

  group('statutsProposables — preuves de correction', () {
    test('sans média joint, « validée » n’est pas proposée', () {
      // Le serveur exige au moins une preuve (`Media.count > 0`) et refuse
      // sinon, APRÈS que l'utilisateur a choisi le statut.
      final statuts = statutsProposables(
        statutActuel: ReserveStatut.corrigee,
        role: UserRole.chefProjet,
        estAssigneAMoi: false,
        aDesPreuves: false,
      );

      expect(statuts, isNot(contains(ReserveStatut.validee)));
      // Le refus, lui, ne demande aucune preuve.
      expect(statuts, contains(ReserveStatut.refusee));
    });

    test('avec une preuve, « validée » redevient proposable', () {
      final statuts = statutsProposables(
        statutActuel: ReserveStatut.corrigee,
        role: UserRole.chefProjet,
        estAssigneAMoi: false,
        aDesPreuves: true,
      );

      expect(statuts, contains(ReserveStatut.validee));
    });
  });

  group('statutsProposables — rôles de pilotage', () {
    test('un rôle de pilotage voit les verdicts autorisés par la matrice', () {
      final statuts = statutsProposables(
        statutActuel: ReserveStatut.corrigee,
        role: UserRole.chefProjet,
        estAssigneAMoi: false,
        aDesPreuves: true,
      );

      expect(statuts, contains(ReserveStatut.validee));
      expect(statuts, contains(ReserveStatut.refusee));
      expect(statuts, isNot(contains(ReserveStatut.corrigee)),
          reason: 'le statut actuel ne se propose pas lui-même');
    });
  });

  group('statutsProposables — intervenants non-pilotage (ex: Pilote)', () {
    test('les verdicts sont masqués — le back les refuserait de toute façon', () {
      // Le sujet n'est plus 'Entreprise' : le titulaire de l'organisation
      // pilote désormais son propre chantier, verdicts compris. Le rôle
      // « Pilote » intervient sur les réserves sans prononcer de verdict.
      final statuts = statutsProposables(
        statutActuel: ReserveStatut.corrigee,
        role: UserRole.pilote,
        estAssigneAMoi: false,
        aDesPreuves: true,
      );

      expect(statuts, isNot(contains(ReserveStatut.validee)));
      expect(statuts, isNot(contains(ReserveStatut.refusee)));
      expect(statuts, isNot(contains(ReserveStatut.cloturee)));
      expect(statuts, isNot(contains(ReserveStatut.rouverte)));
      expect(statuts, contains(ReserveStatut.aVerifier),
          reason: 'les statuts non-verdict restent proposés');
    });

    test('un client ne se voit RIEN proposer : la route lui est fermée', () {
      // `PATCH /reserves/:id/statut` n'est ouverte qu'aux intervenants
      // (RESERVE_INTERVENANTS) et au sous-traitant. Lui proposer « à
      // vérifier » menait à un 403 à l'appui sur le bouton.
      for (final role in [UserRole.client, UserRole.inconnu]) {
        final statuts = statutsProposables(
          statutActuel: ReserveStatut.corrigee,
          role: role,
          estAssigneAMoi: true,
          aDesPreuves: true,
        );
        expect(statuts, isEmpty, reason: role.name);
      }
    });

    test('le titulaire, lui, prononce les verdicts sur SON chantier', () {
      final statuts = statutsProposables(
        statutActuel: ReserveStatut.corrigee,
        role: UserRole.entreprise,
        estAssigneAMoi: false,
        aDesPreuves: true,
      );

      expect(statuts, contains(ReserveStatut.validee));
      expect(statuts, contains(ReserveStatut.refusee));
    });
  });

  group('statutsProposables — SousTraitant', () {
    test('aucun statut proposé si la réserve ne lui est pas assignée', () {
      final statuts = statutsProposables(
        statutActuel: ReserveStatut.affectee,
        role: UserRole.sousTraitant,
        estAssigneAMoi: false,
        aDesPreuves: true,
      );

      expect(statuts, isEmpty);
    });

    test('assigné : seuls prise en charge / en cours / corrigée sont proposés', () {
      final statuts = statutsProposables(
        statutActuel: ReserveStatut.affectee,
        role: UserRole.sousTraitant,
        estAssigneAMoi: true,
        aDesPreuves: true,
      );

      expect(statuts, unorderedEquals([
        ReserveStatut.priseEnCharge,
        ReserveStatut.enCours,
        ReserveStatut.corrigee,
      ]));
    });

    test('même assigné, aucun verdict ni ré-affectation ne sont proposés', () {
      final statuts = statutsProposables(
        statutActuel: ReserveStatut.corrigee,
        role: UserRole.sousTraitant,
        estAssigneAMoi: true,
        aDesPreuves: true,
      );

      expect(statuts, isNot(contains(ReserveStatut.validee)));
      expect(statuts, isNot(contains(ReserveStatut.affectee)));
      expect(statuts, isNot(contains(ReserveStatut.aVerifier)));
    });
  });

  group('statutsProposables — Pilote', () {
    test('depuis « créée » : les transitions de la matrice, sans les verdicts', () {
      final statuts = statutsProposables(
        statutActuel: ReserveStatut.creee,
        role: UserRole.pilote,
        estAssigneAMoi: false,
        aDesPreuves: true,
      );

      expect(statuts, contains(ReserveStatut.affectee));
      expect(statuts, contains(ReserveStatut.enCours));
      // `rouverte` est un verdict : masqué pour un rôle non-pilotage.
      expect(statuts, isNot(contains(ReserveStatut.rouverte)));
      expect(statuts, isNot(contains(ReserveStatut.cloturee)));
      // `prise_en_charge` n'est pas atteignable depuis « créée ».
      expect(statuts, isNot(contains(ReserveStatut.priseEnCharge)));
    });
  });
}

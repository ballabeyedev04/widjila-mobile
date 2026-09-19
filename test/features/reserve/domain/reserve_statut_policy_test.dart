import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/reserve_statut_policy.dart';

// Miroir client de ReserveService.changerStatut (backend) — chaque cas ici a
// son pendant exact dans reserve.statutsClient.test.js et
// reserve.changerStatut.roles.test.js (backend). Les deux suites doivent
// rester synchronisées : un statut ajouté d'un côté sans l'autre est le genre
// d'écart qu'aucun des deux tests ne détecte seul.
void main() {
  List<ReserveStatut> pilotage(ReserveStatut depuis, {bool aDesPreuves = true}) => statutsProposables(
        statutActuel: depuis,
        role: UserRole.chefProjet,
        estAssigneAMoi: false,
        aDesPreuves: aDesPreuves,
      );

  final vivants = ReserveStatut.values.where((s) => !s.estFerme).toList();

  group('statutsProposables — choix de statut libre (décision client)', () {
    test('depuis une réserve en cours de vie, TOUT statut est proposé, sauf créée et clôturée', () {
      for (final depart in vivants) {
        final statuts = pilotage(depart);
        final attendus = ReserveStatut.values
            .where((s) => s != depart && s != ReserveStatut.creee && s != ReserveStatut.cloturee)
            .toList();
        expect(statuts, unorderedEquals(attendus), reason: 'depuis $depart');
      }
    });

    test('la liste suit l’ordre du cycle de vie', () {
      final statuts = pilotage(ReserveStatut.enCours);
      final rangs = statuts.map((s) => ReserveStatut.values.indexOf(s)).toList();
      expect(rangs, [...rangs]..sort());
    });

    test('« créée » n’est JAMAIS une destination : c’est l’état initial', () {
      for (final depart in ReserveStatut.values) {
        expect(pilotage(depart), isNot(contains(ReserveStatut.creee)), reason: 'depuis $depart');
      }
    });

    test('« clôturée » n’est atteignable qu’après un verdict positif', () {
      for (final depart in vivants) {
        expect(pilotage(depart), isNot(contains(ReserveStatut.cloturee)), reason: 'depuis $depart');
      }
      expect(pilotage(ReserveStatut.validee), contains(ReserveStatut.cloturee));
      expect(pilotage(ReserveStatut.levee), contains(ReserveStatut.cloturee));
    });

    test('« clôturée » est un état TERMINAL — rien n’est proposé', () {
      expect(pilotage(ReserveStatut.cloturee), isEmpty);
    });

    test('un verdict positif ne se défait que par une réouverture explicite', () {
      expect(pilotage(ReserveStatut.validee), unorderedEquals([
        ReserveStatut.levee,
        ReserveStatut.cloturee,
        ReserveStatut.rouverte,
      ]));
      expect(pilotage(ReserveStatut.levee), unorderedEquals([
        ReserveStatut.cloturee,
        ReserveStatut.rouverte,
      ]));
    });

    test('les statuts du client sont proposés depuis « créée »', () {
      final statuts = pilotage(ReserveStatut.creee);
      for (final s in statutsSuiviClient) {
        expect(statuts, contains(s), reason: '$s');
      }
    });

    test('« en retard » peut désormais être choisi à la main', () {
      expect(pilotage(ReserveStatut.enCours), contains(ReserveStatut.enRetard));
    });

    test('aucun statut ne se propose lui-même', () {
      for (final depart in ReserveStatut.values) {
        expect(pilotage(depart), isNot(contains(depart)), reason: 'depuis $depart');
      }
    });
  });

  group('statutsProposables — preuves de correction', () {
    test('sans média joint, ni « validée » ni « levée » ne sont proposées', () {
      // Le serveur exige au moins une preuve (`Media.count > 0`) pour les deux
      // verdicts positifs, et refuse sinon APRÈS le choix de l'utilisateur.
      final statuts = pilotage(ReserveStatut.traitee, aDesPreuves: false);

      expect(statuts, isNot(contains(ReserveStatut.validee)));
      expect(statuts, isNot(contains(ReserveStatut.levee)));
      // Le refus, lui, ne demande aucune preuve.
      expect(statuts, contains(ReserveStatut.refusee));
    });

    test('avec une preuve, « validée » et « levée » redeviennent proposables', () {
      final statuts = pilotage(ReserveStatut.traitee);

      expect(statuts, contains(ReserveStatut.validee));
      expect(statuts, contains(ReserveStatut.levee));
    });
  });

  group('statutsProposables — intervenants non-pilotage (ex: Pilote)', () {
    test('les verdicts sont masqués — « levée » comprise', () {
      final statuts = statutsProposables(
        statutActuel: ReserveStatut.traitee,
        role: UserRole.pilote,
        estAssigneAMoi: false,
        aDesPreuves: true,
      );

      expect(statuts, isNot(contains(ReserveStatut.validee)));
      expect(statuts, isNot(contains(ReserveStatut.levee)));
      expect(statuts, isNot(contains(ReserveStatut.refusee)));
      expect(statuts, isNot(contains(ReserveStatut.cloturee)));
      expect(statuts, isNot(contains(ReserveStatut.rouverte)));
      // Les statuts de suivi du client, eux, restent proposés.
      expect(statuts, contains(ReserveStatut.aSurveiller));
      expect(statuts, contains(ReserveStatut.aEcheance));
      expect(statuts, contains(ReserveStatut.aVerifier));
    });

    test('un client ne se voit RIEN proposer : la route lui est fermée', () {
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
      expect(statuts, contains(ReserveStatut.levee));
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

    test('assigné : sa progression seulement — « traitée » comprise', () {
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
        ReserveStatut.traitee,
      ]));
    });

    test('même assigné, ni verdict, ni ré-affectation, ni statut de suivi', () {
      final statuts = statutsProposables(
        statutActuel: ReserveStatut.corrigee,
        role: UserRole.sousTraitant,
        estAssigneAMoi: true,
        aDesPreuves: true,
      );

      expect(statuts, isNot(contains(ReserveStatut.validee)));
      expect(statuts, isNot(contains(ReserveStatut.levee)));
      expect(statuts, isNot(contains(ReserveStatut.affectee)));
      expect(statuts, isNot(contains(ReserveStatut.aSurveiller)));
      expect(statuts, isNot(contains(ReserveStatut.aEcheance)));
    });
  });
}

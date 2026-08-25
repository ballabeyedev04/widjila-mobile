import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/reserve_statut_policy.dart';

// Miroir client de ReserveService.changerStatut (backend) — chaque cas ici a
// son pendant exact dans reserve.changerStatut.roles.test.js (backend). Les
// deux suites doivent rester synchronisées : un statut ajouté d'un côté sans
// l'autre est le genre d'écart qu'aucun des deux tests ne détecte seul.
void main() {
  group('statutsProposables — rôles de pilotage (inchangé)', () {
    test('un rôle de pilotage voit tous les statuts, y compris les verdicts', () {
      final statuts = statutsProposables(
        statutActuel: ReserveStatut.corrigee,
        role: UserRole.chefProjet,
        estAssigneAMoi: false,
      );

      expect(statuts, contains(ReserveStatut.validee));
      expect(statuts, contains(ReserveStatut.refusee));
      expect(statuts, isNot(contains(ReserveStatut.corrigee)), reason: 'le statut actuel ne se propose pas lui-même');
    });
  });

  group('statutsProposables — rôles non-pilotage (ex: Entreprise)', () {
    test('les verdicts sont masqués — le back les refuserait de toute façon', () {
      final statuts = statutsProposables(
        statutActuel: ReserveStatut.corrigee,
        role: UserRole.entreprise,
        estAssigneAMoi: false,
      );

      expect(statuts, isNot(contains(ReserveStatut.validee)));
      expect(statuts, isNot(contains(ReserveStatut.refusee)));
      expect(statuts, isNot(contains(ReserveStatut.cloturee)));
      expect(statuts, isNot(contains(ReserveStatut.rouverte)));
      expect(statuts, contains(ReserveStatut.aVerifier), reason: 'les statuts non-verdict restent proposés');
    });
  });

  group('statutsProposables — SousTraitant', () {
    test('aucun statut proposé si la réserve ne lui est pas assignée', () {
      final statuts = statutsProposables(
        statutActuel: ReserveStatut.affectee,
        role: UserRole.sousTraitant,
        estAssigneAMoi: false,
      );

      expect(statuts, isEmpty);
    });

    test('assigné : seuls prise en charge / en cours / corrigée sont proposés', () {
      final statuts = statutsProposables(
        statutActuel: ReserveStatut.affectee,
        role: UserRole.sousTraitant,
        estAssigneAMoi: true,
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
      );

      expect(statuts, isNot(contains(ReserveStatut.validee)));
      expect(statuts, isNot(contains(ReserveStatut.affectee)));
      expect(statuts, isNot(contains(ReserveStatut.aVerifier)));
    });
  });

  group('statutsProposables — Pilote', () {
    test('comme les autres rôles non-pilotage : tout sauf les verdicts', () {
      final statuts = statutsProposables(
        statutActuel: ReserveStatut.creee,
        role: UserRole.pilote,
        estAssigneAMoi: false,
      );

      expect(statuts, contains(ReserveStatut.affectee));
      expect(statuts, contains(ReserveStatut.priseEnCharge));
      expect(statuts, isNot(contains(ReserveStatut.cloturee)));
    });
  });
}

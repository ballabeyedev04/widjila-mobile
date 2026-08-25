import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/inspection/domain/entities/inspection.dart';

/// L'entité fait la traduction entre le JSON du serveur et le modèle Dart.
/// Une erreur ici ne casse pas la compilation — elle produit un écran qui
/// ment (mauvais statut, avancement faux). D'où ces tests.
void main() {
  group('InspectionType', () {
    test('reconnaît les trois valeurs du serveur', () {
      expect(InspectionTypeX.fromString('opr'), InspectionType.opr);
      expect(InspectionTypeX.fromString('visite_contradictoire'),
          InspectionType.visiteContradictoire);
      expect(InspectionTypeX.fromString('inspection'), InspectionType.inspection);
    });

    test('un type inconnu retombe sur inspection plutôt que de lever', () {
      // Le serveur peut introduire un type ; l'app ne doit pas planter à
      // l'ouverture de la liste pour autant.
      expect(InspectionTypeX.fromString('reception_definitive'), InspectionType.inspection);
      expect(InspectionTypeX.fromString(null), InspectionType.inspection);
    });

    test('l\'aller-retour raw/fromString est stable', () {
      for (final t in InspectionType.values) {
        expect(InspectionTypeX.fromString(t.raw), t, reason: t.name);
      }
    });
  });

  group('InspectionStatut', () {
    test('l\'aller-retour raw/fromString est stable', () {
      for (final s in InspectionStatut.values) {
        expect(InspectionStatutX.fromString(s.raw), s, reason: s.name);
      }
    });

    test('seule une visite signée est figée', () {
      expect(InspectionStatut.signee.estFigee, isTrue);
      expect(InspectionStatut.terminee.estFigee, isFalse);
      expect(InspectionStatut.planifiee.estFigee, isFalse);
      expect(InspectionStatut.enCours.estFigee, isFalse);
    });
  });

  group('StatutConvocation', () {
    test('l\'aller-retour raw/fromString est stable', () {
      for (final s in StatutConvocation.values) {
        expect(StatutConvocationX.fromString(s.raw), s, reason: s.name);
      }
    });

    test('une valeur inconnue retombe sur invité', () {
      expect(StatutConvocationX.fromString('excuse'), StatutConvocation.invite);
    });
  });

  group('Inspection.fromJson', () {
    test('lit une visite complète', () {
      final inspection = Inspection.fromJson({
        'id': 'i1',
        'chantierId': 'c1',
        'type': 'opr',
        'statut': 'en_cours',
        'date_visite': '2026-09-15',
        'compte_rendu': 'RAS sur le lot 3.',
        'inspecteur': {'id': 'u1', 'nom': 'Diallo', 'prenom': 'Awa'},
        'checklist': [
          {'id': 'l1', 'libelle': 'Étanchéité', 'coche': true},
          {'id': 'l2', 'libelle': 'Garde-corps', 'coche': false},
        ],
      });

      expect(inspection.type, InspectionType.opr);
      expect(inspection.statut, InspectionStatut.enCours);
      expect(inspection.dateVisite, DateTime(2026, 9, 15));
      expect(inspection.inspecteur?.nomComplet, 'Awa Diallo');
      expect(inspection.checklist, hasLength(2));
      expect(inspection.compteRendu, 'RAS sur le lot 3.');
    });

    test('récupère le chantier depuis l\'objet imbriqué du détail', () {
      // `GET /inspections/:id` renvoie `chantier: { id, nom }` sans
      // `chantierId` à la racine — contrairement à la liste.
      final inspection = Inspection.fromJson({
        'id': 'i1',
        'chantier': {'id': 'c9', 'nom': 'Résidence Les Palmiers'},
      });

      expect(inspection.chantierId, 'c9');
      expect(inspection.chantierNom, 'Résidence Les Palmiers');
    });

    test('survit à une charge utile minimale', () {
      final inspection = Inspection.fromJson({'id': 'i1'});

      expect(inspection.chantierId, '');
      expect(inspection.type, InspectionType.inspection);
      expect(inspection.statut, InspectionStatut.planifiee);
      expect(inspection.checklist, isEmpty);
      expect(inspection.dateVisite, isNull);
    });

    test('une date invalide donne null plutôt qu\'une exception', () {
      final inspection = Inspection.fromJson({'id': 'i1', 'date_visite': 'pas-une-date'});
      expect(inspection.dateVisite, isNull);
    });
  });

  group('avancement', () {
    Inspection avec(List<bool> coches) => Inspection(
          id: 'i1',
          chantierId: 'c1',
          checklist: [
            for (var i = 0; i < coches.length; i++)
              LigneChecklist(id: 'l$i', libelle: 'Point $i', coche: coches[i]),
          ],
        );

    test('compte les points cochés', () {
      final i = avec([true, true, false, false]);
      expect(i.nbCoches, 2);
      expect(i.nbPoints, 4);
      expect(i.avancement, 0.5);
      expect(i.estComplete, isFalse);
    });

    test('une checklist entièrement cochée est complète', () {
      final i = avec([true, true]);
      expect(i.avancement, 1.0);
      expect(i.estComplete, isTrue);
    });

    test('une checklist VIDE vaut 0 et n\'est pas complète', () {
      // Sans ce garde-fou, 0/0 donnerait NaN et la barre de progression
      // s'afficherait cassée.
      final i = avec([]);
      expect(i.avancement, 0);
      expect(i.avancement.isNaN, isFalse);
      expect(i.estComplete, isFalse);
    });
  });

  group('copyWith', () {
    test('remplace la checklist sans toucher au reste', () {
      final origine = Inspection(
        id: 'i1',
        chantierId: 'c1',
        type: InspectionType.opr,
        statut: InspectionStatut.enCours,
        checklist: const [LigneChecklist(id: 'l1', libelle: 'A')],
      );

      final modifiee = origine.copyWith(
        checklist: [const LigneChecklist(id: 'l1', libelle: 'A', coche: true)],
      );

      expect(modifiee.checklist.first.coche, isTrue);
      expect(modifiee.type, InspectionType.opr);
      expect(modifiee.statut, InspectionStatut.enCours);
      expect(modifiee.id, 'i1');
    });
  });
}

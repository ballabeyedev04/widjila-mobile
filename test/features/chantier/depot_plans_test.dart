import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/chantier/presentation/cubit/depot_plans_cubit.dart';
import 'package:suivie_chantier_mobile/features/referentiel/domain/entities/code_niveau.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/chantier_structure.dart';

CodeNiveau _code(String code, TypeNiveau type, {bool standard = true}) => CodeNiveau(
      id: 'id-$code',
      typeNiveau: type,
      code: code,
      standard: standard,
    );

void main() {
  group('TypeNiveauX', () {
    test('fait l’aller-retour sur les trois sections', () {
      for (final type in TypeNiveau.values) {
        expect(TypeNiveauX.fromString(type.raw), type);
      }
    });

    test('range un type inconnu parmi les étages', () {
      // Même défaut que le serveur. Écarter la valeur ferait DISPARAÎTRE le
      // niveau de l'écran sans que rien ne le signale — bien pire que de le
      // ranger dans la section la plus probable.
      expect(TypeNiveauX.fromString('mezzanine'), TypeNiveau.etage);
      expect(TypeNiveauX.fromString(null), TypeNiveau.etage);
    });

    test('envoie les valeurs attendues par le serveur', () {
      // Ces chaînes sont le contrat : les changer casserait la validation Joi
      // sans qu'aucun test de compilation ne le voie.
      expect(TypeNiveau.sousSol.raw, 'sous_sol');
      expect(TypeNiveau.etage.raw, 'etage');
      expect(TypeNiveau.toiture.raw, 'toiture');
    });
  });

  group('CodeNiveau.fromJson', () {
    test('reconnaît un code du catalogue standard', () {
      // `organisationId` nul = catalogue de la plateforme. C'est ce qui
      // distingue un code que l'organisation peut retirer d'un code qu'elle
      // ne fait qu'utiliser.
      final c = CodeNiveau.fromJson({
        'id': '1',
        'typeNiveau': 'sous_sol',
        'code': 'SS1',
        'nom': 'Sous-sol 1',
        'organisationId': null,
      });

      expect(c.standard, isTrue);
      expect(c.typeNiveau, TypeNiveau.sousSol);
      expect(c.libelle, 'SS1 — Sous-sol 1');
    });

    test('reconnaît un code propre à l’organisation', () {
      final c = CodeNiveau.fromJson({
        'id': '2',
        'typeNiveau': 'etage',
        'code': 'R+12',
        'organisationId': 'org1',
      });

      expect(c.standard, isFalse);
    });

    test('se rabat sur le code quand le libellé manque', () {
      // Cas du code créé à la volée depuis le mobile : l'entreprise tape un
      // code, pas une phrase.
      final c = CodeNiveau.fromJson({'id': '3', 'typeNiveau': 'toiture', 'code': 'TOIT'});

      expect(c.libelle, 'TOIT');
    });

    test('accepte la casse serpent du serveur', () {
      final c = CodeNiveau.fromJson({'id': '4', 'type_niveau': 'toiture', 'code': 'COMB'});
      expect(c.typeNiveau, TypeNiveau.toiture);
    });
  });

  group('DepotPlansState.codesDe', () {
    test('ne propose que les codes de la section demandée', () {
      // C'est tout l'intérêt des trois sections : la liste sous « SOUS-SOLS »
      // ne doit pas mélanger les codes de toiture.
      const etat = DepotPlansState(codes: []);
      final avecCodes = etat.copyWith(codes: [
        _code('SS1', TypeNiveau.sousSol),
        _code('SS2', TypeNiveau.sousSol),
        _code('RDC', TypeNiveau.etage),
        _code('TOIT', TypeNiveau.toiture),
      ]);

      expect(avecCodes.codesDe(TypeNiveau.sousSol).map((c) => c.code), ['SS1', 'SS2']);
      expect(avecCodes.codesDe(TypeNiveau.etage).map((c) => c.code), ['RDC']);
      expect(avecCodes.codesDe(TypeNiveau.toiture).map((c) => c.code), ['TOIT']);
    });

    test('rend une liste vide pour une section sans code', () {
      const etat = DepotPlansState();
      expect(etat.codesDe(TypeNiveau.toiture), isEmpty);
    });
  });

  group('EtageStructure.fromJson', () {
    test('lit la nature, le code et la description du niveau', () {
      final e = EtageStructure.fromJson({
        'id': 'e1',
        'nom': 'SS1',
        'niveau': -1,
        'typeNiveau': 'sous_sol',
        'codeNiveau': 'SS1',
        'description': 'Parking',
      });

      expect(e.typeNiveau, TypeNiveau.sousSol);
      expect(e.codeNiveau, 'SS1');
      expect(e.description, 'Parking');
    });

    test('range parmi les étages un niveau saisi avant le référentiel', () {
      // Les étages existants n'ont ni nature ni code : la migration leur a
      // donné `etage`, et le mobile doit dire la même chose.
      final e = EtageStructure.fromJson({'id': 'e2', 'nom': 'Niveau 3'});

      expect(e.typeNiveau, TypeNiveau.etage);
      expect(e.codeNiveau, isNull);
    });
  });
}

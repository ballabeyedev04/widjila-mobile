import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/corps_etat/data/datasources/corps_etat_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/phase/data/datasources/phase_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/referentiel/data/datasources/referentiel_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/referentiel/domain/entities/code_niveau.dart';
import 'package:suivie_chantier_mobile/features/referentiel/domain/entities/type_referentiel.dart';

import '../../../../helpers/dio_espion.dart';

/// Les APIs de RÉFÉRENTIEL — types, pays, codes de niveau, corps d'état,
/// phases.
///
/// ## Pourquoi elles sont réunies ici
///
/// Ce sont cinq catalogues administrables, tous bâtis sur le même modèle :
/// une lecture, une enveloppe, une liste. Les séparer en cinq fichiers
/// n'aurait multiplié que l'échafaudage ; ce qu'ils ont d'intéressant tient
/// en deux points, communs aux cinq.
///
/// **Le nom de l'enveloppe change à chaque catalogue** — `types`, `pays`,
/// `codes`, `corpsEtat`, `phases`. Rien ne les uniformise côté serveur, donc
/// rien ne rattrape une confusion côté mobile : le cast échoue et le
/// formulaire qui en dépend s'ouvre sans aucune option à choisir.
///
/// **Le chemin des types est CALCULÉ** depuis l'énumération
/// (`referentiel.chemin`). C'est le seul endroit de l'application où un
/// chemin d'API n'est pas écrit en toutes lettres : une valeur ajoutée à
/// l'énumération sans son chemin partirait vers `/null/actifs`.
void main() {
  late DioEspion espion;

  setUp(() => espion = DioEspion());

  group('types de référentiel', () {
    test('le chemin est calculé depuis le catalogue demandé', () async {
      final source = ReferentielRemoteDataSourceImpl(dio: dioDeTest(espion));
      espion.repond({
        'success': true,
        'data': {
          'types': [
            {'id': 't1', 'code': 'entreprise', 'libelle': 'Entreprise'},
          ],
        },
      });

      final types = await source.getTypesActifs(ReferentielType.intervenant);

      expect(espion.appel, 'GET ${ReferentielType.intervenant.chemin}/actifs');
      expect(types, hasLength(1));
    });

    test('chaque catalogue vise SON chemin, pas celui du voisin', () async {
      // Les trois catalogues sont distincts côté serveur. Se tromper de
      // chemin remplirait le sélecteur de types de document avec des types
      // d'intervenant — une confusion qui ne se voit qu'à l'usage.
      for (final referentiel in ReferentielType.values) {
        final propre = DioEspion();
        final source = ReferentielRemoteDataSourceImpl(dio: dioDeTest(propre));
        propre.repond({
          'success': true,
          'data': {'types': <dynamic>[]},
        });

        await source.getTypesActifs(referentiel);

        expect(propre.requete.path, '${referentiel.chemin}/actifs');
      }
    });
  });

  test('les pays sont lus sous leur propre enveloppe', () async {
    final source = ReferentielRemoteDataSourceImpl(dio: dioDeTest(espion));
    espion.repond({
      'success': true,
      'data': {
        'pays': [
          {'code': 'SN', 'nom': 'Sénégal', 'indicatif': '+221'},
          {'code': 'FR', 'nom': 'France', 'indicatif': '+33'},
        ],
      },
    });

    final pays = await source.getPays();

    expect(espion.appel, 'GET /referentiels/pays');
    expect(pays, hasLength(2));
    expect(pays.first.code, 'SN');
    expect(pays.first.indicatif, '+221');
  });

  group('codes de niveau', () {
    test('la lecture relit l’enveloppe « codes »', () async {
      final source = ReferentielRemoteDataSourceImpl(dio: dioDeTest(espion));
      espion.repond({
        'success': true,
        'data': {
          'codes': [
            {'id': 'c1', 'code': 'R+1', 'typeNiveau': 'etage'},
          ],
        },
      });

      final codes = await source.getCodesNiveau();

      expect(espion.appel, 'GET /referentiels/codes-niveau');
      expect(codes, hasLength(1));
    });

    test('la création nomme la nature du niveau sous l’écriture serveur',
        () async {
      final source = ReferentielRemoteDataSourceImpl(dio: dioDeTest(espion));
      espion.repond({
        'success': true,
        'data': {
          'code': {'id': 'c9', 'code': 'SS2', 'typeNiveau': 'sous_sol'},
        },
      });

      await source.creerCodeNiveau(typeNiveau: TypeNiveau.sousSol, code: 'SS2');

      expect(espion.appel, 'POST /referentiels/codes-niveau');
      final corps = espion.requete.data as Map<String, dynamic>;
      // `sous_sol`, jamais `sousSol`.
      expect(corps['typeNiveau'], 'sous_sol');
      expect(corps['code'], 'SS2');
    });
  });

  test('les corps d’état ont leur enveloppe en camel : « corpsEtat »', () async {
    // Le serveur écrit ce catalogue en camel là où il écrit les autres en
    // minuscules. C'est une irrégularité, et c'est exactement le genre de
    // détail qu'un test fige plutôt qu'une convention.
    final source = CorpsEtatRemoteDataSourceImpl(dio: dioDeTest(espion));
    espion.repond({
      'success': true,
      'data': {
        'corpsEtat': [
          {'id': 'ce1', 'code': 'GO', 'libelle': 'Gros œuvre'},
        ],
      },
    });

    final corps = await source.getCorpsEtatActifs();

    expect(espion.appel, 'GET /corps-etat/actifs');
    expect(corps, hasLength(1));
  });

  test('les phases sont lues sous l’enveloppe « phases »', () async {
    final source = PhaseRemoteDataSourceImpl(dio: dioDeTest(espion));
    espion.repond({
      'success': true,
      'data': {
        'phases': [
          {'id': 'ph1', 'code': 'gros_oeuvre', 'libelle': 'Gros œuvre'},
        ],
      },
    });

    final phases = await source.getPhasesActives();

    expect(espion.appel, 'GET /phases/actives');
    expect(phases, hasLength(1));
  });

  test('un catalogue vide reste une liste vide, jamais une erreur', () async {
    // Un référentiel non encore alimenté est une situation normale au
    // démarrage d'un client. Elle ne doit pas se présenter comme une panne :
    // le formulaire s'ouvre, simplement sans option.
    final source = PhaseRemoteDataSourceImpl(dio: dioDeTest(espion));
    espion.repond({
      'success': true,
      'data': {'phases': <dynamic>[]},
    });

    expect(await source.getPhasesActives(), isEmpty);
  });
}

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/document/data/datasources/document_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/document/domain/entities/document.dart';

import '../../../../helpers/dio_espion.dart';

/// L'API Document.
///
/// ## Le filtre par type
///
/// L'écran répartit les fichiers en trois onglets — photos, vidéos, autres —
/// à partir d'une SEULE requête. Le paramètre `type` sert donc au filtre
/// explicite de l'utilisateur, pas à la répartition en onglets. Envoyer un
/// type par défaut ferait disparaître les deux autres onglets sans que
/// personne ne comprenne pourquoi.
void main() {
  late DioEspion espion;
  late DocumentRemoteDataSourceImpl source;
  late Directory dossier;

  setUp(() {
    espion = DioEspion();
    source = DocumentRemoteDataSourceImpl(dio: dioDeTest(espion));
    dossier = Directory.systemTemp.createTempSync('documents_test');
  });

  tearDown(() => dossier.deleteSync(recursive: true));

  String fichierTemporaire(String nom) {
    final f = File('${dossier.path}${Platform.pathSeparator}$nom')
      ..writeAsBytesSync(List<int>.filled(64, 0));
    return f.path;
  }

  test('la liste passe par le chemin du chantier', () async {
    espion.repond({
      'success': true,
      'data': {
        'documents': [
          {
            'id': 'd1',
            'chantierId': 'c1',
            'type': 'doe',
            'nom_fichier': 'DOE.pdf',
            'fichier_url': 'https://exemple.test/d1.pdf',
          },
        ],
      },
    });

    final documents = await source.getDocuments(chantierId: 'c1');

    expect(espion.appel, 'GET /chantiers/c1/documents');
    expect(documents, hasLength(1));
  });

  test('sans filtre, AUCUN type n’est imposé', () async {
    // Les trois onglets viennent d'une seule requête : imposer un type ici
    // en viderait deux.
    espion.repond({
      'success': true,
      'data': {'documents': <dynamic>[]},
    });

    await source.getDocuments(chantierId: 'c1');

    expect(espion.requete.queryParameters.containsKey('type'), isFalse);
    expect(espion.requete.queryParameters.containsKey('search'), isFalse);
  });

  test('un filtre explicite part sous l’écriture du serveur', () async {
    espion.repond({
      'success': true,
      'data': {'documents': <dynamic>[]},
    });

    await source.getDocuments(chantierId: 'c1', type: DocumentType.compteRendu);

    // `compte_rendu`, pas `compteRendu`.
    expect(espion.requete.queryParameters['type'], DocumentType.compteRendu.raw);
  });

  test('une recherche vide n’est pas envoyée', () async {
    espion.repond({
      'success': true,
      'data': {'documents': <dynamic>[]},
    });

    await source.getDocuments(chantierId: 'c1', search: '');

    expect(espion.requete.queryParameters.containsKey('search'), isFalse);
  });

  test('le dépôt envoie le fichier ET son type', () async {
    espion.repond({
      'success': true,
      'data': {
        'document': {
          'id': 'd9',
          'chantierId': 'c1',
          'type': 'photo',
          'nom_fichier': 'photo.jpg',
          'fichier_url': 'https://exemple.test/d9.jpg',
        },
      },
    });

    await source.ajouterDocument(
      chantierId: 'c1',
      cheminFichier: fichierTemporaire('photo.jpg'),
      type: DocumentType.photo,
    );

    expect(espion.appel, 'POST /chantiers/c1/documents');
    final formulaire = espion.requete.data as FormData;
    expect(formulaire.files.map((e) => e.key), contains('fichier'));
    expect(
      formulaire.fields.firstWhere((e) => e.key == 'type').value,
      DocumentType.photo.raw,
    );
  });
}

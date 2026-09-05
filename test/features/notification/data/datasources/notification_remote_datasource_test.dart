import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/notification/data/datasources/notification_remote_datasource.dart';

import '../../../../helpers/dio_espion.dart';

/// L'API Notification.
///
/// ## Le compteur qui compte
///
/// `nonLuesCount` alimente la pastille rouge de la cloche, présente sur tous
/// les écrans. Une clé mal orthographiée ne provoque aucune erreur : le
/// `as num?` rend `null`, le `?? 0` en fait un zéro, et la pastille disparaît
/// pour de bon. Personne ne signale une alerte qui ne s'affiche pas — on
/// suppose simplement qu'il n'y a rien à lire.
///
/// ## Marquer tout comme lu
///
/// La même route sert à marquer une sélection ET la totalité. Sans
/// identifiants, le corps doit être VIDE, et non `{"ids": []}` : une liste
/// vide se lit côté serveur comme « ces zéro notifications-là », c'est-à-dire
/// aucune — le bouton « tout marquer comme lu » ne ferait rien.
void main() {
  late DioEspion espion;
  late NotificationRemoteDataSourceImpl source;

  setUp(() {
    espion = DioEspion();
    source = NotificationRemoteDataSourceImpl(dio: dioDeTest(espion));
  });

  test('la liste relit ses trois chiffres : éléments, total, non lues', () async {
    espion.repond({
      'success': true,
      'data': {
        'notifications': [
          {
            'id': 'n1',
            'type': 'reserve_creee',
            'titre': 'Nouvelle réserve',
            'message': 'Une réserve vous a été affectée.',
            'lu_le': null,
          },
        ],
        'total': 42,
        'nonLuesCount': 7,
      },
    });

    final page = await source.lister(page: 2, limit: 20);

    expect(espion.appel, 'GET /notifications');
    expect(espion.requete.queryParameters['page'], 2);
    expect(page.items, hasLength(1));
    expect(page.total, 42);
    // Le compteur de la pastille — la valeur la plus visible de l'API.
    expect(page.nonLues, 7);
  });

  test('le compteur seul a sa propre route, plus légère', () async {
    // La cloche est présente sur tous les écrans : lui faire rapatrier la
    // liste entière à chaque affichage coûterait une page de données pour un
    // seul entier.
    espion.repond({
      'success': true,
      'data': {'nonLuesCount': 3},
    });

    final nb = await source.compterNonLues();

    expect(espion.appel, 'GET /notifications/non-lues/count');
    expect(nb, 3);
  });

  test('un compteur absent vaut zéro, sans faire tomber l’écran', () async {
    espion.repond({'success': true, 'data': <String, dynamic>{}});

    expect(await source.compterNonLues(), 0);
  });

  test('« tout marquer comme lu » envoie un corps VIDE', () async {
    espion.repond({'success': true, 'data': <String, dynamic>{}});

    await source.marquerLues(const []);

    expect(espion.appel, 'PATCH /notifications/lues');
    // Pas de clé `ids` : sa présence avec une liste vide désignerait zéro
    // notification, et le bouton n'aurait aucun effet.
    expect((espion.requete.data as Map<String, dynamic>).containsKey('ids'), isFalse);
  });

  test('une sélection nomme ses identifiants', () async {
    espion.repond({'success': true, 'data': <String, dynamic>{}});

    await source.marquerLues(const ['n1', 'n2']);

    expect((espion.requete.data as Map<String, dynamic>)['ids'], ['n1', 'n2']);
  });

  group('jeton d’appareil', () {
    test('l’enregistrement nomme le jeton ET la plateforme', () async {
      // La plateforme décide du service d'envoi côté serveur : l'omettre
      // rendrait le jeton inutilisable.
      espion.repond({'success': true, 'data': <String, dynamic>{}});

      await source.enregistrerAppareil('jeton-abc', 'android');

      expect(espion.appel, 'POST /notifications/device-token');
      final corps = espion.requete.data as Map<String, dynamic>;
      expect(corps['token'], 'jeton-abc');
      expect(corps['platform'], 'android');
    });

    test('l’oubli passe le jeton dans le CORPS, pas dans l’URL', () async {
      // Un jeton de notification est un secret d'appareil : dans une URL, il
      // finirait dans les journaux d'accès du serveur et des proxys.
      espion.repond({'success': true, 'data': <String, dynamic>{}});

      await source.oublierAppareil('jeton-abc');

      expect(espion.appel, 'DELETE /notifications/device-token');
      expect((espion.requete.data as Map<String, dynamic>)['token'], 'jeton-abc');
      expect(espion.requete.uri.toString(), isNot(contains('jeton-abc')));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/core/offline/cache_reserves.dart';
import 'package:suivie_chantier_mobile/core/offline/executeur_actions.dart';
import 'package:suivie_chantier_mobile/core/offline/file_attente.dart';
import 'package:suivie_chantier_mobile/core/offline/stockage_medias.dart';
import 'package:suivie_chantier_mobile/features/reserve/data/datasources/reserve_remote_datasource.dart';

class MockReserveRemoteDataSource extends Mock implements ReserveRemoteDataSource {}

class MockCacheReserves extends Mock implements CacheReserves {}

class MockStockageMedias extends Mock implements StockageMedias {}

/// Action de création telle qu'elle est déposée dans la file hors ligne.
ActionEnAttente action(Map<String, dynamic> charge) => ActionEnAttente(
      id: 'a-1',
      type: TypeAction.creerReserve,
      charge: {
        'id': 'res-1',
        'chantierId': 'ch-1',
        'titre': 'Fissure au plafond',
        ...charge,
      },
      creeLe: DateTime(2026, 8, 30),
    );

void main() {
  late MockReserveRemoteDataSource reserves;
  late MockCacheReserves cache;
  late ExecuteurActionsHorsLigne executeur;

  setUp(() {
    reserves = MockReserveRemoteDataSource();
    cache = MockCacheReserves();
    executeur = ExecuteurActionsHorsLigne(
      reserves: reserves,
      cache: cache,
      medias: MockStockageMedias(),
    );
  });

  group('rejeu d’une création de réserve', () {
    // Le cas de la mise à jour : une réserve déposée dans la file AVANT que la
    // phase devienne obligatoire côté serveur. Elle ne doit pas partir pour se
    // faire refuser par un 400 dont le message ne dit pas quoi faire de la
    // réserve déjà saisie.
    test('refuse une action héritée sans phase, sans appeler le serveur', () async {
      await expectLater(
        executeur.executer(action({})),
        throwsA(isA<ServerException>()
            // 400 : `SynchronisationService` en fait un échec DÉFINITIF, ce
            // qui est exact — la retenter échouera toujours — et libère la
            // file au lieu de la bloquer derrière cette action.
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', contains('phase'))),
      );

      // Ni appel réseau, ni ligne marquée comme confirmée : la réserve reste
      // locale, telle que l'utilisateur l'a saisie.
      verifyZeroInteractions(reserves);
      verifyZeroInteractions(cache);
    });

    test('le message indique la marche à suivre', () async {
      // Ce message s'affiche tel quel dans l'écran de synchronisation : il
      // doit dire quoi faire, pas seulement ce qui manque.
      try {
        await executeur.executer(action({}));
        fail('une ServerException était attendue');
      } on ServerException catch (e) {
        expect(e.message, contains('à nouveau'));
      }
    });

    test('laisse passer une action portant une phase', () async {
      // La garde ne doit filtrer QUE l'absence de phase : elle est franchie
      // ici, et c'est l'appel réseau (non simulé) qui échoue ensuite. Le
      // contrat vérifié est donc « ce n'est plus notre ServerException 400 ».
      await expectLater(
        executeur.executer(action({'phaseId': 'ph-1'})),
        throwsA(isNot(isA<ServerException>()
            .having((e) => e.message, 'message', contains('phase')))),
      );
    });
  });
}

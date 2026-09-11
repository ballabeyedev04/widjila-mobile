import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/core/network/cache_reponses_get.dart';
import 'package:suivie_chantier_mobile/core/network/dio_exception_mapper.dart';
import 'package:suivie_chantier_mobile/features/rapport/data/datasources/rapport_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/envoi_rapport.dart';
import 'package:suivie_chantier_mobile/features/reserve/data/datasources/reserve_remote_datasource.dart';

import '../../helpers/dio_espion.dart';

DioException _refus(int statut, Map<String, dynamic> corps) {
  final options = RequestOptions(path: '/x');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: statut, data: corps),
  );
}

/// Audit synchronisation — le CONTRAT HTTP entre le mobile et le backend
/// corrigé : ce qui part (chemin, paramètres, en-têtes) et ce qui est relu
/// (code d'erreur stable).
void main() {
  group('Code d’erreur stable (mapDioException)', () {
    test('le `code` du serveur voyage avec l’exception', () {
      final e = mapDioException(_refus(409, {'message': 'Déjà en cours', 'code': 'ENVOI_EN_COURS'}));

      expect(e, isA<ServerException>()
          .having((s) => s.statusCode, 'statut', 409)
          .having((s) => s.code, 'code', 'ENVOI_EN_COURS'));
    });

    test('un refus d’abonnement garde son préfixe d’affichage ET son code', () {
      final e = mapDioException(_refus(403, {'message': 'Abonnement requis', 'code': 'SUBSCRIPTION_REQUIRED'}))
          as ServerException;

      expect(e.code, 'SUBSCRIPTION_REQUIRED');
      expect(e.message, contains('SUBSCRIPTION_REQUIRED'));
    });

    test('sans code, `code` est nul', () {
      final e = mapDioException(_refus(400, {'message': 'Transition impossible'})) as ServerException;

      expect(e.code, isNull);
    });
  });

  group('GET /sync/reserves', () {
    late DioEspion espion;
    late ReserveRemoteDataSourceImpl source;

    setUp(() {
      espion = DioEspion();
      source = ReserveRemoteDataSourceImpl(dio: dioDeTest(espion));
    });

    test('envoie le curseur et la limite, et contourne le cache des GET', () async {
      espion.repond({
        'success': true,
        'data': {
          'modifiees': [
            {'id': 'a', 'numero': 'R-0001', 'chantierId': 'ch-1', 'titre': 'Fissure', 'statut': 'creee'},
          ],
          'supprimees': [
            {'id': 'z', 'supprimeeLe': '2026-09-10T09:00:00Z'},
          ],
          'curseur': 'c2',
          'termine': false,
        },
      });

      final lot = await source.syncReserves(curseur: 'c1');

      expect(espion.appel, 'GET /sync/reserves');
      expect(espion.requete.queryParameters, {'curseur': 'c1', 'limite': 200});
      expect(espion.requete.extra[CacheReponsesGet.ignorerCache], isTrue,
          reason: 'deux tirages rapprochés doivent voir ce qui a changé entre-temps');
      expect(lot.modifiees.single.id, 'a');
      expect(lot.supprimees, ['z']);
      expect(lot.curseur, 'c2');
      expect(lot.termine, isFalse);
    });

    test('premier tirage : aucun curseur envoyé', () async {
      espion.repond({
        'success': true,
        'data': {'modifiees': [], 'supprimees': [], 'curseur': 'c0', 'termine': true},
      });

      await source.syncReserves();

      expect(espion.requete.queryParameters.containsKey('curseur'), isFalse);
    });
  });

  group('POST /reports/:id/send-email — Idempotency-Key', () {
    late DioEspion espion;
    late RapportRemoteDataSourceImpl source;

    setUp(() {
      espion = DioEspion();
      source = RapportRemoteDataSourceImpl(dio: dioDeTest(espion));
      espion.repond({'success': true, 'message': 'Envoyé', 'data': {}});
    });

    test('la clé part dans l’en-tête', () async {
      await source.envoyerRapport('r1', const DemandeEnvoiRapport(), cleIdempotence: 'cle-1234567890');

      expect(espion.requete.headers['Idempotency-Key'], 'cle-1234567890');
    });

    test('sans clé, aucun en-tête inventé', () async {
      await source.envoyerRapport('r1', const DemandeEnvoiRapport());

      expect(espion.requete.headers.containsKey('Idempotency-Key'), isFalse);
    });
  });
}

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/errors/error_codes.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/core/network/dio_exception_mapper.dart';

/// Message que Dio pose sur une réponse d'erreur — c'est lui qui s'affichait.
const _messageDio = 'This exception was thrown because the response has a status code of 502 '
    'and RequestOptions.validateStatus was configured to throw for this status code.';

DioException _reponse(int statut, Object? corps, {Map<String, List<String>> entetes = const {}, String? message}) {
  final options = RequestOptions(path: '/reserves', headers: {'X-Request-Id': 'envoye-par-le-mobile'});
  return DioException(
    requestOptions: options,
    response: Response<dynamic>(
      requestOptions: options,
      statusCode: statut,
      data: corps,
      headers: Headers.fromMap(entetes),
    ),
    type: DioExceptionType.badResponse,
    message: message ?? _messageDio,
  );
}

/// Audit observabilité — conversion des erreurs HTTP.
///
/// Défaut reproduit : une réponse d'erreur SANS corps JSON — typiquement la
/// page HTML de nginx en 502/504 quand l'API est arrêtée ou redémarre —
/// retombait sur le message technique de Dio, affiché tel quel, en anglais,
/// dans l'écran d'erreur.
void main() {
  test('502 du proxy (page HTML) : plus de texte technique de Dio', () {
    final e = mapDioException(_reponse(502, '<html><body>502 Bad Gateway</body></html>')) as ServerException;

    expect(e.message, ErrCodes.serviceUnavailable);
    expect(e.message, isNot(contains('exception')));
    expect(e.statusCode, 502);
  });

  test('4xx sans corps : marqueur générique, jamais le texte de Dio', () {
    final e = mapDioException(_reponse(404, null)) as ServerException;

    expect(e.message, ErrCodes.generic);
  });

  test('le marqueur posé par l’intercepteur (403/429/503 sans message) est conservé', () {
    final e = mapDioException(_reponse(429, null, message: ErrCodes.rateLimit)) as ServerException;

    expect(e.message, ErrCodes.rateLimit);
  });

  test('corps au nouveau format : message, code uniforme et requestId remontent', () {
    final e = mapDioException(_reponse(500, {
      'success': false,
      'message': 'Erreur interne du serveur',
      'error': {'code': 'ERREUR_INTERNE', 'message': 'Erreur interne du serveur'},
      'requestId': 'req-serveur-1234',
    })) as ServerException;

    expect(e.message, 'Erreur interne du serveur');
    expect(e.codeErreur, 'ERREUR_INTERNE');
    expect(e.requestId, 'req-serveur-1234');
    // Le code de premier niveau reste réservé aux codes métier explicites :
    // la synchronisation classe ses reprises dessus.
    expect(e.code, isNull);
  });

  test('sans requestId dans le corps : repris de l’en-tête de réponse, sinon de la requête', () {
    final avecEntete = mapDioException(_reponse(502, '<html/>', entetes: {
      'x-request-id': ['entete-reponse-1'],
    })) as ServerException;
    final sansRien = mapDioException(_reponse(502, '<html/>')) as ServerException;

    expect(avecEntete.requestId, 'entete-reponse-1');
    expect(sansRien.requestId, 'envoye-par-le-mobile');
  });

  test('non-régression : refus d’abonnement toujours préfixé, code conservé', () {
    final e = mapDioException(_reponse(403, {
      'message': 'Abonnement requis',
      'code': 'SUBSCRIPTION_REQUIRED',
      'error': {'code': 'SUBSCRIPTION_REQUIRED', 'message': 'Abonnement requis'},
      'requestId': 'req-abo-00001',
    })) as ServerException;

    expect(e.message, '${ErrCodes.prefixeAbonnement}SUBSCRIPTION_REQUIRED|Abonnement requis');
    expect(e.code, 'SUBSCRIPTION_REQUIRED');
    expect(e.requestId, 'req-abo-00001');
  });

  test('non-régression : détails de validation joints au message', () {
    final e = mapDioException(_reponse(422, {
      'message': 'Données invalides',
      'details': ['"titre" est requis'],
    })) as ServerException;

    expect(e.message, 'Données invalides\n"titre" est requis');
  });

  test('coupure réseau : toujours une NetworkException', () {
    final e = mapDioException(DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.connectionError,
    ));

    expect(e, isA<NetworkException>());
  });
}

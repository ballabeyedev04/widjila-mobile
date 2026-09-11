import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/errors/error_codes.dart';
import 'package:suivie_chantier_mobile/core/errors/exception_to_failure.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/services/collecteur_erreurs.dart';

class _PuitsEspion implements PuitsErreurs {
  final List<Object> nonFatales = [];
  final List<Map<String, Object?>> contextes = [];

  @override
  void erreurFlutter(FlutterErrorDetails details) {}

  @override
  void erreur(Object erreur, StackTrace? pile) {}

  @override
  void erreurNonFatale(Object erreur, StackTrace? pile, {String? raison, Map<String, Object?> contexte = const {}}) {
    nonFatales.add(erreur);
    contextes.add({'raison': raison, ...contexte});
  }

  @override
  void identifierUtilisateur(String? id) {}
}

/// Audit observabilité — les échecs affichés ne restent plus invisibles pour l'équipe.
///
/// Défauts reproduits :
///   - une erreur NON typée (réponse mal lue, `null` inattendu) s'affichait en
///     clair — « type 'Null' is not a subtype of type 'String' » — et ne
///     partait nulle part ;
///   - une erreur serveur 5xx devenait un « Réessayer » à l'écran, sans aucun
///     rapport : l'équipe l'apprenait par un appel au support.
void main() {
  late _PuitsEspion puits;

  setUp(() {
    collecteurErreurs.reinitialiser();
    puits = _PuitsEspion();
    collecteurErreurs.brancher(puits);
  });

  tearDown(collecteurErreurs.reinitialiser);

  test('erreur non typée : message générique (pas de texte technique) ET signalement', () {
    final failure = exceptionToFailure(TypeError());

    expect(failure, isA<ServerFailure>());
    expect(failure.errorMessage, ErrCodes.generic);
    expect(puits.nonFatales.single, isA<TypeError>());
    expect(puits.contextes.single['raison'], contains('TypeError'));
  });

  test('erreur serveur 5xx : signalée avec son requestId', () {
    final failure = exceptionToFailure(const ServerException(
      message: 'Erreur interne du serveur',
      statusCode: 500,
      codeErreur: 'ERREUR_INTERNE',
      requestId: 'req-serveur-1234',
    ));

    expect(failure.errorMessage, 'Erreur interne du serveur');
    expect(puits.contextes.single, containsPair('requestId', 'req-serveur-1234'));
    expect(puits.contextes.single, containsPair('statut', 500));
  });

  test('refus métier 4xx : affiché, PAS signalé (ce n’est pas un défaut)', () {
    exceptionToFailure(const ServerException(message: 'Transition impossible', statusCode: 400));
    exceptionToFailure(const ServerException(message: 'Introuvable', statusCode: 404));

    expect(puits.nonFatales, isEmpty);
  });

  test('coupure réseau : échec réseau, pas signalé', () {
    final failure = exceptionToFailure(const NetworkException());

    expect(failure, isA<NetworkFailure>());
    expect(puits.nonFatales, isEmpty);
  });

  test('DioException non convertie par la source : convertie ici, pas prise pour un bug', () {
    final failure = exceptionToFailure(DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.connectionTimeout,
    ));

    expect(failure, isA<NetworkFailure>());
    expect(puits.nonFatales, isEmpty);
  });

  test('non-régression : session expirée → AuthFailure', () {
    expect(exceptionToFailure(const UnauthorizedException()), isA<AuthFailure>());
  });
}

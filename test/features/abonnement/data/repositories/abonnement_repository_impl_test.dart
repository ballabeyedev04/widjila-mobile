import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/features/abonnement/data/datasources/abonnement_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/abonnement/data/repositories/abonnement_repository_impl.dart';
import 'package:suivie_chantier_mobile/features/abonnement/domain/entities/abonnement.dart';

class _MockRemote extends Mock implements AbonnementRemoteDataSource {}

/// Le dépôt Abonnement — ce qu'il fait des pannes.
///
/// Deux politiques opposées, et c'est voulu :
///  - les DROITS ont un repli en mémoire : hors ligne, l'application doit
///    continuer de savoir quoi afficher (le serveur reste seul juge) ;
///  - le CODE DE TRANSFERT et l'HISTORIQUE n'en ont aucun : un code ne sert
///    qu'une fois et deux minutes, un montant périmé tromperait.
void main() {
  late _MockRemote remote;
  late AbonnementRepositoryImpl depot;

  setUp(() {
    remote = _MockRemote();
    depot = AbonnementRepositoryImpl(remote);
  });

  group('code de transfert vers le web', () {
    test('relaie le code du serveur', () async {
      when(() => remote.creerCodeTransfertWeb()).thenAnswer((_) async => 'code-court');

      final r = await depot.creerCodeTransfertWeb();

      expect(r.getOrElse(() => ''), 'code-court');
    });

    test('un refus reste un ÉCHEC — jamais un code vide', () async {
      // Un code vide ouvrirait la page de paiement sans session : exactement
      // les 401 que ce transfert sert à éviter.
      when(() => remote.creerCodeTransfertWeb())
          .thenThrow(const ServerException(message: 'Compte désactivé', statusCode: 403));

      expect((await depot.creerCodeTransfertWeb()).isLeft(), isTrue);
    });

    test('hors ligne : échec, et rien de mis en cache pour la fois suivante', () async {
      when(() => remote.creerCodeTransfertWeb()).thenThrow(const NetworkException());
      expect((await depot.creerCodeTransfertWeb()).isLeft(), isTrue);

      when(() => remote.creerCodeTransfertWeb()).thenAnswer((_) async => 'code-2');
      expect((await depot.creerCodeTransfertWeb()).getOrElse(() => ''), 'code-2');
    });
  });

  group('droits', () {
    const droits = DroitsAbonnement(actif: true, source: 'abonnement', planCode: 'pro');

    test('hors ligne, les DERNIERS droits reçus servent de repli', () async {
      when(() => remote.getDroits()).thenAnswer((_) async => droits);
      await depot.getDroits();

      when(() => remote.getDroits()).thenThrow(const NetworkException());
      final r = await depot.getDroits();

      expect(r.getOrElse(() => const DroitsAbonnement()), droits);
    });

    test('sans rien reçu auparavant, la panne remonte', () async {
      when(() => remote.getDroits()).thenThrow(const NetworkException());

      expect((await depot.getDroits()).isLeft(), isTrue);
    });
  });

  test('historique : aucun repli — un montant périmé tromperait', () async {
    when(() => remote.getHistorique()).thenThrow(const NetworkException());

    expect((await depot.getHistorique()).isLeft(), isTrue);
  });
}

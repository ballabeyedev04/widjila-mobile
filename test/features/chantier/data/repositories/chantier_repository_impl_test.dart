import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/core/offline/base_locale.dart';
import 'package:suivie_chantier_mobile/core/offline/cache_chantiers.dart';
import 'package:suivie_chantier_mobile/features/chantier/data/datasources/chantier_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/chantier/data/repositories/chantier_repository_impl.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/entities/chantier.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/repositories/chantier_repository.dart';

class MockChantierRemoteDataSource extends Mock implements ChantierRemoteDataSource {}

Chantier _chantierServeur({String id = 'c1', String nom = 'Résidence Y'}) =>
    Chantier(id: id, nom: nom, statut: ChantierStatut.enCours);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late BaseLocale base;
  late CacheChantiers cache;
  late MockChantierRemoteDataSource remote;

  setUp(() async {
    base = BaseLocale.instance;
    await base.fermer();
    await base.viderTout();
    cache = CacheChantiers(base);
    remote = MockChantierRemoteDataSource();
  });

  tearDown(() async {
    await base.viderTout();
    await base.fermer();
  });

  ChantierRepositoryImpl repository() => ChantierRepositoryImpl(remote, cache: cache);

  test('liste en ligne : la réponse serveur est mise en cache', () async {
    when(() => remote.getChantiers(page: any(named: 'page'), limit: any(named: 'limit')))
        .thenAnswer((_) async => ChantierPage(items: [_chantierServeur()], total: 1));

    final resultat = await repository().getChantiers();

    expect(resultat.isRight(), isTrue);
    expect(await cache.lire('c1'), isNotNull);
  });

  test('liste hors ligne (coupure réseau) : sert le cache', () async {
    await cache.enregistrer(_chantierServeur(id: 'en-cache', nom: 'Vu hier'));
    when(() => remote.getChantiers(page: any(named: 'page'), limit: any(named: 'limit')))
        .thenThrow(const NetworkException());

    final resultat = await repository().getChantiers();

    expect(resultat.isRight(), isTrue);
    resultat.fold((_) => fail('doit réussir depuis le cache'), (page) {
      expect(page.items.single.nom, 'Vu hier');
    });
  });

  test('refus applicatif : ne retombe pas sur le cache', () async {
    await cache.enregistrer(_chantierServeur(id: 'en-cache'));
    when(() => remote.getChantiers(page: any(named: 'page'), limit: any(named: 'limit')))
        .thenThrow(const ServerException(message: 'Abonnement expiré', statusCode: 402));

    final resultat = await repository().getChantiers();

    expect(resultat.isLeft(), isTrue);
  });

  test('détail hors ligne : sert la fiche en cache si connue', () async {
    await cache.enregistrer(_chantierServeur(id: 'c9', nom: 'Chantier connu'));
    when(() => remote.getChantierDetail('c9')).thenThrow(const NetworkException());

    final resultat = await repository().getChantierDetail('c9');

    expect(resultat.isRight(), isTrue);
    resultat.fold((_) => fail('doit réussir'), (c) => expect(c.nom, 'Chantier connu'));
  });

  test('détail hors ligne : échoue si le chantier n’a jamais été consulté', () async {
    when(() => remote.getChantierDetail('inconnu')).thenThrow(const NetworkException());

    final resultat = await repository().getChantierDetail('inconnu');

    expect(resultat.isLeft(), isTrue);
  });
}

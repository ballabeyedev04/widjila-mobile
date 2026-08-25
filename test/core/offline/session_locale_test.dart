import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/offline/base_locale.dart';
import 'package:suivie_chantier_mobile/core/offline/session_locale.dart';
import 'package:suivie_chantier_mobile/core/offline/stockage_medias.dart';

class MockBaseLocale extends Mock implements BaseLocale {}

class MockStockageMedias extends Mock implements StockageMedias {}

/// Tests de non-régression du cloisonnement entre comptes — voir
/// `SessionLocale` pour le raisonnement complet.
///
/// Ce qui est vérifié ici est la propriété de sécurité la plus importante de
/// l'application sur un appareil de chantier PARTAGÉ : un compte ne doit
/// jamais lire, ni resynchroniser, les données hors ligne d'un autre.
void main() {
  late MockBaseLocale base;
  late MockStockageMedias medias;
  late SessionLocale session;

  setUp(() {
    base = MockBaseLocale();
    medias = MockStockageMedias();
    session = SessionLocale(base: base, medias: medias);

    when(() => base.viderTout()).thenAnswer((_) async {});
    when(() => base.definirProprietaire(any())).thenAnswer((_) async {});
    when(() => medias.viderTout()).thenAnswer((_) async {});
  });

  group('adopterUtilisateur', () {
    test('purge tout quand les données appartiennent à un AUTRE compte', () async {
      when(() => base.proprietaire()).thenAnswer((_) async => 'utilisateur-A');

      await session.adopterUtilisateur('utilisateur-B');

      verify(() => base.viderTout()).called(1);
      verify(() => medias.viderTout()).called(1);
    });

    test('ne purge RIEN quand c\'est le même compte qui revient', () async {
      // Cas nominal : redémarrage de l'app, reconnexion après expiration de
      // session. Purger ici détruirait le travail hors ligne non synchronisé.
      when(() => base.proprietaire()).thenAnswer((_) async => 'utilisateur-A');

      await session.adopterUtilisateur('utilisateur-A');

      verifyNever(() => base.viderTout());
      verifyNever(() => medias.viderTout());
    });

    test('ne purge RIEN sur une base vierge (première connexion)', () async {
      when(() => base.proprietaire()).thenAnswer((_) async => null);

      await session.adopterUtilisateur('utilisateur-A');

      verifyNever(() => base.viderTout());
      verify(() => base.definirProprietaire('utilisateur-A')).called(1);
    });

    test('écrit le propriétaire APRÈS la purge, jamais avant', () async {
      // `viderTout()` vide aussi `sync_meta` : l'ordre inverse effacerait le
      // propriétaire qu'on vient de poser, et la purge se rejouerait
      // indéfiniment à chaque connexion.
      when(() => base.proprietaire()).thenAnswer((_) async => 'utilisateur-A');

      await session.adopterUtilisateur('utilisateur-B');

      verifyInOrder([
        () => base.viderTout(),
        () => base.definirProprietaire('utilisateur-B'),
      ]);
    });

    test('purge les PHOTOS autant que les tables', () async {
      // Sans cette purge, les photos du compte précédent — géolocalisées,
      // horodatées — resteraient sur le disque indéfiniment : vider la file
      // d'attente détruit les seuls chemins qui les référençaient.
      when(() => base.proprietaire()).thenAnswer((_) async => 'utilisateur-A');

      await session.adopterUtilisateur('utilisateur-B');

      verify(() => medias.viderTout()).called(1);
    });
  });

  group('purger', () {
    test('efface les tables ET les photos hors ligne', () async {
      await session.purger();

      verify(() => base.viderTout()).called(1);
      verify(() => medias.viderTout()).called(1);
    });
  });
}

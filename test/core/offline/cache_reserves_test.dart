import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:suivie_chantier_mobile/core/offline/base_locale.dart';
import 'package:suivie_chantier_mobile/core/offline/cache_reserves.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';

Reserve _reserve(String id, {String titre = 'Fissure', String chantier = 'c1'}) =>
    Reserve(id: id, numero: 'R-$id', chantierId: chantier, titre: titre, statut: ReserveStatut.creee);

/// Le miroir local des réserves — invalidation et travail hors ligne.
void main() {
  late BaseLocale base;
  late CacheReserves cache;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Base PROPRE à ce fichier : `flutter test` exécute les fichiers en
    // parallèle sur le même disque, et ils vident tous la base au démarrage.
    BaseLocale.surchargeNomFichier = 'test_cache_reserves.db';
  });

  setUp(() async {
    base = BaseLocale.instance;
    await base.viderTout();
    cache = CacheReserves(base);
  });

  tearDown(() async => base.viderTout());

  group('suppression', () {
    test('supprimer() retire la ligne du miroir local', () async {
      // Sans cette methode, une reserve supprimee sur le serveur restait en
      // base : masquee tant qu'on etait en ligne — la reponse reseau fait
      // autorite — puis REAPPARAISSANT au premier repli hors ligne, sans
      // qu'aucune action de l'utilisateur puisse l'en faire partir.
      await cache.enregistrer(_reserve('a'));
      await cache.enregistrer(_reserve('b'));
      expect((await cache.listerTout()).length, 2);

      await cache.supprimer('a');

      final restantes = await cache.listerTout();
      expect(restantes.map((r) => r.id), ['b']);
    });

    test('supprimer() un id inconnu ne casse rien', () async {
      await cache.enregistrer(_reserve('a'));
      await cache.supprimer('inexistante');
      expect((await cache.listerTout()).length, 1);
    });
  });

  group('enregistrerTous : les modifications hors ligne survivent', () {
    test('une ligne EN ATTENTE n’est pas ecrasee par la version serveur', () async {
      // Course reelle au retour du reseau : le rafraichissement de la liste et
      // la vidange de la file partent ensemble. La version serveur est
      // l'ANCIENNE — l'ecrire remettait le texte d'avant a l'ecran et faisait
      // disparaitre le badge « en attente d'envoi ».
      await cache.enregistrer(_reserve('a', titre: 'Titre corrige hors ligne'), enAttente: true);

      await cache.enregistrerTous([_reserve('a', titre: 'Ancien titre serveur')]);

      final relue = await cache.lire('a');
      expect(relue!.titre, 'Titre corrige hors ligne');
      expect(await cache.estEnAttente('a'), isTrue,
          reason: 'le badge « en attente d’envoi » doit rester');
    });

    test('les lignes CONFIRMEES sont bien mises a jour, elles', () async {
      await cache.enregistrer(_reserve('b', titre: 'Ancien'));

      await cache.enregistrerTous([_reserve('b', titre: 'Nouveau')]);

      expect((await cache.lire('b'))!.titre, 'Nouveau');
      expect(await cache.estEnAttente('b'), isFalse);
    });

    test('une page serveur melangee ne touche que ce qu’elle doit', () async {
      await cache.enregistrer(_reserve('a', titre: 'Local en attente'), enAttente: true);
      await cache.enregistrer(_reserve('b', titre: 'Ancien confirme'));

      await cache.enregistrerTous([
        _reserve('a', titre: 'Serveur perime'),
        _reserve('b', titre: 'Serveur frais'),
        _reserve('c', titre: 'Nouvelle du serveur'),
      ]);

      expect((await cache.lire('a'))!.titre, 'Local en attente');
      expect((await cache.lire('b'))!.titre, 'Serveur frais');
      expect((await cache.lire('c'))!.titre, 'Nouvelle du serveur');
      expect(await cache.estEnAttente('a'), isTrue);
    });

    test('une liste vide ne fait rien et ne leve pas', () async {
      await cache.enregistrer(_reserve('a'));
      await cache.enregistrerTous([]);
      expect((await cache.listerTout()).length, 1);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/core/offline/base_locale.dart';
import 'package:suivie_chantier_mobile/core/offline/cache_reserves.dart';
import 'package:suivie_chantier_mobile/core/offline/tirage_reserves.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';

Reserve _reserve(String id, {ReserveStatut statut = ReserveStatut.creee, String titre = 'Fissure'}) => Reserve(
      id: id,
      numero: 'R-$id',
      chantierId: 'ch-1',
      titre: titre,
      statut: statut,
    );

LotSyncReserves _lot({
  List<Reserve> modifiees = const [],
  List<String> supprimees = const [],
  required String curseur,
  bool termine = true,
}) =>
    LotSyncReserves(modifiees: modifiees, supprimees: supprimees, curseur: curseur, termine: termine);

/// Audit synchronisation — tirage INCRÉMENTAL des réserves vers le cache.
///
/// Défaut corrigé : une réserve supprimée sur le serveur restait dans le
/// cache et réapparaissait hors ligne ; une réserve modifiée ailleurs restait
/// sur son ancienne version tant que son écran n'était pas rouvert en ligne.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    BaseLocale.surchargeNomFichier = 'test_tirage_reserves.db';
  });

  late BaseLocale base;
  late CacheReserves cache;

  setUp(() async {
    base = BaseLocale.instance;
    await base.fermer();
    await base.viderTout();
    await base.definirProprietaire('u-1');
    cache = CacheReserves(base);
  });

  tearDown(() async {
    await base.viderTout();
    await base.fermer();
  });

  TirageReserves tirage(List<Object> pages, {List<String?>? curseursRecus, int pagesMax = 50}) {
    var i = 0;
    return TirageReserves(
      base: base,
      cache: cache,
      pagesMax: pagesMax,
      lireLot: (curseur) async {
        curseursRecus?.add(curseur);
        final page = pages[i < pages.length ? i : pages.length - 1];
        i++;
        if (page is Exception) throw page;
        if (page is Future<LotSyncReserves> Function()) return page();
        return page as LotSyncReserves;
      },
    );
  }

  test('premier tirage : part de l’origine, remplit le cache, retient le curseur', () async {
    final curseurs = <String?>[];
    final t = tirage([_lot(modifiees: [_reserve('a'), _reserve('b')], curseur: 'c1')], curseursRecus: curseurs);

    final pages = await t.tirer();

    expect(pages, 1);
    expect(curseurs, [null]);
    expect((await cache.listerTout()).map((r) => r.id).toSet(), {'a', 'b'});
    expect(await t.curseur(), 'c1');
  });

  test('enchaîne les pages jusqu’à « terminé », chacune reprenant au curseur précédent', () async {
    final curseurs = <String?>[];
    final t = tirage([
      _lot(modifiees: [_reserve('a')], curseur: 'c1', termine: false),
      _lot(modifiees: [_reserve('b')], curseur: 'c2', termine: false),
      _lot(modifiees: [_reserve('c')], curseur: 'c3'),
    ], curseursRecus: curseurs);

    expect(await t.tirer(), 3);
    expect(curseurs, [null, 'c1', 'c2']);
    expect(await t.curseur(), 'c3');
    expect(await cache.listerTout(), hasLength(3));
  });

  test('une SUPPRESSION serveur retire la réserve du cache (elle ne réapparaîtra plus hors ligne)', () async {
    await cache.enregistrer(_reserve('morte'));

    await tirage([_lot(supprimees: ['morte'], curseur: 'c1')]).tirer();

    expect(await cache.lire('morte'), isNull);
  });

  test('la suppression serveur l’emporte même sur une ligne en attente', () async {
    await cache.enregistrer(_reserve('morte'), enAttente: true);

    await tirage([_lot(supprimees: ['morte'], curseur: 'c1')]).tirer();

    expect(await cache.lire('morte'), isNull);
  });

  test('une MODIFICATION serveur n’écrase pas un changement local encore en file', () async {
    await cache.enregistrer(_reserve('r', statut: ReserveStatut.corrigee), enAttente: true);

    await tirage([_lot(modifiees: [_reserve('r', statut: ReserveStatut.affectee)], curseur: 'c1')]).tirer();

    expect((await cache.lire('r'))!.statut, ReserveStatut.corrigee);
    expect(await cache.estEnAttente('r'), isTrue);
  });

  test('une modification serveur met à jour une ligne à jour', () async {
    await cache.enregistrer(_reserve('r', titre: 'Ancien titre'));

    await tirage([_lot(modifiees: [_reserve('r', titre: 'Titre corrigé ailleurs')], curseur: 'c1')]).tirer();

    expect((await cache.lire('r'))!.titre, 'Titre corrigé ailleurs');
  });

  test('coupure en cours de tirage : les pages complètes restent, la reprise repart de la dernière', () async {
    final curseurs = <String?>[];
    final t = tirage([
      _lot(modifiees: [_reserve('a')], curseur: 'c1', termine: false),
      const NetworkException(),
    ], curseursRecus: curseurs);

    await expectLater(t.tirer(), throwsA(isA<NetworkException>()));

    expect(await t.curseur(), 'c1', reason: 'la page 1 est appliquée et retenue');
    expect(await cache.lire('a'), isNotNull);

    final reprise = <String?>[];
    await tirage([_lot(modifiees: [_reserve('b')], curseur: 'c2')], curseursRecus: reprise).tirer();
    expect(reprise, ['c1'], reason: 'reprise exacte, sans retélécharger la page 1');
  });

  test('changement de compte PENDANT le tirage : la page en vol n’écrit RIEN', () async {
    // Sans cette garde, les réserves du compte précédent atterrissaient dans
    // la base toute neuve du suivant.
    final t = tirage([
      () async {
        await base.viderTout();
        await base.definirProprietaire('u-2');
        return _lot(modifiees: [_reserve('du-compte-precedent')], curseur: 'c1');
      },
    ]);

    expect(await t.tirer(), 0);
    expect(await cache.lire('du-compte-precedent'), isNull);
    expect(await t.curseur(), isNull);
  });

  test('base sans propriétaire : aucun tirage', () async {
    await base.viderTout();
    var appels = 0;
    final t = TirageReserves(
      base: base,
      cache: cache,
      lireLot: (_) async {
        appels++;
        return _lot(curseur: 'c1');
      },
    );

    expect(await t.tirer(), 0);
    expect(appels, 0);
  });

  test('borné à pagesMax pages par appel', () async {
    final t = tirage([_lot(modifiees: [_reserve('a')], curseur: 'c', termine: false)], pagesMax: 3);

    expect(await t.tirer(), 3);
  });

  test('une base purgée repart d’un tirage complet', () async {
    await tirage([_lot(curseur: 'c9')]).tirer();
    await base.viderTout();
    await base.definirProprietaire('u-1');

    final curseurs = <String?>[];
    await tirage([_lot(curseur: 'c1')], curseursRecus: curseurs).tirer();
    expect(curseurs, [null]);
  });

  test('LotSyncReserves lit le format EXACT du serveur', () {
    final lot = LotSyncReserves.fromJson({
      'modifiees': [_reserve('a').toJson()],
      'supprimees': [
        {'id': 'z', 'supprimeeLe': '2026-09-10T09:00:00Z'},
      ],
      'curseur': 'eyJtIjoiMjAyNiJ9',
      'termine': false,
    });

    expect(lot.modifiees.single.id, 'a');
    expect(lot.supprimees, ['z']);
    expect(lot.curseur, 'eyJtIjoiMjAyNiJ9');
    expect(lot.termine, isFalse);
  });
}

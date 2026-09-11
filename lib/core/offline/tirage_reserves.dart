import 'package:sqflite/sqflite.dart';

import '../../features/reserve/domain/entities/reserve.dart';
import 'base_locale.dart';
import 'cache_reserves.dart';

/// Une page du tirage incrémental — réponse de `GET /sync/reserves`.
class LotSyncReserves {
  /// Réserves créées ou modifiées depuis le curseur, au format des listes.
  final List<Reserve> modifiees;

  /// Identifiants des réserves supprimées depuis le curseur (« pierres
  /// tombales »).
  final List<String> supprimees;

  /// Position de reprise, opaque : à renvoyer tel quel au tirage suivant.
  final String curseur;

  /// `false` s'il reste au moins une page à tirer.
  final bool termine;

  const LotSyncReserves({
    required this.modifiees,
    required this.supprimees,
    required this.curseur,
    required this.termine,
  });

  factory LotSyncReserves.fromJson(Map<String, dynamic> data) => LotSyncReserves(
        modifiees: ((data['modifiees'] as List?) ?? const [])
            .map((e) => Reserve.fromJson(e as Map<String, dynamic>))
            .toList(),
        supprimees: ((data['supprimees'] as List?) ?? const [])
            .map((e) => (e as Map)['id'] as String)
            .toList(),
        curseur: data['curseur'] as String,
        termine: data['termine'] as bool? ?? true,
      );
}

/// Tirage INCRÉMENTAL des réserves : le serveur → le cache local.
///
/// ## Le défaut corrigé
///
/// Le cache ne se remplissait qu'au fil des écrans consultés en ligne, et ne
/// se vidait jamais : une réserve supprimée sur le serveur (depuis le web, ou
/// par un autre appareil) restait en base locale et RÉAPPARAISSAIT hors
/// ligne ; une réserve modifiée ailleurs restait sur son ancienne version.
///
/// ## Garanties
///
///  - **Reprise exacte** : chaque page est appliquée dans UNE transaction avec
///    le curseur qui la suit. Une application tuée en pleine page reprend à la
///    dernière page complète — ni trou, ni page appliquée deux fois à moitié.
///  - **Travail local protégé** : une réserve en attente d'envoi n'est jamais
///    écrasée par une version serveur (voir `CacheReserves.appliquerTirage`).
///  - **Aucun mélange de comptes** : le tirage note le propriétaire des
///    données au départ et n'écrit RIEN si la base a changé de main entre-temps
///    (déconnexion, autre compte) — sans cela, une page en vol pouvait écrire
///    les réserves du compte précédent dans la base toute neuve du suivant.
///  - **Borné** : au plus [pagesMax] pages par appel, pour qu'un premier
///    tirage sur une grosse organisation ne bloque pas la synchronisation.
class TirageReserves {
  /// Clé de `sync_meta` portant le curseur. Effacée avec le reste par
  /// `BaseLocale.viderTout` : une base purgée repart d'un tirage complet.
  static const String cleCurseur = 'curseur_reserves';

  final BaseLocale _base;
  final CacheReserves _cache;
  final Future<LotSyncReserves> Function(String? curseur) _lireLot;
  final int _pagesMax;

  // ignore_for_file: prefer_initializing_formals
  TirageReserves({
    required BaseLocale base,
    required CacheReserves cache,
    required Future<LotSyncReserves> Function(String? curseur) lireLot,
    int pagesMax = 50,
  })  : _base = base,
        _cache = cache,
        _lireLot = lireLot,
        _pagesMax = pagesMax;

  /// Curseur de reprise enregistré, `null` avant le premier tirage.
  Future<String?> curseur() async {
    final db = await _base.base;
    final lignes = await db.query(
      BaseLocale.tableSyncMeta,
      where: 'cle = ?',
      whereArgs: [cleCurseur],
      limit: 1,
    );
    return lignes.isEmpty ? null : lignes.first['valeur'] as String?;
  }

  /// Tire les changements jusqu'à épuisement (ou [pagesMax] pages).
  ///
  /// Retourne le nombre de pages APPLIQUÉES. Lève si le réseau ou le serveur
  /// échoue : le curseur n'a alors pas bougé, rien n'est perdu, et l'appelant
  /// décide quand réessayer.
  Future<int> tirer() async {
    // Base sans propriétaire : aucune session n'a encore adopté ces données
    // (ou elles viennent d'être purgées). Rien ne doit y être écrit.
    final proprietaire = await _base.proprietaire();
    if (proprietaire == null) return 0;

    var pages = 0;
    while (pages < _pagesMax) {
      final lot = await _lireLot(await curseur());
      final db = await _base.base;
      var applique = false;
      await db.transaction((txn) async {
        final actuel = await txn.query(
          BaseLocale.tableSyncMeta,
          columns: ['valeur'],
          where: 'cle = ?',
          whereArgs: ['proprietaire'],
          limit: 1,
        );
        if (actuel.isEmpty || actuel.first['valeur'] != proprietaire) return;
        await _cache.appliquerTirage(modifiees: lot.modifiees, supprimees: lot.supprimees, executeur: txn);
        await txn.insert(
          BaseLocale.tableSyncMeta,
          {'cle': cleCurseur, 'valeur': lot.curseur},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        applique = true;
      });
      if (!applique) break;
      pages++;
      if (lot.termine) break;
    }
    return pages;
  }
}

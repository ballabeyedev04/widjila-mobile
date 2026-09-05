import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../features/reserve/domain/entities/reserve.dart';
import 'base_locale.dart';

/// Miroir local de la table `reserves`.
///
/// Même principe que [CacheChantiers] : stockage en JSON via [Reserve.toJson],
/// relecture via [Reserve.fromJson]. La colonne `en_attente` s'ajoute au JSON
/// pour distinguer une réserve confirmée par le serveur d'une réserve créée
/// ou modifiée hors ligne, pas encore synchronisée — c'est elle qui alimente
/// le badge « en attente d'envoi » sur la carte.
class CacheReserves {
  final BaseLocale _base;
  CacheReserves(this._base);

  Future<void> enregistrer(Reserve reserve, {bool enAttente = false}) async {
    final db = await _base.base;
    await db.insert(
      BaseLocale.tableReserves,
      {
        'id': reserve.id,
        'chantier_id': reserve.chantierId,
        'donnees': jsonEncode(reserve.toJson()),
        'maj_le': DateTime.now().millisecondsSinceEpoch,
        'en_attente': enAttente ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> enregistrerTous(List<Reserve> reserves) async {
    if (reserves.isEmpty) return;
    final db = await _base.base;

    // Les lignes EN ATTENTE sont épargnées.
    //
    // Elles portent une modification faite hors ligne que le serveur ne
    // connaît pas encore : l'action correspondante est toujours dans la file.
    // La version qui arrive du réseau est donc l'ANCIENNE. L'écrire par-dessus
    // — ce que faisait `ConflictAlgorithm.replace` avec `en_attente: 0` —
    // remettait le texte d'avant à l'écran et faisait disparaître le badge
    // « en attente d'envoi », donnant une donnée périmée pour confirmée.
    //
    // C'est une vraie course : au retour du réseau, le rafraîchissement de la
    // liste et la vidange de la file partent en même temps. La ligne redevient
    // normale d'elle-même quand l'action aboutit — c'est `ExecuteurActions`
    // qui la réécrit alors avec `enAttente: false`.
    //
    // Une seule requête, sans clause `IN` : les lignes en attente sont par
    // nature peu nombreuses, et cela évite la limite de variables de SQLite.
    final enAttente = (await db.query(
      BaseLocale.tableReserves,
      columns: ['id'],
      where: 'en_attente = 1',
    ))
        .map((l) => l['id'] as String)
        .toSet();

    final lot = db.batch();
    for (final r in reserves) {
      if (enAttente.contains(r.id)) continue;
      lot.insert(
        BaseLocale.tableReserves,
        {
          'id': r.id,
          'chantier_id': r.chantierId,
          'donnees': jsonEncode(r.toJson()),
          'maj_le': DateTime.now().millisecondsSinceEpoch,
          'en_attente': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await lot.commit(noResult: true);
  }

  /// Retire une réserve du miroir local.
  ///
  /// Sans elle, une réserve supprimée sur le serveur restait indéfiniment en
  /// base : la liste la masquait tant qu'on était en ligne — la réponse
  /// réseau fait autorité — puis elle RÉAPPARAISSAIT au premier repli hors
  /// ligne, sans qu'aucune action de l'utilisateur puisse la faire partir.
  Future<void> supprimer(String id) async {
    final db = await _base.base;
    await db.delete(BaseLocale.tableReserves, where: 'id = ?', whereArgs: [id]);
  }

  Future<Reserve?> lire(String id) async {
    final db = await _base.base;
    final lignes = await db.query(BaseLocale.tableReserves, where: 'id = ?', whereArgs: [id], limit: 1);
    if (lignes.isEmpty) return null;
    return Reserve.fromJson(jsonDecode(lignes.first['donnees'] as String) as Map<String, dynamic>);
  }

  /// `true` si cette réserve a été créée ou modifiée hors ligne et n'a pas
  /// encore été confirmée par le serveur.
  Future<bool> estEnAttente(String id) async {
    final db = await _base.base;
    final lignes = await db.query(
      BaseLocale.tableReserves,
      columns: ['en_attente'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (lignes.isEmpty) return false;
    return (lignes.first['en_attente'] as int?) == 1;
  }

  Future<List<Reserve>> listerParChantier(String chantierId) async {
    final db = await _base.base;
    final lignes = await db.query(
      BaseLocale.tableReserves,
      where: 'chantier_id = ?',
      whereArgs: [chantierId],
      orderBy: 'maj_le DESC',
    );
    return lignes
        .map((l) => Reserve.fromJson(jsonDecode(l['donnees'] as String) as Map<String, dynamic>))
        .toList();
  }

  Future<List<Reserve>> listerTout() async {
    final db = await _base.base;
    final lignes = await db.query(BaseLocale.tableReserves, orderBy: 'maj_le DESC');
    return lignes
        .map((l) => Reserve.fromJson(jsonDecode(l['donnees'] as String) as Map<String, dynamic>))
        .toList();
  }
}

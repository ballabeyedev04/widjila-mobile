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
    final db = await _base.base;
    final lot = db.batch();
    for (final r in reserves) {
      lot.insert(
        BaseLocale.tableReserves,
        {
          'id': r.id,
          'chantier_id': r.chantierId,
          'donnees': jsonEncode(r.toJson()),
          'maj_le': DateTime.now().millisecondsSinceEpoch,
          // Une réserve qui arrive du RÉSEAU est par définition confirmée :
          // ne jamais écraser un `en_attente` local avec `enregistrerTous`
          // serait une erreur, mais ce chemin ne sert justement qu'aux
          // réponses serveur.
          'en_attente': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await lot.commit(noResult: true);
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

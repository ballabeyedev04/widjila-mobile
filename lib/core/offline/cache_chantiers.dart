import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../features/chantier/domain/entities/chantier.dart';
import 'base_locale.dart';

/// Miroir local de la table `chantiers` — lu quand le réseau est absent.
///
/// L'entité est stockée en JSON brut (voir la justification dans
/// `BaseLocale._creerSchema`) : `enregistrer` appelle [Chantier.toJson], la
/// lecture repasse par [Chantier.fromJson]. C'est ce même chemin qui décode
/// aussi bien une réponse réseau fraîche qu'une ligne mise en cache hier —
/// aucune divergence de format possible entre les deux sources.
class CacheChantiers {
  final BaseLocale _base;
  CacheChantiers(this._base);

  Future<void> enregistrer(Chantier chantier) async {
    final db = await _base.base;
    await db.insert(
      BaseLocale.tableChantiers,
      {
        'id': chantier.id,
        'donnees': jsonEncode(chantier.toJson()),
        'maj_le': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> enregistrerTous(List<Chantier> chantiers) async {
    final db = await _base.base;
    // `Batch` : un aller-retour SQLite pour toute la page plutôt qu'un par
    // chantier — la liste transversale peut en compter plusieurs dizaines.
    final lot = db.batch();
    for (final c in chantiers) {
      lot.insert(
        BaseLocale.tableChantiers,
        {
          'id': c.id,
          'donnees': jsonEncode(c.toJson()),
          'maj_le': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await lot.commit(noResult: true);
  }

  Future<Chantier?> lire(String id) async {
    final db = await _base.base;
    final lignes = await db.query(BaseLocale.tableChantiers, where: 'id = ?', whereArgs: [id], limit: 1);
    if (lignes.isEmpty) return null;
    return Chantier.fromJson(jsonDecode(lignes.first['donnees'] as String) as Map<String, dynamic>);
  }

  /// Tous les chantiers en cache, les plus récemment vus en premier.
  ///
  /// Aucune pagination : hors ligne, il n'existe pas de « page 2 » côté
  /// serveur à demander — l'écran affiche tout ce qui a déjà été consulté.
  Future<List<Chantier>> listerTout() async {
    final db = await _base.base;
    final lignes = await db.query(BaseLocale.tableChantiers, orderBy: 'maj_le DESC');
    return lignes
        .map((l) => Chantier.fromJson(jsonDecode(l['donnees'] as String) as Map<String, dynamic>))
        .toList();
  }
}

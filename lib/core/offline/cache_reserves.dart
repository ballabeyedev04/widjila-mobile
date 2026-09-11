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

  /// Écrit (ou remplace) une réserve.
  ///
  /// [executeur] — transaction en cours, quand l'écriture doit être ATOMIQUE
  /// avec une autre (dépôt de l'action correspondante dans la file, voir
  /// `FileAttente.deposer`). Absent : la base elle-même.
  Future<void> enregistrer(Reserve reserve, {bool enAttente = false, DatabaseExecutor? executeur}) async {
    final db = executeur ?? await _base.base;
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
    final enAttente = await _idsEnAttente(db);

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

  /// Applique UNE page du tirage incrémental (`GET /sync/reserves`).
  ///
  /// Toujours appelée dans la transaction qui enregistre aussi le curseur
  /// (voir `TirageReserves`) : la page et la position de reprise avancent
  /// ensemble, ou pas du tout — une application tuée en pleine page reprend
  /// exactement là où la dernière page COMPLÈTE s'est arrêtée.
  ///
  /// Règles de conflit :
  ///  - SUPPRESSION : le serveur l'emporte, même sur une ligne en attente. Une
  ///    réserve supprimée ne peut plus recevoir de changement ; les actions
  ///    qui la visaient échoueront en 404 et resteront visibles, avec leur
  ///    motif, dans l'écran des tâches ;
  ///  - MODIFICATION : une ligne en attente est épargnée, pour la même raison
  ///    que dans [enregistrerTous] — la version serveur est plus ancienne que
  ///    le changement local encore en file.
  Future<void> appliquerTirage({
    required List<Reserve> modifiees,
    required List<String> supprimees,
    required DatabaseExecutor executeur,
  }) async {
    if (modifiees.isEmpty && supprimees.isEmpty) return;
    final enAttente = await _idsEnAttente(executeur);
    final maintenant = DateTime.now().millisecondsSinceEpoch;

    final lot = executeur.batch();
    for (final id in supprimees) {
      lot.delete(BaseLocale.tableReserves, where: 'id = ?', whereArgs: [id]);
    }
    for (final r in modifiees) {
      if (enAttente.contains(r.id)) continue;
      lot.insert(
        BaseLocale.tableReserves,
        {
          'id': r.id,
          'chantier_id': r.chantierId,
          'donnees': jsonEncode(r.toJson()),
          'maj_le': maintenant,
          'en_attente': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await lot.commit(noResult: true);
  }

  Future<Set<String>> _idsEnAttente(DatabaseExecutor db) async => (await db.query(
        BaseLocale.tableReserves,
        columns: ['id'],
        where: 'en_attente = 1',
      ))
          .map((l) => l['id'] as String)
          .toSet();

  /// Relâche une ligne restée « en attente » : elle redevient écrasable par
  /// la version du serveur.
  ///
  /// Contrepartie indispensable de la protection d'[enregistrerTous], qui
  /// épargne les lignes `en_attente = 1`. Cette protection garde le travail
  /// non synchronisé — mais si l'action correspondante est DÉFINITIVEMENT
  /// refusée, plus rien ne viendrait jamais la lever : la ligne restait
  /// éternellement figée sur une valeur que le serveur n'a pas acceptée.
  Future<void> libererEnAttente(String id) async {
    final db = await _base.base;
    await db.update(
      BaseLocale.tableReserves,
      {'en_attente': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
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

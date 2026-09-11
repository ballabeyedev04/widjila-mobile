import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../features/reserve/domain/entities/reserve.dart';
import 'base_locale.dart';
import 'file_attente.dart';
import 'reconciliation.dart';

/// Miroir local de la table `reserves`.
///
/// Même principe que [CacheChantiers] : stockage en JSON via [Reserve.toJson],
/// relecture via [Reserve.fromJson]. La colonne `en_attente` s'ajoute au JSON
/// pour distinguer une réserve confirmée par le serveur d'une réserve créée
/// ou modifiée hors ligne, pas encore synchronisée — c'est elle qui alimente
/// le badge « en attente d'envoi » sur la carte.
///
/// ## Qui fait foi (deuxième audit)
///
/// Voir `reconciliation.dart` : toute version venue du SERVEUR (liste,
/// tirage, détail, réponse à une action) passe par la réconciliation — les
/// changements locaux encore en file sont rejoués dessus. Une réserve
/// supprimée localement et dont la suppression n'est pas encore partie n'est
/// jamais réinsérée par une réponse serveur.
class CacheReserves {
  final BaseLocale _base;
  CacheReserves(this._base);

  /// Écrit (ou remplace) une réserve, SANS condition.
  ///
  /// [executeur] — transaction en cours, quand l'écriture doit être ATOMIQUE
  /// avec une autre (dépôt de l'action correspondante dans la file, voir
  /// `FileAttente.deposer`). Absent : la base elle-même.
  ///
  /// Réservée aux écritures qui SAVENT ce qu'elles font (écriture optimiste,
  /// restauration). Une version venue du serveur passe par [reconcilier].
  Future<void> enregistrer(Reserve reserve, {bool enAttente = false, DatabaseExecutor? executeur}) async {
    final db = executeur ?? await _base.base;
    await db.insert(
      BaseLocale.tableReserves,
      _ligne(reserve, enAttente: enAttente, majLe: DateTime.now().millisecondsSinceEpoch),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Map<String, Object?> _ligne(Reserve r, {required bool enAttente, required int majLe}) => {
        'id': r.id,
        'chantier_id': r.chantierId,
        'donnees': jsonEncode(r.toJson()),
        'maj_le': majLe,
        'en_attente': enAttente ? 1 : 0,
      };

  /// Écrit une version SERVEUR en y rejouant les changements locaux encore en
  /// file ; retourne la VUE résultante (celle à afficher), ou `null` si une
  /// suppression locale est en attente.
  ///
  /// [saufAction] — action en cours de confirmation : déjà appliquée par le
  /// serveur, elle ne compte pas parmi les changements « encore en file ».
  ///
  /// Lecture de la file et écriture dans la MÊME transaction : une action
  /// déposée entre les deux ne peut pas être écrasée.
  Future<Reserve?> reconcilier(Reserve serveur, {String? saufAction}) async {
    final db = await _base.base;
    return db.transaction((txn) => _reconcilier(txn, serveur, saufAction: saufAction));
  }

  Future<Reserve?> _reconcilier(DatabaseExecutor db, Reserve serveur, {String? saufAction, int? majLe}) async {
    final horodatage = majLe ?? DateTime.now().millisecondsSinceEpoch;
    final actions = await _actionsLocales(db, serveur.id, saufAction: saufAction);
    if (actions.isEmpty) {
      // Ligne « en attente » SANS action en file : état hérité d'une version
      // antérieure à l'écriture atomique. Prudence : on garde la version
      // locale, jamais on n'efface ce que l'utilisateur voit sans preuve.
      if (saufAction == null) {
        final existante = await db.query(
          BaseLocale.tableReserves,
          columns: ['donnees', 'en_attente'],
          where: 'id = ?',
          whereArgs: [serveur.id],
          limit: 1,
        );
        if (existante.isNotEmpty && existante.first['en_attente'] == 1) {
          return Reserve.fromJson(jsonDecode(existante.first['donnees'] as String) as Map<String, dynamic>);
        }
      }
      await db.insert(BaseLocale.tableReserves, _ligne(serveur, enAttente: false, majLe: horodatage),
          conflictAlgorithm: ConflictAlgorithm.replace);
      return serveur;
    }
    final vue = rejouerActionsLocales(serveur, actions);
    if (vue == null) return null;
    await db.insert(BaseLocale.tableReserves, _ligne(vue, enAttente: true, majLe: horodatage),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return vue;
  }

  /// Actions EN ATTENTE qui réécrivent la réserve [id], dans leur ordre —
  /// requête indexée sur `cle_entite` (schéma v2).
  Future<List<ActionEnAttente>> _actionsLocales(DatabaseExecutor db, String id, {String? saufAction}) async {
    final types = typesQuiReecriventLaReserve.map((t) => t.code).toList();
    final lignes = await db.query(
      BaseLocale.tableFileAttente,
      where: 'cle_entite = ? AND statut = ? AND id != ? AND type IN (${List.filled(types.length, '?').join(', ')})',
      whereArgs: ['reserve:$id', ActionEnAttente.statutAttente, saufAction ?? '', ...types],
      orderBy: 'cree_le ASC',
    );
    final actions = <ActionEnAttente>[];
    for (final l in lignes) {
      try {
        actions.add(ActionEnAttente.depuisLigne(l));
      } catch (_) {
        // Type inconnu (version plus récente) : ignoré, comme dans la file.
      }
    }
    return actions;
  }

  /// Réserves dont la SUPPRESSION locale n'est pas encore partie.
  Future<Set<String>> idsEnSuppression() async => _idsEnSuppression(await _base.base);

  Future<Set<String>> _idsEnSuppression(DatabaseExecutor db) async => (await db.query(
        BaseLocale.tableFileAttente,
        columns: ['cle_entite'],
        where: 'type = ? AND statut = ?',
        whereArgs: [TypeAction.supprimerReserve.code, ActionEnAttente.statutAttente],
      ))
          .map((l) => (l['cle_entite'] as String? ?? '').replaceFirst('reserve:', ''))
          .where((id) => id.isNotEmpty)
          .toSet();

  /// Écrit une PAGE de versions serveur (liste en ligne).
  ///
  /// Les lignes sans changement local sont remplacées d'un bloc. Les lignes
  /// en attente sont RÉCONCILIÉES (voir [reconcilier]) — elles ne sont plus
  /// figées. Une réserve supprimée localement n'est pas réinsérée.
  Future<void> enregistrerTous(List<Reserve> reserves) async {
    if (reserves.isEmpty) return;
    final db = await _base.base;
    await db.transaction((txn) => _appliquerVersionsServeur(txn, reserves));
  }

  Future<void> _appliquerVersionsServeur(DatabaseExecutor db, List<Reserve> reserves) async {
    final enAttente = await _idsEnAttente(db);
    final enSuppression = await _idsEnSuppression(db);
    final maintenant = DateTime.now().millisecondsSinceEpoch;

    final lot = db.batch();
    final aReconcilier = <Reserve>[];
    for (final r in reserves) {
      if (enSuppression.contains(r.id)) continue;
      if (enAttente.contains(r.id)) {
        aReconcilier.add(r);
        continue;
      }
      lot.insert(BaseLocale.tableReserves, _ligne(r, enAttente: false, majLe: maintenant),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await lot.commit(noResult: true);
    for (final r in aReconcilier) {
      await _reconcilier(db, r, majLe: maintenant);
    }
  }

  /// Applique UNE page du tirage incrémental (`GET /sync/reserves`).
  ///
  /// Toujours appelée dans la transaction qui enregistre aussi le curseur
  /// (voir `TirageReserves`) : la page et la position de reprise avancent
  /// ensemble, ou pas du tout — une application tuée en pleine page reprend
  /// exactement là où la dernière page COMPLÈTE s'est arrêtée.
  ///
  /// Règles de conflit :
  ///  - SUPPRESSION serveur : le serveur l'emporte, même sur une ligne en
  ///    attente. Une réserve supprimée ne peut plus recevoir de changement ;
  ///    les actions qui la visaient échoueront et resteront visibles, avec
  ///    leur motif, dans l'écran des tâches ;
  ///  - MODIFICATION serveur : réconciliée comme une page de liste.
  Future<void> appliquerTirage({
    required List<Reserve> modifiees,
    required List<String> supprimees,
    required DatabaseExecutor executeur,
  }) async {
    if (modifiees.isEmpty && supprimees.isEmpty) return;
    if (supprimees.isNotEmpty) {
      final lot = executeur.batch();
      for (final id in supprimees) {
        lot.delete(BaseLocale.tableReserves, where: 'id = ?', whereArgs: [id]);
      }
      await lot.commit(noResult: true);
    }
    if (modifiees.isNotEmpty) await _appliquerVersionsServeur(executeur, modifiees);
  }

  Future<Set<String>> _idsEnAttente(DatabaseExecutor db) async => (await db.query(
        BaseLocale.tableReserves,
        columns: ['id'],
        where: 'en_attente = 1',
      ))
          .map((l) => l['id'] as String)
          .toSet();

  /// Réserves créées ou modifiées localement et pas encore confirmées —
  /// facultativement celles d'un chantier. Les plus récentes d'abord.
  Future<List<Reserve>> listerEnAttente({String? chantierId}) async {
    final db = await _base.base;
    final lignes = await db.query(
      BaseLocale.tableReserves,
      where: chantierId == null ? 'en_attente = 1' : 'en_attente = 1 AND chantier_id = ?',
      whereArgs: chantierId == null ? null : [chantierId],
      orderBy: 'maj_le DESC',
    );
    return lignes
        .map((l) => Reserve.fromJson(jsonDecode(l['donnees'] as String) as Map<String, dynamic>))
        .toList();
  }

  /// Relâche une ligne restée « en attente » : elle redevient écrasable par
  /// la version du serveur.
  ///
  /// Contrepartie indispensable de la protection des lignes en attente. Cette
  /// protection garde le travail non synchronisé — mais si l'action
  /// correspondante est DÉFINITIVEMENT refusée, plus rien ne viendrait jamais
  /// la lever : la ligne restait éternellement figée sur une valeur que le
  /// serveur n'a pas acceptée.
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
  ///
  /// [executeur] — transaction en cours (suppression faite hors ligne, voir
  /// `FileAttente.deposer`).
  Future<void> supprimer(String id, {DatabaseExecutor? executeur}) async {
    final db = executeur ?? await _base.base;
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

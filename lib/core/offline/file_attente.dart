import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'base_locale.dart';

/// Types d'actions différables. La valeur est PERSISTÉE en base : ne jamais
/// renommer une entrée existante sans migration, les appareils ont des actions
/// en attente écrites avec l'ancien nom.
enum TypeAction {
  creerReserve('creerReserve'),
  changerStatutReserve('changerStatutReserve'),
  ajouterPhotoReserve('ajouterPhotoReserve');

  const TypeAction(this.code);
  final String code;

  static TypeAction? depuisCode(String code) {
    for (final t in TypeAction.values) {
      if (t.code == code) return t;
    }
    // Action écrite par une version PLUS RÉCENTE de l'app puis ouverte par une
    // ancienne (rare, mais possible après un downgrade) : on renvoie null
    // plutôt que de lever, et l'appelant la laissera en attente.
    return null;
  }
}

/// Une action faite hors ligne, en attente d'envoi.
class ActionEnAttente {
  final String id;
  final TypeAction type;
  final Map<String, dynamic> charge;

  /// Fichier local à téléverser (photo). Conservé jusqu'à confirmation.
  final String? cheminFichier;

  final DateTime creeLe;
  final int tentatives;
  final String statut;
  final String? derniereErreur;

  const ActionEnAttente({
    required this.id,
    required this.type,
    required this.charge,
    required this.creeLe,
    this.cheminFichier,
    this.tentatives = 0,
    this.statut = statutAttente,
  this.derniereErreur,
  });

  static const String statutAttente = 'attente';

  /// Refus MÉTIER du serveur (chantier supprimé, droits retirés…). Inutile de
  /// retenter : seule une intervention humaine peut débloquer.
  static const String statutEchecDefinitif = 'echec_definitif';

  bool get estDefinitivementEnEchec => statut == statutEchecDefinitif;

  factory ActionEnAttente.depuisLigne(Map<String, Object?> l) {
    final type = TypeAction.depuisCode(l['type'] as String);
    if (type == null) {
      throw StateError('Type d\'action inconnu : ${l['type']}');
    }
    return ActionEnAttente(
      id: l['id'] as String,
      type: type,
      charge: jsonDecode(l['charge'] as String) as Map<String, dynamic>,
      cheminFichier: l['chemin_fichier'] as String?,
      creeLe: DateTime.fromMillisecondsSinceEpoch(l['cree_le'] as int),
      tentatives: (l['tentatives'] as int?) ?? 0,
      statut: (l['statut'] as String?) ?? statutAttente,
      derniereErreur: l['derniere_erreur'] as String?,
    );
  }

  Map<String, Object?> versLigne() => {
        'id': id,
        'type': type.code,
        'charge': jsonEncode(charge),
        'chemin_fichier': cheminFichier,
        'cree_le': creeLe.millisecondsSinceEpoch,
        'tentatives': tentatives,
        'statut': statut,
        'derniere_erreur': derniereErreur,
      };
}

/// File d'attente des actions hors ligne (pattern *outbox*).
///
/// Toute écriture faite sans réseau y est déposée, puis rejouée AUTOMATIQUEMENT
/// dès le retour de la connexion (voir `SynchronisationService`). L'ordre
/// chronologique est respecté : créer une réserve part forcément avant la photo
/// qui s'y rattache.
class FileAttente {
  final BaseLocale _base;
  final _uuid = const Uuid();

  FileAttente(this._base);

  /// Dépose une action. Retourne son identifiant local.
  Future<String> deposer({
    required TypeAction type,
    required Map<String, dynamic> charge,
    String? cheminFichier,
  }) async {
    final db = await _base.base;
    final action = ActionEnAttente(
      id: _uuid.v4(),
      type: type,
      charge: charge,
      cheminFichier: cheminFichier,
      creeLe: DateTime.now(),
    );
    await db.insert(
      BaseLocale.tableFileAttente,
      action.versLigne(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return action.id;
  }

  /// Actions à rejouer AUTOMATIQUEMENT, dans l'ordre de création.
  ///
  /// Exclut les échecs définitifs : les retenter en boucle bloquerait la file
  /// derrière une action qui ne passera jamais SANS intervention humaine —
  /// voir [toutesLesTaches] pour l'écran qui, lui, doit les montrer.
  Future<List<ActionEnAttente>> aTraiter() => _lister(where: 'statut = ?', args: [ActionEnAttente.statutAttente]);

  /// TOUTES les tâches à afficher sur l'écran dédié — en attente ET en échec
  /// définitif. Une tâche en échec définitif n'est jamais rejouée toute
  /// seule (voir [aTraiter]), mais l'utilisateur doit pouvoir la VOIR et la
  /// relancer manuellement ([remettreEnAttente]).
  Future<List<ActionEnAttente>> toutesLesTaches() => _lister();

  Future<ActionEnAttente?> parId(String id) async {
    final resultats = await _lister(where: 'id = ?', args: [id]);
    return resultats.isEmpty ? null : resultats.first;
  }

  Future<List<ActionEnAttente>> _lister({String? where, List<Object?>? args}) async {
    final db = await _base.base;
    final lignes = await db.query(
      BaseLocale.tableFileAttente,
      where: where,
      whereArgs: args,
      orderBy: 'cree_le ASC',
    );
    // Une ligne au type inconnu ne doit pas faire échouer toute la lecture de
    // la file : on l'ignore, elle reste en base pour une version ultérieure.
    return lignes
        .map((l) {
          try {
            return ActionEnAttente.depuisLigne(l);
          } catch (_) {
            return null;
          }
        })
        .whereType<ActionEnAttente>()
        .toList();
  }

  /// Nombre d'actions encore à envoyer — alimente le bandeau d'état.
  Future<int> nombreEnAttente() async {
    final db = await _base.base;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM ${BaseLocale.tableFileAttente} WHERE statut = ?',
      [ActionEnAttente.statutAttente],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<int> nombreEnEchec() async {
    final db = await _base.base;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM ${BaseLocale.tableFileAttente} WHERE statut = ?',
      [ActionEnAttente.statutEchecDefinitif],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// Retire une action envoyée avec succès.
  Future<void> supprimer(String id) async {
    final db = await _base.base;
    await db.delete(BaseLocale.tableFileAttente, where: 'id = ?', whereArgs: [id]);
  }

  /// Échec RÉSEAU : on incrémente le compteur mais l'action reste en attente,
  /// elle repartira à la prochaine reconnexion.
  Future<void> marquerEchecTemporaire(String id, String erreur) async {
    final db = await _base.base;
    await db.rawUpdate(
      'UPDATE ${BaseLocale.tableFileAttente} '
      'SET tentatives = tentatives + 1, derniere_erreur = ? WHERE id = ?',
      [erreur, id],
    );
  }

  /// Échec MÉTIER : inutile de retenter, l'action sort du cycle automatique.
  Future<void> marquerEchecDefinitif(String id, String erreur) async {
    final db = await _base.base;
    await db.update(
      BaseLocale.tableFileAttente,
      {
        'statut': ActionEnAttente.statutEchecDefinitif,
        'derniere_erreur': erreur,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Repasse UNE tâche en « attente » — geste EXPLICITE de l'utilisateur
  /// depuis l'écran des tâches (bouton « Synchroniser » sur une ligne en
  /// échec). Ne réinitialise PAS le compteur de tentatives : il continue de
  /// documenter l'historique de la tâche, seul son statut change.
  Future<void> remettreEnAttente(String id) async {
    final db = await _base.base;
    await db.update(
      BaseLocale.tableFileAttente,
      {'statut': ActionEnAttente.statutAttente},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Repasse TOUTES les tâches en échec définitif en « attente » — geste du
  /// bouton « Synchroniser tout » de l'écran dédié. Contrairement à la
  /// synchronisation automatique (qui ignore délibérément les échecs
  /// définitifs, voir [aTraiter]), un clic explicite de l'utilisateur vaut
  /// pour un nouvel essai de tout ce qui est visible à l'écran.
  Future<void> remettreToutEnAttente() async {
    final db = await _base.base;
    await db.update(
      BaseLocale.tableFileAttente,
      {'statut': ActionEnAttente.statutAttente},
      where: 'statut = ?',
      whereArgs: [ActionEnAttente.statutEchecDefinitif],
    );
  }
}

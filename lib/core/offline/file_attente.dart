import 'dart:async';
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
  ajouterPhotoReserve('ajouterPhotoReserve'),

  /// Envoi d'un rapport par e-mail — cahier des charges Rapports § 22 :
  /// « l'envoi d'un rapport nécessite une connexion. Widjila peut mettre
  /// l'action en file d'attente et la transmettre lorsque le réseau revient. »
  envoyerRapport('envoyerRapport');

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

/// Action de la file qu'il est IMPOSSIBLE de rejouer telle quelle, pour une
/// raison locale (charge incohérente, dépendance manquante) — la retenter
/// n'y changerait rien.
///
/// Sous-classe de [StateError] pour rester compatible avec les appelants qui
/// attrapaient déjà ce type ; `SynchronisationService` la reconnaît
/// SPÉCIFIQUEMENT et la classe en échec définitif. Un [StateError] quelconque
/// (bogue d'analyse d'une réponse pourtant réussie, par exemple) reste, lui,
/// un échec temporaire : le classer définitif ferait défaire une écriture que
/// le serveur a peut-être acceptée.
class ActionInvalide extends StateError {
  ActionInvalide(super.message);
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

  /// L'entité métier que cette action touche.
  ///
  /// Sert à respecter les DÉPENDANCES pendant la synchronisation : la photo et
  /// le changement de statut d'une réserve ne partent jamais tant que la
  /// création de cette réserve n'a pas abouti — ils échoueraient en 404 et
  /// seraient classés en échec définitif pour une raison évitable. Deux
  /// réserves différentes, elles, ne se bloquent jamais l'une l'autre.
  ///
  /// Une action dont l'entité est inconnue (charge incomplète) n'est reliée à
  /// AUCUNE autre : sans identifiant, on ne suppose pas de dépendance — deux
  /// actions sans rapport ne doivent pas se bloquer mutuellement.
  String get cleEntite {
    final cible = switch (type) {
      TypeAction.creerReserve => charge['id'],
      TypeAction.changerStatutReserve || TypeAction.ajouterPhotoReserve => charge['reserveId'],
      TypeAction.envoyerRapport => charge['rapportId'],
    };
    if (cible == null) return 'action:$id';
    return type == TypeAction.envoyerRapport ? 'rapport:$cible' : 'reserve:$cible';
  }

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
  final _depots = StreamController<void>.broadcast();

  FileAttente(this._base);

  /// Émet après CHAQUE dépôt réussi.
  ///
  /// `SynchronisationService` s'y abonne : une action déposée alors que
  /// l'appareil est en ligne (envoi direct tombé en délai dépassé, par
  /// exemple) part d'elle-même, sans attendre un événement réseau qui ne
  /// viendrait pas — l'appareil n'a jamais cessé d'être « en ligne ».
  Stream<void> get depots => _depots.stream;

  /// Dépose une action. Retourne son identifiant local.
  ///
  /// [avecEcriture] — écriture locale OPTIMISTE qui accompagne l'action
  /// (réserve « en attente » dans le cache, statut provisoire). Elle est
  /// exécutée dans la MÊME transaction SQLite que le dépôt : les deux
  /// existent, ou aucun des deux.
  ///
  /// Sans cela, un échec entre les deux écritures (disque plein, process tué
  /// par le système) laissait une réserve affichée « en attente d'envoi » que
  /// rien n'enverrait jamais — et que la protection des lignes en attente
  /// empêchait même le serveur de corriger. Une perte silencieuse.
  ///
  /// [id] — identifiant imposé par l'appelant, quand il doit être connu AVANT
  /// le dépôt (nom du fichier copié d'une photo, clé d'idempotence déjà
  /// utilisée par une tentative en ligne).
  Future<String> deposer({
    required TypeAction type,
    required Map<String, dynamic> charge,
    String? cheminFichier,
    String? id,
    Future<void> Function(Transaction txn)? avecEcriture,
  }) async {
    final db = await _base.base;
    final action = ActionEnAttente(
      id: id ?? _uuid.v4(),
      type: type,
      charge: charge,
      cheminFichier: cheminFichier,
      creeLe: DateTime.now(),
    );
    // `versLigne` AVANT la transaction : une charge non sérialisable échoue
    // ici, sans avoir rien ouvert ni rien écrit.
    final ligne = action.versLigne();
    await db.transaction((txn) async {
      if (avecEcriture != null) await avecEcriture(txn);
      await txn.insert(
        BaseLocale.tableFileAttente,
        ligne,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    if (!_depots.isClosed) _depots.add(null);
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

  /// `true` s'il reste une action EN ATTENTE sur [cleEntite] (voir
  /// [ActionEnAttente.cleEntite]), autre que [sauf].
  ///
  /// Sert à ne pas déclarer « confirmée » une réserve dont un autre
  /// changement, fait hors ligne, n'est pas encore parti.
  ///
  /// [types] restreint la recherche à certains types d'action — par exemple
  /// ceux qui RÉÉCRIVENT la ligne locale (une photo en file, elle, ne la
  /// modifie pas et ne doit pas la retenir « en attente »).
  Future<bool> aDesActionsEnAttentePour(String cleEntite, {String? sauf, Set<TypeAction>? types}) async {
    final actions = await aTraiter();
    return actions.any((a) => a.id != sauf && a.cleEntite == cleEntite && (types == null || types.contains(a.type)));
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

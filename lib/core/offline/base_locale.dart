import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'cle_entite.dart';

/// Base de données locale — socle du mode hors ligne.
///
/// ## Pourquoi `sqflite` et pas `drift`
///
/// `drift` offre des requêtes typées et réactives, mais sa configuration
/// standard passe par `path_provider`, dont l'implémentation iOS
/// (`path_provider_foundation` → `objective_c`) a un historique d'échec de
/// build sur ce projet. `sqflite` résout son chemin de fichier NATIVEMENT
/// (`getDatabasesPath()`), sans cette dépendance — c'est ce qui a motivé le
/// choix. Le coût est du SQL écrit à la main, assumé ici.
///
/// ## Ce que cette base contient
///
///  1. les **miroirs** des entités consultables hors ligne (chantiers,
///     réserves) — ce que l'utilisateur doit pouvoir lire au sous-sol ;
///  2. la **file d'attente** [tableFileAttente] des actions faites sans
///     réseau, rejouées automatiquement au retour de la connexion ;
///  3. les **métadonnées de synchronisation**, pour ne pas tout retélécharger
///     à chaque fois.
///
/// La base est la SOURCE DE VÉRITÉ lue par l'interface : le réseau ne fait
/// qu'y écrire quand il est disponible. C'est ce qui permet aux écrans de
/// fonctionner à l'identique en ligne et hors ligne, sans code conditionnel
/// dispersé dans chaque page.
class BaseLocale {
  BaseLocale._();
  static final BaseLocale instance = BaseLocale._();

  static const String _nomFichier = 'suivi_chantier_offline.db';

  /// Nom de fichier de substitution — RÉSERVÉ AUX TESTS, `null` en production.
  ///
  /// `flutter test` exécute les fichiers de test en parallèle, dans des
  /// isolats distincts mais sur le même disque. Quatre d'entre eux ouvrent
  /// cette base et la vident dans leur `setUp` : sans nom propre à chacun, ils
  /// se marchent dessus et échouent selon l'ordre d'exécution, alors que
  /// chacun passe parfaitement isolé. Un échec dont la cause est le voisin est
  /// le pire genre — on cherche le défaut dans le code testé, qui n'a rien.
  @visibleForTesting
  static String? surchargeNomFichier;

  /// Version du schéma. À incrémenter à CHAQUE modification de structure, en
  /// ajoutant la migration correspondante dans [_migrer] — sans quoi les
  /// appareils déjà installés garderont l'ancien schéma et planteront à la
  /// première requête sur une colonne absente.
  ///
  /// v2 (deuxième audit synchronisation) : colonne `cle_entite` indexée sur la
  /// file, index sur `reserves.en_attente`.
  static const int _version = 2;

  Database? _db;

  Future<Database> get base async => _db ??= await _ouvrir();

  Future<Database> _ouvrir() async {
    final chemin = '${await getDatabasesPath()}/${surchargeNomFichier ?? _nomFichier}';
    return openDatabase(
      chemin,
      version: _version,
      onCreate: (db, version) async => _creerSchema(db),
      onUpgrade: (db, ancienne, nouvelle) async => _migrer(db, ancienne, nouvelle),
      // RETOUR ARRIÈRE de version (rollback Play Store, sideload d'un APK plus
      // ancien) : sans ce gestionnaire, sqflite LÈVE à l'ouverture et l'app
      // devient impossible à démarrer sans désinstallation. On préfère perdre
      // le cache — reconstructible depuis le réseau — plutôt que de bloquer
      // l'utilisateur sur un écran d'erreur définitif.
      onDowngrade: onDatabaseDowngradeDelete,
      onConfigure: (db) async {
        // Les clés étrangères ne sont PAS actives par défaut dans SQLite.
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  // ───────────────────────────── Noms de tables ─────────────────────────────

  static const String tableChantiers = 'chantiers';
  static const String tableReserves = 'reserves';
  static const String tableFileAttente = 'file_attente';
  static const String tableSyncMeta = 'sync_meta';

  Future<void> _creerSchema(Database db) async {
    // Les entités sont stockées en JSON brut plutôt qu'en colonnes détaillées :
    // le mobile ne fait AUCUNE requête métier dessus (pas de tri ni de filtre
    // SQL), il relit l'objet complet et le désérialise avec le `fromJson`
    // existant. Une colonne par champ imposerait de faire évoluer le schéma
    // local à chaque ajout de champ côté serveur, pour aucun gain.
    await db.execute('''
      CREATE TABLE $tableChantiers (
        id TEXT PRIMARY KEY,
        donnees TEXT NOT NULL,
        maj_le INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableReserves (
        id TEXT PRIMARY KEY,
        chantier_id TEXT,
        donnees TEXT NOT NULL,
        maj_le INTEGER NOT NULL,
        -- 1 = créée ou modifiée hors ligne, pas encore confirmée par le
        -- serveur. L'interface s'en sert pour afficher « en attente d'envoi ».
        en_attente INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Index sur le filtre le plus courant : les réserves d'un chantier donné.
    await db.execute('CREATE INDEX idx_reserves_chantier ON $tableReserves (chantier_id)');

    await db.execute('''
      CREATE TABLE $tableFileAttente (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        charge TEXT NOT NULL,
        -- Fichier local à envoyer (photo), conservé jusqu'à confirmation.
        chemin_fichier TEXT,
        cree_le INTEGER NOT NULL,
        tentatives INTEGER NOT NULL DEFAULT 0,
        -- 'attente' | 'echec_definitif'. Un échec RÉSEAU ne change pas le
        -- statut (on retentera), seul un refus métier du serveur le fait.
        statut TEXT NOT NULL DEFAULT 'attente',
        derniere_erreur TEXT
      )
    ''');

    // L'ordre de rejeu est chronologique : créer une réserve doit partir avant
    // la photo qui s'y rattache.
    await db.execute('CREATE INDEX idx_file_ordre ON $tableFileAttente (cree_le)');

    await db.execute('''
      CREATE TABLE $tableSyncMeta (
        cle TEXT PRIMARY KEY,
        valeur TEXT NOT NULL
      )
    ''');

    await _ajouterIndexV2(db);
  }

  /// Schéma v2 — ajouts du deuxième audit synchronisation.
  ///
  ///  - `file_attente.cle_entite` : l'entité que l'action touche, INDEXÉE.
  ///    « Reste-t-il une action sur cette réserve ? » était calculé en relisant
  ///    et en décodant TOUTE la file à chaque confirmation : vider N actions
  ///    coûtait ~N²/2 lignes (mesuré : 300 actions → 45 450 lignes relues,
  ///    10,7 s). C'est désormais une requête indexée.
  ///  - index sur `reserves.en_attente` : lu à chaque page de liste et de
  ///    tirage pour protéger les changements locaux.
  static Future<void> _ajouterIndexV2(DatabaseExecutor db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_file_entite ON $tableFileAttente (cle_entite, statut)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_reserves_attente ON $tableReserves (en_attente)');
  }

  /// Migrations de schéma — chacune idempotente, dans une transaction
  /// (sqflite exécute `onUpgrade` dans une transaction : une migration
  /// interrompue ne laisse pas un schéma à moitié modifié).
  Future<void> _migrer(Database db, int ancienne, int nouvelle) async {
    if (ancienne < 2) {
      final colonnes = await db.rawQuery('PRAGMA table_info($tableFileAttente)');
      if (!colonnes.any((c) => c['name'] == 'cle_entite')) {
        await db.execute('ALTER TABLE $tableFileAttente ADD COLUMN cle_entite TEXT');
      }
      // Les actions DÉJÀ en file sur l'appareil reçoivent leur clé : sans
      // elle, une photo migrée ne serait plus reconnue comme dépendante de sa
      // réserve.
      final lignes = await db.query(tableFileAttente, columns: ['id', 'type', 'charge']);
      for (final l in lignes) {
        Map<String, dynamic> charge;
        try {
          charge = jsonDecode(l['charge'] as String) as Map<String, dynamic>;
        } catch (_) {
          charge = const {};
        }
        await db.update(
          tableFileAttente,
          {'cle_entite': cleEntitePour(type: l['type'] as String, charge: charge, idAction: l['id'] as String)},
          where: 'id = ?',
          whereArgs: [l['id']],
        );
      }
      await _ajouterIndexV2(db);
    }
  }

  /// Purge les entités mises en cache plus anciennes que [anciennete].
  ///
  /// La file d'attente n'est JAMAIS purgée : elle contient du travail de
  /// l'utilisateur non encore envoyé au serveur. Le cache, lui, est
  /// reconstructible depuis le réseau — sans cette purge, la base grossirait
  /// indéfiniment sur le téléphone d'un utilisateur qui consulte beaucoup.
  Future<void> purgerCacheAncien({Duration anciennete = const Duration(days: 90)}) async {
    final db = await base;
    final seuil = DateTime.now().subtract(anciennete).millisecondsSinceEpoch;

    await db.delete(tableChantiers, where: 'maj_le < ?', whereArgs: [seuil]);
    // Une réserve encore en attente d'envoi n'est pas du cache : on la garde
    // même si elle est ancienne.
    await db.delete(
      tableReserves,
      where: 'maj_le < ? AND en_attente = 0',
      whereArgs: [seuil],
    );
  }

  /// Clé de [tableSyncMeta] portant l'identifiant du compte propriétaire des
  /// données locales. Voir [proprietaire] pour le raisonnement.
  static const String _cleProprietaire = 'proprietaire';

  /// Identifiant du compte à qui appartiennent les données locales, `null` si
  /// la base est vierge.
  ///
  /// ## Pourquoi un propriétaire plutôt qu'une colonne par table
  ///
  /// L'isolation entre comptes ne peut pas reposer sur une purge déclenchée à
  /// la DÉCONNEXION : ce moment est interruptible (l'utilisateur balaie
  /// l'application juste après avoir tapé « Déconnexion », Android tue le
  /// process au milieu des DELETE) et laisserait alors les données du compte
  /// précédent intactes pour le suivant.
  ///
  /// Le propriétaire déplace le contrôle vers la CONNEXION — un moment, lui,
  /// non interruptible du point de vue de l'utilisateur suivant : tant que
  /// [SessionLocale.adopterUtilisateur] n'a pas rendu la main, aucune donnée
  /// n'est servie. Une purge ratée est donc systématiquement rattrapée au
  /// prochain démarrage, quel qu'ait été l'état d'arrêt de l'app.
  Future<String?> proprietaire() async {
    final db = await base;
    final lignes = await db.query(
      tableSyncMeta,
      where: 'cle = ?',
      whereArgs: [_cleProprietaire],
      limit: 1,
    );
    return lignes.isEmpty ? null : lignes.first['valeur'] as String?;
  }

  Future<void> definirProprietaire(String utilisateurId) async {
    final db = await base;
    await db.insert(
      tableSyncMeta,
      {'cle': _cleProprietaire, 'valeur': utilisateurId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Vide tout le contenu local — chantiers, réserves, file d'attente et
  /// métadonnées (propriétaire compris).
  ///
  /// ⚠️ Ne PAS appeler directement : passer par [SessionLocale.purger], qui
  /// supprime aussi les PHOTOS hors ligne. Vider les tables sans elles
  /// détruirait les seuls chemins référençant ces fichiers, qui resteraient
  /// alors orphelins sur le disque pour toujours.
  Future<void> viderTout() async {
    final db = await base;
    await db.delete(tableChantiers);
    await db.delete(tableReserves);
    await db.delete(tableFileAttente);
    await db.delete(tableSyncMeta);
  }

  Future<void> fermer() async {
    await _db?.close();
    _db = null;
  }
}

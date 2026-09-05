import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

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
  static const int _version = 1;

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
  }

  /// Migrations de schéma.
  ///
  /// Vide aujourd'hui (version 1), mais le point d'entrée existe dès le départ
  /// : rétro-ajouter un système de migration sur une base déjà déployée chez
  /// des utilisateurs est bien plus risqué que de le prévoir maintenant.
  Future<void> _migrer(Database db, int ancienne, int nouvelle) async {
    // Exemple pour la v2 :
    // if (ancienne < 2) {
    //   await db.execute('ALTER TABLE reserves ADD COLUMN xxx TEXT');
    // }
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

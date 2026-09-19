import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:suivie_chantier_mobile/core/offline/base_locale.dart';

/// Le schéma de la base hors ligne — sur une installation NEUVE et après
/// migration.
///
/// ## Le plantage (Crashlytics, 1.0.4 (14), 30 plantages / 3 utilisateurs)
///
/// ```
/// DatabaseException(no such column: cle_entite … CREATE INDEX IF NOT EXISTS
/// idx_file_entite ON file_attente (cle_entite, statut))
///   BaseLocale._ajouterIndexV2 ← BaseLocale._creerSchema ← … ← auRetourAuPremierPlan
/// ```
///
/// Sur une installation neuve, `onCreate` créait `file_attente` SANS la
/// colonne `cle_entite` puis posait un index dessus : l'ouverture échouait,
/// et TOUT le mode hors ligne était inutilisable — à chaque retour au premier
/// plan, la synchronisation relançait l'ouverture et replantait.
///
/// ## Pourquoi les tests ne l'ont pas vu
///
/// Leurs fichiers `.db` persistaient dans `.dart_tool/` depuis la v1 et avaient
/// été MIGRÉS (`_migrer` ajoute bien la colonne) : `onCreate` n'y tournait
/// plus jamais. Ce fichier supprime donc la base AVANT de l'ouvrir : c'est le
/// seul moyen d'exercer `onCreate` comme sur le téléphone d'un nouvel
/// utilisateur.
void main() {
  const fichier = 'test_base_locale_schema.db';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    BaseLocale.surchargeNomFichier = fichier;
  });

  Future<String> chemin() async => '${await getDatabasesPath()}/$fichier';

  /// Repart d'un disque VIERGE : ferme la base si elle est ouverte, et
  /// supprime le fichier — sans quoi `onCreate` ne tourne pas.
  Future<void> effacer() async {
    await BaseLocale.instance.fermer();
    await databaseFactory.deleteDatabase(await chemin());
  }

  setUp(effacer);
  tearDown(effacer);

  Future<Set<String>> colonnes(DatabaseExecutor db, String table) async =>
      (await db.rawQuery('PRAGMA table_info($table)')).map((c) => c['name'] as String).toSet();

  Future<Set<String>> index(DatabaseExecutor db, String table) async =>
      (await db.rawQuery('PRAGMA index_list($table)')).map((i) => i['name'] as String).toSet();

  test('installation NEUVE : la base s’ouvre, avec la colonne cle_entite et son index', () async {
    final db = await BaseLocale.instance.base;

    expect(await colonnes(db, BaseLocale.tableFileAttente), contains('cle_entite'));
    expect(await index(db, BaseLocale.tableFileAttente), containsAll(['idx_file_entite', 'idx_file_ordre']));
    expect(await index(db, BaseLocale.tableReserves), containsAll(['idx_reserves_attente', 'idx_reserves_chantier']));
    expect(await db.getVersion(), 2);
  });

  test('installation NEUVE : la file d’attente accepte une action avec sa clé d’entité', () async {
    // Ce que fait la première réserve créée hors ligne — le geste qui
    // plantait chez 100 % des nouveaux utilisateurs.
    final db = await BaseLocale.instance.base;
    await db.insert(BaseLocale.tableFileAttente, {
      'id': 'a1', 'type': 'creer_reserve', 'charge': '{}', 'cree_le': 1, 'cle_entite': 'reserve:r1',
    });
    final lignes = await db.query(BaseLocale.tableFileAttente, where: 'cle_entite = ? AND statut = ?', whereArgs: ['reserve:r1', 'attente']);
    expect(lignes, hasLength(1));
  });

  test('appareil en v1 : la migration ajoute la colonne, remplit la clé et pose l’index', () async {
    // Un téléphone qui a installé l'app avant le schéma v2, avec une action
    // déjà en file. Sa base est créée ICI telle qu'elle était en v1.
    final v1 = await databaseFactory.openDatabase(
      await chemin(),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE ${BaseLocale.tableChantiers} (id TEXT PRIMARY KEY, donnees TEXT NOT NULL, maj_le INTEGER NOT NULL)');
          await db.execute('CREATE TABLE ${BaseLocale.tableReserves} (id TEXT PRIMARY KEY, chantier_id TEXT, donnees TEXT NOT NULL, maj_le INTEGER NOT NULL, en_attente INTEGER NOT NULL DEFAULT 0)');
          await db.execute('CREATE TABLE ${BaseLocale.tableFileAttente} (id TEXT PRIMARY KEY, type TEXT NOT NULL, charge TEXT NOT NULL, chemin_fichier TEXT, cree_le INTEGER NOT NULL, tentatives INTEGER NOT NULL DEFAULT 0, statut TEXT NOT NULL DEFAULT \'attente\', derniere_erreur TEXT)');
          await db.execute('CREATE TABLE ${BaseLocale.tableSyncMeta} (cle TEXT PRIMARY KEY, valeur TEXT NOT NULL)');
          await db.insert(BaseLocale.tableFileAttente, {
            'id': 'ancienne', 'type': 'creer_reserve', 'charge': '{"id":"r-hors-ligne"}', 'cree_le': 1,
          });
        },
      ),
    );
    await v1.close();

    final db = await BaseLocale.instance.base;

    expect(await db.getVersion(), 2);
    expect(await colonnes(db, BaseLocale.tableFileAttente), contains('cle_entite'));
    expect(await index(db, BaseLocale.tableFileAttente), contains('idx_file_entite'));
    final ligne = (await db.query(BaseLocale.tableFileAttente, where: 'id = ?', whereArgs: ['ancienne'])).single;
    expect(ligne['cle_entite'], isNotNull, reason: 'l’action déjà en file reçoit sa clé d’entité');
  });

  test('rouvrir une base déjà en v2 ne change rien et ne plante pas', () async {
    await BaseLocale.instance.base;
    await BaseLocale.instance.fermer();

    final db = await BaseLocale.instance.base;
    expect(await db.getVersion(), 2);
    expect(await colonnes(db, BaseLocale.tableFileAttente), contains('cle_entite'));
  });
}

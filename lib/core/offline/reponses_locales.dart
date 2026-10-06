import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'base_locale.dart';
import 'stockage_medias.dart';

/// Copie DURABLE des réponses du serveur, relue quand il est injoignable.
///
/// ## Pourquoi
///
/// Tout ce qui servait à travailler sur un chantier — structure (bâtiments,
/// niveaux, zones), liste des plans, fichiers de plans, corps d'état, phases —
/// était redemandé au serveur à chaque ouverture d'écran, sans aucune trace
/// locale. Sans réseau, le formulaire de réserve ne pouvait pas s'ouvrir et un
/// plan ne pouvait pas s'afficher : le guide hors connexion le range en tête
/// des causes d'échec (« les plans sont seulement affichés depuis une URL
/// Internet », « les listes sont chargées à chaque ouverture du formulaire »).
///
/// ## Ce qui est stocké
///
///  - les réponses JSON de lecture (`type = json`) dans SQLite ;
///  - les fichiers (plans PDF/images, photos : `type = fichier`) sur disque,
///    dans un dossier privé de l'application, référencés par la table.
///
/// ## Garde-fous
///
///  - **Plafonds** : [plafondJson] par réponse, [plafondFichier] par fichier,
///    [plafondTotal] en tout — au-delà, les entrées les moins récemment lues
///    sont évincées. Le travail de l'utilisateur (file d'attente, photos à
///    envoyer) n'est JAMAIS ici et n'est jamais évincé.
///  - **Isolation entre comptes** : la table est vidée avec le reste par
///    `BaseLocale.viderTout`, le dossier par `StockageMedias.viderTout`.
///  - **Péremption** : [purger] retire ce qui n'a pas servi depuis 90 jours.
class ReponsesLocales {
  final BaseLocale _base;

  ReponsesLocales(this._base);

  static const int plafondJson = 3 * 1024 * 1024;
  static const int plafondFichier = 80 * 1024 * 1024;
  static const int plafondTotal = 400 * 1024 * 1024;

  Future<Directory> _dossier() async {
    final racine = await getDatabasesPath();
    final dossier = Directory(p.join(p.dirname(racine), StockageMedias.sousDossierReponses));
    if (!await dossier.exists()) await dossier.create(recursive: true);
    return dossier;
  }

  static String _nomFichier(String cle) => '${sha1.convert(cle.codeUnits)}.bin';

  Future<void> ecrireJson(String cle, String corps) async {
    if (corps.length > plafondJson) return;
    final db = await _base.base;
    final maintenant = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      BaseLocale.tableReponsesLocales,
      {
        'cle': cle,
        'type': 'json',
        'corps': corps,
        'taille': corps.length,
        'maj_le': maintenant,
        'acces_le': maintenant,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> lireJson(String cle) async {
    final db = await _base.base;
    final lignes = await db.query(
      BaseLocale.tableReponsesLocales,
      columns: ['corps'],
      where: 'cle = ? AND type = ?',
      whereArgs: [cle, 'json'],
      limit: 1,
    );
    if (lignes.isEmpty) return null;
    return lignes.first['corps'] as String?;
  }

  /// Écrit le fichier AVANT la ligne d'index : un arrêt entre les deux laisse
  /// un fichier orphelin (nettoyé au prochain [purger]), jamais une ligne qui
  /// pointe dans le vide.
  Future<void> ecrireFichier(String cle, List<int> octets) async {
    if (octets.length > plafondFichier) return;
    final dossier = await _dossier();
    final chemin = p.join(dossier.path, _nomFichier(cle));
    await File(chemin).writeAsBytes(octets, flush: true);
    final db = await _base.base;
    final maintenant = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      BaseLocale.tableReponsesLocales,
      {
        'cle': cle,
        'type': 'fichier',
        'chemin': chemin,
        'taille': octets.length,
        'maj_le': maintenant,
        'acces_le': maintenant,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _evincerSiBesoin(db);
  }

  Future<Uint8List?> lireFichier(String cle) async {
    final db = await _base.base;
    final lignes = await db.query(
      BaseLocale.tableReponsesLocales,
      columns: ['chemin'],
      where: 'cle = ? AND type = ?',
      whereArgs: [cle, 'fichier'],
      limit: 1,
    );
    if (lignes.isEmpty) return null;
    final fichier = File(lignes.first['chemin'] as String);
    if (!await fichier.exists()) {
      // Fichier disparu (stockage vidé par l'OS) : l'index est périmé.
      await db.delete(BaseLocale.tableReponsesLocales, where: 'cle = ?', whereArgs: [cle]);
      return null;
    }
    await db.update(
      BaseLocale.tableReponsesLocales,
      {'acces_le': DateTime.now().millisecondsSinceEpoch},
      where: 'cle = ?',
      whereArgs: [cle],
    );
    return fichier.readAsBytes();
  }

  /// Existe-t-il une copie (JSON ou fichier) pour [cle] ?
  Future<bool> contient(String cle) async {
    final db = await _base.base;
    final n = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM ${BaseLocale.tableReponsesLocales} WHERE cle = ?',
      [cle],
    ));
    return (n ?? 0) > 0;
  }

  Future<void> _evincerSiBesoin(Database db) async {
    var total = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COALESCE(SUM(taille), 0) FROM ${BaseLocale.tableReponsesLocales}')) ??
        0;
    if (total <= plafondTotal) return;
    final anciennes = await db.query(
      BaseLocale.tableReponsesLocales,
      columns: ['cle', 'type', 'chemin', 'taille'],
      orderBy: 'acces_le ASC',
    );
    for (final l in anciennes) {
      if (total <= plafondTotal) break;
      await _retirer(db, l);
      total -= l['taille'] as int;
    }
  }

  Future<void> _retirer(Database db, Map<String, Object?> ligne) async {
    if (ligne['type'] == 'fichier') {
      try {
        final f = File(ligne['chemin'] as String);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await db.delete(BaseLocale.tableReponsesLocales, where: 'cle = ?', whereArgs: [ligne['cle']]);
  }

  /// Retire ce qui n'a pas servi depuis [anciennete] et les fichiers orphelins.
  Future<void> purger({Duration anciennete = const Duration(days: 90)}) async {
    final db = await _base.base;
    final seuil = DateTime.now().subtract(anciennete).millisecondsSinceEpoch;
    final perimees = await db.query(
      BaseLocale.tableReponsesLocales,
      columns: ['cle', 'type', 'chemin'],
      where: 'acces_le < ?',
      whereArgs: [seuil],
    );
    for (final l in perimees) {
      await _retirer(db, l);
    }
    // Orphelins : fichiers que plus aucune ligne ne référence.
    try {
      final connus = (await db.query(BaseLocale.tableReponsesLocales, columns: ['chemin'], where: 'chemin IS NOT NULL'))
          .map((l) => l['chemin'] as String)
          .toSet();
      final dossier = await _dossier();
      await for (final e in dossier.list()) {
        if (e is File && !connus.contains(e.path)) await e.delete();
      }
    } catch (_) {}
  }
}

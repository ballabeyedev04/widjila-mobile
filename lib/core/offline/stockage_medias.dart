import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Copie durable des photos prises hors ligne, en attente d'envoi.
///
/// ## Pourquoi une copie, et pas le chemin renvoyé par le sélecteur d'image
///
/// `image_picker` rend un fichier logé dans un dossier de CACHE — celui-ci
/// peut être purgé par l'OS à tout moment pour libérer de l'espace, y compris
/// pendant que l'application est en arrière-plan. Une photo prise au
/// sous-sol, mise en file d'attente, doit survivre jusqu'à sa synchronisation
/// — potentiellement plusieurs heures ou jours plus tard. La copier dans un
/// dossier propre à l'application, hors du cache, est ce qui garantit sa
/// présence au moment où la synchronisation en a besoin.
///
/// ## Pourquoi ce dossier précisément
///
/// Sous-dossier de `getDatabasesPath()` (la même racine que `BaseLocale`,
/// voir sa justification) plutôt que `path_provider` : ce chemin est déjà
/// PROUVÉ accessible en écriture par l'ouverture réussie de la base SQLite —
/// aucune supposition supplémentaire sur la structure de dossiers de chaque
/// plateforme n'est nécessaire.
class StockageMedias {
  static const String _sousDossier = 'photos_hors_ligne';

  Future<Directory> _dossier() async {
    final racine = await getDatabasesPath();
    final dossier = Directory(p.join(p.dirname(racine), _sousDossier));
    if (!await dossier.exists()) await dossier.create(recursive: true);
    return dossier;
  }

  /// Copie [cheminSource] dans le stockage durable et retourne le nouveau
  /// chemin. Le nom de fichier est préfixé par [idAction] (l'identifiant de
  /// l'action en file d'attente) : deux photos du même appareil ne peuvent
  /// jamais se percuter, même prises à la même milliseconde.
  Future<String> copier(String cheminSource, String idAction) async {
    final dossier = await _dossier();
    final extension = p.extension(cheminSource);
    final destination = p.join(dossier.path, '$idAction$extension');
    final copie = await File(cheminSource).copy(destination);
    return copie.path;
  }

  /// Supprime la copie locale — à appeler UNIQUEMENT après confirmation
  /// d'envoi par le serveur. Un fichier absent ne lève pas : la synchronisation
  /// ne doit jamais échouer sur un ménage qui a déjà eu lieu.
  Future<void> supprimer(String chemin) async {
    final fichier = File(chemin);
    if (await fichier.exists()) await fichier.delete();
  }

  /// Supprime TOUTES les photos hors ligne — au changement de compte.
  ///
  /// Indispensable et non substituable par [supprimer] : cette dernière est
  /// appelée avec le chemin lu dans la file d'attente, or vider la file
  /// détruit ces chemins. Sans cette purge globale, les photos du compte
  /// précédent — géolocalisées, horodatées, montrant des défauts, des
  /// documents, parfois des personnes — resteraient sur le disque
  /// INDÉFINIMENT : plus aucune ligne ne les référence, donc plus aucun
  /// ménage ne peut les atteindre. Double conséquence : donnée personnelle
  /// conservée au-delà de sa finalité, et stockage qui gonfle sans limite.
  ///
  /// Tolérante à l'échec : sur un disque saturé ou un fichier verrouillé par
  /// l'OS, une exception ici ne doit pas empêcher la déconnexion d'aboutir.
  Future<void> viderTout() async {
    try {
      final dossier = await _dossier();
      if (await dossier.exists()) await dossier.delete(recursive: true);
    } catch (_) {
      // Best-effort : voir la note ci-dessus.
    }
  }
}

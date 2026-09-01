import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tout cas d'usage qui existe doit être ENREGISTRÉ dans le conteneur.
///
/// ── Pourquoi ce test existe ───────────────────────────────────────────────
/// Quatre cas d'usage du parcours « Envoi de plans » avaient été écrits,
/// câblés dans un cubit, et oubliés à l'enregistrement. Rien ne l'a signalé :
/// GetIt résout par type À L'EXÉCUTION, donc ni le compilateur ni
/// `flutter analyze` ne voient le trou. L'écran plantait au premier
/// affichage — après que la demande de chantier eut été créée, ce qui est le
/// pire moment.
///
/// ── Pourquoi une lecture du SOURCE ────────────────────────────────────────
/// Rejouer `init()` demanderait de simuler le stockage sécurisé, les
/// préférences, SQLite et Dio — beaucoup de mécanique pour vérifier une chose
/// simple. La lecture du fichier suffit et ne dépend d'aucun canal de
/// plateforme.
///
/// ── Sa limite ─────────────────────────────────────────────────────────────
/// Il vérifie la PRÉSENCE d'un enregistrement, pas que ses dépendances se
/// résolvent. Un `sl()` imbriqué qui manquerait passerait encore. C'est
/// néanmoins la moitié utile : c'est l'oubli pur et simple qui se produit.
void main() {
  /// Cas d'usage volontairement NON enregistrés.
  ///
  /// Vide aujourd'hui. Un ajout ici doit s'accompagner de sa raison — un cas
  /// d'usage sans enregistrement est presque toujours un oubli, pas un choix.
  const exceptions = <String>{};

  test('chaque cas d’usage est enregistré dans le conteneur', () {
    final conteneur = File('lib/injection_container.dart').readAsStringSync();

    final classes = <String, String>{};
    for (final entree in Directory('lib/features').listSync(recursive: true)) {
      if (entree is! File) continue;
      final chemin = entree.path.replaceAll(r'\', '/');
      if (!chemin.contains('/domain/usecases/') || !chemin.endsWith('.dart')) continue;

      for (final m in RegExp(r'^class\s+(\w+)', multiLine: true)
          .allMatches(entree.readAsStringSync())) {
        classes[m.group(1)!] = chemin;
      }
    }

    // Garde-fou : si le motif de recherche cessait de trouver des fichiers,
    // le test passerait en ne vérifiant rien.
    expect(classes.length, greaterThan(20),
        reason: 'Aucun cas d’usage trouvé — le chemin a-t-il changé ?');

    final oublis = <String>[];
    for (final entree in classes.entries) {
      if (exceptions.contains(entree.key)) continue;
      // `NomDuCasDUsage(` — la forme de l'enregistrement.
      if (!RegExp('\\b${entree.key}\\s*\\(').hasMatch(conteneur)) {
        oublis.add('${entree.key}  (${entree.value})');
      }
    }

    expect(
      oublis,
      isEmpty,
      reason: 'Cas d’usage non enregistrés — GetIt lèvera à l’exécution :\n'
          '${oublis.join('\n')}',
    );
  });
}

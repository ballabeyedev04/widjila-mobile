import 'package:flutter/material.dart';

/// Formats d'écran balayés par les tests de mise en page.
///
/// ## Pourquoi une liste, et pas trois tailles bien choisies
///
/// Un écran testé à 390 × 844 passe presque toujours : c'est le format sur
/// lequel il a été dessiné. Les débordements se produisent aux EXTRÊMES — sur
/// un petit téléphone de 320 dp, où trois libellés côte à côte ne tiennent
/// plus, et sur une tablette de 1024 dp, où une rangée conçue pour être serrée
/// se distend jusqu'à devenir illisible.
///
/// La liste couvre donc l'éventail réel du parc : du petit Android d'entrée de
/// gamme encore très présent sur les chantiers jusqu'à la tablette posée dans
/// la base-vie.
///
/// ## Ce qu'un balayage détecte
///
/// `flutter_test` remonte un `RenderFlex overflowed by N pixels` comme une
/// exception. Un balayage qui pompe l'écran à chaque format et vérifie
/// qu'aucune exception n'a été levée transforme donc l'audit visuel — long,
/// subjectif, jamais rejoué — en une mesure automatique et répétable.

/// Format d'écran nommé, pour que l'échec désigne un appareil réel.
class FormatEcran {
  final String nom;
  final Size taille;

  const FormatEcran(this.nom, this.taille);

  /// Le même format, couché.
  FormatEcran get paysage => FormatEcran(
        '$nom (paysage)',
        Size(taille.height, taille.width),
      );

  @override
  String toString() => '$nom ${taille.width.toInt()}x${taille.height.toInt()}';
}

/// Téléphones — du plus étroit encore en service au plus large.
const telephones = <FormatEcran>[
  // 320 dp : le plancher. Un iPhone SE de première génération, et la plupart
  // des Android d'entrée de gamme vendus en Afrique de l'Ouest.
  FormatEcran('tres petit', Size(320, 568)),
  FormatEcran('petit', Size(360, 640)),
  FormatEcran('standard', Size(390, 844)),
  FormatEcran('grand', Size(414, 896)),
  FormatEcran('tres grand', Size(430, 932)),
];

/// Tablettes — de part et d'autre du seuil de bascule (700 dp).
const tablettes = <FormatEcran>[
  // 600 dp : SOUS le seuil. Une tablette compacte en portrait garde donc la
  // mise en page téléphone, et c'est le cas le plus facile à oublier.
  FormatEcran('tablette compacte', Size(600, 960)),
  FormatEcran('tablette', Size(768, 1024)),
  FormatEcran('tablette large', Size(834, 1194)),
  FormatEcran('grande tablette', Size(1024, 1366)),
];

/// L'éventail complet, portrait et paysage.
///
/// Le paysage n'est pas un détail : c'est là que la hauteur utile s'effondre
/// et qu'une colonne conçue pour un écran debout cesse de tenir.
List<FormatEcran> get tousLesFormats => [
      ...telephones,
      ...telephones.map((f) => f.paysage),
      ...tablettes,
      ...tablettes.map((f) => f.paysage),
    ];

/// Les formats les plus révélateurs, quand balayer les seize serait trop long.
///
/// Les deux extrêmes, la bascule tablette, et un paysage de téléphone — le
/// format où la hauteur manque le plus.
List<FormatEcran> get formatsCritiques => [
      telephones.first,
      telephones[2],
      telephones[2].paysage,
      tablettes.first,
      tablettes[1],
      tablettes.last,
    ];

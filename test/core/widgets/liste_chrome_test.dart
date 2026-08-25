import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/widgets/liste_chrome.dart';

/// Chrome partagé des écrans Réserves, Plans et Notifications.
///
/// La cloche de [EnTeteListe] est éprouvée à part (voir
/// `bouton_cloche_test.dart`) : elle dépend d'un [NotificationsCubit], que les
/// tests de mise en page n'ont pas à monter.
void main() {
  Widget banc(Widget child, {Size taille = const Size(390, 844)}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: taille),
        child: Scaffold(body: child),
      ),
    );
  }

  group('EtatVideIllustre', () {
    testWidgets('affiche titre, description et action', (tester) async {
      var appuis = 0;
      await tester.pumpWidget(banc(
        EtatVideIllustre(
          motif: MotifVide.reserve,
          titre: 'Aucune réserve',
          description: 'Les réserves créées sur vos chantiers apparaîtront ici.',
          cta: BoutonAction(
            icon: Icons.add_rounded,
            label: 'Créer une réserve',
            onTap: () => appuis++,
          ),
        ),
      ));

      expect(find.text('Aucune réserve'), findsOneWidget);
      expect(find.text('Les réserves créées sur vos chantiers apparaîtront ici.'), findsOneWidget);

      await tester.tap(find.text('Créer une réserve'));
      expect(appuis, 1);
    });

    testWidgets('sans action, aucun bouton n’est rendu', (tester) async {
      await tester.pumpWidget(banc(const EtatVideIllustre(
        motif: MotifVide.recherche,
        titre: 'Aucun résultat',
        description: 'Essayez un autre mot-clé.',
      )));

      // C'est le cas d'un rôle sans droit de création, et celui d'une
      // recherche infructueuse : promettre une action serait trompeur.
      expect(find.byType(BoutonAction), findsNothing);
      expect(find.text('Aucun résultat'), findsOneWidget);
    });

    testWidgets('reste utilisable sur un écran très bas (paysage, clavier)', (tester) async {
      // L'illustration seule fait 200 px : sur 320 px de haut, un état vide
      // centré en dur déborderait et rendrait le bouton inatteignable.
      tester.view.physicalSize = const Size(640, 320);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(banc(
        EtatVideIllustre(
          motif: MotifVide.plan,
          titre: 'Aucun plan',
          description: 'Les plans apparaîtront ici.',
          cta: BoutonAction(icon: Icons.add, label: 'Importer un plan', onTap: () {}),
        ),
        taille: const Size(640, 320),
      ));

      expect(tester.takeException(), isNull);
      // Le contenu défile : le bouton est atteignable en faisant glisser.
      await tester.drag(find.byType(EtatVideIllustre), const Offset(0, -260));
      await tester.pump();
      expect(find.text('Importer un plan'), findsOneWidget);
    });
  });

  group('IllustrationVide', () {
    for (final motif in MotifVide.values) {
      testWidgets('se peint sans erreur — $motif', (tester) async {
        await tester.pumpWidget(banc(Center(child: IllustrationVide(motif: motif))));
        expect(tester.takeException(), isNull);
        expect(find.byType(IllustrationVide), findsOneWidget);
      });
    }
  });

  group('ChipFiltre', () {
    testWidgets('répond au tap et distingue actif d’inactif', (tester) async {
      var appuis = 0;
      await tester.pumpWidget(banc(Row(
        children: [
          ChipFiltre(icon: Icons.grid_view_rounded, label: 'Toutes (3)', actif: true, onTap: () {}),
          ChipFiltre(
            icon: Icons.schedule_rounded,
            label: 'En cours',
            actif: false,
            onTap: () => appuis++,
          ),
        ],
      )));

      await tester.tap(find.text('En cours'));
      expect(appuis, 1);

      // La puce active porte l'aplat orange, l'inactive reste blanche.
      final conteneurs = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .map((c) => (c.decoration as BoxDecoration).color)
          .toList();
      expect(conteneurs.first, isNot(conteneurs.last));
    });
  });

  group('ContenuFormulaire', () {
    // Même mécanisme que ContenuCentre, mais avec un plafond plus étroit
    // (440 px) : c'est la brique utilisée pour tous les formulaires de l'app
    // (mfa_page, reserve_wizard_page, les feuilles d'ajout membre/partenaire,
    // import_plan_sheet) après l'audit responsive — verrouiller son
    // comportement couvre indirectement ces 16 fichiers corrigés.
    testWidgets('borne la largeur sur tablette', (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ContenuFormulaire(child: Container(key: const Key('contenu'), height: 40)),
        ),
      ));

      final largeur = tester.getSize(find.byKey(const Key('contenu'))).width;
      expect(largeur, largeurFormulaireMax);
    });

    testWidgets('occupe toute la largeur sur téléphone', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ContenuFormulaire(child: Container(key: const Key('contenu'), height: 40)),
        ),
      ));

      expect(tester.getSize(find.byKey(const Key('contenu'))).width, 360);
    });

    testWidgets('est strictement plus étroit que ContenuCentre', (tester) async {
      // Une liste profite de la largeur d'une tablette, un formulaire non :
      // les deux plafonds doivent rester distincts.
      expect(largeurFormulaireMax, lessThan(largeurContenuMax));
    });
  });

  group('colonnesAdaptatives', () {
    // Remplace les grilles à `crossAxisCount` figé (documents_list_page,
    // reserve_detail_page) : le nombre de colonnes doit croître avec la
    // largeur sans jamais sortir de [min, max].
    test('reste au minimum sur une largeur de téléphone étroit', () {
      expect(colonnesAdaptatives(320), 2);
    });

    test('augmente sur une largeur de tablette', () {
      final colonnes = colonnesAdaptatives(900);
      expect(colonnes, greaterThan(2));
    });

    test('ne dépasse jamais le maximum, même sur très grand écran', () {
      expect(colonnesAdaptatives(4000), 5);
    });

    test('respecte un minimum personnalisé (grille photos : 3)', () {
      // reserve_detail_page.dart fixe min:3 pour ne pas regresser en dessous
      // du rendu téléphone d'origine (3 colonnes fixes).
      expect(colonnesAdaptatives(200, min: 3), 3);
      expect(colonnesAdaptatives(560, min: 3), greaterThanOrEqualTo(3));
    });

    test('ne descend jamais sous le minimum, même à largeur nulle', () {
      expect(colonnesAdaptatives(0), 2);
    });
  });

  group('ContenuCentre', () {
    testWidgets('borne la largeur sur tablette', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(banc(
        const ContenuCentre(child: EnTeteListe(titre: 'Réserves', avecCloche: false)),
        taille: const Size(1200, 900),
      ));

      final largeur = tester.getSize(find.byType(EnTeteListe)).width;

      // Le plafond TABLETTE (1040) et non celui du téléphone (560) : au-delà
      // du seuil de 700 dp, `largeurContenuPour` bascule volontairement, sans
      // quoi la liste resterait une colonne étroite entre deux bandes vides.
      expect(largeur, lessThanOrEqualTo(largeurContenuMaxTablette));

      // Et il reste un PLAFOND : le contenu ne prend pas les 1200 dp de la
      // fenêtre. C'est ce que ce test vérifie vraiment — sans cette seconde
      // assertion, il passerait même si la contrainte disparaissait.
      expect(largeur, lessThan(1200));
    });

    testWidgets('occupe toute la largeur sur téléphone', (tester) async {
      // `MediaQuery` seul ne suffit pas : c'est la surface de rendu qui décide
      // des contraintes reçues par le Scaffold.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          banc(const ContenuCentre(child: EnTeteListe(titre: 'Plans', avecCloche: false))));
      expect(tester.getSize(find.byType(EnTeteListe)).width, 390);
    });
  });
}

import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/services/ouverture_fichier.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/entities/plan.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_plan_detail.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_plans_chantier.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/pages/plan_navigation_page.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/widgets/plan_interactif.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/chantier_structure.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_chantier_structure.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/balayage_responsive.dart';
import '../../../../helpers/pompe_page.dart';

class _MockStructure extends Mock implements GetChantierStructure {}

class _MockPlansChantier extends Mock implements GetPlansChantier {}

class _MockPlanDetail extends Mock implements GetPlanDetail {}

class _MockOuverture extends Mock implements OuvertureFichier {}

class _MockDio extends Mock implements Dio {}

/// La navigation dans les plans d'un chantier, par niveaux.
///
/// ## Ce que cet écran croise
///
/// Il superpose deux sources : la STRUCTURE du chantier (bâtiments, étages,
/// zones) et les PLANS déposés. Les deux sont indépendantes côté serveur, et
/// c'est de leur croisement que vient la difficulté — un chantier peut avoir
/// une structure sans plan, des plans sans structure, ou ni l'un ni l'autre.
///
/// Chacune de ces trois situations est légitime en exploitation. Aucune ne
/// doit se présenter comme une panne, et aucune ne doit laisser un écran
/// blanc : sur un chantier, un écran vide sans explication se lit comme une
/// application cassée, et l'appel qui suit part au support.
void main() {
  late _MockStructure getStructure;
  late _MockPlansChantier getPlans;
  late _MockPlanDetail getDetail;

  void desinscrire() {
    if (sl.isRegistered<GetChantierStructure>()) sl.unregister<GetChantierStructure>();
    if (sl.isRegistered<GetPlansChantier>()) sl.unregister<GetPlansChantier>();
    if (sl.isRegistered<GetPlanDetail>()) sl.unregister<GetPlanDetail>();
    if (sl.isRegistered<OuvertureFichier>()) sl.unregister<OuvertureFichier>();
    if (sl.isRegistered<Dio>()) sl.unregister<Dio>();
  }

  setUp(() {
    getStructure = _MockStructure();
    getPlans = _MockPlansChantier();
    getDetail = _MockPlanDetail();

    desinscrire();
    sl.registerLazySingleton<GetChantierStructure>(() => getStructure);
    sl.registerLazySingleton<GetPlansChantier>(() => getPlans);
    sl.registerLazySingleton<GetPlanDetail>(() => getDetail);
    sl.registerLazySingleton<OuvertureFichier>(() => _MockOuverture());
    sl.registerLazySingleton<Dio>(() => Dio());
  });

  tearDown(desinscrire);

  const page = PlanNavigationPage(chantierId: 'c1', chantierNom: 'Les Cedres');

  /// Une image PNG valide de 1x1 — le plan que le faux Dio renverra.
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  /// Remplace le Dio du conteneur par un double qui rend une vraie image.
  ///
  /// Sans lui, le telechargement du plan echoue et la vue interactive affiche
  /// son message d'erreur : le test ne verrait jamais `PlanInteractif`.
  void dioQuiRendUnPlan() {
    final faux = _MockDio();
    when(() => faux.get<List<int>>(any(), options: any(named: 'options'))).thenAnswer(
      (_) async => Response<List<int>>(
        data: png,
        statusCode: 200,
        requestOptions: RequestOptions(path: '/x'),
      ),
    );
    if (sl.isRegistered<Dio>()) sl.unregister<Dio>();
    sl.registerSingleton<Dio>(faux);
  }

  /// Laisse le VRAI travail asynchrone avancer — decodage de l'image compris.
  Future<void> pomperAvecReseau(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Plan plan(String id, {String? etageId}) => Plan(
        id: id,
        chantierId: 'c1',
        nom: 'Niveau $id',
        fichierUrl: 'https://exemple.test/$id.pdf',
        etage: etageId == null ? null : PlanNiveauRef(id: etageId, nom: 'R+2'),
      );

  void repondre({
    ChantierStructure? structure,
    List<Plan> plans = const [],
  }) {
    when(() => getStructure(any())).thenAnswer(
      (_) async => Right<Failure, ChantierStructure>(
        structure ?? const ChantierStructure(),
      ),
    );
    when(() => getPlans(any()))
        .thenAnswer((_) async => Right<Failure, List<Plan>>(plans));

    // Chaque vignette de plan redemande sa fiche pour construire son apercu.
    when(() => getDetail(any())).thenAnswer(
      (_) async => Right<Failure, Plan>(
        plans.isEmpty ? plan('p0') : plans.first,
      ),
    );
  }

  /// Pompe SANS attendre le repos.
  ///
  /// Les vignettes de plan affichent un indicateur circulaire pendant leur
  /// telechargement, et un indicateur circulaire programme une image a
  /// l'infini : `pumpAndSettle` n'aboutirait jamais des qu'un plan est
  /// affiche.
  Future<void> pomperSansRepos(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('chantier SANS structure ni plan : un message, pas un ecran blanc',
      (tester) async {
    repondre();

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('une structure SANS plan reste lisible', (tester) async {
    // Situation courante d'un chantier qui vient d'etre saisi : les niveaux
    // existent, les plans ne sont pas encore deposes.
    repondre(
      structure: const ChantierStructure(
        batiments: [
          BatimentStructure(
            id: 'b1',
            nom: 'Batiment A',
            etages: [EtageStructure(id: 'e1', nom: 'R+2')],
          ),
        ],
      ),
    );

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('des plans SANS structure ne disparaissent pas', (tester) async {
    // L'inverse : des plans deposes sur un chantier dont personne n'a saisi
    // les niveaux. Les rattacher a une structure absente les ferait
    // disparaitre de l'ecran, alors qu'ils sont bien la.
    repondre(plans: [plan('p1'), plan('p2')]);

    await pomperPage(tester, page);
    await pomperSansRepos(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('structure ET plans : le croisement se monte sans incident',
      (tester) async {
    repondre(
      structure: const ChantierStructure(
        batiments: [
          BatimentStructure(
            id: 'b1',
            nom: 'Batiment A',
            etages: [EtageStructure(id: 'e1', nom: 'R+2')],
          ),
        ],
      ),
      plans: [plan('p1', etageId: 'e1')],
    );

    await pomperPage(tester, page);
    await pomperSansRepos(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('une panne serveur ne laisse pas l ecran en chargement perpetuel',
      (tester) async {
    when(() => getStructure(any())).thenAnswer(
      (_) async => const Left<Failure, ChantierStructure>(NetworkFailure()),
    );
    when(() => getPlans(any())).thenAnswer(
      (_) async => const Left<Failure, List<Plan>>(NetworkFailure()),
    );

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  group('mise en page — balayage des formats', () {
    // Cet ecran range les plans par niveau dans une grille dont le nombre de
    // colonnes bascule d'un coup : une sur telephone, quatre sur tablette.
    // Le balayage verifie qu'aucune des deux configurations ne deborde, aux
    // formats intermediaires compris — notamment la tablette compacte de
    // 600 dp, qui reste en dessous du seuil et garde donc la grille a une
    // colonne.
    for (final format in tousLesFormats) {
      testWidgets('sans debordement sur $format', (tester) async {
        repondre(
          structure: const ChantierStructure(
            batiments: [
              BatimentStructure(
                id: 'b1',
                nom: 'Batiment A — corps principal',
                etages: [
                  EtageStructure(id: 'e1', nom: 'R+2'),
                  EtageStructure(id: 'e2', nom: 'Sous-sol technique'),
                ],
              ),
            ],
          ),
          plans: [plan('p1', etageId: 'e1'), plan('p2', etageId: 'e2')],
        );

        await pomperPage(tester, page, taille: format.taille);
        await pomperSansRepos(tester);

        expect(tester.takeException(), isNull,
            reason: 'debordement de mise en page sur $format');
      });
    }
  });

  // ── Une feuille ouvre la vue interactive, à N'IMPORTE QUEL niveau ────────
  //
  // Elle n'existait qu'au niveau de l'appartement. Un chantier sans bâtiment,
  // un bâtiment sans étage ou un étage sans appartement affichait « aucun
  // bâtiment / étage / appartement » AU-DESSUS de son plan, sans jamais
  // permettre d'y poser une réserve — alors que c'était une feuille comme une
  // autre. Le client l'a écrit : « lorsqu'on arrive sur un plan qui n'a plus
  // de sous-plan, ouvrir la vue interactive de ce plan ».

  testWidgets('un chantier sans bâtiment ouvre directement son plan global',
      (tester) async {
    repondre(
      structure: const ChantierStructure(),
      plans: [plan('global')],
    );
    dioQuiRendUnPlan();

    await pomperPage(tester, page);
    await pomperAvecReseau(tester);

    // Plus le message « aucun plan global » ni une liste vide : le plan lui-même.
    expect(find.byType(PlanInteractif), findsOneWidget);
  });

  testWidgets('un bâtiment sans étage ouvre son plan', (tester) async {
    repondre(
      structure: const ChantierStructure(
        batiments: [BatimentStructure(id: 'b1', nom: 'Bâtiment A', etages: [])],
      ),
      plans: [
        plan('global'),
        Plan(
          id: 'pb1',
          chantierId: 'c1',
          nom: 'Plan du bâtiment A',
          fichierUrl: 'https://exemple.test/pb1.pdf',
          batiment: const PlanNiveauRef(id: 'b1', nom: 'Bâtiment A'),
        ),
      ],
    );
    dioQuiRendUnPlan();

    await pomperPage(tester, page);
    await pomperSansRepos(tester);

    // On descend dans le bâtiment : il n'a aucun étage, sa vue interactive
    // doit s'ouvrir.
    await tester.tap(find.text('Bâtiment A').first);
    await pomperAvecReseau(tester);

    expect(find.byType(PlanInteractif), findsOneWidget);
  });

  testWidgets('un chantier sans bâtiment NI plan garde son message', (tester) async {
    // Pas de plan à ouvrir : le message reste la seule chose honnête à dire.
    repondre(structure: const ChantierStructure(), plans: const []);

    await pomperPage(tester, page);
    await pomperSansRepos(tester);

    expect(find.byType(PlanInteractif), findsNothing);
  });

  // ── Plans de DÉTAIL : la profondeur sous le dernier niveau de structure ───
  //
  // La hiérarchie venait de la structure du chantier et s'arrêtait donc à
  // l'appartement. `parentId` ouvre une profondeur quelconque en dessous : le
  // plan d'une pièce dans celui d'un appartement, celui d'un mur dans celui de
  // la pièce. La règle reste la même à chaque cran — seuls les enfants DIRECTS
  // du plan ouvert sont affichés.

  Plan detail(String id, String parentId) => Plan(
        id: id,
        chantierId: 'c1',
        nom: 'Detail $id',
        fichierUrl: 'https://exemple.test/$id.pdf',
        parentId: parentId,
      );

  testWidgets('un plan qui a des détails les LISTE au lieu de s’ouvrir',
      (tester) async {
    repondre(
      structure: const ChantierStructure(),
      plans: [plan('global'), detail('d1', 'global')],
    );
    dioQuiRendUnPlan();

    await pomperPage(tester, page);
    await pomperAvecReseau(tester);

    // Le plan global a un détail : on doit voir la section qui les liste.
    // (Le plan lui-même reste affiché en tête, c'est voulu : on voit où l'on
    // est en même temps que ce vers quoi on peut descendre.)
    expect(find.text('Detail d1'), findsWidgets);
    expect(find.text('PLANS DE DÉTAIL'), findsWidgets);
  });

  testWidgets('ouvrir un détail sans enfant donne la vue interactive',
      (tester) async {
    repondre(
      structure: const ChantierStructure(),
      plans: [plan('global'), detail('d1', 'global')],
    );
    dioQuiRendUnPlan();

    await pomperPage(tester, page);
    await pomperAvecReseau(tester);

    await tester.tap(find.text('Detail d1').first);
    await pomperAvecReseau(tester);

    // `d1` n'a aucun détail : c'est une feuille, le plan devient la zone de
    // travail — plus de section « Plans de détail » à proposer.
    expect(find.byType(PlanInteractif), findsOneWidget);
    expect(find.text('PLANS DE DÉTAIL'), findsNothing);
  });

  testWidgets('un détail de détail ne remonte JAMAIS au niveau du dessus',
      (tester) async {
    // La navigation est progressive : ouvrir le plan global ne doit pas
    // révéler les petits-enfants.
    repondre(
      structure: const ChantierStructure(),
      plans: [plan('global'), detail('d1', 'global'), detail('d11', 'd1')],
    );
    dioQuiRendUnPlan();

    await pomperPage(tester, page);
    await pomperAvecReseau(tester);

    expect(find.text('Detail d1'), findsWidgets);
    expect(find.text('Detail d11'), findsNothing);

    // Un cran plus bas, c'est lui qu'on voit — et lui seul.
    await tester.tap(find.text('Detail d1').first);
    await pomperAvecReseau(tester);

    expect(find.text('Detail d11'), findsWidgets);
  });

  testWidgets('un plan de détail ne se substitue pas au plan de son niveau',
      (tester) async {
    // Un détail HÉRITE des rattachements de son parent : sans exclusion, le
    // plan de la cuisine pouvait être retenu COMME le plan de l'appartement,
    // qui disparaissait derrière l'un de ses détails.
    repondre(
      structure: const ChantierStructure(),
      plans: [
        plan('global'),
        // Version supérieure : c'est lui qui l'emporterait sans la garde.
        Plan(
          id: 'd1',
          chantierId: 'c1',
          nom: 'Detail d1',
          version: 9,
          fichierUrl: 'https://exemple.test/d1.pdf',
          parentId: 'global',
        ),
      ],
    );
    dioQuiRendUnPlan();

    await pomperPage(tester, page);
    await pomperAvecReseau(tester);

    // Le global reste le plan du niveau : son détail est proposé EN DESSOUS.
    expect(find.text('Detail d1'), findsWidgets);
  });

  // ── La porte d'entrée : créer un plan de détail ──────────────────────────
  //
  // Sans elle, la profondeur existait en base et dans la navigation mais on ne
  // pouvait pas créer un détail depuis l'application. Une fonctionnalité sans
  // porte d'entrée n'existe pas.

  testWidgets('un rôle qui dépose voit l’action « ajouter un détail »',
      (tester) async {
    repondre(structure: const ChantierStructure(), plans: [plan('global')]);
    dioQuiRendUnPlan();

    await pomperPage(tester, page, role: UserRole.entreprise);
    await pomperAvecReseau(tester);

    expect(find.byTooltip('Ajouter un plan de détail'), findsOneWidget);
  });

  testWidgets('un rôle sans droit de dépôt ne la voit pas', (tester) async {
    // Miroir du groupe `DEPOSANT` du serveur : la proposer mènerait à un 403.
    repondre(structure: const ChantierStructure(), plans: [plan('global')]);
    dioQuiRendUnPlan();

    await pomperPage(tester, page, role: UserRole.sousTraitant);
    await pomperAvecReseau(tester);

    expect(find.byTooltip('Ajouter un plan de détail'), findsNothing);
  });

  testWidgets('aucune action quand il n’y a AUCUN plan à l’écran', (tester) async {
    // Un détail se rattache à un plan : sans plan courant, il n'y a rien à
    // quoi le rattacher.
    repondre(structure: const ChantierStructure(), plans: const []);

    await pomperPage(tester, page, role: UserRole.entreprise);
    await pomperSansRepos(tester);

    expect(find.byTooltip('Ajouter un plan de détail'), findsNothing);
  });

  group('plan EN ATTENTE de validation', () {
    // Un plan joint a une demande de chantier encore en attente appartient a
    // un chantier qui n'existe pas encore : le serveur refuse toute reserve
    // posee dessus (`reserve.service.js:189`). Cet ecran etait le SEUL des
    // trois a ignorer la condition — on pouvait donc remplir tout le
    // formulaire pour un envoi refuse a l'arrivee.
    Plan enAttente(String id) => Plan(
          id: id,
          chantierId: 'c1',
          nom: 'Plan $id',
          fichierUrl: 'https://exemple.test/$id.pdf',
          statut: 'en_attente_validation',
        );

    testWidgets('le plan reste consultable', (tester) async {
      repondre(structure: const ChantierStructure(), plans: [enAttente('global')]);
      dioQuiRendUnPlan();

      await pomperPage(tester, page);
      await pomperAvecReseau(tester);

      // On ne cache rien : le plan se regarde, seule la POSE est fermee.
      expect(find.byType(PlanInteractif), findsOneWidget);
    });

    testWidgets('aucun appui sur le plan n ouvre le formulaire', (tester) async {
      repondre(structure: const ChantierStructure(), plans: [enAttente('global')]);
      dioQuiRendUnPlan();

      await pomperPage(tester, page);
      await pomperAvecReseau(tester);

      // `onPointAppuye` nul : la visionneuse ne peut plus declencher la
      // creation, quel que soit l'endroit touche.
      final vue = tester.widget<PlanInteractif>(find.byType(PlanInteractif));
      expect(vue.onPointAppuye, isNull);
    });

    testWidgets('le bouton « Nouvelle reserve » n est pas propose', (tester) async {
      repondre(structure: const ChantierStructure(), plans: [enAttente('global')]);
      dioQuiRendUnPlan();

      await pomperPage(tester, page);
      await pomperAvecReseau(tester);

      expect(find.text('Nouvelle réserve'), findsNothing);
    });

    testWidgets('un plan ACTIF, lui, reste posable', (tester) async {
      // Controle symetrique : sans lui, une regression qui fermerait la pose
      // partout passerait pour un succes.
      repondre(structure: const ChantierStructure(), plans: [plan('global')]);
      dioQuiRendUnPlan();

      await pomperPage(tester, page);
      await pomperAvecReseau(tester);

      final vue = tester.widget<PlanInteractif>(find.byType(PlanInteractif));
      expect(vue.onPointAppuye, isNotNull);
      expect(find.text('Nouvelle réserve'), findsOneWidget);
    });
  });
}

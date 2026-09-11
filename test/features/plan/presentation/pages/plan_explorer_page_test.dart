import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/entities/plan.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_plan_detail.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_plans_chantier.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_plans_racines.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_sous_plans.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/pages/plan_explorer_page.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/widgets/contexte_plan.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/widgets/plan_interactif.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/chantier_structure.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_chantier_structure.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/balayage_responsive.dart';
import '../../../../helpers/pompe_page.dart';

class _MockStructure extends Mock implements GetChantierStructure {}

class _MockPlansChantier extends Mock implements GetPlansChantier {}

class _MockRacines extends Mock implements GetPlansRacines {}

class _MockSousPlans extends Mock implements GetSousPlans {}

class _MockDetail extends Mock implements GetPlanDetail {}

class _MockDio extends Mock implements Dio {}

/// L'explorateur de plans — la navigation PAR NIVEAU.
///
/// ## La règle que ces tests verrouillent
///
/// À chaque étape, l'écran ne montre QUE les enfants directs du plan ouvert.
/// Jamais l'arborescence entière, jamais une branche voisine. C'est la
/// correction demandée par le client : le parcours affichait auparavant tous
/// les plans du chantier à plat, et le premier appui ouvrait directement le
/// formulaire de réserve.
///
/// ## Pourquoi cela se teste ici et pas seulement côté serveur
///
/// Le serveur borne déjà la descente (`/plans/racines`, `/plans/:id/sous-plans`).
/// Mais rien n'empêcherait l'écran de cumuler les niveaux reçus, ou de garder
/// à l'affichage ceux du plan précédent pendant le chargement du suivant — et
/// l'utilisateur verrait alors deux branches mélangées sans qu'aucune requête
/// soit fautive.
void main() {
  late _MockRacines getRacines;
  late _MockSousPlans getSousPlans;
  late _MockDetail getDetail;
  late _MockStructure getStructure;
  late _MockPlansChantier getPlansChantier;

  void desinscrire() {
    if (sl.isRegistered<GetPlansRacines>()) sl.unregister<GetPlansRacines>();
    if (sl.isRegistered<GetSousPlans>()) sl.unregister<GetSousPlans>();
    if (sl.isRegistered<GetPlanDetail>()) sl.unregister<GetPlanDetail>();
    if (sl.isRegistered<GetChantierStructure>()) sl.unregister<GetChantierStructure>();
    if (sl.isRegistered<GetPlansChantier>()) sl.unregister<GetPlansChantier>();
    if (sl.isRegistered<Dio>()) sl.unregister<Dio>();
  }

  /// Une image PNG valide de 1x1 — le plan que le faux Dio renverra.
  ///
  /// Sans elle, le téléchargement échoue et la vue affiche son message
  /// d'erreur : aucun test ne verrait jamais `PlanInteractif`.
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  setUp(() {
    getRacines = _MockRacines();
    getSousPlans = _MockSousPlans();
    getDetail = _MockDetail();

    final dio = _MockDio();
    when(() => dio.get<List<int>>(any(), options: any(named: 'options'))).thenAnswer(
      (_) async => Response<List<int>>(
        data: png,
        statusCode: 200,
        requestOptions: RequestOptions(path: '/x'),
      ),
    );

    desinscrire();
    sl.registerLazySingleton<GetPlansRacines>(() => getRacines);
    sl.registerLazySingleton<GetSousPlans>(() => getSousPlans);
    sl.registerLazySingleton<GetPlanDetail>(() => getDetail);
    sl.registerSingleton<Dio>(dio);

    // Par défaut, un chantier SANS structure : les tests de la descente par
    // sous-plans n'en dépendent pas. Ceux de l'arborescence la redéfinissent.
    getStructure = _MockStructure();
    getPlansChantier = _MockPlansChantier();
    when(() => getStructure(any()))
        .thenAnswer((_) async => const Right<Failure, ChantierStructure>(ChantierStructure()));
    when(() => getPlansChantier(any()))
        .thenAnswer((_) async => const Right<Failure, List<Plan>>([]));
    sl.registerLazySingleton<GetChantierStructure>(() => getStructure);
    sl.registerLazySingleton<GetPlansChantier>(() => getPlansChantier);
  });

  tearDown(desinscrire);

  const page = PlanExplorerPage(chantierId: 'c1', chantierNom: 'Les Cedres');

  Plan planDe(String nom, {int sousPlans = 0, int reserves = 0, String? parentId}) => Plan(
        id: nom,
        chantierId: 'c1',
        nom: nom,
        fichierUrl: 'https://exemple.test/$nom.png',
        parentId: parentId,
        nombreSousPlans: sousPlans,
        nombreReserves: reserves,
      );

  /// Laisse le VRAI travail asynchrone avancer — décodage de l'image compris.
  Future<void> pomperAvecReseau(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  void racines(List<Plan> plans) {
    when(() => getRacines(any()))
        .thenAnswer((_) async => Right<Failure, List<Plan>>(plans));
  }

  /// Le détail rend le plan tel quel — image et réserves comprises.
  void detailRend(Map<String, Plan> parId) {
    when(() => getDetail(any())).thenAnswer((invocation) async {
      final id = invocation.positionalArguments.first as String;
      final plan = parId[id];
      return plan == null
          ? const Left<Failure, Plan>(ServerFailure(errorMessage: 'Plan introuvable'))
          : Right<Failure, Plan>(plan);
    });
  }

  void enfants(Map<String, List<Plan>> parParent) {
    when(() => getSousPlans(any())).thenAnswer((invocation) async {
      final id = invocation.positionalArguments.first as String;
      return Right<Failure, List<Plan>>(parParent[id] ?? const []);
    });
  }

  group('le premier niveau', () {
    testWidgets('n’affiche QUE les plans globaux', (tester) async {
      // Le serveur ne renvoie que les racines ; l'écran ne doit rien y ajouter.
      racines([planDe('Plan Global A', sousPlans: 3), planDe('Plan Global B')]);

      await pomperPage(tester, page, role: UserRole.chefProjet);
      await pomperAvecReseau(tester);

      expect(find.text('Plan Global A'), findsOneWidget);
      expect(find.text('Plan Global B'), findsOneWidget);
      // Aucun sous-plan n'a été demandé : on n'est pas descendu.
      verifyNever(() => getSousPlans(any()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('un chantier sans plan le DIT, au lieu d’un écran blanc',
        (tester) async {
      // Sur un chantier, un écran vide sans explication se lit comme une
      // application cassée — et l'appel qui suit part au support.
      racines(const []);

      await pomperPage(tester, page, role: UserRole.chefProjet);
      await pomperAvecReseau(tester);

      expect(find.textContaining('Aucun plan'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('la descente', () {
    testWidgets('ouvrir un plan global montre SES enfants directs, et eux seuls',
        (tester) async {
      final global = planDe('Plan Global A', sousPlans: 3);
      racines([global, planDe('Plan Global B', sousPlans: 2)]);
      detailRend({'Plan Global A': global});
      enfants({
        'Plan Global A': [planDe('A1', parentId: 'Plan Global A', sousPlans: 2), planDe('A2', parentId: 'Plan Global A')],
        // La branche VOISINE : elle ne doit jamais apparaître.
        'Plan Global B': [planDe('B1', parentId: 'Plan Global B')],
      });

      await pomperPage(tester, page, role: UserRole.chefProjet);
      await pomperAvecReseau(tester);

      await tester.tap(find.text('Plan Global A'));
      await pomperAvecReseau(tester);

      expect(find.text('A1'), findsOneWidget);
      expect(find.text('A2'), findsOneWidget);
      // Ni la branche voisine, ni les petits-enfants de A1.
      expect(find.text('B1'), findsNothing);
      expect(find.text('Plan Global B'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la descente fonctionne sur PLUSIEURS niveaux', (tester) async {
      final global = planDe('G', sousPlans: 1);
      final a1 = planDe('A1', parentId: 'G', sousPlans: 2);
      racines([global]);
      detailRend({'G': global, 'A1': a1});
      enfants({
        'G': [a1],
        'A1': [planDe('A1.1', parentId: 'A1'), planDe('A1.2', parentId: 'A1')],
      });

      await pomperPage(tester, page, role: UserRole.chefProjet);
      await pomperAvecReseau(tester);

      await tester.tap(find.text('G'));
      await pomperAvecReseau(tester);
      await tester.tap(find.text('A1'));
      await pomperAvecReseau(tester);

      // `skipOffstage: false` : la fiche du plan ouvert précède désormais ses
      // sous-plans dans le panneau, qui DÉFILE — le second peut se trouver
      // sous le pli. Ce qui se vérifie ici, c'est qu'ils y sont, tous deux.
      expect(find.text('A1.1', skipOffstage: false), findsOneWidget);
      expect(find.text('A1.2', skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un plan SANS enfant ne déclenche aucune requête de sous-plans',
        (tester) async {
      // Le compteur du serveur (`nombre_sous_plans`) évite un aller-retour sur
      // la feuille de l'arborescence — le cas le plus fréquent.
      final feuille = planDe('Feuille');
      racines([feuille]);
      detailRend({'Feuille': feuille});
      enfants(const {});

      await pomperPage(tester, page, role: UserRole.chefProjet);
      await pomperAvecReseau(tester);

      await tester.tap(find.text('Feuille'));
      await pomperAvecReseau(tester);

      verifyNever(() => getSousPlans(any()));
      expect(tester.takeException(), isNull);
    });
  });

  group('le plan ouvert', () {
    testWidgets('affiche l’IMAGE réelle du plan, pas son nom de fichier',
        (tester) async {
      final feuille = planDe('Feuille');
      racines([feuille]);
      detailRend({'Feuille': feuille});

      await pomperPage(tester, page, role: UserRole.chefProjet);
      await pomperAvecReseau(tester);
      await tester.tap(find.text('Feuille'));
      await pomperAvecReseau(tester);

      expect(find.byType(PlanInteractif), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('propose « Créer une réserve » à un rôle qui peut intervenir',
        (tester) async {
      final feuille = planDe('Feuille');
      racines([feuille]);
      detailRend({'Feuille': feuille});

      await pomperPage(tester, page, role: UserRole.chefProjet);
      await pomperAvecReseau(tester);
      await tester.tap(find.text('Feuille'));
      await pomperAvecReseau(tester);

      expect(find.text('Créer une réserve'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('le propose AUSSI sur un plan qui a des sous-plans',
        (tester) async {
      // Un défaut de façade se relève sur le plan du bâtiment, pas sur celui
      // d'un appartement : limiter la création au dernier niveau obligerait à
      // inventer un sous-plan pour chaque constat.
      final global = planDe('G', sousPlans: 1);
      racines([global]);
      detailRend({'G': global});
      enfants({'G': [planDe('A1', parentId: 'G')]});

      await pomperPage(tester, page, role: UserRole.chefProjet);
      await pomperAvecReseau(tester);
      await tester.tap(find.text('G'));
      await pomperAvecReseau(tester);

      expect(find.text('Créer une réserve'), findsOneWidget);
      expect(find.text('A1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ne le propose PAS à un rôle en lecture seule', (tester) async {
      // Le serveur réserve la pose d'une réserve aux rôles d'intervention :
      // afficher le bouton promettrait une action qui reviendrait en 403.
      final feuille = planDe('Feuille');
      racines([feuille]);
      detailRend({'Feuille': feuille});

      await pomperPage(tester, page, role: UserRole.client);
      await pomperAvecReseau(tester);
      await tester.tap(find.text('Feuille'));
      await pomperAvecReseau(tester);

      expect(find.text('Créer une réserve'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('l’ouverture directe sur un plan', () {
    testWidgets('part du plan désigné, sans passer par les plans globaux',
        (tester) async {
      // Le parcours de la bande « Derniers plans » : on y appuie sur un plan
      // précis et on doit arriver dessus, pas au sommet de l'arborescence.
      final global = planDe('G', sousPlans: 1);
      racines([global]);
      detailRend({'G': global});
      enfants({'G': [planDe('A1', parentId: 'G')]});

      await pomperPage(
        tester,
        const PlanExplorerPage(chantierId: 'c1', chantierNom: 'Les Cedres', planIdInitial: 'G'),
        role: UserRole.chefProjet,
      );
      await pomperAvecReseau(tester);

      expect(find.text('A1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un plan introuvable retombe sur les plans globaux',
        (tester) async {
      // Plan supprimé entre-temps, identifiant erroné : l'utilisateur voulait
      // voir des plans, il en voit — plutôt qu'une page d'erreur.
      racines([planDe('Plan Global A')]);
      detailRend(const {});

      await pomperPage(
        tester,
        const PlanExplorerPage(chantierId: 'c1', planIdInitial: 'disparu'),
        role: UserRole.chefProjet,
      );
      await pomperAvecReseau(tester);

      expect(find.text('Plan Global A'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('mise en page — balayage des formats', () {
    // L'explorateur est l'écran le plus dense du parcours : un bandeau, une
    // image qui occupe la hauteur restante, et un panneau bas qui empile un
    // bouton, deux sections et leurs listes. C'est exactement la structure qui
    // déborde quand la hauteur s'effondre — un téléphone en paysage — ou quand
    // la largeur se resserre à 320 dp.
    for (final format in tousLesFormats) {
      testWidgets('sans débordement, plan ouvert — $format', (tester) async {
        final global = planDe('Plan Global A', sousPlans: 2, reserves: 3);
        racines([global]);
        detailRend({'Plan Global A': global});
        enfants({
          'Plan Global A': [
            planDe('Sous-plan A1', parentId: 'Plan Global A', sousPlans: 4, reserves: 12),
            planDe('Sous-plan A2 au nom particulièrement long', parentId: 'Plan Global A'),
          ],
        });

        await pomperPage(tester, page, role: UserRole.chefProjet, taille: format.taille);
        await pomperAvecReseau(tester);
        await tester.tap(find.text('Plan Global A'));
        await pomperAvecReseau(tester);

        expect(tester.takeException(), isNull,
            reason: 'débordement de mise en page sur $format');
      });
    }

    for (final format in formatsCritiques) {
      testWidgets('sans débordement, liste des plans globaux — $format', (tester) async {
        racines([
          planDe('Plan de masse', sousPlans: 3, reserves: 8),
          planDe('Bâtiment A — façade nord et pignon ouest', sousPlans: 12),
        ]);

        await pomperPage(tester, page, role: UserRole.chefProjet, taille: format.taille);
        await pomperAvecReseau(tester);

        expect(tester.takeException(), isNull,
            reason: 'débordement de mise en page sur $format');
      });
    }
  });

  group('plan EN ATTENTE de validation', () {
    // Le bouton « Creer une reserve » etait bien masque sur un plan en
    // attente, mais le gestionnaire d'appui sur l'IMAGE utilisait la variable
    // brute `pointageAutorise` au lieu du garde calcule trois lignes plus
    // haut : un appui n'importe ou sur le plan ouvrait quand meme le
    // formulaire, que le serveur refuse (`reserve.service.js:189`).
    Plan enAttente(String nom) => Plan(
          id: nom,
          chantierId: 'c1',
          nom: nom,
          fichierUrl: 'https://exemple.test/$nom.png',
          statut: 'en_attente_validation',
        );

    testWidgets('l appui sur l image n ouvre PAS le formulaire', (tester) async {
      final plan = enAttente('Plan en attente');
      racines([plan]);
      detailRend({'Plan en attente': plan});

      await pomperPage(tester, page, role: UserRole.chefProjet);
      await pomperAvecReseau(tester);
      await tester.tap(find.text('Plan en attente'));
      await pomperAvecReseau(tester);

      final vue = tester.widget<PlanInteractif>(find.byType(PlanInteractif));
      expect(vue.onPointAppuye, isNull);
    });

    testWidgets('un plan ACTIF garde l appui createur', (tester) async {
      // Controle symetrique : le garde ne doit pas fermer la pose partout.
      final plan = planDe('Plan actif');
      racines([plan]);
      detailRend({'Plan actif': plan});

      await pomperPage(tester, page, role: UserRole.chefProjet);
      await pomperAvecReseau(tester);
      await tester.tap(find.text('Plan actif'));
      await pomperAvecReseau(tester);

      final vue = tester.widget<PlanInteractif>(find.byType(PlanInteractif));
      expect(vue.onPointAppuye, isNotNull);
    });
  });

  group('le plan global mène aux bâtiments, niveaux et appartements', () {
    // La demande du client : ouvrir le plan GLOBAL montre, sous le plan, les
    // bâtiments ; chaque bâtiment ses sections et ses niveaux, chaque niveau
    // les plans de ses appartements — comme l'écran « Envoi de plans ». Et
    // ouvrir le plan d'un appartement montre, sous lui, où il se trouve.
    //
    // Ces plans ne sont PAS des sous-plans du plan global : ils sont
    // rattachés à la structure, sans parent. Le serveur les renvoyait donc
    // tous à plat parmi les « racines ».

    const structure = ChantierStructure(batiments: [
      BatimentStructure(id: 'b1', nom: 'Bâtiment A', etages: [
        EtageStructure(id: 'e1', nom: 'R+1', niveau: 1, zones: [
          ZoneStructure(id: 'z1', nom: 'A001'),
          ZoneStructure(id: 'z2', nom: 'A002'),
        ]),
        // Cote négative : rangé sous SOUS-SOLS, pas sous ÉTAGES.
        EtageStructure(id: 'e0', nom: 'SS1', niveau: -1),
      ]),
      BatimentStructure(id: 'b2', nom: 'Bâtiment B'),
    ]);

    const global = Plan(
      id: 'g',
      chantierId: 'c1',
      nom: 'Plan de masse',
      fichierUrl: 'https://exemple.test/g.png',
    );
    const planA001 = Plan(
      id: 'p-a001',
      chantierId: 'c1',
      nom: 'Plan A001',
      fichierUrl: 'https://exemple.test/a001.png',
      batiment: PlanNiveauRef(id: 'b1', nom: 'Bâtiment A'),
      etage: PlanNiveauRef(id: 'e1', nom: 'R+1'),
      zone: PlanNiveauRef(id: 'z1', nom: 'A001'),
      // Servis par `GET /chantiers/:id/plans` (`_compterEnfants`).
      nombreReserves: 3,
      nombreReservesATraiter: 2,
    );

    void chantier({List<Plan> racinesServies = const [global, planA001]}) {
      racines(racinesServies);
      detailRend({'g': global, 'p-a001': planA001});
      when(() => getStructure(any()))
          .thenAnswer((_) async => const Right<Failure, ChantierStructure>(structure));
      when(() => getPlansChantier(any()))
          .thenAnswer((_) async => const Right<Failure, List<Plan>>([global, planA001]));
    }

    /// Appuie sur un élément du panneau — amené à l'écran d'abord, le panneau
    /// défile — et laisse l'`ExpansionTile` finir de s'ouvrir.
    Future<void> appuyer(WidgetTester tester, String texte) async {
      await tester.ensureVisible(find.text(texte));
      await tester.pump();
      await tester.tap(find.text(texte));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> ouvrirAppartementDepuisLeGlobal(WidgetTester tester) async {
      await pomperPage(tester, page, role: UserRole.chefProjet);
      await pomperAvecReseau(tester);
      await tester.tap(find.text('Plan de masse'));
      await pomperAvecReseau(tester);
      await appuyer(tester, 'Bâtiment A');
      await appuyer(tester, 'R+1');
      await appuyer(tester, 'Plan A001');
      await pomperAvecReseau(tester);
    }

    testWidgets('la liste de départ ne montre QUE les plans globaux', (tester) async {
      chantier();

      await pomperPage(tester, page, role: UserRole.chefProjet);
      await pomperAvecReseau(tester);

      expect(find.text('Plan de masse'), findsOneWidget);
      // Le plan d'appartement n'est plus mêlé aux plans globaux.
      expect(find.text('Plan A001'), findsNothing);
      // La tuile annonce vers quoi elle mène.
      expect(find.textContaining('2 bâtiments'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ouvrir le plan global montre ses bâtiments, puis leurs niveaux et appartements',
        (tester) async {
      chantier();

      await pomperPage(tester, page, role: UserRole.chefProjet);
      await pomperAvecReseau(tester);
      await tester.tap(find.text('Plan de masse'));
      await pomperAvecReseau(tester);

      // Le plan global EN HAUT, où l'on peut toujours poser une réserve…
      expect(find.byType(PlanInteractif), findsOneWidget);
      expect(find.text('Créer une réserve'), findsOneWidget);
      // … et ses bâtiments EN BAS.
      expect(find.text('Bâtiment A'), findsOneWidget);
      expect(find.text('Bâtiment B'), findsOneWidget);

      await appuyer(tester, 'Bâtiment A');
      expect(find.text('SOUS-SOLS'), findsOneWidget);
      expect(find.text('ÉTAGES'), findsOneWidget);
      expect(find.text('TOITURE'), findsOneWidget);
      expect(find.text('SS1'), findsOneWidget);

      await appuyer(tester, 'R+1');
      expect(find.text('A001'), findsOneWidget);
      expect(find.text('A002'), findsOneWidget);
      expect(find.text('Plan A001'), findsOneWidget);
      // Le compteur : le total, et ce qui reste à lever.
      expect(find.text('3 réserves · 2 à traiter'), findsOneWidget);
      // A002 n'a pas de plan : l'écran le dit plutôt que de le taire.
      expect(find.text('Aucun plan pour cet appartement'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ouvrir le plan d’un appartement montre OÙ il se trouve', (tester) async {
      chantier();

      await ouvrirAppartementDepuisLeGlobal(tester);

      // Le plan de l'appartement s'ouvre en haut, titre en gras…
      expect(find.byType(PlanInteractif), findsOneWidget);
      expect(find.text('Plan A001'), findsOneWidget);
      expect(find.text('Les Cedres › Bâtiment A › R+1 › A001'), findsOneWidget);
      // … et en bas : chantier, bâtiment, niveau, appartement.
      expect(find.text('Les Cedres'), findsOneWidget);
      expect(find.text('Bâtiment A'), findsOneWidget);
      expect(find.text('R+1 · Étages'), findsOneWidget);
      expect(find.text('A001'), findsOneWidget);
      // Un appartement n'a pas de sous-section : plus d'arborescence.
      expect(find.text('Bâtiment B'), findsNothing);
      // Et on y pose une réserve comme sur le plan global.
      expect(find.text('Créer une réserve'), findsOneWidget);
      final vue = tester.widget<PlanInteractif>(find.byType(PlanInteractif));
      expect(vue.onPointAppuye, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('le retour ramène au plan global, arborescence restée dépliée', (tester) async {
      chantier();

      await ouvrirAppartementDepuisLeGlobal(tester);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await pomperAvecReseau(tester);

      expect(find.text('Plan de masse'), findsOneWidget);
      // Rien à redéplier : on reprend là où on s'était arrêté.
      expect(find.text('R+1'), findsOneWidget);
      expect(find.text('Plan A001'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sans plan global, les bâtiments restent atteignables', (tester) async {
      // Un chantier dont on n'a déposé que des plans d'appartement : les
      // retirer de la liste de départ ne doit pas les rendre introuvables.
      chantier(racinesServies: const [planA001]);

      await pomperPage(tester, page, role: UserRole.chefProjet);
      await pomperAvecReseau(tester);

      expect(find.text("Aucun plan global n'est rattaché à ce chantier."), findsOneWidget);
      await appuyer(tester, 'Bâtiment A');
      await appuyer(tester, 'R+1');
      await appuyer(tester, 'Plan A001');
      await pomperAvecReseau(tester);

      expect(find.byType(PlanInteractif), findsOneWidget);
      expect(find.text('R+1 · Étages'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('structure indisponible : le plan reste utilisable, le panneau propose de réessayer',
        (tester) async {
      chantier();
      when(() => getStructure(any())).thenAnswer(
        (_) async => const Left<Failure, ChantierStructure>(ServerFailure(errorMessage: 'Hors ligne')),
      );

      await pomperPage(tester, page, role: UserRole.chefProjet);
      await pomperAvecReseau(tester);
      await tester.tap(find.text('Plan de masse'));
      await pomperAvecReseau(tester);

      expect(find.byType(PlanInteractif), findsOneWidget);
      expect(find.text('Créer une réserve'), findsOneWidget);
      expect(find.text("Les bâtiments du chantier n'ont pas pu être chargés."), findsOneWidget);

      when(() => getStructure(any()))
          .thenAnswer((_) async => const Right<Failure, ChantierStructure>(structure));
      await appuyer(tester, 'Réessayer');
      await pomperAvecReseau(tester);

      expect(find.text('Bâtiment A'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('rangement des plans', () {
    Plan plan(
      String id, {
      String nom = 'plan.pdf',
      int version = 1,
      bool courant = true,
      String? zone,
      String? parent,
    }) =>
        Plan(
          id: id,
          chantierId: 'c1',
          nom: nom,
          fichierUrl: '',
          version: version,
          estVersionCourante: courant,
          parentId: parent,
          zone: zone == null ? null : PlanNiveauRef(id: zone, nom: zone),
        );

    test('une seule version par plan : la courante', () {
      final courants = plansCourants([
        plan('v1', version: 1, courant: false, zone: 'z1'),
        plan('v2', version: 2, zone: 'z1'),
      ]);
      expect(courants.map((p) => p.id), ['v2']);
    });

    test('sans version désignée, la plus récente', () {
      final courants = plansCourants([
        plan('v1', version: 1, courant: false, zone: 'z1'),
        plan('v3', version: 3, courant: false, zone: 'z1'),
      ]);
      expect(courants.map((p) => p.id), ['v3']);
    });

    test('deux appartements peuvent avoir chacun un « plan.pdf »', () {
      // Le dépôt nomme le plan d'après son fichier : regrouper sur le nom
      // seul ferait disparaître l'un des deux.
      final courants = plansCourants([plan('a', zone: 'z1'), plan('b', zone: 'z2')]);
      expect(courants.map((p) => p.id), unorderedEquals(['a', 'b']));
    });

    test('les plans de détail restent sous leur parent', () {
      final courants = plansCourants([plan('a', zone: 'z1'), plan('d', nom: 'cuisine', zone: 'z1', parent: 'a')]);
      expect(courants.map((p) => p.id), ['a']);
    });

    test('le compteur « à traiter » est lu du serveur, et reste NUL s’il est absent', () {
      Plan lu(Map<String, dynamic> extra) =>
          Plan.fromJson({'id': 'p', 'nom': 'A001', 'nombre_reserves': 5, ...extra});

      expect(lu({'nombre_reserves_a_traiter': 2}).nombreReservesATraiter, 2);
      expect(lu({'nombre_reserves_a_traiter': 0}).nombreReservesATraiter, 0);
      // Un serveur pas encore à jour : on ne prétend pas que tout est levé.
      expect(lu(const {}).nombreReservesATraiter, isNull);
      expect(lu(const {}).nombreReserves, 5);
    });

    test('la portée se lit du rattachement le plus précis', () {
      expect(porteeDu(plan('g')), PorteePlan.global);
      expect(porteeDu(plan('a', zone: 'z1')), PorteePlan.appartement);
      expect(porteeDu(plan('d', zone: 'z1', parent: 'a')), PorteePlan.detail);
    });
  });
}

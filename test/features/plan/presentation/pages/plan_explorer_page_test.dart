import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/entities/plan.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_plan_detail.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_plans_racines.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_sous_plans.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/pages/plan_explorer_page.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/widgets/plan_interactif.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/balayage_responsive.dart';
import '../../../../helpers/pompe_page.dart';

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

  void desinscrire() {
    if (sl.isRegistered<GetPlansRacines>()) sl.unregister<GetPlansRacines>();
    if (sl.isRegistered<GetSousPlans>()) sl.unregister<GetSousPlans>();
    if (sl.isRegistered<GetPlanDetail>()) sl.unregister<GetPlanDetail>();
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

      expect(find.text('A1.1'), findsOneWidget);
      expect(find.text('A1.2'), findsOneWidget);
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
}

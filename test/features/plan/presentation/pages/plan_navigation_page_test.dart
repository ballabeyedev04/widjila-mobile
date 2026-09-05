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
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/chantier_structure.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_chantier_structure.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/balayage_responsive.dart';
import '../../../../helpers/pompe_page.dart';

class _MockStructure extends Mock implements GetChantierStructure {}

class _MockPlansChantier extends Mock implements GetPlansChantier {}

class _MockPlanDetail extends Mock implements GetPlanDetail {}

class _MockOuverture extends Mock implements OuvertureFichier {}

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
}

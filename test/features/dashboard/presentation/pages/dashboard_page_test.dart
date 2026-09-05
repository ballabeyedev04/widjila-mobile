import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/widgets/error_view.dart';
import 'package:suivie_chantier_mobile/core/widgets/liste_chrome.dart';
import 'package:suivie_chantier_mobile/core/widgets/loading_list.dart';
import 'package:suivie_chantier_mobile/features/dashboard/domain/entities/dashboard_stats.dart';
import 'package:suivie_chantier_mobile/features/dashboard/domain/usecases/get_dashboard_stats.dart';
import 'package:suivie_chantier_mobile/features/dashboard/presentation/cubit/dashboard_cubit.dart';
import 'package:suivie_chantier_mobile/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/entities/plan.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_plans_chantier.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_tous_plans.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/uploader_plan.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/cubit/plans_list_cubit.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/entities/chantier.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/repositories/reserve_repository.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_reserve_statuts_count.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_toutes_reserves.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/balayage_responsive.dart';
import '../../../../helpers/pompe_page.dart';

class _MockStats extends Mock implements GetDashboardStats {}

class _MockToutesReserves extends Mock implements GetToutesReserves {}

class _MockCountGlobal extends Mock implements GetReserveStatutsCountGlobal {}

class _MockTousPlans extends Mock implements GetTousPlans {}

class _MockPlansChantier extends Mock implements GetPlansChantier {}

class _MockUploader extends Mock implements UploaderPlan {}

/// L'écran d'accueil.
///
/// ## Le défaut que ce fichier a fait apparaître
///
/// Sans chantier, il n'y a ni réserve, ni plan, ni document : tout ce que cet
/// écran sait montrer vaut zéro. La mise en page normale affichait alors une
/// dizaine de compteurs à « 0 », une phrase d'accroche qui annonce l'état
/// d'avancement des réserves — alors qu'il n'y en a aucune — et RIEN qui
/// indique quoi faire ensuite.
///
/// C'est l'écran d'accueil : la première chose que voit quelqu'un qui vient
/// de s'inscrire, et une entreprise à qui aucun chantier n'a encore été
/// rattaché. Une grille de zéros ne lui apprend pas s'il doit créer un
/// chantier, attendre une affectation, ou si l'application est en panne.
void main() {
  late _MockStats getStats;

  void desinscrire() {
    if (sl.isRegistered<DashboardCubit>()) sl.unregister<DashboardCubit>();
    if (sl.isRegistered<GetToutesReserves>()) sl.unregister<GetToutesReserves>();
    if (sl.isRegistered<GetReserveStatutsCountGlobal>()) {
      sl.unregister<GetReserveStatutsCountGlobal>();
    }
    if (sl.isRegistered<PlansListCubit>()) sl.unregister<PlansListCubit>();
  }

  setUp(() {
    getStats = _MockStats();

    final toutesReserves = _MockToutesReserves();
    when(() => toutesReserves(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          search: any(named: 'search'),
          statut: any(named: 'statut'),
        )).thenAnswer(
      (_) async => const Right<Failure, ReservePage>(ReservePage(items: [], total: 0)),
    );

    final countGlobal = _MockCountGlobal();
    when(countGlobal.call).thenAnswer(
      (_) async => Right<Failure, ReserveStatutsCount>(ReserveStatutsCount.vide()),
    );

    final tousPlans = _MockTousPlans();
    when(tousPlans.call).thenAnswer((_) async => const Right<Failure, List<Plan>>([]));

    desinscrire();
    sl.registerFactory<DashboardCubit>(() => DashboardCubit(getDashboardStats: getStats));
    sl.registerLazySingleton<GetToutesReserves>(() => toutesReserves);
    sl.registerLazySingleton<GetReserveStatutsCountGlobal>(() => countGlobal);
    sl.registerFactory<PlansListCubit>(() => PlansListCubit(
          getTousPlans: tousPlans,
          getPlansChantier: _MockPlansChantier(),
          uploaderPlan: _MockUploader(),
        ));
  });

  tearDown(desinscrire);

  /// Fragment de la phrase d'accroche, sans son apostrophe typographique —
  /// la comparer entière rendrait le test sensible à une retouche de style.
  const accroche = 'avancement de vos';

  testWidgets('un squelette pendant le chargement', (tester) async {
    final attente = Completer<Either<Failure, DashboardStats>>();
    when(getStats.call).thenAnswer((_) => attente.future);

    await pomperPage(tester, const DashboardPage());

    expect(find.byType(LoadingList), findsOneWidget);
    expect(tester.takeException(), isNull);

    attente.complete(const Right(DashboardStats()));
    await tester.pumpAndSettle();
  });

  testWidgets('compte neuf : un message qui guide, pas une grille de zeros',
      (tester) async {
    when(getStats.call)
        .thenAnswer((_) async => const Right<Failure, DashboardStats>(DashboardStats()));

    await pomperPage(tester, const DashboardPage(), role: UserRole.entreprise);
    await tester.pumpAndSettle();

    expect(find.text('Aucun chantier pour le moment'), findsOneWidget);
    expect(find.textContaining('premier chantier'), findsOneWidget);
    expect(find.text('Voir mes chantiers'), findsOneWidget);

    // La phrase qui annonce un avancement disparaît : elle ne décrivait rien.
    expect(find.textContaining(accroche), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compte neuf en LECTURE : le message dit d attendre, sans bouton mort',
      (tester) async {
    // Un client ne dépose pas de demande de chantier. Lui proposer le bouton
    // reviendrait à lui promettre un 403.
    when(getStats.call)
        .thenAnswer((_) async => const Right<Failure, DashboardStats>(DashboardStats()));

    await pomperPage(tester, const DashboardPage(), role: UserRole.client);
    await tester.pumpAndSettle();

    expect(find.text('Aucun chantier pour le moment'), findsOneWidget);
    expect(find.textContaining('encore rattach'), findsOneWidget);
    expect(find.byType(BoutonAction), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un chantier, meme sans reserve : les compteurs reprennent la main',
      (tester) async {
    // Le seuil est bien « aucun chantier », pas « tous les compteurs à
    // zéro » : un chantier vide a de quoi lire ses zéros, ils décrivent son
    // état réel.
    when(getStats.call).thenAnswer(
      (_) async => const Right<Failure, DashboardStats>(DashboardStats(chantiers: 1)),
    );

    await pomperPage(tester, const DashboardPage(), role: UserRole.entreprise);
    await tester.pumpAndSettle();

    expect(find.text('Aucun chantier pour le moment'), findsNothing);
    expect(find.textContaining(accroche), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panne serveur : une erreur, pas un accueil vide', (tester) async {
    when(getStats.call).thenAnswer(
      (_) async => const Left<Failure, DashboardStats>(ServerFailure(errorMessage: 'Indisponible')),
    );

    await pomperPage(tester, const DashboardPage());
    await tester.pumpAndSettle();

    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text('Aucun chantier pour le moment'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('mise en page — balayage des formats', () {
    // L'accueil est l'ecran le plus dense de l'application : rangee de
    // compteurs, carte de repartition, donut, grille d'apercu, liste de
    // chantiers. C'est donc celui ou une largeur inattendue casse le plus
    // vite — et celui que tout le monde ouvre en premier.
    final statsRemplies = DashboardStats(
      chantiers: 4,
      plans: 12,
      inspections: 3,
      documents: 27,
      utilisateurs: 5,
      reserves: const ReservesStats(total: 40, ouvertes: 18, validees: 20),
      parStatut: const {ReserveStatut.enCours: 10, ReserveStatut.validee: 22},
      parSeverite: const {
        ReserveSeverite.critique: 4,
        ReserveSeverite.moyenne: 30,
      },
      parChantier: const [
        DashboardChantierResume(
          id: 'c1',
          nom: 'Residence Les Cedres — tranche 2',
          code: 'RLC-2026',
          statut: ChantierStatut.enCours,
        ),
      ],
    );

    for (final format in tousLesFormats) {
      testWidgets('sans debordement sur $format', (tester) async {
        when(getStats.call).thenAnswer(
          (_) async => Right<Failure, DashboardStats>(statsRemplies),
        );

        await pomperPage(
          tester,
          const DashboardPage(),
          role: UserRole.entreprise,
          taille: format.taille,
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'debordement de mise en page sur $format');
      });
    }
  });

  group('mise en page — densite des grilles', () {
    // Le balayage prouve qu'aucun ecran ne DEBORDE. Il ne prouve pas que la
    // largeur est UTILISEE : une grille figee a deux colonnes ne deborde
    // jamais sur une tablette, elle y gaspille simplement la moitie de la
    // place. C'est ce que ce groupe mesure.
    Future<int> colonnesDeLApercu(WidgetTester tester, Size taille) async {
      when(getStats.call).thenAnswer(
        (_) async => const Right<Failure, DashboardStats>(
          DashboardStats(chantiers: 4, plans: 12, inspections: 3, documents: 27, utilisateurs: 5),
        ),
      );

      await pomperPage(
        tester,
        const DashboardPage(),
        role: UserRole.entreprise,
        taille: taille,
      );
      await tester.pumpAndSettle();

      // L'accueil est une `ListView` : la grille d'apercu se trouve sous la
      // ligne de flottaison et n'est pas construite tant qu'on n'a pas
      // defile jusqu'a elle.
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -700));
      await tester.pumpAndSettle();

      // La grille d'apercu est la seule `GridView` de l'ecran d'accueil
      // lorsque aucun chantier n'est resume.
      final grille = tester.widget<GridView>(find.byType(GridView).first);
      final delegue = grille.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      return delegue.crossAxisCount;
    }

    testWidgets('un telephone garde ses deux colonnes', (tester) async {
      expect(await colonnesDeLApercu(tester, const Size(390, 844)), 2);
    });

    testWidgets('le plus petit telephone n en perd pas une', (tester) async {
      // Le plancher : une seule colonne rendrait la grille interminable.
      //
      // La hauteur est volontairement genereuse : ce qui se mesure ici est la
      // LARGEUR, et un ecran court obligerait a defiler plusieurs fois avant
      // d'atteindre la grille — ce que le balayage couvre deja par ailleurs,
      // a la vraie hauteur de 568.
      expect(await colonnesDeLApercu(tester, const Size(320, 900)), 2);
    });

    testWidgets('une tablette COMPACTE en gagne une', (tester) async {
      // 600 dp : sous le seuil de bascule, donc mise en page « telephone ».
      // C'est le cas que le gabarit binaire servait le plus mal — deux
      // colonnes etirees sur 600 dp.
      expect(
        await colonnesDeLApercu(tester, const Size(600, 960)),
        greaterThan(2),
      );
    });

    testWidgets('une grande tablette en profite davantage', (tester) async {
      final compacte = await colonnesDeLApercu(tester, const Size(600, 960));
      final grande = await colonnesDeLApercu(tester, const Size(1024, 1366));

      expect(grande, greaterThanOrEqualTo(compacte));
      expect(grande, greaterThanOrEqualTo(4));
    });
  });

  group('mise en page — texte agrandi', () {
    // Sur un chantier, une bonne part des utilisateurs grossit le texte du
    // systeme. Une hauteur de carte figee en pixels rouvre alors exactement
    // le debordement qu'on vient de fermer : le contenu grandit, le
    // contenant non.
    Future<void> pomperAvecEchelle(WidgetTester tester, double echelle) async {
      when(getStats.call).thenAnswer(
        (_) async => const Right<Failure, DashboardStats>(
          DashboardStats(chantiers: 4, plans: 12, inspections: 3, documents: 27, utilisateurs: 5),
        ),
      );

      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pomperPage(
        tester,
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(echelle)),
          child: const DashboardPage(),
        ),
        role: UserRole.entreprise,
        reglerSurface: false,
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Scrollable).last, const Offset(0, -700));
      await tester.pumpAndSettle();
    }

    for (final echelle in [1.0, 1.3, 1.6]) {
      testWidgets('les cartes tiennent a une echelle de $echelle', (tester) async {
        await pomperAvecEchelle(tester, echelle);

        expect(tester.takeException(), isNull,
            reason: 'debordement a une echelle de texte de $echelle');
      });
    }
  });
}

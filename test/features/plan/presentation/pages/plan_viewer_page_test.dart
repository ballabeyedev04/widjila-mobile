import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/widgets/error_view.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/entities/plan.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_plan_detail.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/cubit/plan_detail_cubit.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/pages/plan_viewer_page.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/pompe_page.dart';

class _MockDetail extends Mock implements GetPlanDetail {}

/// La visionneuse de plan.
///
/// ## Ce que ce fichier protège
///
/// En cas d'échec, cet écran ne doit pas se replier sur un `Scaffold` nu :
/// la flèche de retour est la SEULE sortie d'une visionneuse plein écran.
/// Perdre le bandeau, c'est enfermer l'utilisateur sur un message d'erreur.
///
/// Le second point est la robustesse du plan lui-même : `nombrePages`,
/// `fichierNom`, `batiment`, `etage`, `zone`, les hotspots et les réserves
/// sont tous facultatifs. Un plan déposé sans métadonnée doit s'ouvrir.
void main() {
  late _MockDetail getDetail;

  void desinscrire() {
    if (sl.isRegistered<PlanDetailCubit>()) sl.unregister<PlanDetailCubit>();
  }

  setUp(() {
    getDetail = _MockDetail();
    desinscrire();
    sl.registerFactory<PlanDetailCubit>(() => PlanDetailCubit(getPlanDetail: getDetail));
  });

  tearDown(desinscrire);

  const page = PlanViewerPage(planId: 'p1');

  const planMinimal = Plan(
    id: 'p1',
    chantierId: 'c1',
    nom: 'Niveau R+2',
    fichierUrl: 'https://exemple.test/p1.pdf',
  );

  testWidgets('un indicateur pendant le chargement', (tester) async {
    final attente = Completer<Either<Failure, Plan>>();
    when(() => getDetail(any())).thenAnswer((_) => attente.future);

    await pomperPage(tester, page);

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(tester.takeException(), isNull);

    attente.complete(const Right(planMinimal));
    // `pumpAndSettle` est PROSCRIT sur cet ecran : la visionneuse affiche un
    // indicateur circulaire pendant le telechargement du PDF, et un
    // indicateur circulaire programme une image a l'infini. Attendre le
    // repos, ici, c'est attendre pour toujours.
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('echec : le message s affiche SANS perdre la fleche de retour',
      (tester) async {
    when(() => getDetail(any())).thenAnswer(
      (_) async => const Left<Failure, Plan>(ServerFailure(errorMessage: 'Plan introuvable')),
    );

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.byType(ErrorView), findsOneWidget);
    // La seule sortie d'un écran plein écran.
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan SANS aucune metadonnee : la visionneuse s ouvre', (tester) async {
    when(() => getDetail(any()))
        .thenAnswer((_) async => const Right<Failure, Plan>(planMinimal));

    await pomperPage(tester, page);
    // Voir plus haut : pas de `pumpAndSettle` sur cet ecran.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Le plan est arrive : plus de vue d'erreur de CHARGEMENT DU PLAN. Le
    // telechargement du PDF lui-meme n'aboutit pas en test (aucun reseau) et
    // c'est sans importance : ce qui se verifie ici, c'est que la fiche d'un
    // plan depourvu de toute metadonnee se monte sans lever.
    expect(find.byType(ErrorView), findsNothing);
    expect(find.text('Niveau R+2'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

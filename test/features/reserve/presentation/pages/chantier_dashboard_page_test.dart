import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/widgets/error_view.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve_evolution.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/repositories/reserve_repository.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_reserve_evolution.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_reserve_statuts_count.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/cubit/chantier_dashboard_cubit.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/pages/chantier_dashboard_page.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/pompe_page.dart';

class _MockCount extends Mock implements GetReserveStatutsCount {}

class _MockEvolution extends Mock implements GetReserveEvolution {}

/// Le tableau de bord d'UN chantier.
///
/// ## Ce qu'il faut distinguer ici
///
/// Cet écran superpose deux jeux de données : la répartition par statut et la
/// courbe d'évolution. Un chantier tout neuf a bien une répartition — des
/// zéros honnêtes — mais pas encore de courbe : deux points de mesure sont
/// nécessaires pour tracer quoi que ce soit.
///
/// Un graphique vide, sans un mot, se lit comme un bug d'affichage. La
/// mention « pas assez de données » dit que la mesure viendra, et c'est cette
/// mention que ce fichier surveille.
void main() {
  late _MockCount count;
  late _MockEvolution evolution;

  void desinscrire() {
    if (sl.isRegistered<ChantierDashboardCubit>()) sl.unregister<ChantierDashboardCubit>();
  }

  setUp(() {
    count = _MockCount();
    evolution = _MockEvolution();

    desinscrire();
    sl.registerFactoryParam<ChantierDashboardCubit, String, void>(
      (chantierId, _) => ChantierDashboardCubit(
        getReserveStatutsCount: count,
        getReserveEvolution: evolution,
        chantierId: chantierId,
      ),
    );
  });

  tearDown(desinscrire);

  const page = ChantierDashboardPage(chantierId: 'c1');

  testWidgets('un indicateur pendant le chargement', (tester) async {
    final attente = Completer<Either<Failure, ReserveStatutsCount>>();
    when(() => count(any())).thenAnswer((_) => attente.future);
    when(() => evolution(any()))
        .thenAnswer((_) async => const Right<Failure, ReserveEvolution>(ReserveEvolution()));

    await pomperPage(tester, page);

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(tester.takeException(), isNull);

    attente.complete(Right(ReserveStatutsCount.vide()));
    await tester.pumpAndSettle();
  });

  testWidgets('chantier neuf : la courbe vide s explique au lieu de rester blanche',
      (tester) async {
    when(() => count(any()))
        .thenAnswer((_) async => Right<Failure, ReserveStatutsCount>(ReserveStatutsCount.vide()));
    when(() => evolution(any()))
        .thenAnswer((_) async => const Right<Failure, ReserveEvolution>(ReserveEvolution()));

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.textContaining('donn'), findsWidgets);
    expect(find.byType(ErrorView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panne serveur : une erreur, pas un tableau de zeros', (tester) async {
    when(() => count(any())).thenAnswer(
      (_) async =>
          const Left<Failure, ReserveStatutsCount>(ServerFailure(errorMessage: 'Indisponible')),
    );
    when(() => evolution(any()))
        .thenAnswer((_) async => const Right<Failure, ReserveEvolution>(ReserveEvolution()));

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.byType(ErrorView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('des donnees : l ecran se monte sans incident', (tester) async {
    when(() => count(any())).thenAnswer(
      (_) async => const Right<Failure, ReserveStatutsCount>(
        ReserveStatutsCount(parStatut: {}, total: 12),
      ),
    );
    when(() => evolution(any())).thenAnswer(
      (_) async => const Right<Failure, ReserveEvolution>(
        ReserveEvolution(series: [
          EvolutionPoint(mois: '2026-01', creees: 4, validees: 1),
          EvolutionPoint(mois: '2026-02', creees: 8, validees: 5),
        ]),
      ),
    );

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.byType(ErrorView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

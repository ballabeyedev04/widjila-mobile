import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/repositories/reserve_repository.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_reserve_statuts_count.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_toutes_reserves.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/cubit/reserves_list_state.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/cubit/toutes_reserves_cubit.dart';

class _MockListe extends Mock implements GetToutesReserves {}

class _MockCompteurs extends Mock implements GetReserveStatutsCountGlobal {}

/// L'onglet « Réserves » doit TOUJOURS finir par dire quelque chose.
///
/// ── Ce qui s'est passé ────────────────────────────────────────────────────
/// `charger()` enchaînait `await liste` puis `await compteurs` avant le
/// moindre `emit`. Les compteurs ne décorent que les puces de filtre, mais ils
/// retenaient la liste : tant que `GET /dashboard` ne répondait pas, l'état
/// restait « chargement » et l'écran gardait ses six rectangles gris. Une
/// organisation sans aucune réserve ne voyait donc jamais « Aucune réserve » —
/// seulement un squelette qui scintille, sans rien à comprendre ni à faire.
void main() {
  late _MockListe liste;
  late _MockCompteurs compteurs;

  ReservePage pageVide() => const ReservePage(items: [], total: 0);

  setUp(() {
    liste = _MockListe();
    compteurs = _MockCompteurs();
  });

  ToutesReservesCubit construire() =>
      ToutesReservesCubit(getToutesReserves: liste, getStatutsCountGlobal: compteurs);

  void repondLaListe(ReservePage page) {
    when(() => liste(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          search: any(named: 'search'),
          statut: any(named: 'statut'),
        )).thenAnswer((_) async => Right(page));
  }

  test('la liste VIDE s’affiche même si les compteurs ne répondent jamais', () async {
    repondLaListe(pageVide());
    // Une requête qui ne se termine pas : c'est le cas qui bloquait l'écran.
    when(() => compteurs()).thenAnswer((_) => Completer<Either<Failure, ReserveStatutsCount>>().future);

    final cubit = construire();
    await cubit.charger();

    expect(cubit.state.status, ReservesListStatus.succes,
        reason: 'sans cela, la page reste sur son squelette de chargement');
    expect(cubit.state.items, isEmpty);
    await cubit.close();
  });

  test('un ÉCHEC des compteurs n’empêche pas la liste de s’afficher', () async {
    repondLaListe(pageVide());
    when(() => compteurs()).thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'dashboard indisponible')));

    final cubit = construire();
    await cubit.charger();

    expect(cubit.state.status, ReservesListStatus.succes);
    expect(cubit.state.erreur, isNull, reason: 'les puces ne sont pas la liste');
    await cubit.close();
  });

  test('les compteurs rejoignent l’état quand ils arrivent, après la liste', () async {
    repondLaListe(pageVide());
    final tardif = Completer<Either<Failure, ReserveStatutsCount>>();
    when(() => compteurs()).thenAnswer((_) => tardif.future);

    final cubit = construire();
    await cubit.charger();
    expect(cubit.state.statutsCount.total, 0);

    tardif.complete(const Right(ReserveStatutsCount(parStatut: {}, total: 7)));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.statutsCount.total, 7);
    await cubit.close();
  });

  test('une exception ÉCHAPPÉE devient une erreur affichable, pas un écran figé', () async {
    when(() => liste(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          search: any(named: 'search'),
          statut: any(named: 'statut'),
        )).thenThrow(StateError('dépôt cassé'));
    when(() => compteurs()).thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'x')));

    final cubit = construire();
    await cubit.charger();

    expect(cubit.state.status, ReservesListStatus.erreur,
        reason: 'un message et un bouton « Réessayer » valent mieux qu’un squelette éternel');
    await cubit.close();
  });
}

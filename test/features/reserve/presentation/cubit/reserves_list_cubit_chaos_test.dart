import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/repositories/reserve_repository.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_reserve_statuts_count.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_reserves.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/cubit/reserves_list_cubit.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/cubit/reserves_list_state.dart';

class MockGetReserves extends Mock implements GetReserves {}

class MockGetReserveStatutsCount extends Mock implements GetReserveStatutsCount {}

Reserve _reserve(String id) =>
    Reserve(id: id, numero: 'R-$id', chantierId: 'chantier-1', titre: 'Réserve $id');

const _chantierId = 'chantier-1';

/// Tests de résistance au CHAOS — réponses réseau arrivant dans le désordre,
/// et écran quitté pendant un chargement.
///
/// Ces scénarios ne se produisent jamais dans un test nominal (où les stubs
/// répondent instantanément et dans l'ordre) mais sont la norme sur un réseau
/// de chantier. Ils ont chacun correspondu à un bug réel.
void main() {
  late MockGetReserves getReserves;
  late MockGetReserveStatutsCount getReserveStatutsCount;

  setUp(() {
    getReserves = MockGetReserves();
    getReserveStatutsCount = MockGetReserveStatutsCount();
    when(() => getReserveStatutsCount(_chantierId))
        .thenAnswer((_) async => const Right(ReserveStatutsCount(parStatut: {}, total: 0)));
  });

  ReservesListCubit build() => ReservesListCubit(
        getReserves: getReserves,
        getReserveStatutsCount: getReserveStatutsCount,
        chantierId: _chantierId,
      );

  // Non-régression [C5] — le debounce annule le TIMER, pas la requête déjà
  // partie. Deux frappes rapprochées sur réseau lent produisaient : « fis »
  // part (lent) → « fissure » part (rapide) → « fissure » s'affiche → puis la
  // réponse de « fis » arrive et ÉCRASE la liste, alors que le champ de
  // recherche affiche toujours « fissure ».
  test('une réponse PÉRIMÉE n\'écrase pas une plus récente', () async {
    final lente = Completer<Either<Failure, ReservePage>>();
    final rapide = Completer<Either<Failure, ReservePage>>();

    when(() => getReserves(
          chantierId: _chantierId, page: 1, limit: 20, search: 'fis', statut: null,
        )).thenAnswer((_) => lente.future);
    when(() => getReserves(
          chantierId: _chantierId, page: 1, limit: 20, search: 'fissure', statut: null,
        )).thenAnswer((_) => rapide.future);

    final cubit = build();

    // La recherche « fis » part en premier (elle sera lente).
    cubit.emit(const ReservesListState(recherche: 'fis'));
    final premiere = cubit.charger();

    // Puis « fissure » — plus récente, réponse plus rapide.
    cubit.emit(cubit.state.copyWith(recherche: 'fissure'));
    final seconde = cubit.charger();

    rapide.complete(Right(ReservePage(items: [_reserve('fissure')], total: 1)));
    await seconde;

    // La réponse périmée arrive APRÈS : elle doit être ignorée.
    lente.complete(Right(ReservePage(items: [_reserve('fis')], total: 1)));
    await premiere;

    expect(
      cubit.state.items.single.id,
      'fissure',
      reason: 'la réponse de la recherche précédente ne doit jamais gagner',
    );

    await cubit.close();
  });

  // Non-régression [C6] — un rafraîchissement lancé pendant qu'une page 2 est
  // en vol invalide cette dernière. Sans ça, la page 2 arrivait après le
  // rafraîchissement et s'AJOUTAIT à la liste fraîchement remplacée
  // (`[...state.items, ...page.items]`) : doublons à l'écran, compteurs faux.
  test('une pagination en vol n\'est pas ajoutée à une liste rafraîchie', () async {
    final page2 = Completer<Either<Failure, ReservePage>>();

    when(() => getReserves(
          chantierId: _chantierId, page: 2, limit: 20, search: '', statut: null,
        )).thenAnswer((_) => page2.future);
    when(() => getReserves(
          chantierId: _chantierId, page: 1, limit: 20, search: '', statut: null,
        )).thenAnswer((_) async => Right(ReservePage(items: [_reserve('frais')], total: 1)));

    final cubit = build();
    cubit.emit(ReservesListState(
      status: ReservesListStatus.succes,
      items: [_reserve('a'), _reserve('b')],
      total: 10,
    ));

    final pagination = cubit.chargerPageSuivante();
    // L'utilisateur, impatient, tire pour rafraîchir pendant le chargement.
    await cubit.charger();

    page2.complete(Right(ReservePage(items: [_reserve('c')], total: 10)));
    await pagination;

    expect(
      cubit.state.items.map((r) => r.id).toList(),
      ['frais'],
      reason: 'la page 2 de l\'ancienne liste ne doit pas se greffer sur la nouvelle',
    );

    await cubit.close();
  });

  // Non-régression [C7] — l'utilisateur quitte l'écran pendant le chargement.
  // Émettre sur un cubit fermé lève une `StateError` non gérée, remontée comme
  // crash FATAL par `runZonedGuarded` (voir main.dart) : de quoi noyer les
  // vrais crashs dans Crashlytics.
  test('aucune exception si l\'écran est quitté pendant le chargement', () async {
    final enVol = Completer<Either<Failure, ReservePage>>();
    when(() => getReserves(
          chantierId: _chantierId, page: 1, limit: 20, search: '', statut: null,
        )).thenAnswer((_) => enVol.future);

    final cubit = build();
    final chargement = cubit.charger();

    await cubit.close(); // retour arrière

    enVol.complete(Right(ReservePage(items: [_reserve('a')], total: 1)));

    await expectLater(chargement, completes);
  });
}

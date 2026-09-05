import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/widgets/error_view.dart';
import 'package:suivie_chantier_mobile/core/widgets/loading_list.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/repositories/reserve_repository.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_reserve_statuts_count.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_reserves.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/cubit/reserves_list_cubit.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/pages/reserves_list_page.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/balayage_responsive.dart';
import '../../../../helpers/pompe_page.dart';

class _MockGetReserves extends Mock implements GetReserves {}

class _MockCount extends Mock implements GetReserveStatutsCount {}

/// L'écran Réserves d'un chantier.
///
/// ## Le défaut que ce fichier surveille
///
/// L'état vide de cet écran n'est pas le même pour tout le monde. Le serveur
/// réserve la création aux rôles dits « intervenants » ; proposer le bouton
/// aux autres reviendrait à promettre une action qui revient en 403, et le
/// leur refuser à tort laisserait une entreprise devant un écran vide sans
/// issue — exactement le défaut déjà rencontré sur l'écran Plans.
///
/// Un test de cubit ne verrait rien de tout cela : la décision est dans la
/// condition d'affichage, pas dans les données.
void main() {
  late _MockGetReserves getReserves;
  late _MockCount count;

  Reserve reserve(String id) => Reserve(
        id: id,
        numero: 'R-$id',
        chantierId: 'c1',
        titre: 'Fissure mur porteur $id',
      );

  setUp(() {
    getReserves = _MockGetReserves();
    count = _MockCount();
    when(() => count(any())).thenAnswer(
      (_) async => Right<Failure, ReserveStatutsCount>(ReserveStatutsCount.vide()),
    );

    if (sl.isRegistered<ReservesListCubit>()) sl.unregister<ReservesListCubit>();
    sl.registerFactoryParam<ReservesListCubit, String, void>(
      (chantierId, _) => ReservesListCubit(
        getReserves: getReserves,
        getReserveStatutsCount: count,
        chantierId: chantierId,
      ),
    );
  });

  tearDown(() {
    if (sl.isRegistered<ReservesListCubit>()) sl.unregister<ReservesListCubit>();
  });

  void repondre(List<Reserve> items) {
    when(() => getReserves(
          chantierId: any(named: 'chantierId'),
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          search: any(named: 'search'),
          statut: any(named: 'statut'),
        )).thenAnswer(
      (_) async => Right<Failure, ReservePage>(ReservePage(items: items, total: items.length)),
    );
  }

  const page = ReservesListPage(chantierId: 'c1');

  testWidgets('un squelette pendant le chargement', (tester) async {
    final attente = Completer<Either<Failure, ReservePage>>();
    when(() => getReserves(
          chantierId: any(named: 'chantierId'),
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          search: any(named: 'search'),
          statut: any(named: 'statut'),
        )).thenAnswer((_) => attente.future);

    await pomperPage(tester, page);

    expect(find.byType(LoadingList), findsOneWidget);
    expect(tester.takeException(), isNull);

    attente.complete(const Right(ReservePage(items: [], total: 0)));
    await tester.pumpAndSettle();
  });

  testWidgets('vide + rôle qui PEUT créer : le message propose une issue',
      (tester) async {
    repondre(const []);

    await pomperPage(tester, page, role: UserRole.entreprise);
    await tester.pumpAndSettle();

    expect(find.text('Aucune réserve'), findsOneWidget);
    expect(find.textContaining('Créez la première'), findsOneWidget);
    // L'issue, deux fois : le bouton de l'état vide et le bouton flottant.
    expect(find.text('Créer une réserve'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vide + rôle en LECTURE : un message honnête, sans bouton mort',
      (tester) async {
    // Le client ne crée pas de réserve. Lui montrer le bouton serait lui
    // promettre un 403.
    repondre(const []);

    await pomperPage(tester, page, role: UserRole.client);
    await tester.pumpAndSettle();

    expect(find.text('Aucune réserve'), findsOneWidget);
    expect(find.textContaining('appara'), findsOneWidget);
    expect(find.text('Créer une réserve'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panne serveur : une erreur, pas « aucune réserve »', (tester) async {
    when(() => getReserves(
          chantierId: any(named: 'chantierId'),
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          search: any(named: 'search'),
          statut: any(named: 'statut'),
        )).thenAnswer((_) async =>
        const Left<Failure, ReservePage>(ServerFailure(errorMessage: 'Indisponible')));

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text('Aucune réserve'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('affiche les réserves reçues', (tester) async {
    repondre([reserve('a'), reserve('b')]);

    await pomperPage(tester, page, role: UserRole.entreprise);
    await tester.pumpAndSettle();

    expect(find.text('Aucune réserve'), findsNothing);
    expect(find.textContaining('Fissure mur porteur a'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('mise en page — balayage des formats', () {
    // Un ecran dessine sur un telephone de 390 dp passe presque toujours a
    // 390 dp. Les debordements se produisent aux EXTREMES : sur un petit
    // Android de 320 dp encore courant sur les chantiers, et sur une tablette
    // ou une rangee concue serree se distend.
    //
    // `flutter_test` remonte un `RenderFlex overflowed` comme une exception :
    // pomper l'ecran a chaque format et verifier qu'aucune n'a ete levee
    // transforme l'audit visuel en mesure repetable.
    for (final format in tousLesFormats) {
      testWidgets('sans debordement sur $format', (tester) async {
        repondre([reserve('a'), reserve('b'), reserve('c')]);

        await pomperPage(
          tester,
          page,
          role: UserRole.entreprise,
          taille: format.taille,
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'debordement de mise en page sur $format');
      });
    }
  });
}

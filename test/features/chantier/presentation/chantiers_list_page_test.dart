import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/entities/chantier.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/repositories/chantier_repository.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/usecases/get_chantiers.dart';
import 'package:suivie_chantier_mobile/features/chantier/presentation/cubit/chantiers_list_cubit.dart';
import 'package:suivie_chantier_mobile/features/chantier/presentation/pages/chantiers_list_page.dart';
import 'package:suivie_chantier_mobile/features/dashboard/domain/usecases/get_dashboard_stats.dart';
import 'package:suivie_chantier_mobile/features/notification/presentation/cubit/notifications_cubit.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../helpers/l10n_test_helpers.dart';

class _MockGetChantiers extends Mock implements GetChantiers {}

class _MockGetStats extends Mock implements GetDashboardStats {}

class _MockNotifications extends MockCubit<NotificationsState>
    implements NotificationsCubit {}

const _chantier = Chantier(
  id: 'c1',
  code: 'CH-001',
  nom: 'Résidence Les Acacias',
  statut: ChantierStatut.enCours,
);

/// L'écran « Chantiers ».
///
/// ## Pourquoi ce test existe
///
/// Signalement terrain : le tableau de bord annonce « 1 chantier » et la page
/// Chantiers reste vide. Les deux comptes viennent pourtant de la MÊME règle
/// serveur — l'un comme l'autre écartent les demandes en attente de
/// validation — donc un écart entre eux ne peut pas venir du filtrage.
///
/// Ce test verrouille ce dont le mobile répond : quand l'API rend un chantier,
/// il s'affiche ; quand elle n'en rend aucun, un état vide EXPLICITE apparaît
/// — jamais un écran blanc, qui ne dit rien à personne.
void main() {
  late _MockGetChantiers getChantiers;
  late _MockGetStats getStats;
  late _MockNotifications notifications;

  setUp(() {
    getChantiers = _MockGetChantiers();
    getStats = _MockGetStats();
    notifications = _MockNotifications();
    whenListen(notifications, const Stream<NotificationsState>.empty(),
        initialState: const NotificationsState());

    if (sl.isRegistered<ChantiersListCubit>()) sl.unregister<ChantiersListCubit>();
    sl.registerFactory<ChantiersListCubit>(
      () => ChantiersListCubit(getChantiers: getChantiers, getDashboardStats: getStats),
    );
  });

  tearDown(() {
    if (sl.isRegistered<ChantiersListCubit>()) sl.unregister<ChantiersListCubit>();
  });

  Future<List<FlutterErrorDetails>> pomper(WidgetTester tester, {double largeur = 390}) async {
    tester.view.physicalSize = Size(largeur, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final erreurs = <FlutterErrorDetails>[];
    final precedent = FlutterError.onError;
    FlutterError.onError = erreurs.add;

    await tester.pumpWidget(MaterialApp(
      locale: testLocale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: BlocProvider<NotificationsCubit>.value(
        value: notifications,
        child: const ChantiersListPage(),
      ),
    ));
    await tester.pumpAndSettle();

    FlutterError.onError = precedent;
    return erreurs;
  }

  void stubListeAvecUnChantier() {
    when(() => getChantiers(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          search: any(named: 'search'),
          statut: any(named: 'statut'),
        )).thenAnswer(
      (_) async => const Right(ChantierPage(items: [_chantier], total: 1)),
    );
    when(() => getStats()).thenAnswer((_) async => const Left(NetworkFailure()));
  }

  // 320 dp est le plus étroit encore en circulation, 430 celui d'un grand
  // téléphone récent. C'est à 390 — largeur la plus courante — que le pied de
  // liste débordait de 49 px : un `Row` dont le texte n'avait pas le droit de
  // rétrécir. Flutter lève alors à CHAQUE image, et la zone se dégrade alors
  // même que l'API a bien répondu.
  for (final largeur in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets('affiche la liste sans exception à $largeur dp', (tester) async {
      stubListeAvecUnChantier();

      final erreurs = await pomper(tester, largeur: largeur);

      expect(
        erreurs.map((e) => e.exceptionAsString()).toList(),
        isEmpty,
        reason: 'une exception de mise en page dégrade la zone alors que '
            'le tableau de bord annonce bien un chantier',
      );
      expect(find.text('Résidence Les Acacias'), findsOneWidget);
    });
  }

  testWidgets('un chantier rendu par l’API est AFFICHÉ', (tester) async {
    when(() => getChantiers(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          search: any(named: 'search'),
          statut: any(named: 'statut'),
        )).thenAnswer(
      (_) async => const Right(ChantierPage(items: [_chantier], total: 1)),
    );
    when(() => getStats()).thenAnswer((_) async => const Left(NetworkFailure()));

    final erreurs = await pomper(tester);

    expect(erreurs, isEmpty, reason: 'une exception de mise en page viderait l’écran');
    expect(find.text('Résidence Les Acacias'), findsOneWidget);
  });

  testWidgets('aucun chantier donne un état vide EXPLICITE, pas un écran blanc',
      (tester) async {
    when(() => getChantiers(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          search: any(named: 'search'),
          statut: any(named: 'statut'),
        )).thenAnswer((_) async => const Right(ChantierPage(items: [], total: 0)));
    when(() => getStats()).thenAnswer((_) async => const Left(NetworkFailure()));

    final erreurs = await pomper(tester);

    expect(erreurs, isEmpty);
    expect(find.text('Aucun chantier'), findsOneWidget);
  });

  testWidgets('une panne de l’API donne un message et « Réessayer »', (tester) async {
    when(() => getChantiers(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          search: any(named: 'search'),
          statut: any(named: 'statut'),
        )).thenAnswer((_) async => const Left(NetworkFailure()));
    when(() => getStats()).thenAnswer((_) async => const Left(NetworkFailure()));

    await pomper(tester);

    expect(find.textContaining('Réessayer'), findsOneWidget);
  });

  testWidgets('un échec des compteurs ne vide pas la liste', (tester) async {
    // Les puces de statut sont décoratives. Une panne de `GET /dashboard` ne
    // doit pas emporter la liste avec elle.
    when(() => getChantiers(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          search: any(named: 'search'),
          statut: any(named: 'statut'),
        )).thenAnswer(
      (_) async => const Right(ChantierPage(items: [_chantier], total: 1)),
    );
    when(() => getStats()).thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'boom')));

    await pomper(tester);

    expect(find.text('Résidence Les Acacias'), findsOneWidget);
  });
}

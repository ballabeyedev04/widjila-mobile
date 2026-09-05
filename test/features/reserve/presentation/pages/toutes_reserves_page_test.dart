import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_event.dart';
import 'package:suivie_chantier_mobile/features/notification/presentation/cubit/notifications_cubit.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_state.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/repositories/reserve_repository.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_reserve_statuts_count.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_toutes_reserves.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/cubit/toutes_reserves_cubit.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/pages/toutes_reserves_page.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/l10n_test_helpers.dart';

class _MockGetToutes extends Mock implements GetToutesReserves {}

class _MockCompteurs extends Mock implements GetReserveStatutsCountGlobal {}

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

/// La cloche de l'en-tete lit ce cubit. Dans l'app il vient d'`AppShell`,
/// qui enveloppe cet onglet ; ici il faut le fournir a la main.
class _MockNotifications extends MockCubit<NotificationsState>
    implements NotificationsCubit {}

/// L'onglet « Réserves » quand l'organisation n'en a aucune.
///
/// ## Ce qui s'était cassé
///
/// L'écran restait indéfiniment sur ses six rectangles gris. Le message
/// « Aucune réserve » existait pourtant dans le code — il n'était simplement
/// jamais atteint, parce que `charger()` attendait les compteurs des puces de
/// filtre avant d'émettre quoi que ce soit. Un utilisateur devant une
/// organisation vide n'avait donc aucun moyen de comprendre ce qu'il voyait.
///
/// Un test sur le cubit seul ne suffit pas ici : il vérifie un état, pas ce
/// que la personne a devant les yeux. Ces tests pompent l'écran ENTIER et
/// cherchent le texte.
void main() {
  late _MockGetToutes getToutes;
  late _MockCompteurs getCompteurs;
  late _MockAuthBloc authBloc;
  late _MockNotifications notifications;

  setUp(() {
    getToutes = _MockGetToutes();
    getCompteurs = _MockCompteurs();
    authBloc = _MockAuthBloc();
    whenListen(authBloc, const Stream<AuthState>.empty(),
        initialState: const AuthState.inconnu());
    notifications = _MockNotifications();
    whenListen(notifications, const Stream<NotificationsState>.empty(),
        initialState: const NotificationsState());

    if (sl.isRegistered<ToutesReservesCubit>()) sl.unregister<ToutesReservesCubit>();
    sl.registerFactory<ToutesReservesCubit>(() => ToutesReservesCubit(
          getToutesReserves: getToutes,
          getStatutsCountGlobal: getCompteurs,
        ));
  });

  tearDown(() {
    if (sl.isRegistered<ToutesReservesCubit>()) sl.unregister<ToutesReservesCubit>();
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
      home: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider<NotificationsCubit>.value(value: notifications),
        ],
        child: const ToutesReservesPage(),
      ),
    ));
    await tester.pumpAndSettle();

    FlutterError.onError = precedent;
    return erreurs;
  }

  testWidgets('organisation sans reserve : le message « Aucune reserve » est AFFICHE', (tester) async {
    when(() => getToutes(page: 1, limit: 20, search: '', statut: null))
        .thenAnswer((_) async => const Right(ReservePage(items: [], total: 0)));
    when(() => getCompteurs())
        .thenAnswer((_) async => const Right(ReserveStatutsCount(parStatut: {}, total: 0)));

    await pomper(tester);

    expect(find.text('Aucune réserve'), findsOneWidget);
    expect(
      find.text('Les réserves créées sur vos chantiers apparaîtront ici.'),
      findsOneWidget,
    );
  });

  testWidgets('le message s’affiche MEME si les compteurs ne repondent jamais', (tester) async {
    // Le defaut d'origine, vu depuis l'ecran : les compteurs ne decorent que
    // les puces de filtre, ils ne doivent pas pouvoir retenir la reponse.
    when(() => getToutes(page: 1, limit: 20, search: '', statut: null))
        .thenAnswer((_) async => const Right(ReservePage(items: [], total: 0)));
    when(() => getCompteurs())
        .thenAnswer((_) => Completer<Either<Failure, ReserveStatutsCount>>().future);

    await pomper(tester);

    expect(find.text('Aucune réserve'), findsOneWidget);
  });

  testWidgets('back en panne : un message d’erreur et « Reessayer », jamais un squelette fige', (tester) async {
    when(() => getToutes(page: 1, limit: 20, search: '', statut: null))
        .thenAnswer((_) async => const Left(NetworkFailure()));
    when(() => getCompteurs())
        .thenAnswer((_) async => const Left(NetworkFailure()));

    await pomper(tester);

    expect(find.textContaining('Réessayer'), findsOneWidget);
  });

  group('liste peuplée', () {
    // Manque comblé : ce fichier ne couvrait que les états VIDES. Le
    // signalement terrain porte justement sur des réserves créées puis
    // invisibles — un défaut de mise en page dans une carte ne se voit que
    // lorsqu'il y a quelque chose à afficher.
    Reserve reserve(String id) => Reserve(
          id: id,
          numero: 'R-$id',
          chantierId: 'c1',
          titre: 'Fissure en façade nord du bâtiment principal',
          statut: ReserveStatut.creee,
        );

    for (final largeur in [320.0, 360.0, 390.0, 430.0]) {
      testWidgets('affiche les réserves sans exception à $largeur dp', (tester) async {
        when(() => getToutes(page: 1, limit: 20, search: '', statut: null)).thenAnswer(
          (_) async => Right(ReservePage(items: [reserve('a'), reserve('b')], total: 2)),
        );
        when(() => getCompteurs())
            .thenAnswer((_) async => const Right(ReserveStatutsCount(parStatut: {}, total: 2)));

        final erreurs = await pomper(tester, largeur: largeur);

        expect(
          erreurs.map((e) => e.exceptionAsString()).toList(),
          isEmpty,
          reason: 'une exception de mise en page dégrade la liste alors que '
              'les réserves sont bien arrivées',
        );
        expect(find.textContaining('R-a'), findsWidgets);
      });
    }
  });
}

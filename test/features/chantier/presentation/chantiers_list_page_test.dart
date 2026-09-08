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

import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_state.dart';

import '../../../helpers/balayage_responsive.dart';
import '../../../helpers/l10n_test_helpers.dart';
import '../../../helpers/pompe_page.dart';

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

  /// L'écran lit l'[AuthBloc] : c'est le rôle qui décide de l'affichage du
  /// bouton « Demander un chantier ».
  AuthBloc _auth(UserRole role) {
    final bloc = MockAuthBloc();
    whenListen(
      bloc,
      const Stream<AuthState>.empty(),
      initialState: AuthState(
        status: AuthStatus.authentifie,
        utilisateur: utilisateurTest(role),
      ),
    );
    return bloc;
  }

  Future<List<FlutterErrorDetails>> pomper(
    WidgetTester tester, {
    double largeur = 390,
    double hauteur = 844,
    UserRole role = UserRole.conducteurTravaux,
  }) async {
    // La HAUTEUR est un paramètre, et pas une constante : à 844 dp, ni le
    // paysage ni la tablette n'étaient jamais vus — et c'est là que la place
    // manque le plus.
    tester.view.physicalSize = Size(largeur, hauteur);
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
          BlocProvider<NotificationsCubit>.value(value: notifications),
          BlocProvider<AuthBloc>.value(value: _auth(role)),
        ],
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

  // ── Demander un chantier ──────────────────────────────────────────────────
  //
  // Signalement terrain : « je suis connecté en tant qu'entreprise et je ne
  // vois même pas le bouton Ajouter un chantier ». L'écran n'en avait aucun —
  // ni dans la barre, ni dans l'état vide, dont le texte renvoyait vers
  // « l'espace d'administration » où une entreprise n'a pas de compte.
  //
  // Le serveur, lui, acceptait la demande depuis le début : `POST /chantiers`
  // est gardé par le groupe `DEPOSANT`, qui inclut l'entreprise.

  testWidgets('une entreprise peut demander un chantier', (tester) async {
    stubListeAvecUnChantier();

    await pomper(tester, role: UserRole.entreprise);

    expect(find.text('Demander un chantier'), findsOneWidget);
  });

  testWidgets('le bouton survit à une liste REMPLIE', (tester) async {
    // Il ne doit pas vivre seulement dans l'état vide : une entreprise dépose
    // plusieurs demandes, et le bouton disparaîtrait au premier chantier
    // validé.
    stubListeAvecUnChantier();

    await pomper(tester, role: UserRole.entreprise);

    expect(find.text('Résidence Les Acacias'), findsOneWidget);
    expect(find.text('Demander un chantier'), findsOneWidget);
  });

  testWidgets("l'état vide d'un demandeur propose l'action, pas un renvoi", (tester) async {
    when(() => getChantiers(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          search: any(named: 'search'),
          statut: any(named: 'statut'),
        )).thenAnswer((_) async => const Right(ChantierPage(items: [], total: 0)));
    when(() => getStats()).thenAnswer((_) async => const Left(NetworkFailure()));

    await pomper(tester, role: UserRole.entreprise);

    // Le bouton flottant ET celui de l'état vide : c'est là que l'utilisateur
    // regarde quand l'écran est vide.
    expect(find.text('Demander un chantier'), findsNWidgets(2));
    // L'ancien texte renvoyait ailleurs ; il ne doit plus s'adresser à elle.
    expect(find.textContaining("espace d'administration"), findsNothing);
  });

  testWidgets("un rôle sans droit de dépôt ne voit pas le bouton", (tester) async {
    // Miroir du groupe `DEPOSANT` : le sous-traitant n'en fait pas partie, le
    // bouton le mènerait à un 403.
    stubListeAvecUnChantier();

    await pomper(tester, role: UserRole.sousTraitant);

    expect(find.text('Demander un chantier'), findsNothing);
  });

  group('mise en page — balayage complet des formats', () {
    // Le balayage par largeur ci-dessus gardait une hauteur fixe de 844 dp :
    // la liste des chantiers n'était donc jamais vu couché, ni sur une tablette.
    // Ces deux situations sont pourtant celles où la mise en page cède —
    // hauteur divisée par trois d'un côté, largeur doublée de l'autre.
    for (final format in tousLesFormats) {
      testWidgets('sans débordement sur $format', (tester) async {
        stubListeAvecUnChantier();
        final erreurs = await pomper(
          tester,
          largeur: format.taille.width,
          hauteur: format.taille.height,
        );

        expect(
          erreurs.map((e) => e.exceptionAsString()).toList(),
          isEmpty,
          reason: 'débordement de mise en page sur $format',
        );
      });
    }
  });
}

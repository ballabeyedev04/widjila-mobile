import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/auth/domain/entities/user.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_event.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_state.dart';
import 'package:suivie_chantier_mobile/features/notification/presentation/cubit/notifications_cubit.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/entities/plan.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_plans_chantier.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_tous_plans.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/uploader_plan.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/cubit/plans_list_cubit.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/pages/plans_list_page.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/balayage_responsive.dart';
import '../../../../helpers/l10n_test_helpers.dart';

class _MockTousPlans extends Mock implements GetTousPlans {}

class _MockPlansChantier extends Mock implements GetPlansChantier {}

class _MockUploader extends Mock implements UploaderPlan {}

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _MockNotifications extends MockCubit<NotificationsState> implements NotificationsCubit {}

/// Trois plans tels que le serveur les sert : un plan global, un plan de
/// façade rattaché à un bâtiment, un plan d'appartement avec des réserves.
final _plans = [
  Plan(
    id: 'p-global',
    chantierId: 'c1',
    nom: 'Plan de masse — Résidence Les Almadies',
    fichierUrl: '/uploads/plans/masse.pdf',
    chantierNom: 'Résidence Les Almadies',
    createdAt: DateTime(2026, 9, 10),
    typePlan: 'Architecture',
  ),
  Plan(
    id: 'p-facade',
    chantierId: 'c1',
    nom: 'Façade nord — Bâtiment A',
    fichierUrl: '/uploads/plans/facade.png',
    version: 2,
    chantierNom: 'Résidence Les Almadies',
    createdAt: DateTime(2026, 9, 8),
    batiment: const PlanNiveauRef(id: 'b1', nom: 'Bâtiment A'),
  ),
  Plan(
    id: 'p-a201',
    chantierId: 'c1',
    nom: 'Appartement A201',
    fichierUrl: '/uploads/plans/a201.pdf',
    chantierNom: 'Résidence Les Almadies',
    createdAt: DateTime(2026, 9, 1),
    batiment: const PlanNiveauRef(id: 'b1', nom: 'Bâtiment A'),
    etage: const PlanNiveauRef(id: 'e2', nom: 'R+2'),
    nombreReserves: 5,
    nombreReservesATraiter: 3,
  ),
];

/// Rapports d'erreur de rendu reçus pendant le test (voir `pomper`).
final _rapportsRendu = <FlutterErrorDetails>[];

/// Échoue sur toute erreur de rendu en donnant le RAPPORT COMPLET : pour un
/// débordement, il nomme la rangée fautive (« creator: Row ← … »). L'exception
/// seule, telle que la rend `takeException`, n'en dit que la première ligne.
void _sansErreurDeRendu(WidgetTester tester) {
  final erreur = tester.takeException();
  final rapport = _rapportsRendu.map((d) => d.toString()).join('\n');
  expect(erreur, isNull, reason: rapport.isEmpty ? erreur?.toString() : rapport);
}

/// La liste des plans AVEC des plans — le test voisin ne rend que la liste vide.
///
/// Défaut signalé (capture d'écran d'un téléphone) : chaque carte n'affichait
/// qu'une vignette de 52 points, recadrée, dans un grand bloc grisé — ni nom,
/// ni date, ni bouton. Aucune carte n'avait jamais été rendue par un test.
void main() {
  late _MockTousPlans tousPlans;

  setUp(() {
    tousPlans = _MockTousPlans();
    when(() => tousPlans()).thenAnswer((_) async => Right<Failure, List<Plan>>(_plans));
    if (sl.isRegistered<PlansListCubit>()) sl.unregister<PlansListCubit>();
    sl.registerFactory<PlansListCubit>(() => PlansListCubit(
          getTousPlans: tousPlans,
          getPlansChantier: _MockPlansChantier(),
          uploaderPlan: _MockUploader(),
        ));
  });

  tearDown(() {
    if (sl.isRegistered<PlansListCubit>()) sl.unregister<PlansListCubit>();
  });

  Future<void> pomper(WidgetTester tester, {Size taille = const Size(360, 780), double echelleTexte = 1}) async {
    tester.view.physicalSize = taille;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    _rapportsRendu.clear();
    final precedent = FlutterError.onError;
    FlutterError.onError = (details) {
      _rapportsRendu.add(details);
      precedent?.call(details);
    };
    addTearDown(() => FlutterError.onError = precedent);

    final authBloc = _MockAuthBloc();
    whenListen(authBloc, const Stream<AuthState>.empty(),
        initialState: const AuthState(
          status: AuthStatus.authentifie,
          utilisateur: User(
            id: 'u1',
            nom: 'BEYE',
            prenom: 'Balla',
            email: 'balla@widjila.com',
            role: UserRole.conducteurTravaux,
            statut: 'actif',
          ),
        ));
    final notifications = _MockNotifications();
    whenListen(notifications, const Stream<NotificationsState>.empty(),
        initialState: const NotificationsState());

    await tester.pumpWidget(MaterialApp(
      locale: testLocale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(echelleTexte)),
        child: child!,
      ),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider<NotificationsCubit>.value(value: notifications),
        ],
        child: const PlansListPage(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('chaque carte affiche le nom du plan, sans erreur de rendu', (tester) async {
    await pomper(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Plan de masse — Résidence Les Almadies'), findsOneWidget);
    expect(find.text('Façade nord — Bâtiment A'), findsOneWidget);
  });

  testWidgets('la carte dit où se trouve le plan et ce qui reste à traiter', (tester) async {
    await pomper(tester);
    // La page a DEUX zones défilantes (la rangée des filtres de format et la
    // liste) : on vise explicitement la liste.
    await tester.scrollUntilVisible(
      find.text('Appartement A201'),
      200,
      scrollable: find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)),
    );
    await tester.pumpAndSettle();

    _sansErreurDeRendu(tester);
    expect(find.textContaining('Bâtiment A · R+2'), findsOneWidget);
    expect(find.textContaining('3 à traiter'), findsOneWidget);
  });

  testWidgets('les dates sont en français', (tester) async {
    await pomper(tester);

    expect(find.textContaining('10 sept. 2026'), findsOneWidget);
    expect(find.textContaining('Sep'), findsNothing);
  });

  testWidgets('l’aperçu du plan est grand : au moins les deux tiers de la largeur', (tester) async {
    await pomper(tester);

    final apercu = tester.getSize(find.byKey(const ValueKey('apercu-p-global')));
    expect(apercu.width, greaterThanOrEqualTo(360 * 2 / 3));
    expect(apercu.height, greaterThanOrEqualTo(150));
  });

  testWidgets('texte agrandi (accessibilité ×1,3) : aucun débordement', (tester) async {
    await pomper(tester, echelleTexte: 1.3);

    _sansErreurDeRendu(tester);
  });

  group('balayage des formats', () {
    for (final format in tousLesFormats) {
      testWidgets('sans débordement sur $format', (tester) async {
        await pomper(tester, taille: format.taille);

        expect(tester.takeException(), isNull, reason: 'débordement sur $format');
        expect(find.text('Plan de masse — Résidence Les Almadies'), findsOneWidget);
      });
    }
  });
}

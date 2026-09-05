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

import '../../../../helpers/l10n_test_helpers.dart';

class _MockTousPlans extends Mock implements GetTousPlans {}

class _MockPlansChantier extends Mock implements GetPlansChantier {}

class _MockUploader extends Mock implements UploaderPlan {}

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _MockNotifications extends MockCubit<NotificationsState>
    implements NotificationsCubit {}

User _utilisateur(UserRole role) => User(
      id: 'u1',
      nom: 'BEYE',
      prenom: 'Balla',
      email: 'balla@widjila.com',
      role: role,
      statut: 'actif',
    );

/// L'ecran Plans, vide, selon le role.
///
/// ## Ce qui s'etait casse
///
/// Le bouton « Ajouter des plans » etait conditionne a
/// `estOperationnelOuControle`, qui EXCLUT `Entreprise`. Le serveur, lui,
/// garde la route avec `DEPOSANT`, qui l'INCLUT — et dit explicitement
/// pourquoi : l'entreprise joint ses plans a sa demande de chantier.
///
/// Une entreprise voyait donc « Aucun plan » avec un texte de simple lecture
/// et aucune issue, alors qu'elle avait le droit de deposer. Un test sur le
/// cubit n'aurait rien vu : le defaut etait dans la condition d'affichage.
void main() {
  late _MockTousPlans tousPlans;
  late _MockAuthBloc authBloc;
  late _MockNotifications notifications;

  setUp(() {
    tousPlans = _MockTousPlans();
    when(() => tousPlans()).thenAnswer(
      (_) async => Right<Failure, List<Plan>>(const []),
    );

    notifications = _MockNotifications();
    whenListen(notifications, const Stream<NotificationsState>.empty(),
        initialState: const NotificationsState());

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

  Future<void> pomper(WidgetTester tester, UserRole role) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    authBloc = _MockAuthBloc();
    whenListen(authBloc, const Stream<AuthState>.empty(),
        initialState: AuthState(
          status: AuthStatus.authentifie,
          utilisateur: _utilisateur(role),
        ));

    await tester.pumpWidget(MaterialApp(
      locale: testLocale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
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

  testWidgets('Entreprise voit « Ajouter des plans » sur un ecran vide', (tester) async {
    await pomper(tester, UserRole.entreprise);

    expect(
      find.text('Ajouter des plans'),
      findsWidgets,
      reason: 'le serveur autorise le depot a DEPOSANT, qui inclut Entreprise',
    );
  });

  testWidgets('les autres roles deposants le voient aussi', (tester) async {
    for (final role in [
      UserRole.chefProjet,
      UserRole.conducteurTravaux,
      UserRole.maitreOeuvre,
      UserRole.bureauControle,
      UserRole.maitreOuvrage,
    ]) {
      await pomper(tester, role);
      expect(find.text('Ajouter des plans'), findsWidgets,
          reason: '$role appartient a DEPOSANT');
    }
  });

  testWidgets('un client ne le voit pas — il n’a pas le droit de deposer', (tester) async {
    await pomper(tester, UserRole.client);

    expect(find.text('Ajouter des plans'), findsNothing);
    expect(
      find.text("Les plans importés depuis l'espace d'administration apparaîtront ici."),
      findsOneWidget,
      reason: 'le texte de simple lecture reste juste pour qui ne peut pas deposer',
    );
  });
}

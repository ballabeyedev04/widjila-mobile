import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/abonnement/domain/entities/abonnement.dart';
import 'package:suivie_chantier_mobile/features/abonnement/domain/usecases/get_droits.dart';
import 'package:suivie_chantier_mobile/features/abonnement/domain/usecases/get_formules.dart';
import 'package:suivie_chantier_mobile/features/abonnement/domain/usecases/get_historique_abonnement.dart';
import 'package:suivie_chantier_mobile/features/abonnement/presentation/cubit/abonnement_cubit.dart';
import 'package:suivie_chantier_mobile/features/abonnement/presentation/pages/abonnement_page.dart';
import 'package:suivie_chantier_mobile/features/auth/domain/entities/user.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_event.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_state.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../helpers/l10n_test_helpers.dart';

class _MockFormules extends Mock implements GetFormules {}

class _MockDroits extends Mock implements GetDroits {}

class _MockHistorique extends Mock implements GetHistoriqueAbonnement {}

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

User _utilisateur(UserRole role) => User(
      id: 'u1', nom: 'BEYE', prenom: 'Balla',
      email: 'balla@widjila.com', role: role, statut: 'actif',
    );

const _formule = FormuleAbonnement(
  id: 'a1', code: 'essentiel', nom: 'Essentiel', prix: 29,
  limiteUtilisateurs: 5, fonctionnalites: ['reserves'],
);

/// L'écran Abonnement — formule en cours, quota, compte à rebours, facturation.
///
/// La facturation est gardée par le groupe GESTION côté serveur. L'écran doit
/// donc rester utile aux autres rôles : ils ont un intérêt légitime à voir leur
/// formule et leur quota — c'est ce qui explique un refus de créer un chantier
/// — sans pour autant accéder aux montants.
void main() {
  late _MockFormules formules;
  late _MockDroits droits;
  late _MockHistorique historique;
  late _MockAuthBloc authBloc;

  setUp(() {
    formules = _MockFormules();
    droits = _MockDroits();
    historique = _MockHistorique();

    when(() => formules()).thenAnswer((_) async => const Right([_formule]));
    when(() => droits()).thenAnswer((_) async => const Right(DroitsAbonnement(
          actif: true, source: 'abonnement', planCode: 'essentiel',
          planNom: 'Essentiel', joursRestants: 12,
          utilisateurs: UsageRessource(courant: 4, limite: 5),
          chantiers: UsageRessource(courant: 2, limite: 10),
        )));
    when(() => historique()).thenAnswer((_) async => const Right([
          SouscriptionHistorique(
            id: 's1', planNom: 'Essentiel', prixPaye: 29,
            devise: 'EUR', statut: 'active',
          ),
        ]));

    if (sl.isRegistered<AbonnementCubit>()) sl.unregister<AbonnementCubit>();
    sl.registerFactory<AbonnementCubit>(() => AbonnementCubit(
          getFormules: formules, getDroits: droits, getHistorique: historique,
        ));
  });

  tearDown(() {
    if (sl.isRegistered<AbonnementCubit>()) sl.unregister<AbonnementCubit>();
  });

  Future<void> pomper(WidgetTester tester, UserRole role) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    authBloc = _MockAuthBloc();
    whenListen(authBloc, const Stream<AuthState>.empty(),
        initialState: AuthState(
          status: AuthStatus.authentifie, utilisateur: _utilisateur(role),
        ));

    await tester.pumpWidget(MaterialApp(
      locale: testLocale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: BlocProvider<AuthBloc>.value(value: authBloc, child: const AbonnementPage()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('un rôle de gestion voit l’historique et le montant', (tester) async {
    await pomper(tester, UserRole.chefProjet);

    expect(find.text('Historique des paiements'), findsOneWidget);
    expect(find.textContaining('29'), findsWidgets);
    expect(find.text('Payé'), findsOneWidget);
    verify(() => historique()).called(1);
  });

  testWidgets('un rôle sans droit ne voit NI la section NI la requête partir', (tester) async {
    // Le conducteur de travaux n'est pas dans GESTION : appeler la route ne
    // produirait qu'un 403 et un message d'erreur sur un écran utilisable.
    await pomper(tester, UserRole.conducteurTravaux);

    expect(find.text('Historique des paiements'), findsNothing);
    verifyNever(() => historique());
  });

  testWidgets('l’écran reste utile sans droit : formule et quota s’affichent', (tester) async {
    await pomper(tester, UserRole.conducteurTravaux);

    expect(find.text('Essentiel'), findsWidgets);
    expect(find.text('Utilisateurs'), findsOneWidget);
  });

  testWidgets('le compte à rebours du serveur est affiché tel quel', (tester) async {
    await pomper(tester, UserRole.chefProjet);

    expect(find.text('Il vous reste 12 jours'), findsOneWidget);
  });

  testWidgets('une facturation en panne n’empêche pas l’écran de s’afficher', (tester) async {
    when(() => historique())
        .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Indisponible')));

    await pomper(tester, UserRole.chefProjet);

    expect(find.text('Historique des paiements'), findsOneWidget);
    expect(find.text('Aucun paiement pour le moment.'), findsOneWidget);
    expect(find.text('Essentiel'), findsWidgets);
  });
}

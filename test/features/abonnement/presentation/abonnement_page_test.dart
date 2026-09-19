import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/services/feedback_sonore.dart';
import 'package:suivie_chantier_mobile/features/abonnement/domain/entities/abonnement.dart';
import 'package:suivie_chantier_mobile/features/abonnement/domain/usecases/creer_code_transfert_web.dart';
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
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../../helpers/balayage_responsive.dart';
import '../../../helpers/l10n_test_helpers.dart';

class _MockFormules extends Mock implements GetFormules {}

class _MockDroits extends Mock implements GetDroits {}

class _MockHistorique extends Mock implements GetHistoriqueAbonnement {}

class _MockTransfert extends Mock implements CreerCodeTransfertWeb {}

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

/// Un navigateur qui « s'ouvre » toujours, sans rien ouvrir.
class _NavigateurFaux extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  final ouvertures = <String>[];
  @override
  LinkDelegate? get linkDelegate => null;
  @override
  Future<bool> canLaunch(String url) async => true;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    ouvertures.add(url);
    return true;
  }
}

/// Un moteur audio qui note les sons demandés.
class _LecteurEspion implements LecteurSon {
  final joues = <String>[];
  @override
  Future<void> precharger(String asset) async {}
  @override
  Future<void> jouer(String asset) async => joues.add(asset);
}

User _utilisateur(UserRole role) => User(
      id: 'u1', nom: 'BEYE', prenom: 'Balla',
      email: 'balla@widjila.com', role: role, statut: 'actif',
    );

const _formule = FormuleAbonnement(
  id: 'a1', code: 'essentiel', nom: 'Essentiel', prix: 29,
  limiteUtilisateurs: 5, fonctionnalites: ['reserves'],
);

/// Une formule que l'organisation n'a PAS — la seule dont le bouton agit.
const _pro = FormuleAbonnement(
  id: 'a2', code: 'pro', nom: 'Pro', prix: 89,
  limiteUtilisateurs: 10, fonctionnalites: ['reserves', 'rapports'],
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
  late _MockTransfert transfert;
  late _MockAuthBloc authBloc;

  setUp(() {
    formules = _MockFormules();
    droits = _MockDroits();
    historique = _MockHistorique();
    transfert = _MockTransfert();
    when(() => transfert()).thenAnswer((_) async => const Right('code-transfert'));

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
          creerCodeTransfertWeb: transfert,
        ));
  });

  tearDown(() {
    if (sl.isRegistered<AbonnementCubit>()) sl.unregister<AbonnementCubit>();
  });

  Future<void> pomper(WidgetTester tester, UserRole role, {Size? taille}) async {
    // La taille est un PARAMÈTRE : figée à 390 × 900, ni le paysage ni la
    // tablette n'étaient jamais vus.
    tester.view.physicalSize = taille ?? const Size(390, 900);
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

  // ── Le titulaire de l'abonnement ─────────────────────────────────────────
  //
  // L'inscription publique crée l'organisation et son premier compte avec le
  // rôle `entreprise`. C'est lui qui règle l'abonnement — et il ne voyait
  // AUCUN de ses paiements : le miroir local suivait GESTION, qui l'exclut.
  // Côté serveur, la même exclusion lui refusait le paiement d'un 403, au
  // moment précis où son essai s'achevait.

  testWidgets('une entreprise voit SES paiements — elle les a réglés', (tester) async {
    await pomper(tester, UserRole.entreprise);

    expect(find.text('Historique des paiements'), findsOneWidget);
    expect(find.text('Payé'), findsOneWidget);
    verify(() => historique()).called(1);
  });

  testWidgets('une entreprise voit le compte à rebours de son essai', (tester) async {
    // C'est ce chiffre qui lui dit quand payer : le masquer transformait la
    // fin d'essai en coupure sans préavis.
    await pomper(tester, UserRole.entreprise);

    expect(find.text('Il vous reste 12 jours'), findsOneWidget);
  });

  // ── « Choisir cette formule » ─────────────────────────────────────────────
  //
  // Le bouton ouvrait la page de paiement du web SANS session : le navigateur
  // du téléphone enchaînait 401 et « refreshToken manquant », puis renvoyait
  // vers la connexion. Il demande désormais un code de transfert d'abord.

  group('choisir une formule', () {
    // Écran haut : toutes les cartes sont construites, sans défilement.
    const grand = Size(390, 2600);

    testWidgets('demande un code de transfert AVANT d’ouvrir quoi que ce soit', (tester) async {
      when(() => formules()).thenAnswer((_) async => const Right([_formule, _pro]));
      // Échec du code : aucune page ne doit s'ouvrir, un message le dit.
      when(() => transfert())
          .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Indisponible')));

      await pomper(tester, UserRole.entreprise, taille: grand);
      await tester.tap(find.text('Choisir cette formule'));
      await tester.pumpAndSettle();

      verify(() => transfert()).called(1);
      expect(
        find.text('Impossible de préparer le paiement. Vérifiez votre connexion et réessayez.'),
        findsOneWidget,
      );
    });

    testWidgets('un rôle sans facturation voit pourquoi, et rien ne part', (tester) async {
      // Le serveur refuserait le paiement (403) : ouvrir un navigateur pour
      // un refus serait pire que de le dire sur le bouton.
      when(() => formules()).thenAnswer((_) async => const Right([_formule, _pro]));

      await pomper(tester, UserRole.conducteurTravaux, taille: grand);
      expect(find.text('Réservé au responsable de l’abonnement'), findsOneWidget);

      await tester.tap(find.text('Réservé au responsable de l’abonnement'));
      await tester.pumpAndSettle();
      verifyNever(() => transfert());
    });

    testWidgets('la formule PAYÉE en cours ne se choisit pas', (tester) async {
      await pomper(tester, UserRole.entreprise, taille: grand);

      await tester.tap(find.text('Formule actuelle').last);
      await tester.pumpAndSettle();
      verifyNever(() => transfert());
    });

    testWidgets('pendant l’essai, la formule d’essai reste souscriptible', (tester) async {
      // Le code de formule des droits ne dit pas qu'elle est payée : pendant
      // l'essai, neutraliser son bouton empêchait de la souscrire.
      when(() => droits()).thenAnswer((_) async => const Right(DroitsAbonnement(
            actif: true, source: 'essai', planCode: 'essentiel', essaiEnCours: true,
            joursRestants: 1,
            utilisateurs: UsageRessource(courant: 1, limite: 5),
            chantiers: UsageRessource(courant: 1, limite: 10),
          )));

      await pomper(tester, UserRole.entreprise, taille: grand);

      expect(find.text('Choisir cette formule'), findsOneWidget);
    });
  });

  group('adresse de la page de paiement', () {
    test('porte la formule en requête et le code dans le FRAGMENT', () {
      final uri = urlPaiementWeb(
        Uri.parse('https://app.widjila.com/abonnement'),
        formule: 'essentiel',
        codeTransfert: 'aaa.bbb-ccc_ddd',
      );

      expect(uri.toString(), 'https://app.widjila.com/abonnement?plan=essentiel#transfert=aaa.bbb-ccc_ddd');
      // Le fragment ne part jamais au serveur qui sert la page : le code n'a
      // rien à faire dans la requête.
      expect(uri.query, isNot(contains('transfert')));
    });
  });

  group('mise en page — balayage des formats', () {
    // L'écran empile un état d'abonnement, un montant, une échéance et un
    // historique de paiements. Les lignes « libellé / montant » y sont le point
    // sensible : deux textes variables sur la même ligne.
    for (final format in tousLesFormats) {
      testWidgets('sans débordement sur $format', (tester) async {
        await pomper(tester, UserRole.chefProjet, taille: format.taille);

        expect(tester.takeException(), isNull,
            reason: 'débordement de mise en page sur $format');
      });
    }
  });

  /// § PAIEMENT — la règle la plus stricte du feedback sonore.
  ///
  /// Ni l'ouverture du navigateur, ni le retour dans l'application, ni la
  /// demande de paiement ne valent succès. Seul l'abonnement que le SERVEUR
  /// renvoie au retour — la formule payée, active, alors qu'elle ne l'était
  /// pas avant — déclenche la carte verte et son son.
  group('confirmation du paiement', () {
    const grand = Size(390, 2600);
    late _NavigateurFaux navigateur;
    late _LecteurEspion lecteur;
    late UrlLauncherPlatform navigateurInitial;

    const droitsAvant = DroitsAbonnement(
      actif: true, source: 'abonnement', planCode: 'essentiel', planNom: 'Essentiel',
      utilisateurs: UsageRessource(courant: 4, limite: 5),
      chantiers: UsageRessource(courant: 2, limite: 10),
    );
    const droitsProActive = DroitsAbonnement(
      actif: true, source: 'abonnement', planCode: 'pro', planNom: 'Pro',
      utilisateurs: UsageRessource(courant: 4, limite: 10),
      chantiers: UsageRessource(courant: 2, limite: 50),
    );

    setUp(() {
      navigateurInitial = UrlLauncherPlatform.instance;
      navigateur = _NavigateurFaux();
      UrlLauncherPlatform.instance = navigateur;
      lecteur = _LecteurEspion();
      FeedbackSonore.instance = FeedbackSonore(lecteur: lecteur, horloge: () => DateTime(2026, 9, 18));
      when(() => formules()).thenAnswer((_) async => const Right([_formule, _pro]));
    });
    tearDown(() {
      UrlLauncherPlatform.instance = navigateurInitial;
      FeedbackSonore.instance = FeedbackSonore();
    });

    /// Choisit « Pro », part vers le navigateur, puis revient dans l'app avec
    /// [auRetour] comme réponse du serveur.
    Future<void> payerPuisRevenir(WidgetTester tester, DroitsAbonnement auRetour) async {
      when(() => droits()).thenAnswer((_) async => const Right(droitsAvant));
      await pomper(tester, UserRole.entreprise, taille: grand);

      await tester.tap(find.text('Choisir cette formule'));
      await tester.pumpAndSettle();
      expect(navigateur.ouvertures, hasLength(1), reason: 'la page de paiement s’est ouverte');
      expect(lecteur.joues, isEmpty, reason: 'ouvrir le navigateur n’est pas un succès');

      // Retour dans l'application : le serveur répond désormais [auRetour].
      when(() => droits()).thenAnswer((_) async => Right(auRetour));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    }

    testWidgets('le serveur confirme la formule payée → carte verte + son', (tester) async {
      await payerPuisRevenir(tester, droitsProActive);

      expect(find.text('Paiement confirmé : votre formule Pro est active.'), findsOneWidget);
      expect(lecteur.joues, hasLength(1));
    });

    testWidgets('retour SANS changement côté serveur (page fermée, carte refusée) → rien', (tester) async {
      await payerPuisRevenir(tester, droitsAvant);

      expect(find.textContaining('Paiement confirmé'), findsNothing);
      expect(lecteur.joues, isEmpty);
    });

    testWidgets('un simple passage en arrière-plan sans paiement lancé → rien', (tester) async {
      when(() => droits()).thenAnswer((_) async => const Right(droitsAvant));
      await pomper(tester, UserRole.entreprise, taille: grand);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(lecteur.joues, isEmpty);
      expect(find.textContaining('Paiement confirmé'), findsNothing);
    });
  });
}

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/features/auth/domain/entities/user.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_event.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_state.dart';
import 'package:suivie_chantier_mobile/features/notification/presentation/cubit/notifications_cubit.dart';

import 'l10n_test_helpers.dart';

/// Échafaudage commun aux tests d'écran.
///
/// ## Le problème qu'il résout
///
/// Monter une page de cette application demande quatre choses qui n'ont rien
/// à voir avec ce qu'on veut vérifier : les délégués de traduction (sans eux
/// `context.l10n` plante au premier pump), un [AuthBloc] (les pages lisent le
/// rôle pour décider quels boutons afficher), un [NotificationsCubit] (la
/// cloche de l'en-tête le cherche et fait planter l'écran s'il est absent) et
/// une taille d'écran fixe (sinon la surface de test de 800×600 déborde et
/// masque le vrai résultat sous un `RenderFlex overflowed`).
///
/// Recopié dans chaque fichier, cet échafaudage dérive : un test finit par
/// tourner en anglais, un autre sur une surface de tablette, et leurs
/// résultats cessent d'être comparables. Il est donc écrit une fois ici.
///
/// ## Ce qu'il ne fait pas
///
/// Il ne fournit AUCUN cubit de fonctionnalité. Chaque test enregistre
/// lui-même dans `sl` le cubit de la page qu'il monte : c'est précisément ce
/// qu'il cherche à contrôler.

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class MockNotificationsCubit extends MockCubit<NotificationsState>
    implements NotificationsCubit {}

/// Utilisateur de test — l'identité importe peu, le [role] fait tout.
///
/// [organisationId] est renseigné par défaut : plusieurs écrans masquent
/// purement et simplement leur bloc « entreprise » quand il est nul, et un
/// test écrit sans lui chercherait alors un contenu que la page a raison de
/// ne pas afficher. Le passer à `null` reste possible pour vérifier
/// justement ce masquage.
User utilisateurTest(UserRole role, {String? organisationId = 'org-test'}) => User(
      id: 'u-test',
      organisationId: organisationId,
      nom: 'BEYE',
      prenom: 'Balla',
      email: 'balla@widjila.com',
      role: role,
      statut: 'actif',
    );

/// Taille de référence des tests d'écran : un téléphone courant.
///
/// La surface par défaut de `flutter_test` (800×600) est un format qui
/// n'existe sur aucun appareil et déclenche la bascule tablette de
/// `liste_chrome.dart` (seuil 700). Les tests verraient une mise en page que
/// presque aucun utilisateur ne voit.
const Size ecranTelephone = Size(390, 844);

/// Format tablette, pour les tests qui vérifient explicitement la bascule.
const Size ecranTablette = Size(1024, 1366);

/// Monte [page] dans une application complète, prête à être pompée.
///
/// [role] alimente l'[AuthBloc] : c'est lui qui décide, dans la plupart des
/// écrans, si un bouton d'action est affiché ou non.
///
/// [nonLues] alimente la pastille de la cloche.
/// [auth] permet de fournir un bloc DÉJÀ configuré — pour les écrans
/// d'authentification, qui n'affichent pas des données mais la progression
/// d'une action : chargement, erreur du serveur, succès. Un bloc muet ne
/// permettrait d'en observer aucune. Laissé nul, un bloc authentifié au rôle
/// [role] est fabriqué, ce qui convient à tous les autres écrans.
Future<void> pomperPage(
  WidgetTester tester,
  Widget page, {
  UserRole role = UserRole.conducteurTravaux,
  int nonLues = 0,
  Size taille = ecranTelephone,
  bool reglerSurface = true,
  AuthBloc? auth,
}) async {
  if (reglerSurface) {
    tester.view.physicalSize = taille;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  final AuthBloc blocAuth;
  if (auth != null) {
    blocAuth = auth;
  } else {
    final parDefaut = MockAuthBloc();
    whenListen(
      parDefaut,
      const Stream<AuthState>.empty(),
      initialState: AuthState(
        status: AuthStatus.authentifie,
        utilisateur: utilisateurTest(role),
      ),
    );
    blocAuth = parDefaut;
  }

  final notifications = MockNotificationsCubit();
  whenListen(
    notifications,
    const Stream<NotificationsState>.empty(),
    initialState: NotificationsState(
      status: NotificationsStatus.succes,
      nonLues: nonLues,
    ),
  );

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>.value(value: blocAuth),
        BlocProvider<NotificationsCubit>.value(value: notifications),
      ],
      child: MaterialApp(
        locale: testLocale,
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: page,
      ),
    ),
  );
  await tester.pump();
}

/// Rappel : après `pomperPage`, un test qui veut prouver que l'écran s'est
/// monté SANS incident termine par
///
/// ```dart
/// expect(tester.takeException(), isNull);
/// ```
///
/// `flutter_test` capture les exceptions de construction au lieu de les faire
/// remonter. Sans cette ligne, une page qui explose au montage passe pour un
/// test vert dont les `find` ne trouvent simplement rien.

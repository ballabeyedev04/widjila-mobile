import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/routes/app_router.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_state.dart';

class MockAuthBloc extends Mock implements AuthBloc {}

/// Pourquoi ce fichier existe
///
/// `SuivieChantierApp` construisait son routeur DANS `build`, via un `Builder`.
/// Chaque reconstruction fabriquait donc un `AppRouter` neuf. Les tests
/// ci-dessous mesurent ce que coûte exactement une seconde instance — pile de
/// navigation, clé de navigateur, abonnement — et servent de garde-fou : si
/// quelqu'un remet cette construction dans un `build`, ces coûts repartent à
/// chaque image.
void main() {
  late MockAuthBloc bloc;
  late StreamController<AuthState> flux;
  late int abonnements;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    bloc = MockAuthBloc();
    flux = StreamController<AuthState>.broadcast();
    abonnements = 0;
    // `GoRouterRefreshStream` lit `authBloc.stream` exactement une fois par
    // routeur : compter les lectures revient a compter les abonnements.
    when(() => bloc.stream).thenAnswer((_) {
      abonnements++;
      return flux.stream;
    });
    when(() => bloc.state).thenReturn(const AuthState.inconnu());
  });

  tearDown(() => flux.close());

  test('le meme AppRouter rend TOUJOURS le meme GoRouter', () {
    // `late final` : c'est cette garantie qui rend sur le fait de conserver
    // un `AppRouter` dans un champ d'etat.
    final appRouter = AppRouter(bloc);
    final premier = appRouter.router;
    final second = appRouter.router;

    expect(identical(premier, second), isTrue);
    expect(abonnements, 1);
    premier.dispose();
  });

  test('deux AppRouter donnent deux routeurs et deux cles de navigateur distincts', () {
    // C'est le coeur du defaut corrige : reconstruire l'`AppRouter` a chaque
    // `build` jetait la pile de navigation, et faisait coexister deux
    // navigateurs le temps d'une image — chacun keye par go_router avec un
    // `GlobalObjectKey`. C'est le terrain du « Duplicate GlobalKey » observe
    // sur le web ; le lien de cause a effet n'a pas ete reproduit, mais la
    // coexistence, elle, est bien ce que ce test constate.
    final a = AppRouter(bloc).router;
    final b = AppRouter(bloc).router;

    expect(identical(a, b), isFalse);
    expect(
      identical(a.configuration.navigatorKey, b.configuration.navigatorKey),
      isFalse,
      reason: 'chaque routeur amene sa propre cle de navigateur racine',
    );

    a.dispose();
    b.dispose();
  });

  test('chaque routeur construit ouvre un abonnement de plus au flux d authentification', () {
    // `GoRouterRefreshStream` n'est jamais resilie : un routeur construit par
    // reconstruction etait une fuite par reconstruction, et un ancien routeur
    // de plus continuant d'evaluer ses redirections dans le vide.
    final routeurs = [
      AppRouter(bloc).router,
      AppRouter(bloc).router,
      AppRouter(bloc).router,
    ];

    expect(abonnements, 3);
    expect(flux.hasListener, isTrue);

    for (final r in routeurs) {
      r.dispose();
    }
  });

  test('chaque ecran de la coquille a sa propre transition', () {
    // Ce qui manquait : les transitions n'avaient ete posees que sur les
    // ecrans PLEINS. Les onglets — Accueil, Reserves, Plans — et les ecrans du
    // menu « Plus » restaient sur la page par defaut de go_router, sans
    // animation ecrite. C'est pourtant la que les changements de page se
    // voient le plus, puisque ce sont ceux que l'on repete.
    final routeur = AppRouter(bloc).router;

    // `StatefulShellRoute` et non `ShellRoute` : la coquille a été convertie
    // pour que chaque onglet garde son état (listes chargées, filtres,
    // position de défilement) au lieu de tout recharger à chaque retour. Les
    // routes vivent désormais dans des BRANCHES, une par onglet.
    final coquille = routeur.configuration.routes.whereType<StatefulShellRoute>().single;
    final routesDeCoquille = [
      for (final branche in coquille.branches) ...branche.routes.whereType<GoRoute>(),
    ];

    final sansTransition = routesDeCoquille
        .where((r) => r.pageBuilder == null)
        .map((r) => r.path)
        .toList();

    expect(
      sansTransition,
      isEmpty,
      reason: 'ces routes retomberaient sur la page par defaut, sans animation',
    );
    expect(coquille.branches, hasLength(4), reason: 'trois onglets + la branche du menu « Plus »');
    expect(routesDeCoquille.length, greaterThanOrEqualTo(11));

    routeur.dispose();
  });
}

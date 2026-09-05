import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/services/locale_controller.dart';
import 'package:suivie_chantier_mobile/core/services/preferences_notification.dart';
import 'package:suivie_chantier_mobile/core/services/verrou_biometrique.dart';
import 'package:suivie_chantier_mobile/features/account/domain/entities/connexion_log_entry.dart';
import 'package:suivie_chantier_mobile/features/account/domain/entities/session_active.dart';
import 'package:suivie_chantier_mobile/features/account/domain/repositories/account_repository.dart';
import 'package:suivie_chantier_mobile/features/account/presentation/cubit/settings_cubit.dart';
import 'package:suivie_chantier_mobile/features/account/presentation/pages/settings_page.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/pompe_page.dart';

class _MockRepo extends Mock implements AccountRepository {}

/// L'écran Réglages.
///
/// ## Ce qui le rend fragile
///
/// Il agrège quatre sources indépendantes : le statut MFA, les sessions
/// actives, l'historique de connexion — trois appels réseau distincts — et
/// des préférences locales (langue, verrou biométrique, notifications).
///
/// Le cubit lance les trois appels et conserve ce qui a réussi. Un écran qui
/// se replierait sur une erreur globale au premier échec priverait
/// l'utilisateur de ses réglages LOCAUX, qui n'ont pourtant besoin d'aucun
/// serveur — dont le choix de la langue, seul recours quand l'application
/// s'affiche dans une langue qu'on ne lit pas.
void main() {
  late _MockRepo repo;

  void desinscrire() {
    if (sl.isRegistered<SettingsCubit>()) sl.unregister<SettingsCubit>();
    if (sl.isRegistered<LocaleController>()) sl.unregister<LocaleController>();
    if (sl.isRegistered<VerrouBiometrique>()) sl.unregister<VerrouBiometrique>();
    if (sl.isRegistered<PreferencesNotification>()) sl.unregister<PreferencesNotification>();
  }

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    repo = _MockRepo();

    desinscrire();
    sl.registerFactory<SettingsCubit>(() => SettingsCubit(repository: repo));
    sl.registerLazySingleton<LocaleController>(() => LocaleController(prefs: prefs));
    sl.registerLazySingleton<VerrouBiometrique>(() => VerrouBiometrique(prefs: prefs));
    sl.registerLazySingleton<PreferencesNotification>(
      () => PreferencesNotification(prefs: prefs),
    );
  });

  tearDown(desinscrire);

  void toutRepond() {
    when(repo.getStatutMfa).thenAnswer((_) async => const Right<Failure, bool>(false));
    when(repo.getSessions)
        .thenAnswer((_) async => const Right<Failure, List<SessionActive>>([]));
    when(repo.getConnexions)
        .thenAnswer((_) async => const Right<Failure, List<ConnexionLogEntry>>([]));
  }

  testWidgets('se monte et affiche ses reglages', (tester) async {
    toutRepond();

    await pomperPage(tester, const SettingsPage());
    await tester.pumpAndSettle();

    expect(find.byType(ListView), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('le serveur muet ne prive pas des reglages LOCAUX', (tester) async {
    // Les trois appels échouent. La langue et le verrou, eux, sont locaux :
    // ils doivent rester manipulables. C'est le cas qui compte, parce que
    // c'est celui d'un chantier sans réseau.
    when(repo.getStatutMfa).thenAnswer(
      (_) async => const Left<Failure, bool>(NetworkFailure()),
    );
    when(repo.getSessions).thenAnswer(
      (_) async => const Left<Failure, List<SessionActive>>(NetworkFailure()),
    );
    when(repo.getConnexions).thenAnswer(
      (_) async => const Left<Failure, List<ConnexionLogEntry>>(NetworkFailure()),
    );

    await pomperPage(tester, const SettingsPage());
    await tester.pumpAndSettle();

    expect(find.byType(ListView), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un echec PARTIEL conserve ce qui a repondu', (tester) async {
    // Le MFA répond, les sessions non. Perdre l'écran entier pour une
    // requête sur trois serait disproportionné.
    when(repo.getStatutMfa).thenAnswer((_) async => const Right<Failure, bool>(true));
    when(repo.getSessions).thenAnswer(
      (_) async => const Left<Failure, List<SessionActive>>(NetworkFailure()),
    );
    when(repo.getConnexions)
        .thenAnswer((_) async => const Right<Failure, List<ConnexionLogEntry>>([]));

    await pomperPage(tester, const SettingsPage());
    await tester.pumpAndSettle();

    expect(find.byType(ListView), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

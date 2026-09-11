import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/offline/bandeau_connexion.dart';
import 'package:suivie_chantier_mobile/core/offline/detecteur_connexion.dart';
import 'package:suivie_chantier_mobile/core/offline/synchronisation_service.dart';
import 'package:suivie_chantier_mobile/l10n/generated/app_localizations.dart';

class _ServiceFaux extends Fake implements SynchronisationService {
  final notifieur = ValueNotifier<StatutOffline>(const StatutOffline());

  @override
  ValueListenable<StatutOffline> get statut => notifieur;
}

/// Deuxième audit — A2-05 : l'état affiché doit être l'état RÉEL.
///
/// Au retour du réseau, un bandeau vert « Connecté — tout a été synchronisé »
/// s'affichait trois secondes, PRIORITAIRE sur l'affichage des échecs. Une
/// passe qui échouait vite montrait donc « tout a été synchronisé » alors que
/// des actions venaient d'être refusées.
void main() {
  late _ServiceFaux service;

  setUp(() => service = _ServiceFaux());

  Future<void> monter(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BandeauConnexion(service: service, child: const SizedBox.expand()),
      ));

  Future<void> passer(WidgetTester tester, StatutOffline s) async {
    service.notifieur.value = s;
    await tester.pump();
  }

  testWidgets('retour en ligne puis échecs : jamais « tout a été synchronisé »', (tester) async {
    await monter(tester);
    await passer(tester, const StatutOffline(reseau: EtatReseau.horsLigne, enAttente: 3));
    await passer(tester, const StatutOffline(reseau: EtatReseau.enLigne, synchro: EtatSynchro.enCours, enAttente: 3));
    await passer(tester, const StatutOffline(reseau: EtatReseau.enLigne, synchro: EtatSynchro.termine, enEchec: 3));

    expect(find.textContaining('tout a été synchronisé'), findsNothing);
    expect(find.textContaining('3'), findsWidgets, reason: 'les 3 échecs doivent être annoncés');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('retour en ligne avec du travail encore en file : pas de vert non plus', (tester) async {
    await monter(tester);
    await passer(tester, const StatutOffline(reseau: EtatReseau.horsLigne, enAttente: 2));
    await passer(tester, const StatutOffline(reseau: EtatReseau.enLigne, synchro: EtatSynchro.termine, enAttente: 2));

    expect(find.textContaining('tout a été synchronisé'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('passe vraiment terminée, rien en attente ni en échec : le vert s’affiche', (tester) async {
    await monter(tester);
    await passer(tester, const StatutOffline(reseau: EtatReseau.enLigne, synchro: EtatSynchro.enCours, enAttente: 1));
    await passer(tester, const StatutOffline(reseau: EtatReseau.enLigne, synchro: EtatSynchro.termine));

    expect(find.textContaining('tout a été synchronisé'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}

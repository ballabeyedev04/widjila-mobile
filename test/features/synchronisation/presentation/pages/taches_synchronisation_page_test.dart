import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/offline/file_attente.dart';
import 'package:suivie_chantier_mobile/core/offline/synchronisation_service.dart';
import 'package:suivie_chantier_mobile/core/widgets/liste_chrome.dart';
import 'package:suivie_chantier_mobile/core/widgets/loading_list.dart';
import 'package:suivie_chantier_mobile/features/synchronisation/presentation/pages/taches_synchronisation_page.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/pompe_page.dart';

class _MockFile extends Mock implements FileAttente {}

class _MockService extends Mock implements SynchronisationService {}

/// L'écran « Tâches en attente ».
///
/// ## Ce que son état vide veut dire
///
/// Ici, la liste vide est la BONNE nouvelle : tout est parti. C'est le seul
/// écran de l'application où « rien à afficher » mérite d'être annoncé comme
/// un succès plutôt que comme un manque. Un écran blanc, lui, laisserait
/// croire que la file n'a pas su se charger — et donc que des relevés faits
/// sur le chantier dorment quelque part sans être partis.
///
/// Le second point vérifié est le désabonnement : la page s'inscrit au
/// `ValueListenable` du service de synchronisation dans `initState` et doit
/// s'en retirer dans `dispose`. Un écouteur oublié rappelle `setState` sur un
/// widget démonté — une exception qui ne se voit qu'après avoir quitté
/// l'écran, c'est-à-dire là où personne ne la relie à cette page.
void main() {
  late _MockFile file;
  late _MockService service;
  late ValueNotifier<StatutOffline> statut;

  void desinscrire() {
    if (sl.isRegistered<FileAttente>()) sl.unregister<FileAttente>();
    if (sl.isRegistered<SynchronisationService>()) sl.unregister<SynchronisationService>();
  }

  setUp(() {
    file = _MockFile();
    service = _MockService();
    statut = ValueNotifier<StatutOffline>(const StatutOffline());
    when(() => service.statut).thenReturn(statut);

    desinscrire();
    sl.registerLazySingleton<FileAttente>(() => file);
    sl.registerLazySingleton<SynchronisationService>(() => service);
  });

  tearDown(() {
    desinscrire();
    statut.dispose();
  });

  ActionEnAttente tache(String id) => ActionEnAttente(
        id: id,
        type: TypeAction.creerReserve,
        charge: const {'titre': 'Fissure relevee hors ligne'},
        creeLe: DateTime(2026, 7, 1),
        statut: ActionEnAttente.statutAttente,
      );

  testWidgets('file vide : le message annonce que TOUT est parti', (tester) async {
    when(file.toutesLesTaches).thenAnswer((_) async => const <ActionEnAttente>[]);

    await pomperPage(tester, const TachesSynchronisationPage());
    await tester.pumpAndSettle();

    expect(find.byType(EtatVideIllustre), findsOneWidget);
    expect(find.byType(LoadingList), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('des taches en attente : elles sont nommees, pas comptees',
      (tester) async {
    // Un compteur (« 3 en attente ») ne dit pas CE QUI attend. Sur un
    // chantier, savoir que c'est la fissure relevée ce matin qui n'est pas
    // partie change ce qu'on fait ensuite.
    when(file.toutesLesTaches)
        .thenAnswer((_) async => [tache('a'), tache('b')]);

    await pomperPage(tester, const TachesSynchronisationPage());
    await tester.pumpAndSettle();

    expect(find.text('Fissure relevee hors ligne'), findsNWidgets(2));
    expect(find.byType(EtatVideIllustre), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('une synchronisation en tache de fond rafraichit la liste',
      (tester) async {
    // La file peut se vider PENDANT que l'écran est ouvert : la page écoute
    // le service plutôt que de figer sa liste au premier chargement.
    when(file.toutesLesTaches).thenAnswer((_) async => [tache('a')]);

    await pomperPage(tester, const TachesSynchronisationPage());
    await tester.pumpAndSettle();
    expect(find.byType(EtatVideIllustre), findsNothing);

    // Le service annonce que la file est retombee a zero. La valeur doit
    // etre DIFFERENTE de la precedente : `ValueNotifier` ne previent personne
    // quand on lui repose la meme, et deux `const StatutOffline()` identiques
    // sont le meme objet.
    when(file.toutesLesTaches).thenAnswer((_) async => const <ActionEnAttente>[]);
    statut.value = const StatutOffline(enAttente: 0, enEchec: 0, synchro: EtatSynchro.termine);
    await tester.pumpAndSettle();

    expect(find.byType(EtatVideIllustre), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quitter l ecran retire l ecouteur', (tester) async {
    when(file.toutesLesTaches).thenAnswer((_) async => const <ActionEnAttente>[]);

    await pomperPage(tester, const TachesSynchronisationPage());
    await tester.pumpAndSettle();

    // Démonte la page, puis provoque un changement de statut. Si l'écouteur
    // survivait, `setState` serait appelé sur un widget mort.
    await tester.pumpWidget(const SizedBox.shrink());
    statut.value = const StatutOffline(enAttente: 7);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

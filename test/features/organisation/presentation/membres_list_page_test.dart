import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/organisation/domain/entities/membre.dart';
import 'package:suivie_chantier_mobile/features/organisation/domain/usecases/ajouter_membre.dart';
import 'package:suivie_chantier_mobile/features/organisation/domain/usecases/changer_statut_membre.dart';
import 'package:suivie_chantier_mobile/features/organisation/domain/usecases/get_membres.dart';
import 'package:suivie_chantier_mobile/features/organisation/presentation/cubit/membres_cubit.dart';
import 'package:suivie_chantier_mobile/features/organisation/presentation/pages/membres_list_page.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../helpers/l10n_test_helpers.dart';

class _MockGetMembres extends Mock implements GetMembres {}

class _MockAjouter extends Mock implements AjouterMembre {}

class _MockStatut extends Mock implements ChangerStatutMembre {}

Membre _membre(String id) => Membre(
      id: id,
      nom: 'DIOP',
      prenom: 'Abdou',
      email: '$id@widjila.com',
      role: UserRole.conducteurTravaux,
      fonction: 'Conducteur de travaux',
      dernierConnexion: DateTime(2026, 8, 30),
    );

/// L'écran « Équipe ».
///
/// ## Ce qui s'était cassé
///
/// L'en-tête annonçait « 2 membres dans l'équipe » et la zone en dessous
/// restait vide. La cause tenait à cette ligne d'en-tête elle-même : son `Row`
/// posait un `Text` sans `Expanded`, donc sans autorisation de rétrécir. Dès
/// que la phrase traduite dépassait la largeur disponible — écran étroit,
/// langue plus verbeuse, taille de police agrandie dans les réglages du
/// téléphone — la mise en page échouait et Flutter levait à chaque image.
///
/// D'où un test qui pompe l'écran ENTIER à plusieurs largeurs et refuse la
/// moindre exception du framework : une assertion sur « la liste contient deux
/// noms » aurait continué de passer pendant que l'écran restait illisible.
void main() {
  late _MockGetMembres getMembres;
  late _MockAjouter ajouterMembre;
  late MembresCubit cubit;

  setUpAll(() => registerFallbackValue(UserRole.conducteurTravaux));

  setUp(() {
    getMembres = _MockGetMembres();
    ajouterMembre = _MockAjouter();
    when(() => getMembres()).thenAnswer(
      (_) async => Right<Failure, List<Membre>>([_membre('a'), _membre('b')]),
    );

    cubit = MembresCubit(
      getMembres: getMembres,
      ajouterMembreUsecase: ajouterMembre,
      changerStatutMembreUsecase: _MockStatut(),
    );

    // Singleton et non fabrique : le test doit piloter EXACTEMENT le cubit que
    // la page écoute, pour déclencher un ajout comme le ferait le formulaire.
    if (sl.isRegistered<MembresCubit>()) sl.unregister<MembresCubit>();
    sl.registerSingleton<MembresCubit>(cubit);
  });

  tearDown(() {
    if (sl.isRegistered<MembresCubit>()) sl.unregister<MembresCubit>();
  });

  Future<List<FlutterErrorDetails>> pomper(WidgetTester tester, {double largeur = 390}) async {
    tester.view.physicalSize = Size(largeur, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final erreurs = <FlutterErrorDetails>[];
    final precedent = FlutterError.onError;
    FlutterError.onError = erreurs.add;

    await tester.pumpWidget(MaterialApp(
      locale: testLocale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: const MembresListPage(),
    ));
    await tester.pumpAndSettle();

    FlutterError.onError = precedent;
    return erreurs;
  }

  group('rendu de la liste', () {
    // 320 dp est le plus étroit encore en circulation ; 430 celui d'un grand
    // téléphone récent. Entre les deux, l'essentiel du parc.
    for (final largeur in [320.0, 360.0, 390.0, 430.0]) {
      testWidgets('affiche les membres sans exception à $largeur dp', (tester) async {
        final erreurs = await pomper(tester, largeur: largeur);

        expect(
          erreurs.map((e) => e.exceptionAsString()).toList(),
          isEmpty,
          reason: 'une exception de mise en page laisse la zone vide, '
              'alors même que le compteur annonce des membres',
        );
        expect(find.text('Abdou DIOP'), findsNWidgets(2));
      });
    }
  });

  group('après l’ajout d’un membre', () {
    void repondAjout({required bool emailEnvoye, String? motDePasse}) {
      when(() => ajouterMembre(
            nom: any(named: 'nom'),
            prenom: any(named: 'prenom'),
            email: any(named: 'email'),
            role: any(named: 'role'),
            telephone: any(named: 'telephone'),
            fonction: any(named: 'fonction'),
            motDePasse: any(named: 'motDePasse'),
          )).thenAnswer((_) async => Right<Failure, AjouterMembreResult>(
            AjouterMembreResult(
              membre: _membre('nouveau'),
              motDePasseTemporaire: motDePasse,
              emailEnvoye: emailEnvoye,
            ),
          ));
    }

    Future<void> declencherAjout(WidgetTester tester) async {
      await cubit.ajouter(
        nom: 'DIOP',
        prenom: 'Abdou',
        email: 'abdou@widjila.com',
        role: UserRole.conducteurTravaux,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('le mot de passe n’est PAS affiché quand le courriel est parti', (tester) async {
      repondAjout(emailEnvoye: true, motDePasse: 'abc123def456');
      await pomper(tester);
      await declencherAjout(tester);

      // La fenêtre « J'ai noté » ne doit plus paraître : le nouveau membre a
      // reçu ses identifiants à son adresse, et les remontrer ici ne ferait
      // que les faire circuler davantage.
      expect(find.text('abc123def456'), findsNothing);
    });

    testWidgets('le mot de passe REPARAÎT si le courriel a échoué', (tester) async {
      repondAjout(emailEnvoye: false, motDePasse: 'abc123def456');
      await pomper(tester);
      await declencherAjout(tester);

      // C'est alors la DERNIÈRE occasion de le lire — le serveur ne le
      // conserve qu'en empreinte. Le taire perdrait le compte.
      expect(find.text('abc123def456'), findsOneWidget);
    });
  });
}

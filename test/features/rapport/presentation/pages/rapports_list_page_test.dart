import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/widgets/error_view.dart';
import 'package:suivie_chantier_mobile/core/widgets/loading_list.dart';
import 'package:suivie_chantier_mobile/core/services/ouverture_fichier.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/envoi_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/usecases/rapport_usecases.dart';
import 'package:suivie_chantier_mobile/features/rapport/presentation/pages/rapports_list_page.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/balayage_responsive.dart';
import '../../../../helpers/pompe_page.dart';

class _MockGetRapports extends Mock implements GetRapports {}

class _MockGenerer extends Mock implements GenererRapport {}

class _MockSupprimer extends Mock implements SupprimerRapport {}

class _MockOuverture extends Mock implements OuvertureFichier {}

class _MockPreparerEnvoi extends Mock implements PreparerEnvoiRapport {}

class _MockEnvoyer extends Mock implements EnvoyerRapport {}

/// L'écran Rapports, dans ses quatre situations.
///
/// ## Ce que ce test protège
///
/// La page construit son cubit à partir de trois cas d'usage résolus dans
/// `sl` AU MOMENT DU `build`. Une dépendance oubliée à l'enregistrement ne se
/// voit ni à l'analyse, ni à la compilation : elle jette un
/// `StateError` de get_it la première fois qu'un utilisateur ouvre l'écran.
/// Monter réellement la page est la seule façon de s'en apercevoir avant lui.
///
/// Les quatre situations valent chacune pour elle-même : une liste vide n'est
/// pas une panne, une panne n'est pas une liste vide, et confondre les deux
/// est le défaut le plus courant de ces écrans.
void main() {
  late _MockGetRapports getRapports;
  late _MockPreparerEnvoi preparerEnvoi;
  late _MockEnvoyer envoyer;

  Rapport rapport(String id) => Rapport(
        id: id,
        chantierId: 'c1',
        fichierUrl: 'https://exemple.test/$id.pdf',
        createdAt: DateTime(2026, 3, 14),
      );

  setUp(() {
    getRapports = _MockGetRapports();
    preparerEnvoi = _MockPreparerEnvoi();
    envoyer = _MockEnvoyer();

    for (final desinscrire in [
      () => sl.isRegistered<PreparerEnvoiRapport>() ? sl.unregister<PreparerEnvoiRapport>() : null,
      () => sl.isRegistered<EnvoyerRapport>() ? sl.unregister<EnvoyerRapport>() : null,
      () => sl.isRegistered<GetRapports>() ? sl.unregister<GetRapports>() : null,
      () => sl.isRegistered<GenererRapport>() ? sl.unregister<GenererRapport>() : null,
      () => sl.isRegistered<SupprimerRapport>() ? sl.unregister<SupprimerRapport>() : null,
      () => sl.isRegistered<OuvertureFichier>() ? sl.unregister<OuvertureFichier>() : null,
    ]) {
      desinscrire();
    }

    sl.registerFactory<GetRapports>(() => getRapports);
    sl.registerFactory<GenererRapport>(() => _MockGenerer());
    sl.registerFactory<SupprimerRapport>(() => _MockSupprimer());
    sl.registerLazySingleton<OuvertureFichier>(() => _MockOuverture());
    sl.registerFactory<PreparerEnvoiRapport>(() => preparerEnvoi);
    sl.registerFactory<EnvoyerRapport>(() => envoyer);
  });

  tearDown(() {
    if (sl.isRegistered<GetRapports>()) sl.unregister<GetRapports>();
    if (sl.isRegistered<GenererRapport>()) sl.unregister<GenererRapport>();
    if (sl.isRegistered<SupprimerRapport>()) sl.unregister<SupprimerRapport>();
    if (sl.isRegistered<OuvertureFichier>()) sl.unregister<OuvertureFichier>();
    if (sl.isRegistered<PreparerEnvoiRapport>()) sl.unregister<PreparerEnvoiRapport>();
    if (sl.isRegistered<EnvoyerRapport>()) sl.unregister<EnvoyerRapport>();
  });

  const page = RapportsListPage(chantierId: 'c1', chantierNom: 'Résidence Les Cèdres');

  testWidgets('affiche un indicateur pendant le chargement', (tester) async {
    final attente = Completer<Either<Failure, List<Rapport>>>();
    when(() => getRapports(any())).thenAnswer((_) => attente.future);

    await pomperPage(tester, page);

    // Un squelette de liste, pas une roue au milieu du vide : l'écran
    // annonce la forme de ce qui arrive.
    expect(find.byType(LoadingList), findsOneWidget);
    expect(tester.takeException(), isNull);

    attente.complete(const Right([]));
    await tester.pumpAndSettle();
  });

  testWidgets('liste vide : un message qui EXPLIQUE, pas un écran blanc', (tester) async {
    when(() => getRapports(any()))
        .thenAnswer((_) async => const Right<Failure, List<Rapport>>([]));

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.text('Aucun rapport'), findsOneWidget);
    // Le titre seul laisserait l'utilisateur devant un constat. La phrase
    // suivante lui dit ce qu'il peut faire.
    expect(find.textContaining('rapport PDF'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panne serveur : l’écran ne se fait pas passer pour vide', (tester) async {
    when(() => getRapports(any())).thenAnswer(
      (_) async => const Left<Failure, List<Rapport>>(ServerFailure(errorMessage: 'Service indisponible')),
    );

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    // Le mot « Aucun rapport » serait un mensonge : le serveur n'a rien dit.
    expect(find.text('Aucun rapport'), findsNothing);
    expect(find.byType(ErrorView), findsOneWidget);
    // Et l'utilisateur doit pouvoir réessayer sans quitter l'écran.
    expect(find.text('Réessayer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('affiche les rapports reçus', (tester) async {
    when(() => getRapports(any())).thenAnswer(
      (_) async => Right<Failure, List<Rapport>>([rapport('r1'), rapport('r2')]),
    );

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.text('Aucun rapport'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('envoi du rapport par e-mail', () {
    /// Ce que le serveur renvoie quand on PRÉPARE l'envoi — sans rien envoyer.
    EnvoiRapport envoiPrepare() => const EnvoiRapport(
          rapportId: 'r1',
          chantierNom: 'Résidence Les Cèdres',
          objet: 'Rapport de chantier – Résidence Les Cèdres – 14/03/2026',
          message: 'Bonjour,\n\nVeuillez trouver en pièce jointe le rapport.',
          expediteur: 'Balla Beye',
          nbReserves: 12,
          destinataires: [
            DestinataireRapport(id: 'p1', nom: 'SARL Toiture', email: 'toiture@ex.fr'),
            DestinataireRapport(id: 'p2', nom: 'Plomberie Diop', email: 'plomberie@ex.fr'),
          ],
          copies: [DestinataireRapport(id: 'c1', nom: 'MOA Sénégal', email: 'moa@ex.fr')],
          sansEmail: ['Électricité Fall'],
          pieceJointeNom: 'rapport-LC-2026.pdf',
        );

    setUp(() {
      when(() => getRapports(any())).thenAnswer(
        (_) async => Right<Failure, List<Rapport>>([rapport('r1')]),
      );
      when(() => preparerEnvoi(any()))
          .thenAnswer((_) async => Right<Failure, EnvoiRapport>(envoiPrepare()));
      when(() => envoyer(any(), exclure: any(named: 'exclure')))
          .thenAnswer((_) async => const Right<Failure, String>('Rapport envoyé à 2 entreprise(s).'));
    });

    /// Ouvre le menu de la carte puis l'entrée « Envoyer par e-mail ».
    Future<void> ouvrirFeuilleEnvoi(WidgetTester tester) async {
      await pomperPage(tester, page);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Envoyer par e-mail'));
      await tester.pumpAndSettle();
    }

    testWidgets('OUVRIR la feuille prépare le message mais N’ENVOIE RIEN', (tester) async {
      await ouvrirFeuilleEnvoi(tester);

      verify(() => preparerEnvoi('r1')).called(1);
      // La garantie que le client a demandée : rien ne part sans validation.
      verifyNever(() => envoyer(any(), exclure: any(named: 'exclure')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('montre l’entreprise, les clients en copie, l’objet et la pièce jointe',
        (tester) async {
      await ouvrirFeuilleEnvoi(tester);

      expect(find.text('SARL Toiture'), findsOneWidget);
      expect(find.text('toiture@ex.fr'), findsOneWidget);
      expect(find.text('MOA Sénégal'), findsOneWidget);
      expect(find.text('rapport-LC-2026.pdf'), findsOneWidget);
      expect(find.textContaining('Rapport de chantier – Résidence Les Cèdres'), findsOneWidget);
    });

    testWidgets('signale NOMMÉMENT les partenaires sans adresse e-mail', (tester) async {
      await ouvrirFeuilleEnvoi(tester);

      expect(find.textContaining('Électricité Fall'), findsOneWidget);
    });

    testWidgets('n’envoie qu’au appui sur « Envoyer »', (tester) async {
      await ouvrirFeuilleEnvoi(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Envoyer'));
      await tester.pumpAndSettle();

      verify(() => envoyer('r1', exclure: const [])).called(1);
    });

    testWidgets('décocher une adresse la transmet en RETRAIT, pas en ajout', (tester) async {
      await ouvrirFeuilleEnvoi(tester);

      // La deuxième case est celle de « Plomberie Diop ».
      await tester.tap(find.byType(CheckboxListTile).at(1));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Envoyer'));
      await tester.pumpAndSettle();

      verify(() => envoyer('r1', exclure: const ['plomberie@ex.fr'])).called(1);
    });

    testWidgets('sans destinataire principal restant, l’envoi est impossible', (tester) async {
      await ouvrirFeuilleEnvoi(tester);

      await tester.tap(find.byType(CheckboxListTile).at(0));
      await tester.tap(find.byType(CheckboxListTile).at(1));
      await tester.pumpAndSettle();

      final bouton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Envoyer'));
      expect(bouton.onPressed, isNull);
      verifyNever(() => envoyer(any(), exclure: any(named: 'exclure')));
    });

    testWidgets('un échec de préparation est EXPLIQUÉ, pas masqué', (tester) async {
      when(() => preparerEnvoi(any())).thenAnswer(
        (_) async => const Left<Failure, EnvoiRapport>(
          ServerFailure(errorMessage: 'Rapport introuvable dans cette organisation'),
        ),
      );

      await ouvrirFeuilleEnvoi(tester);

      expect(find.textContaining('introuvable'), findsOneWidget);
      verifyNever(() => envoyer(any(), exclure: any(named: 'exclure')));
    });

    testWidgets('un échec d’envoi laisse la feuille ouverte, avec le motif', (tester) async {
      when(() => envoyer(any(), exclure: any(named: 'exclure'))).thenAnswer(
        (_) async => const Left<Failure, String>(
          ServerFailure(errorMessage: 'Aucune adresse e-mail pour : SARL Toiture.'),
        ),
      );

      await ouvrirFeuilleEnvoi(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Envoyer'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Aucune adresse e-mail'), findsOneWidget);
      // La feuille reste ouverte : l'utilisateur peut corriger sa sélection.
      expect(find.text('SARL Toiture'), findsOneWidget);
    });

    testWidgets('un rôle sans pilotage ne se voit PAS proposer l’envoi', (tester) async {
      await pomperPage(tester, page, role: UserRole.sousTraitant);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
      expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);
    });
  });

  group('mise en page — balayage des formats', () {
    // Un ecran dessine sur un telephone de 390 dp passe presque toujours a
    // 390 dp. Les debordements se produisent aux EXTREMES : sur un petit
    // Android de 320 dp encore courant sur les chantiers, et sur une tablette
    // ou une rangee concue serree se distend.
    //
    // `flutter_test` remonte un `RenderFlex overflowed` comme une exception :
    // pomper l'ecran a chaque format et verifier qu'aucune n'a ete levee
    // transforme l'audit visuel en mesure repetable.
    for (final format in tousLesFormats) {
      testWidgets('sans debordement sur $format', (tester) async {
        when(() => getRapports(any())).thenAnswer(
          (_) async => Right<Failure, List<Rapport>>([rapport('r1'), rapport('r2')]),
        );

        await pomperPage(tester, page, taille: format.taille);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'debordement de mise en page sur $format');
      });
    }
  });
}

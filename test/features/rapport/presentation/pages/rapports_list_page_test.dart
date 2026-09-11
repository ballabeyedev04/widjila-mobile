import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/services/ouverture_fichier.dart';
import 'package:suivie_chantier_mobile/core/widgets/error_view.dart';
import 'package:suivie_chantier_mobile/core/widgets/loading_list.dart';
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

/// L'écran Rapports d'un chantier.
///
/// La page construit son cubit à partir de cas d'usage résolus dans `sl` AU
/// MOMENT DU `build` : une dépendance oubliée ne se voit qu'en montant
/// réellement la page. Les quatre situations — chargement, vide, panne,
/// liste — valent chacune pour elle-même : une liste vide n'est pas une
/// panne, et les confondre est le défaut le plus courant de ces écrans.
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

  setUpAll(() => registerFallbackValue(const DemandeEnvoiRapport()));

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

    expect(find.byType(LoadingList), findsOneWidget);
    expect(tester.takeException(), isNull);

    attente.complete(const Right([]));
    await tester.pumpAndSettle();
  });

  testWidgets('liste vide : un message qui EXPLIQUE, pas un écran blanc', (tester) async {
    when(() => getRapports(any())).thenAnswer((_) async => const Right<Failure, List<Rapport>>([]));

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.text('Aucun rapport'), findsOneWidget);
    expect(find.textContaining('rapport PDF'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panne serveur : l’écran ne se fait pas passer pour vide', (tester) async {
    when(() => getRapports(any())).thenAnswer(
      (_) async => const Left<Failure, List<Rapport>>(ServerFailure(errorMessage: 'Service indisponible')),
    );

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.text('Aucun rapport'), findsNothing);
    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('affiche les rapports reçus, avec leur état', (tester) async {
    when(() => getRapports(any())).thenAnswer(
      (_) async => Right<Failure, List<Rapport>>([rapport('r1'), rapport('r2')]),
    );

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.text('Aucun rapport'), findsNothing);
    // Un rapport antérieur au module est un rapport GÉNÉRÉ (§ 19).
    expect(find.textContaining('Généré'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  group('§ 3 — « + Nouveau rapport »', () {
    setUp(() {
      when(() => getRapports(any())).thenAnswer((_) async => const Right<Failure, List<Rapport>>([]));
    });

    testWidgets('proposé au pilotage', (tester) async {
      await pomperPage(tester, page, role: UserRole.conducteurTravaux);
      await tester.pumpAndSettle();

      expect(find.text('Nouveau rapport'), findsOneWidget);
    });

    testWidgets('PAS proposé à un rôle qui ne pilote pas — le serveur le refuserait', (tester) async {
      await pomperPage(tester, page, role: UserRole.sousTraitant);
      await tester.pumpAndSettle();

      expect(find.text('Nouveau rapport'), findsNothing);
    });
  });

  group('§ 13 — envoi du rapport par e-mail', () {
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
          candidats: [
            DestinataireRapport(id: 'p1', nom: 'SARL Toiture', email: 'toiture@ex.fr', type: 'partenaire'),
            DestinataireRapport(id: 'u1', nom: 'Awa Diop', email: 'awa@widjila.com', type: 'membre'),
          ],
          sansEmail: ['Électricité Fall'],
          pieceJointeNom: 'rapport-LC-2026.pdf',
        );

    setUp(() {
      when(() => getRapports(any())).thenAnswer((_) async => Right<Failure, List<Rapport>>([rapport('r1')]));
      when(() => preparerEnvoi(any())).thenAnswer((_) async => Right<Failure, EnvoiRapport>(envoiPrepare()));
      when(() => envoyer(any(), any())).thenAnswer(
        (_) async => const Right<Failure, ResultatEnvoiRapport>(
          ResultatEnvoiRapport(message: 'Rapport envoyé à 2 destinataire(s).'),
        ),
      );
    });

    /// Ouvre le menu de la carte puis l'entrée « Envoyer par e-mail ».
    Future<void> ouvrirFeuilleEnvoi(WidgetTester tester) async {
      await pomperPage(tester, page, taille: const Size(420, 1400));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Envoyer par e-mail'));
      await tester.pumpAndSettle();
    }

    testWidgets('OUVRIR la feuille prépare le message mais N’ENVOIE RIEN', (tester) async {
      await ouvrirFeuilleEnvoi(tester);

      verify(() => preparerEnvoi('r1')).called(1);
      verifyNever(() => envoyer(any(), any()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('montre les entreprises, les clients en copie, l’objet et la pièce jointe', (tester) async {
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

    testWidgets('sans modification, seule la liste des retraits part', (tester) async {
      await ouvrirFeuilleEnvoi(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Envoyer'));
      await tester.pumpAndSettle();

      verify(() => envoyer('r1', const DemandeEnvoiRapport())).called(1);
    });

    testWidgets('décocher une adresse la transmet en RETRAIT, pas en ajout', (tester) async {
      await ouvrirFeuilleEnvoi(tester);

      // La deuxième case est celle de « Plomberie Diop ».
      await tester.tap(find.byType(CheckboxListTile).at(1));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Envoyer'));
      await tester.pumpAndSettle();

      verify(() => envoyer('r1', const DemandeEnvoiRapport(exclure: ['plomberie@ex.fr']))).called(1);
    });

    testWidgets('retoucher l’objet transmet les listes complètes — le serveur les vérifie', (tester) async {
      await ouvrirFeuilleEnvoi(tester);

      final objet = find.byType(TextField).first;
      await tester.ensureVisible(objet);
      await tester.enterText(objet, 'OPR — réserves à lever');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Envoyer'));
      await tester.pumpAndSettle();

      verify(() => envoyer(
            'r1',
            const DemandeEnvoiRapport(
              destinataires: ['toiture@ex.fr', 'plomberie@ex.fr'],
              copies: ['moa@ex.fr'],
              objet: 'OPR — réserves à lever',
            ),
          )).called(1);
    });

    testWidgets('seuls les candidats DU CHANTIER peuvent être ajoutés', (tester) async {
      await ouvrirFeuilleEnvoi(tester);

      await tester.ensureVisible(find.text('Ajouter un destinataire'));
      await tester.tap(find.text('Ajouter un destinataire'));
      await tester.pumpAndSettle();

      // Awa Diop est proposée ; SARL Toiture, déjà destinataire, ne l'est pas deux fois.
      expect(find.text('awa@widjila.com'), findsOneWidget);
      await tester.tap(find.text('Awa Diop'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Envoyer'));
      await tester.pumpAndSettle();

      verify(() => envoyer(
            'r1',
            const DemandeEnvoiRapport(
              destinataires: ['toiture@ex.fr', 'plomberie@ex.fr', 'awa@widjila.com'],
              copies: ['moa@ex.fr'],
            ),
          )).called(1);
    });

    testWidgets('sans destinataire principal restant, l’envoi est impossible', (tester) async {
      await ouvrirFeuilleEnvoi(tester);

      await tester.tap(find.byType(CheckboxListTile).at(0));
      await tester.tap(find.byType(CheckboxListTile).at(1));
      await tester.pumpAndSettle();

      final bouton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Envoyer'));
      expect(bouton.onPressed, isNull);
      verifyNever(() => envoyer(any(), any()));
    });

    testWidgets('§ 22 — hors ligne, l’envoi est MIS EN FILE et l’écran le dit', (tester) async {
      when(() => envoyer(any(), any())).thenAnswer(
        (_) async => const Right<Failure, ResultatEnvoiRapport>(ResultatEnvoiRapport(message: '', enFileAttente: true)),
      );
      await ouvrirFeuilleEnvoi(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Envoyer'));
      await tester.pumpAndSettle();

      expect(find.textContaining('file d’attente'), findsOneWidget);
    });

    testWidgets('un échec de préparation est EXPLIQUÉ, pas masqué', (tester) async {
      when(() => preparerEnvoi(any())).thenAnswer(
        (_) async => const Left<Failure, EnvoiRapport>(
          ServerFailure(errorMessage: 'Rapport introuvable dans cette organisation'),
        ),
      );

      await ouvrirFeuilleEnvoi(tester);

      expect(find.textContaining('introuvable'), findsOneWidget);
      verifyNever(() => envoyer(any(), any()));
    });

    testWidgets('un échec d’envoi laisse la feuille ouverte, avec le motif', (tester) async {
      when(() => envoyer(any(), any())).thenAnswer(
        (_) async => const Left<Failure, ResultatEnvoiRapport>(
          ServerFailure(errorMessage: 'Aucune adresse e-mail pour : SARL Toiture.'),
        ),
      );

      await ouvrirFeuilleEnvoi(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Envoyer'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Aucune adresse e-mail'), findsOneWidget);
      expect(find.text('SARL Toiture'), findsOneWidget);
    });

    testWidgets('un rôle sans pilotage ne se voit PAS proposer l’envoi', (tester) async {
      await pomperPage(tester, page, role: UserRole.sousTraitant);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Télécharger'), findsOneWidget);
      expect(find.byIcon(Icons.mail_outline_rounded), findsNothing);
    });
  });

  group('mise en page — balayage des formats', () {
    for (final format in tousLesFormats) {
      testWidgets('sans debordement sur $format', (tester) async {
        when(() => getRapports(any())).thenAnswer(
          (_) async => Right<Failure, List<Rapport>>([rapport('r1'), rapport('r2')]),
        );

        await pomperPage(tester, page, taille: format.taille);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'debordement de mise en page sur $format');
      });
    }
  });
}

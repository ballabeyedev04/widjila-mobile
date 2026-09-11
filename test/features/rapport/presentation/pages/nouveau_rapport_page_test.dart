import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/theme/app_theme.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/configuration_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/etat_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/modele_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/option_filtre.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/suivi_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/repositories/rapport_repository.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/usecases/rapport_usecases.dart';
import 'package:suivie_chantier_mobile/features/rapport/presentation/pages/nouveau_rapport_page.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/chantier_structure.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_chantier_structure.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/pompe_page.dart';

class _MockRepository extends Mock implements RapportRepository {}

class _MockStructure extends Mock implements GetChantierStructure {}

/// Ouvre la page testée par-dessus un écran de lancement, pour pouvoir
/// constater ce qu'elle RENVOIE en se fermant — le rapport généré.
class _Lanceur extends StatelessWidget {
  final Widget page;
  final void Function(Object?) surRetour;
  const _Lanceur({required this.page, required this.surRetour});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async =>
                surRetour(await Navigator.of(context).push<Object?>(MaterialPageRoute<Object?>(builder: (_) => page))),
            child: const Text('ouvrir'),
          ),
        ),
      );
}

/// L'assistant « + Nouveau rapport », monté pour de vrai : le parcours du
/// § 3 du cahier des charges, écran par écran.
void main() {
  late _MockRepository repository;
  late _MockStructure getStructure;

  const brouillon = Rapport(id: 'r1', chantierId: 'c1', fichierUrl: '', etat: EtatRapport.brouillon);
  const genere = Rapport(id: 'r1', chantierId: 'c1', fichierUrl: '/uploads/rapports/r1.pdf');

  // Une surface HAUTE : chaque étape tient sans défilement, ce qui garde les
  // tests centrés sur le parcours plutôt que sur le défilement.
  const surface = Size(420, 2200);

  void enregistrer<T extends Object>(T instance) {
    if (sl.isRegistered<T>()) sl.unregister<T>();
    sl.registerFactory<T>(() => instance);
  }

  setUpAll(() => registerFallbackValue(const ConfigurationRapport(chantierId: 'c', modele: ModeleRapport.global)));

  setUp(() {
    repository = _MockRepository();
    getStructure = _MockStructure();

    when(() => getStructure(any())).thenAnswer((_) async => const Right(ChantierStructure(batiments: [
          BatimentStructure(id: 'bA', nom: 'A', etages: [EtageStructure(id: 'eA1', nom: 'R+1')]),
          BatimentStructure(id: 'bB', nom: 'B'),
        ])));
    when(() => repository.getOptionsFiltres(any())).thenAnswer((_) async => const Right(OptionsFiltresRapport(
          entreprises: [OptionFiltre(id: 'p1', nom: 'ABC Carrelage')],
          corpsEtat: [OptionFiltre(id: 'ce1', nom: 'Plomberie')],
        )));
    when(() => repository.getProjets()).thenAnswer((_) async => const Right([
          OptionFiltre(id: 'c1', nom: 'Résidence Les Jardins', detail: 'RJ-2026'),
        ]));
    when(() => repository.creerRapport(any())).thenAnswer((_) async => const Right(brouillon));
    when(() => repository.modifierRapport(any(), any())).thenAnswer((_) async => const Right(brouillon));
    when(() => repository.resumeRapport(any())).thenAnswer((_) async => const Right(ResumeRapport(
          total: 12,
          parStatut: {StatutReserveRapport.aTraiter: 12},
          entreprises: 1,
        )));
    when(() => repository.genererRapportConfigure(any())).thenAnswer((_) async => const Right(genere));

    enregistrer<GetChantierStructure>(getStructure);
    enregistrer<GetOptionsFiltresRapport>(GetOptionsFiltresRapport(repository));
    enregistrer<GetProjetsRapport>(GetProjetsRapport(repository));
    enregistrer<CreerRapport>(CreerRapport(repository));
    enregistrer<ModifierRapport>(ModifierRapport(repository));
    enregistrer<CalculerResumeRapport>(CalculerResumeRapport(repository));
    enregistrer<GenererRapportConfigure>(GenererRapportConfigure(repository));
  });

  Finder suivant() => find.widgetWithText(FilledButton, 'Suivant');

  testWidgets('parcours complet : modèle → filtres → sections → aperçu → génération', (tester) async {
    Object? retour;
    await pomperPage(
      tester,
      _Lanceur(
        page: const NouveauRapportPage(chantierId: 'c1', chantierNom: 'Résidence Les Jardins'),
        surRetour: (r) => retour = r,
      ),
      taille: surface,
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();

    // ── Modèle (§ 5) ─────────────────────────────────────────────────────
    expect(find.text('Choisissez un modèle'), findsOneWidget);
    for (final titre in [
      'Rapport global du chantier', 'Rapport par bâtiment', 'Rapport par étage / zone',
      'Rapport par entreprise', 'Rapport par corps d’état', 'Rapport des réserves à traiter',
      'Rapport des réserves levées', 'Rapport OPR / réception',
    ]) {
      expect(find.text(titre), findsOneWidget, reason: titre);
    }
    // Sans modèle choisi, impossible d'avancer.
    expect(tester.widget<FilledButton>(suivant()).onPressed, isNull);

    await tester.tap(find.text('Rapport par bâtiment'));
    await tester.pumpAndSettle();
    await tester.tap(suivant());
    await tester.pumpAndSettle();

    // ── Filtres (§ 4) ────────────────────────────────────────────────────
    for (final titre in ['Bâtiment', 'Niveau', 'Entreprise', 'Corps d’état', 'Statut', 'Gravité', 'Période']) {
      expect(find.text(titre), findsWidgets, reason: titre);
    }
    expect(find.text('Obligatoire pour ce modèle'), findsOneWidget);

    await tester.tap(suivant());
    await tester.pumpAndSettle();
    expect(find.text('Choisissez au moins un bâtiment pour ce modèle.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'A'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'À traiter'));
    await tester.pumpAndSettle();
    await tester.tap(suivant());
    await tester.pumpAndSettle();

    // ── Sections (§ 10) ──────────────────────────────────────────────────
    for (final titre in ['Synthèse', 'Plans', 'Photos', 'Localisation', 'Historique']) {
      expect(find.text(titre), findsOneWidget, reason: titre);
    }
    await tester.tap(find.widgetWithText(FilterChip, 'Excel'));
    await tester.pumpAndSettle();
    await tester.tap(suivant());
    await tester.pumpAndSettle();

    // ── Aperçu (§ 20) ────────────────────────────────────────────────────
    expect(find.text('12 réserve(s) dans ce périmètre'), findsOneWidget);
    final config = verify(() => repository.creerRapport(captureAny())).captured.single as ConfigurationRapport;
    expect(config.modele, ModeleRapport.batiment);
    expect(config.filtres.batiments, ['bA']);
    expect(config.filtres.statuts, [StatutReserveRapport.aTraiter]);
    expect(config.formats, {FormatRapport.pdf, FormatRapport.xlsx});

    // ── Génération (§ 11) ────────────────────────────────────────────────
    await tester.tap(find.text('Générer le rapport'));
    await tester.pumpAndSettle();

    verify(() => repository.genererRapportConfigure('r1')).called(1);
    expect(retour, genere, reason: 'l’assistant se ferme sur le rapport généré');
    expect(tester.takeException(), isNull);
  });

  testWidgets('hors d’un chantier, le parcours commence par le PROJET', (tester) async {
    await pomperPage(tester, const NouveauRapportPage(), taille: surface);
    await tester.pumpAndSettle();

    expect(find.text('Choisissez le projet'), findsOneWidget);
    expect(find.text('RJ-2026'), findsOneWidget);

    await tester.tap(find.text('Résidence Les Jardins'));
    await tester.pumpAndSettle();

    expect(find.text('Choisissez un modèle'), findsOneWidget);
    verify(() => repository.getOptionsFiltres('c1')).called(1);
  });

  testWidgets('un échec de génération est DIT, et l’assistant reste ouvert', (tester) async {
    when(() => repository.genererRapportConfigure(any()))
        .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Stockage saturé')));

    await pomperPage(tester, const NouveauRapportPage(chantierId: 'c1'), taille: surface);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rapport global du chantier'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(suivant());
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Générer le rapport'));
    await tester.pumpAndSettle();

    expect(find.text('Stockage saturé'), findsOneWidget);
    expect(find.text('Générer le rapport'), findsOneWidget);
  });

  testWidgets('modifier un rapport existant reprend à l’étape des filtres (§ 20)', (tester) async {
    const existant = Rapport(
      id: 'r7',
      chantierId: 'c1',
      fichierUrl: '/uploads/rapports/r7.pdf',
      modele: ModeleRapport.entreprise,
      filtres: FiltresRapport(entreprises: ['p1']),
    );

    await pomperPage(tester, const NouveauRapportPage(chantierId: 'c1', existant: existant), taille: surface);
    await tester.pumpAndSettle();

    // Sans nom de chantier transmis, le titre dit ce que fait l'écran.
    expect(find.text('Modifier le rapport'), findsOneWidget);
    // La configuration du rapport est reprise : l'entreprise est déjà cochée.
    final puce = tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'ABC Carrelage'));
    expect(puce.selected, isTrue);
  });

  // ── Avec le thème RÉEL de l'application ──────────────────────────────────
  //
  // Le thème impose aux OutlinedButton une largeur minimale INFINIE
  // (`Size.fromHeight(52)`). Posé dans une Row, « Précédent » faisait échouer
  // la mise en page de toute la barre : en production, une bande blanche,
  // sans « Suivant », dès la deuxième étape. Les tests ci-dessus montent
  // l'écran avec le thème Material de base, et ne pouvaient pas le voir.
  group('avec le thème de l’application', () {
    Finder precedent() => find.widgetWithIcon(OutlinedButton, Icons.arrow_back_rounded);

    testWidgets('« Précédent » et « Suivant » sont là à CHAQUE étape', (tester) async {
      await pomperPage(tester, const NouveauRapportPage(), theme: AppTheme.light);
      await tester.pumpAndSettle();

      // 1. Projet
      await tester.tap(find.text('Résidence Les Jardins'));
      await tester.pumpAndSettle();

      // 2. Modèle — la première étape qui a un « Précédent ».
      await tester.tap(find.text('Rapport global du chantier'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(precedent().hitTestable(), findsOneWidget);
      expect(suivant().hitTestable(), findsOneWidget);

      await tester.tap(suivant());
      await tester.pumpAndSettle();

      // 3. Filtres
      expect(find.text('Bâtiment'), findsWidgets);
      expect(tester.takeException(), isNull);
      expect(precedent().hitTestable(), findsOneWidget);
      expect(suivant().hitTestable(), findsOneWidget);

      await tester.tap(suivant());
      await tester.pumpAndSettle();

      // 4. Sections
      expect(find.text('Synthèse'), findsOneWidget);
      expect(suivant().hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ── « + » dans le filtre Entreprise ──────────────────────────────────────
  //
  // Un annuaire vide bloquait le « Rapport par entreprise » : l'entreprise est
  // exigée, et aucune n'était proposée. Il fallait quitter l'assistant.
  group('ajouter une entreprise depuis les filtres', () {
    Future<void> ouvrirFiltres(WidgetTester tester, UserRole role) async {
      when(() => repository.getOptionsFiltres(any())).thenAnswer((_) async => const Right(OptionsFiltresRapport(
            corpsEtat: [OptionFiltre(id: 'ce1', nom: 'Plomberie')],
          )));
      await pomperPage(tester, const NouveauRapportPage(chantierId: 'c1'), taille: surface, role: role);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rapport par entreprise'));
      await tester.pumpAndSettle();
      await tester.tap(suivant());
      await tester.pumpAndSettle();
    }

    testWidgets('annuaire vide : le « + » est proposé à qui peut l’enrichir', (tester) async {
      await ouvrirFiltres(tester, UserRole.conducteurTravaux);

      expect(find.text('Aucune entreprise dans l’annuaire du chantier.'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Ajouter une entreprise'), findsOneWidget);
    });

    testWidgets('un rôle que le serveur refuserait ne voit pas le « + »', (tester) async {
      await ouvrirFiltres(tester, UserRole.client);

      expect(find.widgetWithText(ActionChip, 'Ajouter une entreprise'), findsNothing);
    });
  });
}

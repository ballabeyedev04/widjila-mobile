import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/configuration_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/etat_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/modele_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/suivi_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/repositories/rapport_repository.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/usecases/rapport_usecases.dart';
import 'package:suivie_chantier_mobile/features/rapport/presentation/pages/rapport_detail_page.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/pompe_page.dart';

class _MockRepository extends Mock implements RapportRepository {}

/// Le détail d'un rapport, monté pour de vrai.
///
/// Ce qui est verrouillé : les gestes de production et de diffusion ne sont
/// proposés qu'au pilotage ; un échec montre son motif ; un rapport diffusé
/// annonce qu'il sera régénéré en nouvelle version (§ 18) ; le lien de
/// partage n'est affiché qu'une fois (§ 14).
void main() {
  late _MockRepository repository;

  final rapport = Rapport(
    id: 'r1',
    chantierId: 'c1',
    fichierUrl: '/uploads/rapports/r1.pdf',
    fichierXlsxUrl: '/uploads/rapports/r1.xlsx',
    nom: 'Rapport Bâtiment A',
    modele: ModeleRapport.batiment,
    version: 2,
    nbReserves: 42,
    formats: const {FormatRapport.pdf, FormatRapport.xlsx},
    genereLe: DateTime(2026, 9, 10, 8),
  );

  // Surface haute : tout le détail tient à l'écran, sans défilement.
  const surface = Size(420, 2600);

  void enregistrer<T extends Object>(T instance) {
    if (sl.isRegistered<T>()) sl.unregister<T>();
    sl.registerFactory<T>(() => instance);
  }

  setUp(() {
    repository = _MockRepository();
    when(() => repository.detailRapport(any())).thenAnswer((_) async => Right(rapport));
    when(() => repository.historique(any())).thenAnswer((_) async => Right([
          EntreeHistoriqueRapport(id: 'h1', action: 'cree', libelle: 'Rapport créé', acteur: 'Balla Beye', date: DateTime(2026, 9, 10, 8)),
          EntreeHistoriqueRapport(id: 'h2', action: 'consulte_via_lien', libelle: 'Rapport consulté via lien', date: DateTime(2026, 9, 11, 9)),
        ]));
    when(() => repository.partages(any())).thenAnswer((_) async => const Right([
          PartageRapport(id: 'p1', nbAcces: 3, actif: true),
        ]));

    enregistrer<GetDetailRapport>(GetDetailRapport(repository));
    enregistrer<GetHistoriqueRapport>(GetHistoriqueRapport(repository));
    enregistrer<GetPartagesRapport>(GetPartagesRapport(repository));
    enregistrer<GenererRapportConfigure>(GenererRapportConfigure(repository));
    enregistrer<DupliquerRapport>(DupliquerRapport(repository));
    enregistrer<ArchiverRapport>(ArchiverRapport(repository));
    enregistrer<GenererRapportsParEntreprise>(GenererRapportsParEntreprise(repository));
    enregistrer<PartagerRapport>(PartagerRapport(repository));
    enregistrer<RevoquerPartageRapport>(RevoquerPartageRapport(repository));
  });

  const page = RapportDetailPage(rapportId: 'r1');

  testWidgets('le pilotage voit fichiers, diffusion, actions et historique', (tester) async {
    await pomperPage(tester, page, role: UserRole.chefProjet, taille: surface);
    await tester.pumpAndSettle();

    expect(find.text('Rapport Bâtiment A'), findsOneWidget);
    expect(find.text('Rapport par bâtiment'), findsOneWidget);
    expect(find.text('Généré'), findsOneWidget);
    expect(find.text('Version 2'), findsOneWidget);
    expect(find.text('42 réserve(s)'), findsOneWidget);

    for (final action in [
      'Voir le PDF', 'Télécharger le PDF', 'Télécharger l’Excel',
      'Envoyer par e-mail', 'Partager par lien',
      'Régénérer', 'Modifier et régénérer', 'Dupliquer', 'Générer les rapports par entreprise', 'Archiver',
    ]) {
      expect(find.text(action), findsOneWidget, reason: action);
    }

    // § 18 — l'historique, y compris la consultation par lien.
    expect(find.text('Rapport créé'), findsOneWidget);
    expect(find.text('Rapport consulté via lien'), findsOneWidget);
    // § 14 — le lien actif et ses consultations.
    expect(find.textContaining('3 consultation(s)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un rôle qui ne pilote pas ne voit ni diffusion ni actions', (tester) async {
    await pomperPage(tester, page, role: UserRole.sousTraitant, taille: surface);
    await tester.pumpAndSettle();

    expect(find.text('Voir le PDF'), findsOneWidget);
    expect(find.text('Envoyer par e-mail'), findsNothing);
    expect(find.text('Partager par lien'), findsNothing);
    expect(find.text('Dupliquer'), findsNothing);
    // Les liens exposent QUI a consulté le rapport : jamais demandés pour lui.
    verifyNever(() => repository.partages(any()));
  });

  testWidgets('un échec de génération montre son MOTIF', (tester) async {
    when(() => repository.detailRapport(any())).thenAnswer((_) async => const Right(Rapport(
          id: 'r1', chantierId: 'c1', fichierUrl: '', etat: EtatRapport.echec, erreur: 'Stockage saturé',
        )));

    await pomperPage(tester, page, role: UserRole.chefProjet, taille: surface);
    await tester.pumpAndSettle();

    expect(find.text('La génération a échoué : Stockage saturé'), findsOneWidget);
    expect(find.text('Générer maintenant'), findsOneWidget);
    expect(find.text('Voir le PDF'), findsNothing);
  });

  testWidgets('§ 18 — un rapport DIFFUSÉ annonce la nouvelle version et ne se modifie plus', (tester) async {
    when(() => repository.detailRapport(any())).thenAnswer((_) async => Right(Rapport(
          id: 'r1', chantierId: 'c1', fichierUrl: '/uploads/rapports/r1.pdf', etat: EtatRapport.envoye,
          genereLe: DateTime(2026, 9, 10),
        )));

    await pomperPage(tester, page, role: UserRole.chefProjet, taille: surface);
    await tester.pumpAndSettle();

    expect(find.textContaining('nouvelle version'), findsOneWidget);
    expect(find.text('Modifier et régénérer'), findsNothing);
    expect(find.text('Régénérer'), findsOneWidget);
  });

  testWidgets('archiver demande CONFIRMATION, puis le confirme', (tester) async {
    when(() => repository.archiver(any())).thenAnswer((_) async => Right(Rapport(
          id: 'r1', chantierId: 'c1', fichierUrl: '/uploads/rapports/r1.pdf', etat: EtatRapport.archive,
        )));

    await pomperPage(tester, page, role: UserRole.chefProjet, taille: surface);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Archiver'));
    await tester.pumpAndSettle();
    verifyNever(() => repository.archiver(any()));

    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();

    verify(() => repository.archiver('r1')).called(1);
    expect(find.text('Rapport archivé.'), findsOneWidget);
  });

  testWidgets('§ 14 — le lien créé s’affiche UNE fois, avec de quoi le copier', (tester) async {
    when(() => repository.partager(any(),
            expireDansJours: any(named: 'expireDansJours'),
            authentificationRequise: any(named: 'authentificationRequise')))
        .thenAnswer((_) async => const Right(LienPartageRapport(url: 'https://widjila.app/r/abc123', partageId: 'p2')));

    await pomperPage(tester, page, role: UserRole.chefProjet, taille: surface);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Partager par lien'));
    await tester.pumpAndSettle();
    expect(find.text('30 jours'), findsOneWidget);

    await tester.tap(find.text('7 jours'));
    await tester.tap(find.text('Créer le lien'));
    await tester.pumpAndSettle();

    verify(() => repository.partager('r1', expireDansJours: 7, authentificationRequise: false)).called(1);
    expect(find.text('https://widjila.app/r/abc123'), findsOneWidget);
    expect(find.text('Copier le lien'), findsOneWidget);
    expect(find.textContaining('affiché qu’une fois'), findsOneWidget);
  });

  testWidgets('un rapport introuvable : une erreur qui propose de réessayer', (tester) async {
    when(() => repository.detailRapport(any()))
        .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Rapport introuvable dans cette organisation')));

    await pomperPage(tester, page, taille: surface);
    await tester.pumpAndSettle();

    expect(find.textContaining('introuvable'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });
}

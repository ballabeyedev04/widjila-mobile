import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shimmer/shimmer.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/widgets/error_view.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve_collaboration.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/repositories/reserve_repository.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/ajouter_media_reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/changer_statut_reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_reserve_detail.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/piece_jointe.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/repositories/pieces_jointes_repository.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/cubit/pieces_jointes_cubit.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/cubit/reserve_detail_cubit.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/pages/reserve_detail_page.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/balayage_responsive.dart';
import '../../../../helpers/pompe_page.dart';

class _MockDetail extends Mock implements GetReserveDetail {}

class _MockChangerStatut extends Mock implements ChangerStatutReserve {}

class _MockAjouterMedia extends Mock implements AjouterMediaReserve {}

class _MockRepo extends Mock implements ReserveRepository {}

class _MockPiecesRepo extends Mock implements PiecesJointesRepository {}

/// La fiche d'une réserve.
///
/// ## Le champ qui casse les fiches
///
/// Presque tout est facultatif sur une réserve : description, échéance,
/// localisation, entreprise, assigné, photos, commentaires, historique. Une
/// fiche écrite en supposant leur présence tombe sur la première réserve
/// saisie en trois secondes sur un chantier — c'est-à-dire sur le cas le plus
/// courant.
///
/// Le test « réserve minimale » est donc le plus utile du fichier : il monte
/// la fiche avec le strict nécessaire et vérifie qu'elle ne lève rien.
void main() {
  late _MockDetail getDetail;

  void desinscrire() {
    if (sl.isRegistered<ReserveDetailCubit>()) sl.unregister<ReserveDetailCubit>();
    if (sl.isRegistered<PiecesJointesCubit>()) sl.unregister<PiecesJointesCubit>();
  }

  late _MockRepo repo;

  setUp(() {
    getDetail = _MockDetail();

    repo = _MockRepo();
    when(() => repo.getCommentaires(any())).thenAnswer(
      (_) async => const Right<Failure, List<CommentaireReserve>>([]),
    );
    when(() => repo.getAffectations(any())).thenAnswer(
      (_) async => const Right<Failure, List<AffectationReserve>>([]),
    );
    // Historique vide par défaut ; les tests de la section le remplacent.
    when(() => repo.getHistorique(any())).thenAnswer(
      (_) async => const Right<Failure, List<ReserveHistoriqueEntry>>([]),
    );

    desinscrire();
    sl.registerFactoryParam<ReserveDetailCubit, String, void>(
      (reserveId, _) => ReserveDetailCubit(
        getReserveDetail: getDetail,
        changerStatutReserve: _MockChangerStatut(),
        ajouterMediaReserve: _MockAjouterMedia(),
        repository: repo,
        reserveId: reserveId,
      ),
    );

    // La fiche porte désormais sa section « Pièces jointes », qui charge sa
    // propre liste : une réserve sans pièce jointe est le cas courant.
    // Enregistrée APRÈS `desinscrire()`, qui la retirerait sinon.
    final pieces = _MockPiecesRepo();
    when(() => pieces.lister(any())).thenAnswer(
      (_) async => const Right<Failure, List<PieceJointe>>([]),
    );
    sl.registerFactoryParam<PiecesJointesCubit, String, void>(
      (reserveId, _) => PiecesJointesCubit(reserveId: reserveId, repository: pieces),
    );
  });

  tearDown(desinscrire);

  const page = ReserveDetailPage(reserveId: 'r1');

  testWidgets('un indicateur pendant le chargement', (tester) async {
    final attente = Completer<Either<Failure, Reserve>>();
    when(() => getDetail(any())).thenAnswer((_) => attente.future);

    await pomperPage(tester, page);

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(tester.takeException(), isNull);

    attente.complete(const Right(
      Reserve(id: 'r1', numero: 'R-001', chantierId: 'c1', titre: 'Fissure'),
    ));
    await tester.pumpAndSettle();
  });

  testWidgets('reserve introuvable : un message, pas une fiche muette',
      (tester) async {
    when(() => getDetail(any())).thenAnswer(
      (_) async => const Left<Failure, Reserve>(
        ServerFailure(errorMessage: 'Reserve introuvable', statusCode: 404),
      ),
    );

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.byType(ErrorView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reserve MINIMALE : aucun champ facultatif, la fiche tient',
      (tester) async {
    when(() => getDetail(any())).thenAnswer(
      (_) async => const Right<Failure, Reserve>(
        Reserve(id: 'r1', numero: 'R-001', chantierId: 'c1', titre: 'Fissure mur nord'),
      ),
    );

    await pomperPage(tester, page, role: UserRole.entreprise);
    await tester.pumpAndSettle();

    expect(find.textContaining('Fissure mur nord'), findsWidgets);
    expect(find.byType(ErrorView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reserve COMPLETE : la fiche se monte sans incident', (tester) async {
    when(() => getDetail(any())).thenAnswer(
      (_) async => Right<Failure, Reserve>(
        Reserve(
          id: 'r1',
          numero: 'R-001',
          chantierId: 'c1',
          titre: 'Fissure mur nord',
          description: 'Fissure traversante au niveau du linteau.',
          severite: ReserveSeverite.critique,
          statut: ReserveStatut.enCours,
          dateLimite: DateTime(2026, 9, 30),
          createdAt: DateTime(2026, 9, 1),
        ),
      ),
    );

    await pomperPage(tester, page, role: UserRole.entreprise);
    await tester.pumpAndSettle();

    expect(find.textContaining('Fissure mur nord'), findsWidgets);
    expect(find.byType(ErrorView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('réserve posée sur un plan : le plan est MONTRÉ, pas seulement nommé',
      (tester) async {
    // Fichier vide : l'aperçu tranche sans réseau (« indisponible »). Ce qui
    // est vérifié ici, c'est la place du bloc sur la fiche — l'aperçu lui-même
    // est testé dans `apercu_plan_reserve_test.dart`.
    when(() => getDetail(any())).thenAnswer(
      (_) async => const Right<Failure, Reserve>(
        Reserve(
          id: 'r1',
          numero: 'R-0003',
          chantierId: 'c1',
          titre: 'Peinture à refaire',
          plan: ReservePlanRef(id: 'p1', nom: 'arkada_13_2np3.jpg', version: 3),
          position: ReservePositionRef(x: 40, y: 55),
        ),
      ),
    );

    await pomperPage(tester, page, role: UserRole.entreprise);
    await tester.pumpAndSettle();

    expect(find.text('Emplacement sur le plan'), findsOneWidget);
    expect(find.text('Voir le plan'), findsOneWidget);
    // L'ancienne ligne « Plans · arkada_13_2np3.jpg · v3 » a laissé la place.
    expect(find.text('Plans'), findsNothing);
    expect(tester.takeException(), isNull);
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
        when(() => getDetail(any())).thenAnswer(
          (_) async => Right<Failure, Reserve>(
            Reserve(
              id: 'r1',
              numero: 'R-001',
              chantierId: 'c1',
              titre: 'Fissure traversante au niveau du linteau nord',
              description: 'Reprise complete de la maconnerie a prevoir.',
              severite: ReserveSeverite.critique,
              statut: ReserveStatut.enCours,
              dateLimite: DateTime(2026, 9, 30),
              createdAt: DateTime(2026, 9, 1),
            ),
          ),
        );

        await pomperPage(
          tester,
          page,
          role: UserRole.entreprise,
          taille: format.taille,
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'debordement de mise en page sur $format');
      });
    }
  });

  group('sous-traitant assigné en SECONDAIRE', () {
    // Le serveur accepte les DEUX voies d'affectation : `assigneA` ou une ligne
    // dans `reserve_affectations` (`reserve.service.js:1021-1023`). L'écran ne
    // regardait que la première : un sous-traitant affecté par
    // `POST /reserves/:id/affectations` n'avait plus AUCUNE action — la barre
    // du bas disparaissait entièrement, alors que le serveur aurait accepté
    // ses transitions.
    const reserveAffectee = Reserve(
      id: 'r1',
      numero: 'R-001',
      chantierId: 'c1',
      titre: 'Fissure',
      statut: ReserveStatut.affectee,
    );

    testWidgets('sans aucune affectation : aucune action, comme avant',
        (tester) async {
      when(() => getDetail(any()))
          .thenAnswer((_) async => const Right<Failure, Reserve>(reserveAffectee));

      await pomperPage(tester, page, role: UserRole.sousTraitant);
      await tester.pumpAndSettle();

      expect(find.text('Changer le statut'), findsNothing);
    });

    testWidgets('affecté en secondaire : les actions lui sont rendues',
        (tester) async {
      when(() => getDetail(any()))
          .thenAnswer((_) async => const Right<Failure, Reserve>(reserveAffectee));
      // `u-test` est l'utilisateur injecté par `pomperPage`.
      when(() => repo.getAffectations(any())).thenAnswer(
        (_) async => const Right<Failure, List<AffectationReserve>>([
          AffectationReserve(
            id: 'a1',
            utilisateur: PersonneReserve(id: 'u-test', nom: 'Ba', prenom: 'Ibrahima'),
          ),
        ]),
      );

      await pomperPage(tester, page, role: UserRole.sousTraitant);
      await tester.pumpAndSettle();

      expect(find.text('Changer le statut'), findsOneWidget);
    });
  });

  group('feuille « Nouveau statut » — choix libre', () {
    // Depuis la recette, un pilote peut poser n'importe quel statut : la
    // feuille passe de trois entrées à treize. Sur un téléphone de 844 dp de
    // haut, une colonne fixe débordait et les derniers statuts restaient hors
    // de portée : la feuille doit défiler.
    const reserve = Reserve(
      id: 'r1',
      numero: 'R-001',
      chantierId: 'c1',
      titre: 'Fissure',
      statut: ReserveStatut.creee,
    );

    testWidgets('propose les statuts du client, et défile jusqu au dernier', (tester) async {
      when(() => getDetail(any())).thenAnswer((_) async => const Right<Failure, Reserve>(reserve));

      await pomperPage(tester, page, role: UserRole.chefProjet);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Changer le statut'));
      await tester.pumpAndSettle();

      expect(find.text('Nouveau statut'), findsOneWidget);
      // Les statuts du client sont dans la feuille — badge + libellé, donc deux
      // textes chacun (construits, même hors
      // écran : la colonne est dans un défilement, pas dans une liste lazy).
      for (final libelle in ['À surveiller', 'À échéance', 'Traitée', 'Refusée', 'En retard']) {
        expect(find.text(libelle), findsNWidgets(2), reason: libelle);
      }
      // « Créée » n'est jamais une destination ; « clôturée » non plus depuis
      // « créée » ; « validée » / « levée » exigent une preuve — aucune ici.
      // « Créée » n'apparaît qu'une fois : le badge de la fiche, pas une entrée.
      expect(find.text('Créée'), findsOneWidget);
      expect(find.text('Clôturée'), findsNothing);
      expect(find.text('Levée'), findsNothing);

      // Le dernier statut est atteignable : on y défile, puis on l'appuie.
      await tester.ensureVisible(find.text('En retard').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('fiche complète — toutes les informations regroupées', () {
    testWidgets('modifiée le, sévérité, levée par / le', (tester) async {
      when(() => getDetail(any())).thenAnswer(
        (_) async => Right<Failure, Reserve>(
          Reserve(
            id: 'r1',
            numero: 'R-0012',
            chantierId: 'c1',
            titre: 'Fissure mur nord',
            description: 'Fissure traversante.',
            severite: ReserveSeverite.critique,
            statut: ReserveStatut.levee,
            createdAt: DateTime(2026, 9, 1, 8),
            updatedAt: DateTime(2026, 9, 20, 16, 48),
            dateLimite: DateTime(2026, 9, 30),
            chantier: const ReserveLocalisationRef(id: 'c1', nom: 'Résidence Les Jardins'),
            phase: const ReserveLocalisationRef(id: 'p1', nom: 'Pré-cloisons'),
            partenaire: const ReserveLocalisationRef(id: 'e1', nom: 'ABC Carrelage'),
            createur: const ReserveUtilisateurRef(id: 'u1', nom: 'Ouattara', prenom: 'Mohamed'),
            validateur: const ReserveUtilisateurRef(id: 'u2', nom: 'Dupont', prenom: 'Jean'),
            dateValidation: DateTime(2026, 9, 20, 16, 48),
          ),
        ),
      );

      await pomperPage(tester, page, role: UserRole.entreprise);
      await tester.pumpAndSettle();

      expect(find.text('Résidence Les Jardins'), findsOneWidget);
      expect(find.text('Pré-cloisons'), findsOneWidget);
      expect(find.text('ABC Carrelage'), findsOneWidget);
      expect(find.text('Mohamed Ouattara'), findsOneWidget);
      expect(find.text('Modifiée le'), findsOneWidget);
      expect(find.text('20/09/2026'), findsWidgets);
      expect(find.text('Sévérité'), findsOneWidget);
      expect(find.text('Levée par'), findsOneWidget);
      expect(find.text('Jean Dupont'), findsOneWidget);
      expect(find.text('Levée le'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('jamais retouchée : pas de « Modifiée le » redondant', (tester) async {
      when(() => getDetail(any())).thenAnswer(
        (_) async => Right<Failure, Reserve>(
          Reserve(
            id: 'r1',
            numero: 'R-0012',
            chantierId: 'c1',
            titre: 'Fissure',
            createdAt: DateTime(2026, 9, 1, 8),
            updatedAt: DateTime(2026, 9, 1, 8, 0, 3),
          ),
        ),
      );

      await pomperPage(tester, page, role: UserRole.entreprise);
      await tester.pumpAndSettle();

      expect(find.text('Modifiée le'), findsNothing);
    });
  });

  group('historique des changements', () {
    const reserve = Reserve(
      id: 'r1',
      numero: 'R-0012',
      chantierId: 'c1',
      titre: 'Fissure',
      statut: ReserveStatut.levee,
    );

    // Du plus récent au plus ancien, comme le sert `GET /reserves/:id/historique`.
    final historique = [
      ReserveHistoriqueEntry(
        id: 'h3',
        action: 'validation',
        createdAt: DateTime.utc(2026, 9, 20, 16, 48),
        utilisateur: const ReserveUtilisateurRef(id: 'u1', nom: 'Dupont', prenom: 'Jean'),
        ancienStatut: ReserveStatut.traitee,
        nouveauStatut: ReserveStatut.levee,
      ),
      ReserveHistoriqueEntry(
        id: 'h2',
        action: 'statut',
        createdAt: DateTime.utc(2026, 9, 19, 9, 15),
        utilisateur: const ReserveUtilisateurRef(id: 'u2', nom: 'Ndiaye', prenom: 'Marie'),
        ancienStatut: ReserveStatut.aSurveiller,
        nouveauStatut: ReserveStatut.traitee,
      ),
      ReserveHistoriqueEntry(
        id: 'hc',
        action: 'commentaire',
        createdAt: DateTime.utc(2026, 9, 18, 15),
        utilisateur: const ReserveUtilisateurRef(id: 'u1', nom: 'Dupont', prenom: 'Jean'),
      ),
      ReserveHistoriqueEntry(
        id: 'h1',
        action: 'statut',
        createdAt: DateTime.utc(2026, 9, 18, 14, 32),
        utilisateur: null, // action du système (traitement des échéances)
        ancienStatut: ReserveStatut.creee,
        nouveauStatut: ReserveStatut.aSurveiller,
      ),
      ReserveHistoriqueEntry(
        id: 'h0',
        action: 'creation',
        createdAt: DateTime.utc(2026, 9, 15, 8),
        utilisateur: const ReserveUtilisateurRef(id: 'u3', nom: 'BEYE', prenom: 'Balla'),
        nouveauStatut: ReserveStatut.creee,
      ),
    ];

    Future<void> monter(WidgetTester tester) async {
      when(() => getDetail(any())).thenAnswer((_) async => const Right<Failure, Reserve>(reserve));
      await pomperPage(tester, page, role: UserRole.entreprise);
      await tester.pumpAndSettle();
      // La section est en bas de la fiche.
      await tester.scrollUntilVisible(
        find.text('Historique des changements'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('ancien → nouveau statut, date serveur, nom complet, du plus récent au plus ancien',
        (tester) async {
      when(() => repo.getHistorique(any()))
          .thenAnswer((_) async => Right<Failure, List<ReserveHistoriqueEntry>>(historique));

      await monter(tester);
      verify(() => repo.getHistorique('r1')).called(1);

      // QUI : le nom complet, jamais un identifiant.
      expect(find.text('Modifié par : Jean Dupont'), findsWidgets);
      expect(find.text('Modifié par : Marie Ndiaye'), findsOneWidget);
      expect(find.text('Modifié par : Balla BEYE'), findsOneWidget);
      expect(find.text('Modifié par : Système (échéance)'), findsOneWidget);
      expect(find.textContaining('u1'), findsNothing);

      // QUEL → QUEL : les badges des deux statuts (le nouveau apparaît aussi
      // comme ancien de la ligne suivante).
      expect(find.text('Traitée'), findsNWidgets(2));
      expect(find.text('À surveiller'), findsNWidgets(2));
      expect(find.text('Statut initial'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsNWidgets(4));

      // QUAND : la date SERVEUR, rendue en heure locale — jour et heure,
      // séparés d'un point médian.
      final local = DateTime.utc(2026, 9, 20, 16, 48).toLocal();
      final heure = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
      expect(find.textContaining('sept. 2026 • $heure'), findsOneWidget);

      // ORDRE : la dernière modification (levée) en tête, la création en fin.
      final yLevee = tester.getTopLeft(find.text('Modifié par : Jean Dupont').first).dy;
      final yCreation = tester.getTopLeft(find.text('Modifié par : Balla BEYE')).dy;
      expect(yLevee, lessThan(yCreation));

      // Un commentaire reste dans la chronologie, sans flèche.
      expect(find.text('Commentaire ajouté'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sans aucune ligne : un message, pas une zone vide', (tester) async {
      await monter(tester);

      expect(find.text('Aucun changement de statut enregistré pour cette réserve.'), findsOneWidget);
      // Rien n'est reconstruit depuis le statut courant (« levée »).
      expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('erreur API : un message clair et « Réessayer », qui relance la lecture', (tester) async {
      when(() => repo.getHistorique(any())).thenAnswer(
        (_) async => const Left<Failure, List<ReserveHistoriqueEntry>>(ServerFailure(errorMessage: 'boom')),
      );

      await monter(tester);

      expect(find.text("Impossible de charger l'historique."), findsOneWidget);
      expect(find.byType(ErrorView), findsNothing, reason: 'la fiche reste lisible');

      when(() => repo.getHistorique(any()))
          .thenAnswer((_) async => Right<Failure, List<ReserveHistoriqueEntry>>(historique));
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();

      expect(find.text('Modifié par : Marie Ndiaye'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('chargement : un squelette tant que le serveur n’a pas répondu', (tester) async {
      final attente = Completer<Either<Failure, List<ReserveHistoriqueEntry>>>();
      when(() => repo.getHistorique(any())).thenAnswer((_) => attente.future);
      when(() => getDetail(any())).thenAnswer((_) async => const Right<Failure, Reserve>(reserve));

      await pomperPage(tester, page, role: UserRole.entreprise);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.scrollUntilVisible(
        find.text('Historique des changements'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      expect(find.byType(Shimmer), findsWidgets);
      expect(tester.takeException(), isNull);

      attente.complete(const Right([]));
      await tester.pumpAndSettle();
    });

    for (final format in formatsCritiques) {
      testWidgets('la chronologie tient sans debordement sur $format', (tester) async {
        when(() => repo.getHistorique(any()))
            .thenAnswer((_) async => Right<Failure, List<ReserveHistoriqueEntry>>(historique));
        when(() => getDetail(any())).thenAnswer((_) async => const Right<Failure, Reserve>(reserve));

        await pomperPage(tester, page, role: UserRole.entreprise, taille: format.taille);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Historique des changements'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'debordement sur $format');
      });
    }
  });
}

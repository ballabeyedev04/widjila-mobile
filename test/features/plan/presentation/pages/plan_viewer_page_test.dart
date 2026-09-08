import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/widgets/error_view.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/entities/plan.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_plan_detail.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/cubit/plan_detail_cubit.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/pages/plan_viewer_page.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/widgets/fiche_reserve_sheet.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/widgets/plan_interactif.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/balayage_responsive.dart';
import '../../../../helpers/pompe_page.dart';

class _MockDetail extends Mock implements GetPlanDetail {}

class _MockDio extends Mock implements Dio {}

/// Une image PNG valide de 1×1 — assez pour que Flutter la décode vraiment.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// La visionneuse de plan.
///
/// ## Ce que ce fichier protège
///
/// En cas d'échec, cet écran ne doit pas se replier sur un `Scaffold` nu :
/// la flèche de retour est la SEULE sortie d'une visionneuse plein écran.
/// Perdre le bandeau, c'est enfermer l'utilisateur sur un message d'erreur.
///
/// Le second point est la robustesse du plan lui-même : `nombrePages`,
/// `fichierNom`, `batiment`, `etage`, `zone`, les hotspots et les réserves
/// sont tous facultatifs. Un plan déposé sans métadonnée doit s'ouvrir.
void main() {
  late _MockDetail getDetail;

  void desinscrire() {
    if (sl.isRegistered<PlanDetailCubit>()) sl.unregister<PlanDetailCubit>();
  }

  setUp(() {
    getDetail = _MockDetail();
    desinscrire();
    sl.registerFactory<PlanDetailCubit>(() => PlanDetailCubit(getPlanDetail: getDetail));
  });

  tearDown(desinscrire);

  const page = PlanViewerPage(planId: 'p1');

  const planMinimal = Plan(
    id: 'p1',
    chantierId: 'c1',
    nom: 'Niveau R+2',
    fichierUrl: 'https://exemple.test/p1.pdf',
  );

  testWidgets('un indicateur pendant le chargement', (tester) async {
    final attente = Completer<Either<Failure, Plan>>();
    when(() => getDetail(any())).thenAnswer((_) => attente.future);

    await pomperPage(tester, page);

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(tester.takeException(), isNull);

    attente.complete(const Right(planMinimal));
    // `pumpAndSettle` est PROSCRIT sur cet ecran : la visionneuse affiche un
    // indicateur circulaire pendant le telechargement du PDF, et un
    // indicateur circulaire programme une image a l'infini. Attendre le
    // repos, ici, c'est attendre pour toujours.
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('echec : le message s affiche SANS perdre la fleche de retour',
      (tester) async {
    when(() => getDetail(any())).thenAnswer(
      (_) async => const Left<Failure, Plan>(ServerFailure(errorMessage: 'Plan introuvable')),
    );

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.byType(ErrorView), findsOneWidget);
    // La seule sortie d'un écran plein écran.
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan SANS aucune metadonnee : la visionneuse s ouvre', (tester) async {
    when(() => getDetail(any()))
        .thenAnswer((_) async => const Right<Failure, Plan>(planMinimal));

    await pomperPage(tester, page);
    // Voir plus haut : pas de `pumpAndSettle` sur cet ecran.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Le plan est arrive : plus de vue d'erreur de CHARGEMENT DU PLAN. Le
    // telechargement du PDF lui-meme n'aboutit pas en test (aucun reseau) et
    // c'est sans importance : ce qui se verifie ici, c'est que la fiche d'un
    // plan depourvu de toute metadonnee se monte sans lever.
    expect(find.byType(ErrorView), findsNothing);
    expect(find.text('Niveau R+2'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  group('un plan IMAGE s’affiche, il ne renvoie pas vers une autre application', () {
    // Le défaut signalé par le client : « on ne voit pas réellement l'image du
    // plan ». Le dépôt accepte png, jpg, jpeg et webp, mais le serveur étiquette
    // 'pdf' tout fichier reçu sans format explicite. L'écran se fiait à cette
    // étiquette : il tentait un rendu PDF sur une image, échouait, et proposait
    // d'ouvrir le fichier dans une application tierce.
    //
    // La décision se prend désormais sur les OCTETS — ce qui répare aussi les
    // plans DÉJÀ en base, que rien ne viendra ré-étiqueter.

    late _MockDio dio;

    setUp(() {
      dio = _MockDio();
      if (sl.isRegistered<Dio>()) sl.unregister<Dio>();
      sl.registerSingleton<Dio>(dio);
    });

    tearDown(() {
      if (sl.isRegistered<Dio>()) sl.unregister<Dio>();
    });

    Future<void> ouvrirAvec(WidgetTester tester, Uint8List octets) async {
      when(() => getDetail(any()))
          .thenAnswer((_) async => const Right<Failure, Plan>(planMinimal));
      when(() => dio.get<List<int>>(any(), options: any(named: 'options'))).thenAnswer(
        (_) async => Response<List<int>>(
          data: octets,
          statusCode: 200,
          requestOptions: RequestOptions(path: '/x'),
        ),
      );

      await pomperPage(tester, page);

      // DEUX tours de `runAsync`, et c'est nécessaire.
      //
      // Depuis que la visionneuse passe par `PlanInteractif`, les octets sont
      // réellement DÉCODÉS (`decodeImageFromList`, ou le rendu `pdfx` pour un
      // PDF) avant d'être affichés : du vrai travail asynchrone, que l'horloge
      // simulée de `pump` ne fait pas avancer.
      //
      // Premier tour : la fiche du plan arrive et le document se télécharge.
      // Le `pump` qui suit MONTE `PlanInteractif`, qui lance alors seulement
      // son décodage — d'où le second tour, sans lequel l'écran resterait sur
      // son indicateur de chargement.
      for (var i = 0; i < 2; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('des octets PNG donnent une image affichée', (tester) async {
      // `planMinimal` porte pourtant une URL en .pdf et le format par défaut :
      // c'est exactement le cas qui échouait.
      await ouvrirAvec(tester, _png);

      expect(find.byType(Image), findsWidgets);
      expect(find.byType(ErrorView), findsNothing);
    });

    testWidgets('l’image est zoomable — un plan se lit en s’approchant', (tester) async {
      await ouvrirAvec(tester, _png);

      expect(find.byType(InteractiveViewer), findsWidgets);
    });

    testWidgets('un format sans visionneuse propose toujours la sortie', (tester) async {
      // DWG, IFC : ni PDF ni image. Le fichier existe, une application tierce
      // sait peut-être le lire — constater l'impasse sans proposer la sortie
      // serait gratuit.
      await ouvrirAvec(tester, Uint8List.fromList([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B]));

      expect(find.byType(Image), findsNothing);
    });
  });

  group('les réserves sont des POINTS sur le plan, pas un compteur', () {
    // Le défaut signalé : l'écran affichait une pastille « 5 repères » dans un
    // coin, et jamais les points. Il rendait le document avec `flutter_pdfview`
    // — une vue NATIVE dont on ne connaît ni le zoom ni le décalage courants,
    // sur laquelle aucun marqueur ne peut être superposé sans dériver.
    //
    // `PlanInteractif` rasterise la page et la place dans un `InteractiveViewer`
    // dont la matrice nous appartient : les repères vivent dans le même
    // conteneur transformé que l'image, ils ne peuvent plus s'en désolidariser.

    late _MockDio dio;

    setUp(() {
      dio = _MockDio();
      if (sl.isRegistered<Dio>()) sl.unregister<Dio>();
      sl.registerSingleton<Dio>(dio);
    });

    tearDown(() {
      if (sl.isRegistered<Dio>()) sl.unregister<Dio>();
    });

    PlanReserve reserve(String id, {PlanPosition? position, String? description}) => PlanReserve(
          id: id,
          numero: 'R-000$id',
          titre: 'Fissure $id',
          description: description,
          statut: ReserveStatut.creee,
          severite: ReserveSeverite.moyenne,
          position: position,
        );

    Future<void> ouvrir(WidgetTester tester, List<PlanReserve> reserves) async {
      when(() => getDetail(any())).thenAnswer(
        (_) async => Right<Failure, Plan>(
          Plan(
            id: 'p1',
            chantierId: 'c1',
            nom: 'Niveau R+2',
            fichierUrl: 'https://exemple.test/p1.png',
            reserves: reserves,
          ),
        ),
      );
      when(() => dio.get<List<int>>(any(), options: any(named: 'options'))).thenAnswer(
        (_) async => Response<List<int>>(
          data: _png,
          statusCode: 200,
          requestOptions: RequestOptions(path: '/x'),
        ),
      );

      await pomperPage(tester, page);
      for (var i = 0; i < 2; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('chaque réserve positionnée devient un repère sur l’image',
        (tester) async {
      await ouvrir(tester, [
        reserve('1', position: const PlanPosition(x: 12, y: 30)),
        reserve('2', position: const PlanPosition(x: 55, y: 61)),
        reserve('3', position: const PlanPosition(x: 80, y: 22)),
      ]);

      final interactif = tester.widget<PlanInteractif>(find.byType(PlanInteractif));
      expect(interactif.marqueurs.map((m) => m.id), ['1', '2', '3']);
      // Et AUX POSITIONS ENREGISTRÉES, pas à des positions inventées.
      expect(interactif.marqueurs.first.x, 12);
      expect(interactif.marqueurs.first.y, 30);
      expect(tester.takeException(), isNull);
    });

    testWidgets('une réserve SANS position n’est pas dessinée, mais reste listée',
        (tester) async {
      // Créée depuis la liste et non depuis le plan : elle appartient bien à ce
      // plan, mais aucune coordonnée ne dit où la poser. L'inventer serait un
      // repère faux — pire que pas de repère.
      await ouvrir(tester, [
        reserve('1', position: const PlanPosition(x: 12, y: 30)),
        reserve('2'),
      ]);

      final interactif = tester.widget<PlanInteractif>(find.byType(PlanInteractif));
      expect(interactif.marqueurs.map((m) => m.id), ['1']);
      // La liste du bas, elle, les porte toutes les deux.
      expect(find.text('Fissure 2'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un plan sans réserve reste utilisable et le DIT', (tester) async {
      await ouvrir(tester, const []);

      final interactif = tester.widget<PlanInteractif>(find.byType(PlanInteractif));
      expect(interactif.marqueurs, isEmpty);
      // L'image est là, et l'appui y pose une réserve : le plan vierge est le
      // premier jour de chaque chantier, pas une impasse.
      expect(interactif.onPointAppuye, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un appui sur un repère ouvre la fiche, il ne crée rien',
        (tester) async {
      // Les deux gestes ne doivent jamais se confondre : un appui sur un point
      // CONSULTE, un appui sur une zone libre CRÉE.
      await ouvrir(tester, [
        reserve('1', position: const PlanPosition(x: 40, y: 40), description: 'Enduit à reprendre'),
      ]);

      final interactif = tester.widget<PlanInteractif>(find.byType(PlanInteractif));
      interactif.onMarqueurAppuye!(interactif.marqueurs.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(FicheReserveSheet), findsOneWidget);
      // Et la fiche montre CE QUI A ÉTÉ SAISI, pas seulement un titre.
      expect(find.text('Enduit à reprendre'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('le bouton « Créer une réserve » est proposé sur le plan',
        (tester) async {
      await ouvrir(tester, const []);

      expect(find.text('Créer une réserve'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('mise en page — balayage des formats', () {
    // La visionneuse donne toute la hauteur restante au plan et pose un
    // panneau bas plafonné à 34 % de l'écran. En paysage, ces 34 % deviennent
    // une bande très courte qui doit encore loger un bouton, un titre et une
    // liste — c'est là que ça déborde si les contraintes sont mal posées.
    late _MockDio dio;

    setUp(() {
      dio = _MockDio();
      if (sl.isRegistered<Dio>()) sl.unregister<Dio>();
      sl.registerSingleton<Dio>(dio);
      when(() => dio.get<List<int>>(any(), options: any(named: 'options'))).thenAnswer(
        (_) async => Response<List<int>>(
          data: _png,
          statusCode: 200,
          requestOptions: RequestOptions(path: '/x'),
        ),
      );
    });

    tearDown(() {
      if (sl.isRegistered<Dio>()) sl.unregister<Dio>();
    });

    for (final format in tousLesFormats) {
      testWidgets('sans débordement sur $format', (tester) async {
        when(() => getDetail(any())).thenAnswer(
          (_) async => Right<Failure, Plan>(
            Plan(
              id: 'p1',
              chantierId: 'c1',
              nom: 'Appartement A203 — cuisine et salle d’eau',
              fichierUrl: 'https://exemple.test/p1.png',
              reserves: [
                for (var i = 0; i < 6; i++)
                  PlanReserve(
                    id: 'r$i',
                    numero: 'R-000$i',
                    titre: 'Fissure au plafond, angle nord-ouest $i',
                    statut: ReserveStatut.creee,
                    severite: ReserveSeverite.haute,
                    position: PlanPosition(x: 10.0 * i, y: 12.0 * i),
                  ),
              ],
            ),
          ),
        );

        await pomperPage(tester, page, taille: format.taille);
        for (var i = 0; i < 2; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 80));
          });
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(tester.takeException(), isNull,
            reason: 'débordement de mise en page sur $format');
      });
    }
  });
}

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/repositories/rapport_repository.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/usecases/rapport_usecases.dart';
import 'package:suivie_chantier_mobile/features/rapport/presentation/cubit/rapports_cubit.dart';

class _MockRepository extends Mock implements RapportRepository {}

void main() {
  group('RapportType', () {
    test('l\'aller-retour raw/fromString est stable', () {
      for (final t in RapportType.values) {
        expect(RapportTypeX.fromString(t.raw), t, reason: t.name);
      }
    });

    test('un type inconnu retombe sur reserves sans lever', () {
      // Le serveur stocke le type en STRING(50), pas en ENUM : une valeur
      // inattendue peut revenir d'un rapport généré par une autre version.
      expect(RapportTypeX.fromString('synthese_mensuelle'), RapportType.reserves);
      expect(RapportTypeX.fromString(null), RapportType.reserves);
    });
  });

  group('Rapport.fromJson', () {
    test('lit un rapport complet', () {
      final rapport = Rapport.fromJson({
        'id': 'r1',
        'chantierId': 'c1',
        'type': 'opr',
        'fichier_url': 'https://exemple.test/r1.pdf',
        'createdAt': '2026-08-20T10:00:00.000Z',
      });

      expect(rapport.type, RapportType.opr);
      expect(rapport.fichierUrl, 'https://exemple.test/r1.pdf');
      expect(rapport.createdAt, isNotNull);
      expect(rapport.typeInconnu, isFalse);
    });

    test('signale un type que cette version ne connaît pas', () {
      final rapport = Rapport.fromJson({
        'id': 'r1',
        'type': 'synthese_mensuelle',
        'fichier_url': 'u',
      });

      // L'écran affichera « synthese_mensuelle » plutôt que de le travestir
      // en « Réserves », ce qui induirait l'utilisateur en erreur.
      expect(rapport.typeInconnu, isTrue);
      expect(rapport.typeBrut, 'synthese_mensuelle');
    });

    test('survit à une charge utile minimale', () {
      final rapport = Rapport.fromJson({'id': 'r1'});
      expect(rapport.fichierUrl, '');
      expect(rapport.chantierId, '');
      expect(rapport.createdAt, isNull);
    });
  });

  group('RapportsCubit', () {
    late _MockRepository repository;
    late RapportsCubit cubit;

    const chantierId = 'c1';
    const rapport = Rapport(id: 'r1', chantierId: chantierId, fichierUrl: 'u1');

    RapportsCubit construire() => RapportsCubit(
          getRapports: GetRapports(repository),
          genererRapport: GenererRapport(repository),
          supprimerRapport: SupprimerRapport(repository),
          chantierId: chantierId,
        );

    setUpAll(() => registerFallbackValue(RapportType.reserves));

    setUp(() {
      repository = _MockRepository();
      when(() => repository.getRapports(any())).thenAnswer((_) async => const Right([]));
    });

    tearDown(() async => cubit.close());

    test('charge la liste', () async {
      when(() => repository.getRapports(any()))
          .thenAnswer((_) async => const Right([rapport]));

      cubit = construire();
      await cubit.charger();

      expect(cubit.state.status, RapportsStatus.succes);
      expect(cubit.state.items, hasLength(1));
    });

    test('insère le rapport généré en tête et le retient', () async {
      when(() => repository.genererRapport(
            chantierId: any(named: 'chantierId'),
            type: any(named: 'type'),
            statutReserve: any(named: 'statutReserve'),
            entrepriseId: any(named: 'entrepriseId'),
            batimentId: any(named: 'batimentId'),
          )).thenAnswer((_) async => const Right(rapport));

      cubit = construire();
      await cubit.generer(type: RapportType.opr);

      expect(cubit.state.generationStatus, GenerationStatus.succes);
      expect(cubit.state.items.first.id, 'r1');
      // Retenu pour proposer « Ouvrir » sans forcer à le chercher dans la liste.
      expect(cubit.state.dernierGenere?.id, 'r1');
    });

    test('ignore une seconde génération pendant la première', () async {
      var appels = 0;
      when(() => repository.genererRapport(
            chantierId: any(named: 'chantierId'),
            type: any(named: 'type'),
            statutReserve: any(named: 'statutReserve'),
            entrepriseId: any(named: 'entrepriseId'),
            batimentId: any(named: 'batimentId'),
          )).thenAnswer((_) async {
        appels++;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return const Right(rapport);
      });

      cubit = construire();
      // La génération est longue : deux appuis produiraient deux PDF
      // identiques.
      final a = cubit.generer(type: RapportType.reserves);
      final b = cubit.generer(type: RapportType.reserves);
      await Future.wait([a, b]);

      expect(appels, 1);
    });

    test('un échec de génération n\'efface pas la liste déjà chargée', () async {
      when(() => repository.getRapports(any()))
          .thenAnswer((_) async => const Right([rapport]));
      when(() => repository.genererRapport(
            chantierId: any(named: 'chantierId'),
            type: any(named: 'type'),
            statutReserve: any(named: 'statutReserve'),
            entrepriseId: any(named: 'entrepriseId'),
            batimentId: any(named: 'batimentId'),
          )).thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'timeout')));

      cubit = construire();
      await cubit.charger();
      await cubit.generer(type: RapportType.qualite);

      expect(cubit.state.generationStatus, GenerationStatus.erreur);
      expect(cubit.state.generationErreur, 'timeout');
      expect(cubit.state.items, hasLength(1), reason: 'la liste reste affichée');
    });

    test('restaure la ligne si la suppression échoue', () async {
      when(() => repository.getRapports(any()))
          .thenAnswer((_) async => const Right([rapport]));
      when(() => repository.supprimerRapport(any()))
          .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'interdit')));

      cubit = construire();
      await cubit.charger();
      await cubit.supprimer(rapport);

      // Retrait optimiste annulé : le rapport existe toujours côté serveur.
      expect(cubit.state.items, hasLength(1));
      expect(cubit.state.erreur, 'interdit');
    });

    test('retire la ligne quand la suppression réussit', () async {
      when(() => repository.getRapports(any()))
          .thenAnswer((_) async => const Right([rapport]));
      when(() => repository.supprimerRapport(any()))
          .thenAnswer((_) async => const Right(null));

      cubit = construire();
      await cubit.charger();
      await cubit.supprimer(rapport);

      expect(cubit.state.items, isEmpty);
    });
  });
}

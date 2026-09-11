import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/etat_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/suivi_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/repositories/rapport_repository.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/usecases/rapport_usecases.dart';
import 'package:suivie_chantier_mobile/features/rapport/presentation/cubit/rapport_detail_cubit.dart';

class _MockRepository extends Mock implements RapportRepository {}

/// Le détail d'un rapport — ce qu'on en fait une fois généré.
///
/// Les règles verrouillées : les liens de partage ne sont demandés qu'au
/// pilotage ; un historique indisponible ne masque pas le rapport ; régénérer
/// un rapport diffusé produit une NOUVELLE version (§ 18) ; une action à la
/// fois.
void main() {
  late _MockRepository repository;

  const rapport = Rapport(id: 'r1', chantierId: 'c1', fichierUrl: '/uploads/rapports/r1.pdf', version: 1);
  const diffuse = Rapport(
    id: 'r1', chantierId: 'c1', fichierUrl: '/uploads/rapports/r1.pdf', etat: EtatRapport.envoye,
  );

  RapportDetailCubit construire({bool avecPartages = true}) => RapportDetailCubit(
        rapportId: 'r1',
        getDetail: GetDetailRapport(repository),
        getHistorique: GetHistoriqueRapport(repository),
        getPartages: GetPartagesRapport(repository),
        genererRapport: GenererRapportConfigure(repository),
        dupliquerRapport: DupliquerRapport(repository),
        archiverRapport: ArchiverRapport(repository),
        genererParEntreprise: GenererRapportsParEntreprise(repository),
        partagerRapport: PartagerRapport(repository),
        revoquerPartage: RevoquerPartageRapport(repository),
        avecPartages: avecPartages,
      );

  setUp(() {
    repository = _MockRepository();
    when(() => repository.detailRapport(any())).thenAnswer((_) async => const Right(rapport));
    when(() => repository.historique(any())).thenAnswer((_) async => const Right([
          EntreeHistoriqueRapport(id: 'h1', action: 'cree', libelle: 'Rapport créé'),
          EntreeHistoriqueRapport(id: 'h2', action: 'genere', libelle: 'PDF généré'),
        ]));
    when(() => repository.partages(any())).thenAnswer((_) async => const Right([PartageRapport(id: 'p1')]));
  });

  group('chargement', () {
    test('le rapport, son historique et ses liens', () async {
      final cubit = construire();
      await cubit.charger();

      expect(cubit.state.statut, StatutDetailRapport.succes);
      expect(cubit.state.rapport, rapport);
      expect(cubit.state.historique.map((h) => h.libelle), ['Rapport créé', 'PDF généré']);
      expect(cubit.state.partages.single.id, 'p1');
      await cubit.close();
    });

    test('les liens ne sont PAS demandés à qui ne pilote pas', () async {
      final cubit = construire(avecPartages: false);
      await cubit.charger();

      verifyNever(() => repository.partages(any()));
      expect(cubit.state.statut, StatutDetailRapport.succes);
      await cubit.close();
    });

    test('un historique indisponible ne masque pas le rapport', () async {
      when(() => repository.historique(any()))
          .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'timeout')));

      final cubit = construire();
      await cubit.charger();

      expect(cubit.state.statut, StatutDetailRapport.succes);
      expect(cubit.state.historique, isEmpty);
      await cubit.close();
    });

    test('un rapport introuvable est une ERREUR, avec son motif', () async {
      when(() => repository.detailRapport(any()))
          .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Rapport introuvable')));

      final cubit = construire();
      await cubit.charger();

      expect(cubit.state.statut, StatutDetailRapport.erreur);
      expect(cubit.state.erreur, 'Rapport introuvable');
      await cubit.close();
    });
  });

  group('§ 11 et § 18 — génération', () {
    test('régénérer un rapport non diffusé met à jour CE rapport', () async {
      when(() => repository.genererRapportConfigure(any()))
          .thenAnswer((_) async => const Right(Rapport(id: 'r1', chantierId: 'c1', fichierUrl: '/v2.pdf', version: 2)));
      final cubit = construire();
      await cubit.charger();

      final r = await cubit.generer();

      expect(r?.id, 'r1');
      expect(cubit.state.rapport?.fichierUrl, '/v2.pdf');
      await cubit.close();
    });

    test('régénérer un rapport DIFFUSÉ rend la nouvelle version, sans toucher l’ancienne', () async {
      when(() => repository.detailRapport(any())).thenAnswer((_) async => const Right(diffuse));
      when(() => repository.genererRapportConfigure(any())).thenAnswer((_) async =>
          const Right(Rapport(id: 'r2', chantierId: 'c1', fichierUrl: '/v2.pdf', version: 2)));
      final cubit = construire();
      await cubit.charger();

      final emis = <RapportDetailState>[];
      final abonnement = cubit.stream.listen(emis.add);
      final r = await cubit.generer();
      // Le flux d'un cubit livre ses états en microtâche : le dernier n'est
      // pas encore arrivé quand l'action rend la main.
      await Future<void>.delayed(Duration.zero);
      await abonnement.cancel();

      expect(r?.id, 'r2');
      expect(emis.map((e) => e.evenement), contains(EvenementDetailRapport.nouvelleVersion));
      // L'écran reste sur la version diffusée tant que la page ne bascule pas.
      expect(cubit.state.rapport, diffuse);
      await cubit.close();
    });

    test('un échec est dit, et l’action se libère', () async {
      when(() => repository.genererRapportConfigure(any()))
          .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Stockage saturé')));
      final cubit = construire();
      await cubit.charger();

      expect(await cubit.generer(), isNull);
      expect(cubit.state.occupe, isFalse);
      await cubit.close();
    });
  });

  group('duplication, archivage, par entreprise', () {
    test('dupliquer rend la copie à ouvrir', () async {
      when(() => repository.dupliquer(any())).thenAnswer((_) async =>
          const Right(Rapport(id: 'r9', chantierId: 'c1', fichierUrl: '', etat: EtatRapport.brouillon)));
      final cubit = construire();
      await cubit.charger();

      final emis = <RapportDetailState>[];
      final abonnement = cubit.stream.listen(emis.add);
      await cubit.dupliquer();
      // Le flux d'un cubit livre ses états en microtâche : le dernier n'est
      // pas encore arrivé quand l'action rend la main.
      await Future<void>.delayed(Duration.zero);
      await abonnement.cancel();

      final evenement = emis.firstWhere((e) => e.evenement == EvenementDetailRapport.duplique);
      expect(evenement.copie?.id, 'r9');
      await cubit.close();
    });

    test('archiver recharge le rapport', () async {
      when(() => repository.archiver(any())).thenAnswer((_) async =>
          const Right(Rapport(id: 'r1', chantierId: 'c1', fichierUrl: '/r1.pdf', etat: EtatRapport.archive)));
      final cubit = construire();
      await cubit.charger();

      await cubit.archiver();

      verify(() => repository.archiver('r1')).called(1);
      verify(() => repository.detailRapport('r1')).called(greaterThanOrEqualTo(2));
      await cubit.close();
    });

    test('§ 15 — le bilan de la génération par entreprise', () async {
      when(() => repository.genererParEntreprise(any())).thenAnswer((_) async => const Right(ResultatParEntreprise(
            message: '2 rapport(s) générés',
            nbRapports: 2,
            reservesSansEntreprise: 1,
          )));
      final cubit = construire();
      await cubit.charger();

      final emis = <RapportDetailState>[];
      final abonnement = cubit.stream.listen(emis.add);
      await cubit.genererRapportsParEntreprise();
      // Le flux d'un cubit livre ses états en microtâche : le dernier n'est
      // pas encore arrivé quand l'action rend la main.
      await Future<void>.delayed(Duration.zero);
      await abonnement.cancel();

      final evenement = emis.firstWhere((e) => e.evenement == EvenementDetailRapport.parEntreprise);
      expect(evenement.parEntreprise?.nbRapports, 2);
      expect(evenement.parEntreprise?.reservesSansEntreprise, 1);
      await cubit.close();
    });
  });

  group('§ 14 — partage', () {
    test('créer un lien le rend à l’appelant et recharge la liste', () async {
      when(() => repository.partager(any(), expireDansJours: any(named: 'expireDansJours'),
              authentificationRequise: any(named: 'authentificationRequise')))
          .thenAnswer((_) async => const Right(LienPartageRapport(url: 'https://w/r/abc', partageId: 'p2')));
      final cubit = construire();
      await cubit.charger();

      final r = await cubit.partager(expireDansJours: 7, authentificationRequise: true);

      expect(r.getOrElse(() => throw 'échec').url, 'https://w/r/abc');
      verify(() => repository.partager('r1', expireDansJours: 7, authentificationRequise: true)).called(1);
      await Future<void>.delayed(Duration.zero);
      verify(() => repository.partages('r1')).called(greaterThanOrEqualTo(2));
      await cubit.close();
    });

    test('révoquer un lien', () async {
      when(() => repository.revoquerPartage(any(), any())).thenAnswer((_) async => const Right(null));
      final cubit = construire();
      await cubit.charger();

      await cubit.revoquer('p1');

      verify(() => repository.revoquerPartage('r1', 'p1')).called(1);
      await cubit.close();
    });
  });
}

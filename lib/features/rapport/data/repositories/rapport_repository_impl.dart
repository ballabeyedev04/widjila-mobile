import 'package:dartz/dartz.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/errors/exception_to_failure.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/offline/detecteur_connexion.dart';
import '../../../../core/offline/file_attente.dart';
import '../../domain/entities/configuration_rapport.dart';
import '../../domain/entities/envoi_rapport.dart';
import '../../domain/entities/option_filtre.dart';
import '../../domain/entities/rapport.dart';
import '../../domain/entities/suivi_rapport.dart';
import '../../domain/repositories/rapport_repository.dart';
import '../datasources/rapport_remote_datasource.dart';

class RapportRepositoryImpl implements RapportRepository {
  final RapportRemoteDataSource remoteDataSource;

  /// File d'attente hors ligne — § 22 du cahier des charges : « l'envoi d'un
  /// rapport nécessite une connexion. Widjila peut mettre l'action en file
  /// d'attente et la transmettre lorsque le réseau revient. »
  ///
  /// Facultative : sans elle (tests, contexte sans base locale), un envoi
  /// hors ligne échoue simplement, avec un message qui le dit.
  final FileAttente? fileAttente;
  final DetecteurConnexion? detecteur;

  RapportRepositoryImpl(this.remoteDataSource, {this.fileAttente, this.detecteur});

  Future<Either<Failure, T>> _essayer<T>(Future<T> Function() action) async {
    try {
      return Right(await action());
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<Rapport>>> getRapports(String chantierId) =>
      _essayer(() => remoteDataSource.getRapports(chantierId));

  @override
  Future<Either<Failure, Rapport>> genererRapport({
    required String chantierId,
    required RapportType type,
    String? statutReserve,
    String? entrepriseId,
    String? batimentId,
  }) =>
      _essayer(() => remoteDataSource.genererRapport(
            chantierId: chantierId,
            type: type,
            statutReserve: statutReserve,
            entrepriseId: entrepriseId,
            batimentId: batimentId,
          ));

  @override
  Future<Either<Failure, void>> supprimerRapport(String id) =>
      _essayer(() => remoteDataSource.supprimerRapport(id));

  @override
  Future<Either<Failure, Rapport>> creerRapport(ConfigurationRapport configuration) =>
      _essayer(() => remoteDataSource.creerRapport(configuration));

  @override
  Future<Either<Failure, Rapport>> modifierRapport(String id, ConfigurationRapport configuration) =>
      _essayer(() => remoteDataSource.modifierRapport(id, configuration));

  @override
  Future<Either<Failure, Rapport>> detailRapport(String id) => _essayer(() => remoteDataSource.detailRapport(id));

  @override
  Future<Either<Failure, Rapport>> genererRapportConfigure(String id) =>
      _essayer(() => remoteDataSource.genererRapportConfigure(id));

  @override
  Future<Either<Failure, ResultatParEntreprise>> genererParEntreprise(String id) =>
      _essayer(() => remoteDataSource.genererParEntreprise(id));

  @override
  Future<Either<Failure, ResumeRapport>> resumeRapport(String id) => _essayer(() => remoteDataSource.resumeRapport(id));

  @override
  Future<Either<Failure, List<EntreeHistoriqueRapport>>> historique(String id) =>
      _essayer(() => remoteDataSource.historique(id));

  @override
  Future<Either<Failure, List<PartageRapport>>> partages(String id) => _essayer(() => remoteDataSource.partages(id));

  @override
  Future<Either<Failure, LienPartageRapport>> partager(
    String id, {
    int? expireDansJours,
    bool authentificationRequise = false,
  }) =>
      _essayer(() => remoteDataSource.partager(
            id,
            expireDansJours: expireDansJours,
            authentificationRequise: authentificationRequise,
          ));

  @override
  Future<Either<Failure, void>> revoquerPartage(String id, String partageId) =>
      _essayer(() => remoteDataSource.revoquerPartage(id, partageId));

  @override
  Future<Either<Failure, Rapport>> dupliquer(String id) => _essayer(() => remoteDataSource.dupliquer(id));

  @override
  Future<Either<Failure, Rapport>> archiver(String id) => _essayer(() => remoteDataSource.archiver(id));

  @override
  Future<Either<Failure, EnvoiRapport>> preparerEnvoi(String rapportId) =>
      _essayer(() => remoteDataSource.preparerEnvoi(rapportId));

  static const _uuid = Uuid();

  @override
  Future<Either<Failure, ResultatEnvoiRapport>> envoyerRapport(
    String rapportId,
    DemandeEnvoiRapport demande,
  ) async {
    // Clé d'idempotence de CETTE intention d'envoi (audit synchronisation) —
    // partagée par la tentative en ligne et, si elle tombe en coupure, par
    // l'action déposée dans la file. Une réponse perdue APRÈS l'expédition ne
    // produit donc jamais un second envoi au rejeu : le serveur retrouve la
    // clé et répond sans réexpédier.
    final cle = _uuid.v4();

    // Hors ligne CONSTATÉ : inutile d'attendre un délai réseau pour savoir
    // que l'envoi ne partira pas.
    if (fileAttente != null && detecteur != null && !detecteur!.estEnLigne) {
      return _mettreEnFile(rapportId, demande, cle);
    }
    try {
      final message = await remoteDataSource.envoyerRapport(rapportId, demande, cleIdempotence: cle);
      return Right(ResultatEnvoiRapport(message: message));
    } on NetworkException catch (_) {
      // Coupure pendant l'envoi : c'est exactement le cas du § 22. Un refus
      // du SERVEUR (adresse étrangère au chantier, rapport non généré), lui,
      // n'est pas mis en file — le rejouer échouerait toujours.
      if (fileAttente != null) return _mettreEnFile(rapportId, demande, cle);
      return Left(exceptionToFailure(const NetworkException()));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<OptionFiltre>>> getProjets() => _essayer(remoteDataSource.getProjets);

  @override
  Future<Either<Failure, OptionsFiltresRapport>> getOptionsFiltres(String chantierId) => _essayer(() async {
        // Les deux listes en parallèle : elles ne dépendent pas l'une de
        // l'autre, et l'écran des filtres attend les deux pour s'afficher.
        final resultats = await Future.wait([
          remoteDataSource.getEntreprisesChantier(chantierId),
          remoteDataSource.getCorpsEtat(),
        ]);
        return OptionsFiltresRapport(entreprises: resultats[0], corpsEtat: resultats[1]);
      });

  Future<Either<Failure, ResultatEnvoiRapport>> _mettreEnFile(
    String rapportId,
    DemandeEnvoiRapport demande,
    String cleIdempotence,
  ) async {
    try {
      await fileAttente!.deposer(
        type: TypeAction.envoyerRapport,
        // La clé de la tentative en ligne voyage avec l'action : si cette
        // tentative a en fait abouti côté serveur, le rejeu ne réexpédie rien.
        charge: {'rapportId': rapportId, 'demande': demande.toJson(), 'cleIdempotence': cleIdempotence},
      );
      return const Right(ResultatEnvoiRapport(message: '', enFileAttente: true));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }
}

import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/configuration_rapport.dart';
import '../entities/envoi_rapport.dart';
import '../entities/option_filtre.dart';
import '../entities/rapport.dart';
import '../entities/suivi_rapport.dart';
import '../repositories/rapport_repository.dart';

class GetRapports {
  final RapportRepository repository;
  GetRapports(this.repository);

  Future<Either<Failure, List<Rapport>>> call(String chantierId) => repository.getRapports(chantierId);
}

/// Ancien point d'entrée : un rapport en un seul geste, sans configuration.
class GenererRapport {
  final RapportRepository repository;
  GenererRapport(this.repository);

  Future<Either<Failure, Rapport>> call({
    required String chantierId,
    required RapportType type,
    String? statutReserve,
    String? entrepriseId,
    String? batimentId,
  }) =>
      repository.genererRapport(
        chantierId: chantierId,
        type: type,
        statutReserve: statutReserve,
        entrepriseId: entrepriseId,
        batimentId: batimentId,
      );
}

class SupprimerRapport {
  final RapportRepository repository;
  SupprimerRapport(this.repository);

  Future<Either<Failure, void>> call(String id) => repository.supprimerRapport(id);
}

/// § 3 et § 11, étape 1 — enregistrer la configuration.
class CreerRapport {
  final RapportRepository repository;
  CreerRapport(this.repository);

  Future<Either<Failure, Rapport>> call(ConfigurationRapport configuration) =>
      repository.creerRapport(configuration);
}

/// § 20 — revenir aux filtres, aux sections, puis régénérer.
class ModifierRapport {
  final RapportRepository repository;
  ModifierRapport(this.repository);

  Future<Either<Failure, Rapport>> call(String id, ConfigurationRapport configuration) =>
      repository.modifierRapport(id, configuration);
}

class GetDetailRapport {
  final RapportRepository repository;
  GetDetailRapport(this.repository);

  Future<Either<Failure, Rapport>> call(String id) => repository.detailRapport(id);
}

/// § 11 — générer le PDF et/ou l'Excel d'un rapport configuré.
class GenererRapportConfigure {
  final RapportRepository repository;
  GenererRapportConfigure(this.repository);

  Future<Either<Failure, Rapport>> call(String id) => repository.genererRapportConfigure(id);
}

/// § 15 — « Générer les rapports par entreprise ».
class GenererRapportsParEntreprise {
  final RapportRepository repository;
  GenererRapportsParEntreprise(this.repository);

  Future<Either<Failure, ResultatParEntreprise>> call(String id) => repository.genererParEntreprise(id);
}

/// § 20 — le périmètre chiffré, avant de produire quoi que ce soit.
class CalculerResumeRapport {
  final RapportRepository repository;
  CalculerResumeRapport(this.repository);

  Future<Either<Failure, ResumeRapport>> call(String id) => repository.resumeRapport(id);
}

/// § 18 — l'historique.
class GetHistoriqueRapport {
  final RapportRepository repository;
  GetHistoriqueRapport(this.repository);

  Future<Either<Failure, List<EntreeHistoriqueRapport>>> call(String id) => repository.historique(id);
}

class GetPartagesRapport {
  final RapportRepository repository;
  GetPartagesRapport(this.repository);

  Future<Either<Failure, List<PartageRapport>>> call(String id) => repository.partages(id);
}

/// § 14 — partager par lien sécurisé.
class PartagerRapport {
  final RapportRepository repository;
  PartagerRapport(this.repository);

  Future<Either<Failure, LienPartageRapport>> call(
    String id, {
    int? expireDansJours,
    bool authentificationRequise = false,
  }) =>
      repository.partager(id, expireDansJours: expireDansJours, authentificationRequise: authentificationRequise);
}

class RevoquerPartageRapport {
  final RapportRepository repository;
  RevoquerPartageRapport(this.repository);

  Future<Either<Failure, void>> call(String id, String partageId) => repository.revoquerPartage(id, partageId);
}

class DupliquerRapport {
  final RapportRepository repository;
  DupliquerRapport(this.repository);

  Future<Either<Failure, Rapport>> call(String id) => repository.dupliquer(id);
}

class ArchiverRapport {
  final RapportRepository repository;
  ArchiverRapport(this.repository);

  Future<Either<Failure, Rapport>> call(String id) => repository.archiver(id);
}

/// Les projets accessibles — l'étape « Choisir le projet » du § 3.
class GetProjetsRapport {
  final RapportRepository repository;
  GetProjetsRapport(this.repository);

  Future<Either<Failure, List<OptionFiltre>>> call() => repository.getProjets();
}

/// Les listes des filtres « Entreprise » et « Corps d'état » (§ 4).
class GetOptionsFiltresRapport {
  final RapportRepository repository;
  GetOptionsFiltresRapport(this.repository);

  Future<Either<Failure, OptionsFiltresRapport>> call(String chantierId) =>
      repository.getOptionsFiltres(chantierId);
}

/// Compose l'e-mail sans l'envoyer — étape de vérification (§ 13).
class PreparerEnvoiRapport {
  final RapportRepository repository;
  PreparerEnvoiRapport(this.repository);

  Future<Either<Failure, EnvoiRapport>> call(String rapportId) => repository.preparerEnvoi(rapportId);
}

/// Envoie le rapport, sur confirmation explicite de l'utilisateur — ou le
/// met en file d'attente faute de réseau (§ 22).
class EnvoyerRapport {
  final RapportRepository repository;
  EnvoyerRapport(this.repository);

  Future<Either<Failure, ResultatEnvoiRapport>> call(
    String rapportId, [
    DemandeEnvoiRapport demande = const DemandeEnvoiRapport(),
  ]) =>
      repository.envoyerRapport(rapportId, demande);
}

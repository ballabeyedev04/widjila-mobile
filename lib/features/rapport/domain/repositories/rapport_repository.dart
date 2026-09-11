import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/configuration_rapport.dart';
import '../entities/envoi_rapport.dart';
import '../entities/option_filtre.dart';
import '../entities/rapport.dart';
import '../entities/suivi_rapport.dart';

/// Rapports d'un chantier — le module du cahier des charges.
///
/// La production et la diffusion sont réservées côté serveur au pilotage ;
/// le mobile masque les gestes correspondants aux autres rôles, mais c'est le
/// serveur qui décide.
abstract class RapportRepository {
  Future<Either<Failure, List<Rapport>>> getRapports(String chantierId);

  Future<Either<Failure, Rapport>> genererRapport({
    required String chantierId,
    required RapportType type,
    String? statutReserve,
    String? entrepriseId,
    String? batimentId,
  });

  Future<Either<Failure, void>> supprimerRapport(String id);

  Future<Either<Failure, Rapport>> creerRapport(ConfigurationRapport configuration);
  Future<Either<Failure, Rapport>> modifierRapport(String id, ConfigurationRapport configuration);
  Future<Either<Failure, Rapport>> detailRapport(String id);
  Future<Either<Failure, Rapport>> genererRapportConfigure(String id);
  Future<Either<Failure, ResultatParEntreprise>> genererParEntreprise(String id);
  Future<Either<Failure, ResumeRapport>> resumeRapport(String id);
  Future<Either<Failure, List<EntreeHistoriqueRapport>>> historique(String id);
  Future<Either<Failure, List<PartageRapport>>> partages(String id);
  Future<Either<Failure, LienPartageRapport>> partager(
    String id, {
    int? expireDansJours,
    bool authentificationRequise,
  });
  Future<Either<Failure, void>> revoquerPartage(String id, String partageId);
  Future<Either<Failure, Rapport>> dupliquer(String id);
  Future<Either<Failure, Rapport>> archiver(String id);

  Future<Either<Failure, EnvoiRapport>> preparerEnvoi(String rapportId);

  /// Envoie — ou, faute de réseau, met l'envoi en file d'attente (§ 22).
  Future<Either<Failure, ResultatEnvoiRapport>> envoyerRapport(String rapportId, DemandeEnvoiRapport demande);

  Future<Either<Failure, List<OptionFiltre>>> getProjets();

  /// Entreprises et corps d'état du chantier, lus ensemble.
  Future<Either<Failure, OptionsFiltresRapport>> getOptionsFiltres(String chantierId);
}

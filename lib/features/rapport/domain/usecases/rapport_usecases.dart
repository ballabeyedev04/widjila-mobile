import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/envoi_rapport.dart';
import '../entities/rapport.dart';
import '../repositories/rapport_repository.dart';

class GetRapports {
  final RapportRepository repository;
  GetRapports(this.repository);

  Future<Either<Failure, List<Rapport>>> call(String chantierId) => repository.getRapports(chantierId);
}

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

/// Compose l'e-mail sans l'envoyer — étape de vérification.
class PreparerEnvoiRapport {
  final RapportRepository repository;
  PreparerEnvoiRapport(this.repository);

  Future<Either<Failure, EnvoiRapport>> call(String rapportId) =>
      repository.preparerEnvoi(rapportId);
}

/// Envoie le rapport, sur confirmation explicite de l'utilisateur.
class EnvoyerRapport {
  final RapportRepository repository;
  EnvoyerRapport(this.repository);

  Future<Either<Failure, String>> call(String rapportId, {List<String> exclure = const []}) =>
      repository.envoyerRapport(rapportId, exclure: exclure);
}

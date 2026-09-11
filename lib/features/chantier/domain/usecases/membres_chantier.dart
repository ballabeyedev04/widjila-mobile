import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/membre_chantier.dart';
import '../repositories/chantier_repository.dart';

/// Membres affectés à un chantier.
class GetMembresChantier {
  final ChantierRepository repository;
  GetMembresChantier(this.repository);

  Future<Either<Failure, List<MembreChantier>>> call(String chantierId) =>
      repository.getMembresChantier(chantierId);
}

/// Membres actifs de l'organisation qui peuvent encore être affectés.
class GetCandidatsMembres {
  final ChantierRepository repository;
  GetCandidatsMembres(this.repository);

  Future<Either<Failure, List<MembreChantier>>> call(String chantierId) =>
      repository.getCandidatsMembres(chantierId);
}

/// Affecte des membres à un chantier.
class AffecterMembres {
  final ChantierRepository repository;
  AffecterMembres(this.repository);

  Future<Either<Failure, void>> call(
    String chantierId, {
    required List<String> membreIds,
    String? roleChantier,
  }) =>
      repository.affecterMembres(chantierId, membreIds: membreIds, roleChantier: roleChantier);
}

/// Retire un membre d'un chantier.
class RetirerMembreChantier {
  final ChantierRepository repository;
  RetirerMembreChantier(this.repository);

  Future<Either<Failure, void>> call(String chantierId, String membreId) =>
      repository.retirerMembre(chantierId, membreId);
}

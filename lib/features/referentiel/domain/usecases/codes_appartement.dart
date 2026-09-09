import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/code_appartement.dart';
import '../repositories/referentiel_repository.dart';

/// Codes d'appartement proposés à la saisie — « A001 » à « A015 », plus ceux
/// que l'organisation a ajoutés.
class GetCodesAppartement {
  final ReferentielRepository repository;
  GetCodesAppartement(this.repository);

  Future<Either<Failure, List<CodeAppartement>>> call() => repository.getCodesAppartement();
}

/// Crée un code d'appartement absent de la liste — le « + » de la feuille de
/// niveau.
///
/// Le code appartient à l'organisation de l'appelant : ses collègues le
/// verront, les autres clients de la plateforme non.
class CreerCodeAppartement {
  final ReferentielRepository repository;
  CreerCodeAppartement(this.repository);

  Future<Either<Failure, CodeAppartement>> call({
    required String code,
    String? nom,
  }) =>
      repository.creerCodeAppartement(code: code, nom: nom);
}

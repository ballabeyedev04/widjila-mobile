import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/code_niveau.dart';
import '../repositories/referentiel_repository.dart';

/// Codes de niveau proposés à la saisie — « SS1 », « RDC », « R+1 »…
class GetCodesNiveau {
  final ReferentielRepository repository;
  GetCodesNiveau(this.repository);

  Future<Either<Failure, List<CodeNiveau>>> call() => repository.getCodesNiveau();
}

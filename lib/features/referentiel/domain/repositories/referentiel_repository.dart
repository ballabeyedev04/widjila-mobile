import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/code_niveau.dart';
import '../entities/pays.dart';
import '../entities/type_referentiel.dart';

abstract class ReferentielRepository {
  /// Types ACTIFS d'un référentiel — alimente les sélecteurs.
  Future<Either<Failure, List<TypeReferentiel>>> getTypesActifs(ReferentielType referentiel);

  /// Pays proposés à l'inscription, et les identifiants de chacun.
  Future<Either<Failure, List<Pays>>> getPays();

  /// Codes de niveau proposés à la saisie — « SS1 », « RDC », « R+1 »…
  Future<Either<Failure, List<CodeNiveau>>> getCodesNiveau();

  /// Crée un code absent de la liste.
  Future<Either<Failure, CodeNiveau>> creerCodeNiveau({
    required TypeNiveau typeNiveau,
    required String code,
    String? nom,
  });
}

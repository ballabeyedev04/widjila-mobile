import 'package:dartz/dartz.dart';

import '../../../../core/errors/exception_to_failure.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/entities/corps_etat.dart';
import '../../domain/repositories/corps_etat_repository.dart';
import '../datasources/corps_etat_remote_datasource.dart';

class CorpsEtatRepositoryImpl implements CorpsEtatRepository {
  final CorpsEtatRemoteDataSource remoteDataSource;

  /// Dernier catalogue reçu, conservé pour la durée de la session.
  ///
  /// Le catalogue est une donnée de RÉFÉRENCE : elle ne change qu'à
  /// l'occasion d'une modification dans l'espace d'administration. Sans ce
  /// cache, chaque ouverture du formulaire de réserve — geste répété des
  /// dizaines de fois par jour sur un chantier — repartait en requête, y
  /// compris en 3G au sous-sol.
  ///
  /// Il sert aussi de REPLI hors ligne : si l'appel échoue mais qu'on a déjà
  /// reçu le catalogue, on rend la dernière version connue plutôt qu'une
  /// erreur qui viderait la liste déroulante.
  List<CorpsEtat>? _cache;

  CorpsEtatRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, List<CorpsEtat>>> getCorpsEtatActifs() async {
    try {
      final liste = await remoteDataSource.getCorpsEtatActifs();
      _cache = liste;
      return Right(liste);
    } catch (e) {
      final cache = _cache;
      if (cache != null) return Right(cache);
      return Left(exceptionToFailure(e));
    }
  }
}

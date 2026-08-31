import 'package:dartz/dartz.dart';

import '../../../../core/errors/exception_to_failure.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/entities/pays.dart';
import '../../domain/entities/type_referentiel.dart';
import '../../domain/repositories/referentiel_repository.dart';
import '../datasources/referentiel_remote_datasource.dart';

class ReferentielRepositoryImpl implements ReferentielRepository {
  final ReferentielRemoteDataSource remoteDataSource;

  /// Dernier catalogue reçu pour CHAQUE référentiel, gardé le temps de la
  /// session.
  ///
  /// Ce sont des données de RÉFÉRENCE : elles ne changent qu'à l'occasion
  /// d'une modification dans l'espace d'administration. Sans ce cache, chaque
  /// ouverture d'un formulaire repartait en requête, y compris en 3G au
  /// sous-sol.
  ///
  /// Il sert aussi de REPLI hors ligne : si l'appel échoue mais qu'on a déjà
  /// reçu la liste, on rend la dernière version connue plutôt qu'une erreur
  /// qui viderait le sélecteur.
  final Map<ReferentielType, List<TypeReferentiel>> _cache = {};

  /// Catalogue des pays, gardé pour la session. Il ne change qu'avec une
  /// livraison : le relire à chaque ouverture du formulaire d'inscription
  /// n'apprendrait rien.
  List<Pays>? _cachePays;

  ReferentielRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, List<TypeReferentiel>>> getTypesActifs(
    ReferentielType referentiel,
  ) async {
    try {
      final liste = await remoteDataSource.getTypesActifs(referentiel);
      _cache[referentiel] = liste;
      return Right(liste);
    } catch (e) {
      final cache = _cache[referentiel];
      if (cache != null) return Right(cache);
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<Pays>>> getPays() async {
    try {
      final liste = await remoteDataSource.getPays();
      _cachePays = liste;
      return Right(liste);
    } catch (e) {
      final cache = _cachePays;
      if (cache != null) return Right(cache);
      return Left(exceptionToFailure(e));
    }
  }
}

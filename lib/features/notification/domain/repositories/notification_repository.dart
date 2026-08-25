import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../../data/datasources/notification_remote_datasource.dart';

abstract class NotificationRepository {
  Future<Either<Failure, PageNotifications>> lister({int page, int limit});
  Future<Either<Failure, int>> compterNonLues();

  /// [ids] vide = tout marquer comme lu.
  Future<Either<Failure, void>> marquerLues(List<String> ids);

  Future<Either<Failure, void>> enregistrerAppareil(String jeton, String plateforme);
  Future<Either<Failure, void>> oublierAppareil(String jeton);
}

import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../../data/datasources/notification_remote_datasource.dart';
import '../repositories/notification_repository.dart';

class GetNotifications {
  final NotificationRepository repository;
  GetNotifications(this.repository);

  Future<Either<Failure, PageNotifications>> call({int page = 1, int limit = 20}) =>
      repository.lister(page: page, limit: limit);
}

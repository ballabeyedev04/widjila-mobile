import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../repositories/notification_repository.dart';

class MarquerNotificationsLues {
  final NotificationRepository repository;
  MarquerNotificationsLues(this.repository);

  /// Sans identifiants, marque TOUTES les notifications comme lues.
  Future<Either<Failure, void>> call([List<String> ids = const []]) => repository.marquerLues(ids);
}

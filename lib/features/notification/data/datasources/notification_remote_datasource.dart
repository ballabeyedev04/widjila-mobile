import 'package:dio/dio.dart';

import '../../../../core/network/dio_exception_mapper.dart';
import '../../domain/entities/notification.dart';

/// Résultat d'une page de notifications, compteur de non-lues inclus : le
/// serveur le renvoie dans la même réponse (voir `notification.service.js`),
/// autant l'exploiter plutôt que de rappeler l'endpoint de comptage.
typedef PageNotifications = ({List<NotificationItem> items, int total, int nonLues});

abstract class NotificationRemoteDataSource {
  Future<PageNotifications> lister({int page, int limit});
  Future<int> compterNonLues();
  Future<void> marquerLues(List<String> ids);

  /// Déclare l'appareil courant auprès du serveur, pour qu'il reçoive les
  /// push. Idempotent : le back fait un upsert sur le jeton.
  Future<void> enregistrerAppareil(String jeton, String plateforme);

  /// Oublie l'appareil à la déconnexion — sans quoi il continuerait de
  /// recevoir les alertes du compte précédent.
  Future<void> oublierAppareil(String jeton);
}

class NotificationRemoteDataSourceImpl implements NotificationRemoteDataSource {
  final Dio dio;
  NotificationRemoteDataSourceImpl({required this.dio});

  Map<String, dynamic> _data(Response response) =>
      (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;

  @override
  Future<PageNotifications> lister({int page = 1, int limit = 20}) async {
    try {
      final response = await dio.get('/notifications', queryParameters: {'page': page, 'limit': limit});
      final data = _data(response);
      final items = (data['notifications'] as List? ?? [])
          .map((e) => NotificationItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return (
        items: items,
        total: (data['total'] as num?)?.toInt() ?? items.length,
        nonLues: (data['nonLuesCount'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<int> compterNonLues() async {
    try {
      final response = await dio.get('/notifications/non-lues/count');
      return (_data(response)['nonLuesCount'] as num?)?.toInt() ?? 0;
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// Liste vide = tout marquer comme lu (le serveur omet alors le filtre sur
  /// les identifiants).
  @override
  Future<void> marquerLues(List<String> ids) async {
    try {
      await dio.patch('/notifications/lues', data: ids.isEmpty ? <String, dynamic>{} : {'ids': ids});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> enregistrerAppareil(String jeton, String plateforme) async {
    try {
      await dio.post('/notifications/device-token', data: {'token': jeton, 'platform': plateforme});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> oublierAppareil(String jeton) async {
    try {
      await dio.delete('/notifications/device-token', data: {'token': jeton});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}

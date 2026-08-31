import 'package:dio/dio.dart';
import '../../../../core/network/dio_exception_mapper.dart';
import '../../domain/entities/chantier.dart';
import '../../domain/repositories/chantier_repository.dart';

abstract class ChantierRemoteDataSource {
  Future<ChantierPage> getChantiers({
    int page,
    int limit,
    String? search,
    ChantierStatut? statut,
    VueDemandes? demandes,
  });
  Future<Chantier> getChantierDetail(String id);
  Future<Chantier> creerChantier({
    required String nom,
    String? adresse,
    String? description,
  });
}

class ChantierRemoteDataSourceImpl implements ChantierRemoteDataSource {
  final Dio dio;
  ChantierRemoteDataSourceImpl({required this.dio});

  @override
  Future<ChantierPage> getChantiers({
    int page = 1,
    int limit = 20,
    String? search,
    ChantierStatut? statut,
    VueDemandes? demandes,
  }) async {
    try {
      // `statut` est filtré CÔTÉ SERVEUR (`ChantierService.listChantiers`) :
      // filtrer localement une liste paginée ne montrerait que les chantiers
      // de la page déjà chargée.
      final response = await dio.get('/chantiers', queryParameters: {
        'page': page,
        'limit': limit,
        if (search != null && search.isNotEmpty) 'search': search,
        if (statut != null) 'statut': statut.raw,
        // Sans ce paramètre, le serveur écarte les demandes : l'écran de
        // suivi n'afficherait jamais rien.
        if (demandes != null) 'demandes': demandes.raw,
      });
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      final items = (data['chantiers'] as List).map((e) => Chantier.fromJson(e as Map<String, dynamic>)).toList();
      return ChantierPage(items: items, total: data['total'] as int? ?? items.length);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Chantier> creerChantier({
    required String nom,
    String? adresse,
    String? description,
  }) async {
    try {
      // Aucun `statut` n'est envoyé : le serveur le DÉDUIT du rôle de
      // l'appelant, et l'ignorerait de toute façon pour une demande. En
      // envoyer un laisserait croire que le mobile en décide.
      final response = await dio.post('/chantiers', data: {
        'nom': nom,
        if (adresse != null && adresse.isNotEmpty) 'adresse': adresse,
        if (description != null && description.isNotEmpty) 'description': description,
      });
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      return Chantier.fromJson(data['chantier'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Chantier> getChantierDetail(String id) async {
    try {
      final response = await dio.get('/chantiers/$id');
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      return Chantier.fromJson(data['chantier'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}

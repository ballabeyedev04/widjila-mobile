import 'package:dio/dio.dart';
import '../../../../core/network/dio_exception_mapper.dart';
import '../../domain/entities/chantier_structure.dart';
import '../../domain/entities/reserve.dart';
import '../../domain/entities/reserve_collaboration.dart';
import '../../domain/entities/reserve_evolution.dart';
import '../../domain/repositories/reserve_repository.dart';

abstract class ReserveRemoteDataSource {
  Future<ReservePage> getReserves({
    required String chantierId,
    int page,
    int limit,
    String? search,
    ReserveStatut? statut,
  });

  Future<ReservePage> getToutesReserves({
    int page,
    int limit,
    String? search,
    ReserveStatut? statut,
  });

  Future<ReserveStatutsCount> getStatutsCount(String chantierId);

  /// Répartition par statut sur TOUTE l'organisation — alimente les compteurs
  /// des puces de filtre de l'onglet « Réserves », qui n'est rattaché à aucun
  /// chantier.
  Future<ReserveStatutsCount> getStatutsCountGlobal();

  /// `PUT /reserves/:id` — champs partiels (`modifierReserveSchema`).
  Future<Reserve> modifierReserve(String id, Map<String, dynamic> payload);

  /// `DELETE /reserves/:id` — suppression logique (paranoid) côté serveur.
  Future<void> supprimerReserve(String id);

  Future<List<CommentaireReserve>> getCommentaires(String reserveId);
  Future<CommentaireReserve> ajouterCommentaire(String reserveId, String message);

  Future<List<AffectationReserve>> getAffectations(String reserveId);
  Future<AffectationReserve> affecter(String reserveId, Map<String, dynamic> payload);
  Future<void> retirerAffectation(String reserveId, String affectationId);

  /// `POST /reserves/:id/dupliquer` — renvoie la COPIE, pas l'original.
  Future<Reserve> dupliquerReserve(String id);

  /// `GET /reserves/:id/qr` — image régénérée à chaque appel.
  Future<QrReserve> getQr(String id);

  Future<Reserve> getReserveDetail(String id);

  Future<Reserve> creerReserve({
    required String chantierId,
    required String titre,
    String? description,
    required ReserveSeverite priorite,
    required ReserveCategorie categorie,
    String? batimentId,
    String? etageId,
    String? zoneId,
    String? lotId,
    DateTime? dateLimite,
    // Identifiant CLIENT (mode hors ligne) — voir la justification dans
    // `backend/src/modules/reserve/validation/reserve.validation.js`. Absent
    // en usage normal (en ligne) : le serveur génère l'id comme avant.
    String? id,
  });

  Future<Reserve> changerStatut({required String reserveId, required ReserveStatut statut, String? motif});

  Future<List<ReserveMedia>> getMedias(String reserveId);

  Future<ReserveMedia> ajouterMedia({required String reserveId, required String cheminFichier, String type = 'photo'});

  Future<ChantierStructure> getStructure(String chantierId);

  Future<ReserveEvolution> getEvolution(String chantierId);
}

class ReserveRemoteDataSourceImpl implements ReserveRemoteDataSource {
  final Dio dio;
  ReserveRemoteDataSourceImpl({required this.dio});

  /// Enveloppe `data` des réponses de l'API (`{ success, message, data }`).
  Map<String, dynamic> _data(Response response) =>
      (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;

  @override
  Future<ReservePage> getReserves({
    required String chantierId,
    int page = 1,
    int limit = 20,
    String? search,
    ReserveStatut? statut,
  }) async {
    try {
      final response = await dio.get('/chantiers/$chantierId/reserves', queryParameters: {
        'page': page,
        'limit': limit,
        if (search != null && search.isNotEmpty) 'search': search,
        if (statut != null) 'statut': statut.raw,
      });
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      final items = (data['reserves'] as List).map((e) => Reserve.fromJson(e as Map<String, dynamic>)).toList();
      return ReservePage(items: items, total: data['total'] as int? ?? items.length);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<ReservePage> getToutesReserves({
    int page = 1,
    int limit = 20,
    String? search,
    ReserveStatut? statut,
  }) async {
    try {
      final response = await dio.get('/reserves', queryParameters: {
        'page': page,
        'limit': limit,
        if (search != null && search.isNotEmpty) 'search': search,
        if (statut != null) 'statut': statut.raw,
      });
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      final items = (data['reserves'] as List).map((e) => Reserve.fromJson(e as Map<String, dynamic>)).toList();
      return ReservePage(items: items, total: data['total'] as int? ?? items.length);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// `GET /dashboard` et `GET /dashboard/chantiers/:id` renvoient la MÊME
  /// forme (`data.stats.parStatut` + `data.stats.reserves.total`) — une seule
  /// lecture sert donc les deux échelles.
  ReserveStatutsCount _lireStatuts(Response response) {
    final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    final stats = data['stats'] as Map<String, dynamic>;
    final parStatutRaw = (stats['parStatut'] as Map<String, dynamic>?) ?? const {};
    final parStatut = <ReserveStatut, int>{
      for (final entry in parStatutRaw.entries) ReserveStatutX.fromString(entry.key): entry.value as int,
    };
    final total = (stats['reserves'] as Map<String, dynamic>?)?['total'] as int? ??
        parStatut.values.fold<int>(0, (a, b) => a + b);
    return ReserveStatutsCount(parStatut: parStatut, total: total);
  }

  @override
  Future<ReserveStatutsCount> getStatutsCount(String chantierId) async {
    try {
      return _lireStatuts(await dio.get('/dashboard/chantiers/$chantierId'));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<ReserveStatutsCount> getStatutsCountGlobal() async {
    try {
      return _lireStatuts(await dio.get('/dashboard'));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Reserve> modifierReserve(String id, Map<String, dynamic> payload) async {
    try {
      final response = await dio.put('/reserves/$id', data: payload);
      return Reserve.fromJson(_data(response)['reserve'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> supprimerReserve(String id) async {
    try {
      await dio.delete('/reserves/$id');
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<CommentaireReserve>> getCommentaires(String reserveId) async {
    try {
      final response = await dio.get('/reserves/$reserveId/commentaires');
      final liste = _data(response)['commentaires'] as List;
      return liste.map((e) => CommentaireReserve.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<CommentaireReserve> ajouterCommentaire(String reserveId, String message) async {
    try {
      final response = await dio.post('/reserves/$reserveId/commentaires', data: {'message': message});
      return CommentaireReserve.fromJson(_data(response)['commentaire'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<AffectationReserve>> getAffectations(String reserveId) async {
    try {
      final response = await dio.get('/reserves/$reserveId/affectations');
      final liste = _data(response)['affectations'] as List;
      return liste.map((e) => AffectationReserve.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<AffectationReserve> affecter(String reserveId, Map<String, dynamic> payload) async {
    try {
      final response = await dio.post('/reserves/$reserveId/affectations', data: payload);
      return AffectationReserve.fromJson(_data(response)['affectation'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> retirerAffectation(String reserveId, String affectationId) async {
    try {
      await dio.delete('/reserves/$reserveId/affectations/$affectationId');
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Reserve> dupliquerReserve(String id) async {
    try {
      final response = await dio.post('/reserves/$id/dupliquer');
      return Reserve.fromJson(_data(response)['reserve'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<QrReserve> getQr(String id) async {
    try {
      final response = await dio.get('/reserves/$id/qr');
      return QrReserve.fromJson(_data(response));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Reserve> getReserveDetail(String id) async {
    try {
      final response = await dio.get('/reserves/$id');
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      return Reserve.fromJson(data['reserve'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Reserve> creerReserve({
    required String chantierId,
    required String titre,
    String? description,
    required ReserveSeverite priorite,
    required ReserveCategorie categorie,
    String? batimentId,
    String? etageId,
    String? zoneId,
    String? lotId,
    DateTime? dateLimite,
    String? id,
  }) async {
    try {
      final response = await dio.post('/chantiers/$chantierId/reserves', data: {
        if (id != null) 'id': id,
        'titre': titre,
        if (description != null && description.isNotEmpty) 'description': description,
        'priorite': priorite.raw,
        'categorie': categorie.raw,
        if (batimentId != null) 'batimentId': batimentId,
        if (etageId != null) 'etageId': etageId,
        if (zoneId != null) 'zoneId': zoneId,
        if (lotId != null) 'lotId': lotId,
        if (dateLimite != null) 'date_limite': dateLimite.toIso8601String().split('T').first,
      });
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      return Reserve.fromJson(data['reserve'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Reserve> changerStatut({required String reserveId, required ReserveStatut statut, String? motif}) async {
    try {
      final response = await dio.patch('/reserves/$reserveId/statut', data: {
        'statut': statut.raw,
        if (motif != null && motif.isNotEmpty) 'motif': motif,
      });
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      return Reserve.fromJson(data['reserve'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<ReserveMedia>> getMedias(String reserveId) async {
    try {
      final response = await dio.get('/reserves/$reserveId/medias');
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      return (data['medias'] as List).map((e) => ReserveMedia.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<ReserveMedia> ajouterMedia({required String reserveId, required String cheminFichier, String type = 'photo'}) async {
    try {
      final formData = FormData.fromMap({
        'type': type,
        'fichier': await MultipartFile.fromFile(cheminFichier),
      });
      final response = await dio.post('/reserves/$reserveId/medias', data: formData);
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      return ReserveMedia.fromJson(data['media'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<ChantierStructure> getStructure(String chantierId) async {
    try {
      final response = await dio.get('/chantiers/$chantierId');
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      return ChantierStructure.fromJson(data['chantier'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<ReserveEvolution> getEvolution(String chantierId) async {
    try {
      final response = await dio.get('/dashboard/chantiers/$chantierId/evolution');
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      return ReserveEvolution.fromJson(data['stats'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}

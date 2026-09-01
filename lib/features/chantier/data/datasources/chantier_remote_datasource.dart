import 'package:dio/dio.dart';
import '../../../../core/network/dio_exception_mapper.dart';
import '../../../referentiel/domain/entities/code_niveau.dart';
import '../../../reserve/domain/entities/chantier_structure.dart';
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
    String? code,
    String? adresse,
    String? description,
    double? latitude,
    double? longitude,
    DateTime? dateDebut,
    DateTime? dateFin,
    num? budget,
    String? responsableId,
  });

  /// Ajoute un bâtiment au chantier.
  Future<BatimentStructure> creerBatiment(String chantierId, {required String nom, String? code});

  /// Ajoute un niveau à un bâtiment — sa nature range l'étage sous
  /// « SOUS-SOLS », « ÉTAGES » ou « TOITURE ».
  Future<EtageStructure> creerEtage(
    String chantierId,
    String batimentId, {
    required String nom,
    required TypeNiveau typeNiveau,
    String? codeNiveau,
    String? description,
    int? niveau,
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
    String? code,
    String? adresse,
    String? description,
    double? latitude,
    double? longitude,
    DateTime? dateDebut,
    DateTime? dateFin,
    num? budget,
    String? responsableId,
  }) async {
    try {
      // Aucun `statut` n'est envoyé : le serveur le DÉDUIT du rôle de
      // l'appelant, et l'ignorerait de toute façon pour une demande. En
      // envoyer un laisserait croire que le mobile en décide.
      //
      // Les champs vides sont OMIS plutôt qu'envoyés à null : le schéma Joi
      // les tolère, mais une chaîne vide en base se relit ensuite comme une
      // valeur renseignée.
      final response = await dio.post('/chantiers', data: {
        'nom': nom,
        if (code != null && code.isNotEmpty) 'code': code,
        if (adresse != null && adresse.isNotEmpty) 'adresse': adresse,
        if (description != null && description.isNotEmpty) 'description': description,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        // Date SEULE (yyyy-MM-dd) : le serveur attend une date de chantier,
        // pas un instant. Envoyer l'heure locale décalerait la date d'un jour
        // pour les fuseaux à l'ouest de Greenwich.
        if (dateDebut != null) 'date_debut': _jour(dateDebut),
        if (dateFin != null) 'date_fin': _jour(dateFin),
        if (budget != null) 'budget': budget,
        if (responsableId != null && responsableId.isNotEmpty) 'responsableId': responsableId,
      });
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      return Chantier.fromJson(data['chantier'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<BatimentStructure> creerBatiment(
    String chantierId, {
    required String nom,
    String? code,
  }) async {
    try {
      final response = await dio.post('/chantiers/$chantierId/batiments', data: {
        'nom': nom,
        if (code != null && code.isNotEmpty) 'code': code,
      });
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      return BatimentStructure.fromJson(data['batiment'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<EtageStructure> creerEtage(
    String chantierId,
    String batimentId, {
    required String nom,
    required TypeNiveau typeNiveau,
    String? codeNiveau,
    String? description,
    int? niveau,
  }) async {
    try {
      final response = await dio.post(
        '/chantiers/$chantierId/batiments/$batimentId/etages',
        data: {
          'nom': nom,
          'typeNiveau': typeNiveau.raw,
          if (codeNiveau != null && codeNiveau.isNotEmpty) 'codeNiveau': codeNiveau,
          if (description != null && description.isNotEmpty) 'description': description,
          if (niveau != null) 'niveau': niveau,
        },
      );
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      return EtageStructure.fromJson(data['etage'] as Map<String, dynamic>);
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

/// Date SEULE, sans heure — `yyyy-MM-dd`.
///
/// Le serveur attend une date de chantier, pas un instant. Envoyer un
/// horodatage complet décalerait la date d'un jour pour tout fuseau à l'ouest
/// de Greenwich, une fois converti en UTC.
String _jour(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

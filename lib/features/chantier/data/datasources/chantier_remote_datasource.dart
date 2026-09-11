import 'package:dio/dio.dart';
import '../../../../core/network/dio_exception_mapper.dart';
import '../../../referentiel/domain/entities/code_niveau.dart';
import '../../../reserve/domain/entities/chantier_structure.dart';
import '../../domain/entities/chantier.dart';
import '../../domain/entities/membre_chantier.dart';
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

  /// `PUT /chantiers/:id/batiments/:b` — renomme un bâtiment.
  Future<BatimentStructure> modifierBatiment(String chantierId, String batimentId, {required String nom});

  /// `DELETE /chantiers/:id/batiments/:b`. Refusé par le serveur tant qu'une
  /// réserve y est rattachée — son message remonte tel quel.
  Future<void> supprimerBatiment(String chantierId, String batimentId);

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

  /// `PUT /chantiers/:id/batiments/:b/etages/:e` — renomme un niveau.
  Future<EtageStructure> modifierEtage(
    String chantierId,
    String batimentId,
    String etageId, {
    required String nom,
  });

  /// `DELETE /chantiers/:id/batiments/:b/etages/:e`. Même garde que le
  /// bâtiment : refusé tant qu'une réserve y est rattachée.
  Future<void> supprimerEtage(String chantierId, String batimentId, String etageId);

  /// Ajoute un appartement (zone) à un niveau.
  Future<ZoneStructure> creerZone(
    String chantierId,
    String batimentId,
    String etageId, {
    required String nom,
    String? type,
  });

  /// `PUT /chantiers/:id/batiments/:b/etages/:e/zones/:z` — renomme un
  /// appartement. Le serveur exige au moins un champ (`modifierZoneSchema`).
  Future<ZoneStructure> modifierZone(
    String chantierId,
    String batimentId,
    String etageId,
    String zoneId, {
    required String nom,
  });

  /// `DELETE /chantiers/:id/batiments/:b/etages/:e/zones/:z`.
  ///
  /// Le serveur REFUSE tant qu'une réserve pointe sur l'appartement : la
  /// garde qui compte n'est pas le rôle mais l'état (voir
  /// `chantier.service.js#supprimerZone`). Le message de refus remonte tel
  /// quel à l'écran.
  Future<void> supprimerZone(
    String chantierId,
    String batimentId,
    String etageId,
    String zoneId,
  );

  /// `GET /chantiers/:id/membres` — membres affectés au chantier.
  Future<List<MembreChantier>> getMembresChantier(String chantierId);

  /// `GET /chantiers/:id/membres/candidats` — membres ACTIFS de
  /// l'organisation pas encore affectés.
  Future<List<MembreChantier>> getCandidatsMembres(String chantierId);

  /// `POST /chantiers/:id/membres` — affecte un ou plusieurs membres.
  Future<void> affecterMembres(String chantierId, {required List<String> membreIds, String? roleChantier});

  /// `DELETE /chantiers/:id/membres/:membreId`.
  Future<void> retirerMembre(String chantierId, String membreId);
}

class ChantierRemoteDataSourceImpl implements ChantierRemoteDataSource {
  final Dio dio;
  ChantierRemoteDataSourceImpl({required this.dio});

  Map<String, dynamic> _data(Response<dynamic> response) =>
      (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;

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
      final data = _data(response);
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
      return Chantier.fromJson(_data(response)['chantier'] as Map<String, dynamic>);
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
      return BatimentStructure.fromJson(_data(response)['batiment'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<BatimentStructure> modifierBatiment(String chantierId, String batimentId, {required String nom}) async {
    try {
      final response = await dio.put('/chantiers/$chantierId/batiments/$batimentId', data: {'nom': nom});
      return BatimentStructure.fromJson(_data(response)['batiment'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> supprimerBatiment(String chantierId, String batimentId) async {
    try {
      await dio.delete('/chantiers/$chantierId/batiments/$batimentId');
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
      return EtageStructure.fromJson(_data(response)['etage'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<EtageStructure> modifierEtage(
    String chantierId,
    String batimentId,
    String etageId, {
    required String nom,
  }) async {
    try {
      final response = await dio.put(
        '/chantiers/$chantierId/batiments/$batimentId/etages/$etageId',
        data: {'nom': nom},
      );
      return EtageStructure.fromJson(_data(response)['etage'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> supprimerEtage(String chantierId, String batimentId, String etageId) async {
    try {
      await dio.delete('/chantiers/$chantierId/batiments/$batimentId/etages/$etageId');
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<ZoneStructure> creerZone(
    String chantierId,
    String batimentId,
    String etageId, {
    required String nom,
    String? type,
  }) async {
    try {
      final response = await dio.post(
        '/chantiers/$chantierId/batiments/$batimentId/etages/$etageId/zones',
        data: {
          'nom': nom,
          if (type != null && type.isNotEmpty) 'type': type,
        },
      );
      return ZoneStructure.fromJson(_data(response)['zone'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<ZoneStructure> modifierZone(
    String chantierId,
    String batimentId,
    String etageId,
    String zoneId, {
    required String nom,
  }) async {
    try {
      final response = await dio.put(
        '/chantiers/$chantierId/batiments/$batimentId/etages/$etageId/zones/$zoneId',
        data: {'nom': nom},
      );
      return ZoneStructure.fromJson(_data(response)['zone'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> supprimerZone(
    String chantierId,
    String batimentId,
    String etageId,
    String zoneId,
  ) async {
    try {
      await dio.delete(
        '/chantiers/$chantierId/batiments/$batimentId/etages/$etageId/zones/$zoneId',
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Chantier> getChantierDetail(String id) async {
    try {
      final response = await dio.get('/chantiers/$id');
      return Chantier.fromJson(_data(response)['chantier'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<MembreChantier>> getMembresChantier(String chantierId) async {
    try {
      final response = await dio.get('/chantiers/$chantierId/membres');
      return (_data(response)['membres'] as List? ?? [])
          .map((e) => MembreChantier.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<MembreChantier>> getCandidatsMembres(String chantierId) async {
    try {
      final response = await dio.get('/chantiers/$chantierId/membres/candidats');
      return (_data(response)['candidats'] as List? ?? [])
          .map((e) => MembreChantier.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> affecterMembres(String chantierId, {required List<String> membreIds, String? roleChantier}) async {
    try {
      await dio.post('/chantiers/$chantierId/membres', data: {
        'membreIds': membreIds,
        if (roleChantier != null && roleChantier.trim().isNotEmpty) 'roleChantier': roleChantier.trim(),
      });
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> retirerMembre(String chantierId, String membreId) async {
    try {
      await dio.delete('/chantiers/$chantierId/membres/$membreId');
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

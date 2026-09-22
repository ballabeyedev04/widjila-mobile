import 'package:dio/dio.dart';

import '../../../../core/network/dio_exception_mapper.dart';
import '../../domain/entities/configuration_rapport.dart';
import '../../domain/entities/envoi_rapport.dart';
import '../../domain/entities/option_filtre.dart';
import '../../domain/entities/rapport.dart';
import '../../domain/entities/suivi_rapport.dart';

/// API du module Rapports — § 9 du cahier des charges.
///
/// Deux familles de routes cohabitent :
///  - `/reports/…` — le module du cahier des charges (configuration,
///    génération, envoi, partage, historique) ;
///  - `/chantiers/:id/rapports` et `/rapports/:id` — les anciennes, gardées
///    pour la liste et la suppression, qu'utilisent encore l'espace web et
///    les versions du mobile déjà installées.
abstract class RapportRemoteDataSource {
  Future<List<Rapport>> getRapports(String chantierId);

  /// Ancien point d'entrée — un rapport en un seul geste, sans configuration.
  Future<Rapport> genererRapport({
    required String chantierId,
    required RapportType type,
    String? statutReserve,
    String? entrepriseId,
    String? batimentId,
  });

  Future<void> supprimerRapport(String id);

  /// `POST /reports` — enregistre la configuration, en BROUILLON.
  Future<Rapport> creerRapport(ConfigurationRapport configuration);

  /// `PATCH /reports/:id` — revient sur la configuration (§ 20).
  Future<Rapport> modifierRapport(String id, ConfigurationRapport configuration);

  Future<Rapport> detailRapport(String id);

  /// `POST /reports/:id/generate` — les douze étapes du § 11.
  Future<Rapport> genererRapportConfigure(String id);

  /// `POST /reports/:id/generate-by-company` — § 15.
  Future<ResultatParEntreprise> genererParEntreprise(String id);

  /// `GET /reports/:id/preview?mode=resume` — le périmètre chiffré.
  Future<ResumeRapport> resumeRapport(String id);

  Future<List<EntreeHistoriqueRapport>> historique(String id);
  Future<List<PartageRapport>> partages(String id);
  Future<LienPartageRapport> partager(String id, {int? expireDansJours, bool authentificationRequise = false});
  Future<void> revoquerPartage(String id, String partageId);
  Future<Rapport> dupliquer(String id);
  Future<Rapport> archiver(String id);

  /// Compose l'e-mail SANS l'envoyer — l'écran de vérification (§ 13).
  Future<EnvoiRapport> preparerEnvoi(String rapportId);

  /// Envoie réellement, sur confirmation.
  /// [cleIdempotence] — même valeur pour une même intention d'envoi (tentative
  /// en ligne, puis rejeu de la file) : le serveur ne réexpédie pas un envoi
  /// déjà parti, et répond 409 `ENVOI_EN_COURS` s'il est en train de partir.
  Future<String> envoyerRapport(String rapportId, DemandeEnvoiRapport demande, {String? cleIdempotence});

  /// Les projets accessibles — l'étape « Choisir le projet » du § 3.
  Future<List<OptionFiltre>> getProjets();

  /// L'annuaire ACCESSIBLE au chantier — ses entreprises et celles de
  /// l'organisation (ajoutées depuis « Intervenants »), archivées exclues.
  Future<List<OptionFiltre>> getEntreprisesChantier(String chantierId);

  Future<List<OptionFiltre>> getCorpsEtat();
}

class RapportRemoteDataSourceImpl implements RapportRemoteDataSource {
  final Dio dio;
  RapportRemoteDataSourceImpl({required this.dio});

  /// La génération relit réserves, photos et plans puis compose le PDF :
  /// sur un gros chantier, elle dépasse le délai de réception par défaut. On
  /// l'allonge pour ELLE seule — une liste qui mettrait cinq minutes à
  /// répondre serait, elle, une panne à signaler.
  static const _delaiGeneration = Duration(minutes: 5);

  Map<String, dynamic> _data(Response response) =>
      (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;

  Rapport _rapport(Response response) =>
      Rapport.fromJson(_data(response)['rapport'] as Map<String, dynamic>);

  Future<T> _appel<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<Rapport>> getRapports(String chantierId) => _appel(() async {
        final response = await dio.get('/chantiers/$chantierId/rapports');
        return (_data(response)['rapports'] as List)
            .map((e) => Rapport.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  @override
  Future<Rapport> genererRapport({
    required String chantierId,
    required RapportType type,
    String? statutReserve,
    String? entrepriseId,
    String? batimentId,
  }) =>
      _appel(() async {
        final response = await dio.post(
          '/chantiers/$chantierId/rapports/generer',
          data: {
            'chantierId': chantierId,
            'type': type.raw,
            // Un filtre absent n'est PAS transmis : `null` serait lu comme
            // « aucune entreprise », et le rapport sortirait vide.
            'statut': ?statutReserve,
            'entrepriseId': ?entrepriseId,
            'batimentId': ?batimentId,
          },
          options: Options(receiveTimeout: _delaiGeneration),
        );
        return _rapport(response);
      });

  @override
  Future<void> supprimerRapport(String id) => _appel(() => dio.delete('/rapports/$id'));

  @override
  Future<Rapport> creerRapport(ConfigurationRapport configuration) => _appel(() async {
        final response = await dio.post('/reports', data: configuration.toJson());
        return _rapport(response);
      });

  @override
  Future<Rapport> modifierRapport(String id, ConfigurationRapport configuration) => _appel(() async {
        // Le chantier ne change pas : un rapport ne se déplace pas d'un projet
        // à l'autre, et le serveur ne l'accepterait pas dans ce corps.
        final response = await dio.patch('/reports/$id', data: configuration.toJson(avecChantier: false));
        return _rapport(response);
      });

  @override
  Future<Rapport> detailRapport(String id) => _appel(() async => _rapport(await dio.get('/reports/$id')));

  @override
  Future<Rapport> genererRapportConfigure(String id) => _appel(() async {
        final response = await dio.post(
          '/reports/$id/generate',
          options: Options(receiveTimeout: _delaiGeneration),
        );
        return _rapport(response);
      });

  @override
  Future<ResultatParEntreprise> genererParEntreprise(String id) => _appel(() async {
        final response = await dio.post(
          '/reports/$id/generate-by-company',
          // Un document par entreprise : dix entreprises, dix générations.
          options: Options(receiveTimeout: _delaiGeneration * 3),
        );
        return ResultatParEntreprise.fromJson(response.data as Map<String, dynamic>);
      });

  @override
  Future<ResumeRapport> resumeRapport(String id) => _appel(() async {
        final response = await dio.get('/reports/$id/preview', queryParameters: {'mode': 'resume'});
        return ResumeRapport.fromJson(_data(response)['resume'] as Map<String, dynamic>);
      });

  @override
  Future<List<EntreeHistoriqueRapport>> historique(String id) => _appel(() async {
        final response = await dio.get('/reports/$id/history');
        return ((_data(response)['historique'] as List?) ?? const [])
            .map((e) => EntreeHistoriqueRapport.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  @override
  Future<List<PartageRapport>> partages(String id) => _appel(() async {
        final response = await dio.get('/reports/$id/shares');
        return ((_data(response)['partages'] as List?) ?? const [])
            .map((e) => PartageRapport.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  @override
  Future<LienPartageRapport> partager(String id, {int? expireDansJours, bool authentificationRequise = false}) =>
      _appel(() async {
        final response = await dio.post('/reports/$id/share', data: {
          'expireDansJours': expireDansJours,
          'authentificationRequise': authentificationRequise,
        });
        return LienPartageRapport.fromJson(_data(response));
      });

  @override
  Future<void> revoquerPartage(String id, String partageId) =>
      _appel(() => dio.delete('/reports/$id/shares/$partageId'));

  @override
  Future<Rapport> dupliquer(String id) => _appel(() async => _rapport(await dio.post('/reports/$id/duplicate')));

  @override
  Future<Rapport> archiver(String id) => _appel(() async => _rapport(await dio.post('/reports/$id/archive')));

  @override
  Future<EnvoiRapport> preparerEnvoi(String rapportId) => _appel(() async {
        // GET : PRÉPARE et n'envoie rien. Le POST sur la même route envoie ;
        // les confondre enverrait le rapport à la simple ouverture de l'écran.
        final response = await dio.get('/reports/$rapportId/send-email');
        return EnvoiRapport.fromJson(_data(response)['envoi'] as Map<String, dynamic>);
      });

  @override
  Future<String> envoyerRapport(String rapportId, DemandeEnvoiRapport demande, {String? cleIdempotence}) =>
      _appel(() async {
        final response = await dio.post(
          '/reports/$rapportId/send-email',
          data: demande.toJson(),
          options: cleIdempotence == null ? null : Options(headers: {'Idempotency-Key': cleIdempotence}),
        );
        // Le message du serveur dit qui a reçu quoi — le reprendre tel quel
        // vaut mieux qu'un « Envoyé » qui n'apprend rien.
        return (response.data as Map<String, dynamic>)['message']?.toString() ?? '';
      });

  @override
  Future<List<OptionFiltre>> getProjets() => _appel(() async {
        final response = await dio.get('/chantiers', queryParameters: {'page': 1, 'limit': 100});
        return ((_data(response)['chantiers'] as List?) ?? const [])
            .map((e) => OptionFiltre.fromJson(e as Map<String, dynamic>, cleDetail: 'code'))
            .toList();
      });

  @override
  Future<List<OptionFiltre>> getEntreprisesChantier(String chantierId) => _appel(() async {
        final response = await dio.get(
          '/chantiers/$chantierId/partenaires',
          queryParameters: {'limit': 100, 'actif': 'true'},
        );
        return ((_data(response)['partenaires'] as List?) ?? const [])
            .map((e) => OptionFiltre.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  @override
  Future<List<OptionFiltre>> getCorpsEtat() => _appel(() async {
        final response = await dio.get('/corps-etat/actifs');
        return ((_data(response)['corpsEtat'] as List?) ?? const [])
            .map((e) => OptionFiltre.fromJson(e as Map<String, dynamic>))
            .toList();
      });
}

import 'package:equatable/equatable.dart';

import 'configuration_rapport.dart';

/// Une ligne de l'historique d'un rapport — § 18 du cahier des charges.
///
/// « 10/09/2026 - Rapport créé par utilisateur A », « 11/09/2026 - Rapport
/// consulté via lien ». Le LIBELLÉ vient du serveur, qui connaît toutes les
/// actions ; une action ajoutée plus tard s'affiche donc correctement sans
/// mise à jour du mobile.
class EntreeHistoriqueRapport extends Equatable {
  final String id;
  final String action;
  final String libelle;

  /// Nul pour une consultation par lien public : personne n'était connecté.
  final String? acteur;
  final DateTime? date;
  final Map<String, dynamic> metadata;

  const EntreeHistoriqueRapport({
    required this.id,
    required this.action,
    required this.libelle,
    this.acteur,
    this.date,
    this.metadata = const {},
  });

  factory EntreeHistoriqueRapport.fromJson(Map<String, dynamic> json) => EntreeHistoriqueRapport(
        id: json['id']?.toString() ?? '',
        action: json['action']?.toString() ?? '',
        libelle: json['libelle']?.toString() ?? json['action']?.toString() ?? '',
        acteur: json['acteur'] as String?,
        date: json['date'] is String ? DateTime.tryParse(json['date'] as String) : null,
        metadata: (json['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  @override
  List<Object?> get props => [id, action, libelle, acteur, date, metadata];
}

/// Un lien de partage — § 14.
///
/// Le jeton lui-même n'est JAMAIS relu : le serveur n'en garde que
/// l'empreinte. Seul le lien rendu à la création ([LienPartageRapport]) le
/// contient.
class PartageRapport extends Equatable {
  final String id;
  final DateTime? expireLe;
  final DateTime? revoqueLe;
  final int nbAcces;
  final DateTime? dernierAccesLe;
  final bool authentificationRequise;
  final bool actif;
  final DateTime? creeLe;

  const PartageRapport({
    required this.id,
    this.expireLe,
    this.revoqueLe,
    this.nbAcces = 0,
    this.dernierAccesLe,
    this.authentificationRequise = false,
    this.actif = true,
    this.creeLe,
  });

  factory PartageRapport.fromJson(Map<String, dynamic> json) {
    DateTime? date(String cle) => json[cle] is String ? DateTime.tryParse(json[cle] as String) : null;
    return PartageRapport(
      id: json['id']?.toString() ?? '',
      expireLe: date('expireLe'),
      revoqueLe: date('revoqueLe'),
      nbAcces: (json['nbAcces'] as num?)?.toInt() ?? 0,
      dernierAccesLe: date('dernierAccesLe'),
      authentificationRequise: json['authentificationRequise'] as bool? ?? false,
      actif: json['actif'] as bool? ?? true,
      creeLe: date('creeLe'),
    );
  }

  @override
  List<Object?> get props =>
      [id, expireLe, revoqueLe, nbAcces, dernierAccesLe, authentificationRequise, actif, creeLe];
}

/// Le lien tout juste créé — seul moment où son URL complète est connue.
class LienPartageRapport extends Equatable {
  final String url;
  final String partageId;
  final DateTime? expireLe;
  final bool authentificationRequise;

  const LienPartageRapport({
    required this.url,
    required this.partageId,
    this.expireLe,
    this.authentificationRequise = false,
  });

  factory LienPartageRapport.fromJson(Map<String, dynamic> json) {
    final partage = (json['partage'] as Map?)?.cast<String, dynamic>() ?? const {};
    return LienPartageRapport(
      url: json['url']?.toString() ?? '',
      partageId: partage['id']?.toString() ?? '',
      expireLe: partage['expireLe'] is String ? DateTime.tryParse(partage['expireLe'] as String) : null,
      authentificationRequise: partage['authentificationRequise'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [url, partageId, expireLe, authentificationRequise];
}

/// Le périmètre chiffré d'un rapport, AVANT de le produire (§ 20).
///
/// C'est ce qui évite de découvrir un rapport vide après trente secondes de
/// génération.
class ResumeRapport extends Equatable {
  final int total;
  final Map<StatutReserveRapport, int> parStatut;
  final Map<GraviteRapport, int> parGravite;
  final int entreprises;

  const ResumeRapport({
    required this.total,
    this.parStatut = const {},
    this.parGravite = const {},
    this.entreprises = 0,
  });

  factory ResumeRapport.fromJson(Map<String, dynamic> json) {
    Map<K, int> compter<K>(String cle, K? Function(String?) lire) {
      final brut = (json[cle] as Map?)?.cast<String, dynamic>() ?? const {};
      final sortie = <K, int>{};
      brut.forEach((code, valeur) {
        final k = lire(code);
        if (k != null) sortie[k] = (valeur as num?)?.toInt() ?? 0;
      });
      return sortie;
    }

    return ResumeRapport(
      total: (json['total'] as num?)?.toInt() ?? (json['reserves'] as num?)?.toInt() ?? 0,
      parStatut: compter('parStatut', StatutReserveRapportX.fromString),
      parGravite: compter('parGravite', GraviteRapportX.fromString),
      entreprises: (json['entreprises'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [total, parStatut, parGravite, entreprises];
}

/// Résultat de « Générer les rapports par entreprise » — § 15.
class ResultatParEntreprise extends Equatable {
  final String message;
  final int nbRapports;
  final List<String> echecs;

  /// Réserves du périmètre qui ne sont rattachées à aucune entreprise : elles
  /// ne figurent dans aucun des documents, et l'écran doit le dire.
  final int reservesSansEntreprise;

  const ResultatParEntreprise({
    required this.message,
    required this.nbRapports,
    this.echecs = const [],
    this.reservesSansEntreprise = 0,
  });

  factory ResultatParEntreprise.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ResultatParEntreprise(
      message: json['message']?.toString() ?? '',
      nbRapports: ((data['rapports'] as List?) ?? const []).length,
      echecs: ((data['echecs'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => '${e['entreprise']} : ${e['message']}')
          .toList(),
      reservesSansEntreprise: (data['reservesSansEntreprise'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [message, nbRapports, echecs, reservesSansEntreprise];
}

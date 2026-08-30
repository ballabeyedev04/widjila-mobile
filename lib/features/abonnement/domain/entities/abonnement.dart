import 'package:equatable/equatable.dart';

/// Formule d'abonnement — miroir de `backend/src/models/planAbonnement.model.js`.
///
/// Le PRIX vient du serveur et n'est jamais calculé ici : le mobile ne fait
/// que l'afficher. Un montant décidé côté client n'aurait de toute façon aucun
/// effet, le backend relit le tarif en base au moment de facturer.
class FormuleAbonnement extends Equatable {
  final String id;
  final String code;
  final String nom;
  final String? description;

  /// `null` = sur devis : la formule s'affiche mais ne se souscrit pas en
  /// ligne. Afficher 0 confondrait « gratuit » et « nous consulter ».
  final double? prix;
  final String devise;
  final String periode;
  final bool surDevis;

  /// `null` = illimité, jamais -1.
  final int? limiteUtilisateurs;
  final int? limiteChantiers;

  /// CODES des fonctionnalités (`reserves`, `rapports`…), traduits à
  /// l'affichage : les recevoir déjà traduits figerait la langue.
  final List<String> fonctionnalites;

  const FormuleAbonnement({
    required this.id,
    required this.code,
    required this.nom,
    this.description,
    this.prix,
    this.devise = 'EUR',
    this.periode = 'mois',
    this.surDevis = false,
    this.limiteUtilisateurs,
    this.limiteChantiers,
    this.fonctionnalites = const [],
  });

  factory FormuleAbonnement.fromJson(Map<String, dynamic> json) => FormuleAbonnement(
        id: json['id'] as String,
        code: json['code'] as String? ?? '',
        nom: json['nom'] as String? ?? '',
        description: json['description'] as String?,
        prix: (json['prix'] as num?)?.toDouble(),
        devise: json['devise'] as String? ?? 'EUR',
        periode: json['periode'] as String? ?? 'mois',
        surDevis: json['surDevis'] as bool? ?? (json['prix'] == null),
        limiteUtilisateurs: (json['limiteUtilisateurs'] as num?)?.toInt(),
        limiteChantiers: (json['limiteChantiers'] as num?)?.toInt(),
        fonctionnalites: (json['fonctionnalites'] as List?)?.cast<String>() ?? const [],
      );

  @override
  List<Object?> get props =>
      [id, code, nom, description, prix, devise, periode, surDevis, limiteUtilisateurs, limiteChantiers, fonctionnalites];
}

/// Consommation face à une limite — alimente « 4 / 5 utilisateurs ».
class UsageRessource extends Equatable {
  final int courant;

  /// `null` = illimité.
  final int? limite;

  const UsageRessource({required this.courant, this.limite});

  factory UsageRessource.fromJson(Map<String, dynamic>? json) => UsageRessource(
        courant: (json?['courant'] as num?)?.toInt() ?? 0,
        limite: (json?['limite'] as num?)?.toInt(),
      );

  bool get illimite => limite == null;

  /// Vrai quand le plafond est atteint — sert à prévenir AVANT le refus.
  bool get atteint => limite != null && courant >= limite!;

  @override
  List<Object?> get props => [courant, limite];
}

/// Droits effectifs de l'organisation, tels que calculés par le serveur.
///
/// Le mobile s'en sert pour MASQUER ou griser, jamais pour autoriser : les
/// gardes réelles vivent dans l'API. Un code mobile modifié ne donne donc
/// aucun accès supplémentaire.
class DroitsAbonnement extends Equatable {
  final bool actif;

  /// `abonnement`, `essai` ou `aucun`.
  final String source;
  final String? planNom;
  final String? planCode;

  /// `null` = toutes (période d'essai).
  final List<String>? fonctionnalites;

  final bool essaiEnCours;
  final DateTime? dateFin;
  final UsageRessource utilisateurs;
  final UsageRessource chantiers;

  const DroitsAbonnement({
    this.actif = false,
    this.source = 'aucun',
    this.planNom,
    this.planCode,
    this.fonctionnalites,
    this.essaiEnCours = false,
    this.dateFin,
    this.utilisateurs = const UsageRessource(courant: 0),
    this.chantiers = const UsageRessource(courant: 0),
  });

  factory DroitsAbonnement.fromJson(Map<String, dynamic> json) {
    final droits = json['droits'] as Map<String, dynamic>? ?? const {};
    final usage = json['usage'] as Map<String, dynamic>? ?? const {};
    final liste = droits['fonctionnalites'] as List?;

    return DroitsAbonnement(
      actif: droits['actif'] as bool? ?? false,
      source: droits['source'] as String? ?? 'aucun',
      planNom: droits['planNom'] as String?,
      planCode: droits['planCode'] as String?,
      // `null` (toutes) et `[]` (aucune) sont deux choses différentes : les
      // confondre ouvrirait tout aux organisations sans droits.
      fonctionnalites: liste?.cast<String>(),
      essaiEnCours: droits['essaiEnCours'] as bool? ?? false,
      dateFin: droits['dateFin'] != null ? DateTime.tryParse(droits['dateFin'] as String) : null,
      utilisateurs: UsageRessource.fromJson(usage['utilisateurs'] as Map<String, dynamic>?),
      chantiers: UsageRessource.fromJson(usage['chantiers'] as Map<String, dynamic>?),
    );
  }

  /// Vrai si la formule ouvre cette fonctionnalité.
  bool peut(String fonctionnalite) {
    if (!actif) return false;
    if (fonctionnalites == null) return true; // essai : tout est ouvert
    return fonctionnalites!.contains(fonctionnalite);
  }

  @override
  List<Object?> get props =>
      [actif, source, planNom, planCode, fonctionnalites, essaiEnCours, dateFin, utilisateurs, chantiers];
}

import 'package:equatable/equatable.dart';

/// Organisation de l'utilisateur connecté — miroir de
/// `backend/src/models/organisation.model.js`, tel que renvoyé par
/// `GET /organisation` (`OrganisationService.getOrganisation`).
///
/// Deux familles de champs, à ne pas confondre à l'écran :
///
///  - IDENTITÉ (nom, raison sociale, SIRET, TVA, RCCM, NINEA, coordonnées,
///    adresse) : modifiable via `PUT /organisation`, réservé aux rôles GESTION
///    (`requireRole(...GESTION)` sur la route) ;
///  - ABONNEMENT (formule, essai, actif) : piloté par la facturation, jamais
///    modifiable depuis l'application — affiché en lecture seule.
class Organisation extends Equatable {
  final String id;
  final String nom;
  final String? raisonSociale;
  final String? siret;
  final String? numTva;
  final String? rccm;
  final String? ninea;
  final String? telephone;
  final String? email;
  final String? adresse;
  final String? ville;
  final String? pays;
  final String? logoUrl;

  /// 'Starter' | 'Pro' | 'Business' | 'Enterprise'
  final String? abonnement;
  final bool estAbonnee;
  final DateTime? finEssai;

  /// 'siege' | 'filiale' | 'agence' — voir le modèle backend.
  final String? type;
  final String? statut;

  const Organisation({
    required this.id,
    required this.nom,
    this.raisonSociale,
    this.siret,
    this.numTva,
    this.rccm,
    this.ninea,
    this.telephone,
    this.email,
    this.adresse,
    this.ville,
    this.pays,
    this.logoUrl,
    this.abonnement,
    this.estAbonnee = false,
    this.finEssai,
    this.type,
    this.statut,
  });

  /// Adresse en une ligne : « 12 rue X, Dakar, Sénégal », en sautant les
  /// morceaux absents plutôt qu'en laissant des virgules orphelines.
  String get adresseComplete =>
      [adresse, ville, pays].where((e) => e != null && e.trim().isNotEmpty).join(', ');

  /// Vrai tant que la période d'essai court — le backend applique la même
  /// règle dans `checkSubscription.middleware.js` (une date absente vaut
  /// essai TERMINÉ, jamais illimité).
  bool get essaiEnCours => finEssai != null && finEssai!.isAfter(DateTime.now());

  factory Organisation.fromJson(Map<String, dynamic> json) => Organisation(
        id: json['id'] as String,
        nom: json['nom'] as String? ?? '',
        raisonSociale: json['raison_sociale'] as String?,
        siret: json['siret'] as String?,
        numTva: json['num_tva'] as String?,
        rccm: json['rccm'] as String?,
        ninea: json['ninea'] as String?,
        telephone: json['telephone'] as String?,
        email: json['email'] as String?,
        adresse: json['adresse'] as String?,
        ville: json['ville'] as String?,
        pays: json['pays'] as String?,
        logoUrl: json['logo_url'] as String?,
        abonnement: json['abonnement'] as String?,
        estAbonnee: json['is_subscribed'] as bool? ?? false,
        finEssai: json['trial_ends_at'] != null
            ? DateTime.tryParse(json['trial_ends_at'] as String)
            : null,
        type: json['type'] as String?,
        statut: json['statut'] as String?,
      );

  @override
  List<Object?> get props => [
        id, nom, raisonSociale, siret, numTva, rccm, ninea,
        telephone, email, adresse, ville, pays, logoUrl,
        abonnement, estAbonnee, finEssai, type, statut,
      ];
}

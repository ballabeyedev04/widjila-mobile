import 'package:equatable/equatable.dart';

import '../../../../l10n/generated/app_localizations.dart';

/// Type de partenaire — miroir de l'ENUM `type`
/// (`backend/src/models/partenaire.model.js`).
enum PartenaireType {
  client,
  maitreOuvrage,
  maitreOeuvre,
  sousTraitant,
  fournisseur,
  bureauControle,
  autre,
}

extension PartenaireTypeX on PartenaireType {
  static PartenaireType fromString(String? raw) {
    switch (raw) {
      case 'client':
        return PartenaireType.client;
      case 'maitre_ouvrage':
        return PartenaireType.maitreOuvrage;
      case 'maitre_oeuvre':
        return PartenaireType.maitreOeuvre;
      case 'sous_traitant':
        return PartenaireType.sousTraitant;
      case 'fournisseur':
        return PartenaireType.fournisseur;
      case 'bureau_controle':
        return PartenaireType.bureauControle;
      default:
        return PartenaireType.autre;
    }
  }

  String get raw => switch (this) {
        PartenaireType.client => 'client',
        PartenaireType.maitreOuvrage => 'maitre_ouvrage',
        PartenaireType.maitreOeuvre => 'maitre_oeuvre',
        PartenaireType.sousTraitant => 'sous_traitant',
        PartenaireType.fournisseur => 'fournisseur',
        PartenaireType.bureauControle => 'bureau_controle',
        PartenaireType.autre => 'autre',
      };

  String label(AppLocalizations l10n) => switch (this) {
        PartenaireType.client => l10n.roleClient,
        PartenaireType.maitreOuvrage => l10n.roleMaitreOuvrage,
        PartenaireType.maitreOeuvre => l10n.roleMaitreOeuvre,
        PartenaireType.sousTraitant => l10n.roleSousTraitant,
        PartenaireType.fournisseur => l10n.partenaireFournisseur,
        PartenaireType.bureauControle => l10n.roleBureauControle,
        PartenaireType.autre => l10n.commonAutre,
      };
}

/// Partenaire / intervenant — miroir de
/// `backend/src/models/partenaire.model.js`.
class Partenaire extends Equatable {
  final String id;
  final String nom;
  final PartenaireType type;
  final String? email;
  final String? telephone;

  /// Personne référente chez ce partenaire (champ libre côté back).
  final String? contact;

  final String? adresse;
  final String? notes;

  /// Intervenant actif ou archivé — miroir de la colonne `actif`
  /// (`backend/src/models/partenaire.model.js`).
  ///
  /// À DISTINGUER de la suppression : un intervenant inactif reste dans
  /// l'annuaire, garde son historique et peut être réactivé ; la suppression
  /// (réservée au chef de projet) le retire pour de bon.
  final bool actif;

  /// Chantier auquel le partenaire est rattaché — `null` si le partenaire
  /// est déclaré au niveau de l'organisation et non d'un chantier précis.
  final String? chantierId;

  const Partenaire({
    required this.id,
    required this.nom,
    required this.type,
    this.email,
    this.telephone,
    this.contact,
    this.adresse,
    this.notes,
    this.chantierId,
    this.actif = true,
  });

  factory Partenaire.fromJson(Map<String, dynamic> json) => Partenaire(
        id: json['id'] as String,
        nom: json['nom'] as String? ?? '',
        type: PartenaireTypeX.fromString(json['type'] as String?),
        email: json['email'] as String?,
        telephone: json['telephone'] as String?,
        contact: json['contact'] as String?,
        adresse: json['adresse'] as String?,
        notes: json['notes'] as String?,
        chantierId: json['chantierId'] as String? ?? json['chantier_id'] as String?,
        // Défaut à `true` : les fiches créées avant la migration `actif`
        // n'ont pas le champ, et une absence ne doit pas les faire passer
        // pour archivées.
        actif: json['actif'] as bool? ?? true,
      );

  /// Initiales — sert de pastille à défaut de logo (le modèle back n'en
  /// stocke pas pour les partenaires).
  String get initiales {
    final mots = nom.trim().split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
    if (mots.isEmpty) return '?';
    if (mots.length == 1) return mots.first.substring(0, 1).toUpperCase();
    return (mots[0].substring(0, 1) + mots[1].substring(0, 1)).toUpperCase();
  }

  /// Copie avec un [actif] différent — sert au retour optimiste de la
  /// bascule si le serveur ne renvoie pas la fiche complète.
  Partenaire copyWith({bool? actif}) => Partenaire(
        id: id,
        nom: nom,
        type: type,
        email: email,
        telephone: telephone,
        contact: contact,
        adresse: adresse,
        notes: notes,
        chantierId: chantierId,
        actif: actif ?? this.actif,
      );

  @override
  List<Object?> get props =>
      [id, nom, type, email, telephone, contact, adresse, notes, chantierId, actif];
}

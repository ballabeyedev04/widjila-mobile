import 'package:equatable/equatable.dart';

import '../../../../l10n/generated/app_localizations.dart';

/// Statut d'une réserve — miroir exact de l'ENUM Sequelize
/// (`backend/src/models/reserve.model.js` + la matrice de transitions dans
/// `reserve.service.js`). Les libellés/tons sont alignés sur l'admin web
/// (`admin/src/utils/constants.js#STATUTS_RESERVE`) — même vocabulaire des
/// deux côtés plutôt qu'un regroupement simplifié qui diverge du back.
enum ReserveStatut {
  creee,
  affectee,
  priseEnCharge,
  enCours,
  corrigee,
  aVerifier,
  validee,
  refusee,
  rouverte,
  enRetard,
  cloturee,
}

extension ReserveStatutX on ReserveStatut {
  static ReserveStatut fromString(String? raw) {
    switch (raw) {
      case 'creee':
        return ReserveStatut.creee;
      case 'affectee':
        return ReserveStatut.affectee;
      case 'prise_en_charge':
        return ReserveStatut.priseEnCharge;
      case 'en_cours':
        return ReserveStatut.enCours;
      case 'corrigee':
        return ReserveStatut.corrigee;
      case 'a_verifier':
        return ReserveStatut.aVerifier;
      case 'validee':
        return ReserveStatut.validee;
      case 'refusee':
        return ReserveStatut.refusee;
      case 'rouverte':
        return ReserveStatut.rouverte;
      case 'en_retard':
        return ReserveStatut.enRetard;
      case 'cloturee':
        return ReserveStatut.cloturee;
      default:
        return ReserveStatut.creee;
    }
  }

  String get raw {
    switch (this) {
      case ReserveStatut.creee:
        return 'creee';
      case ReserveStatut.affectee:
        return 'affectee';
      case ReserveStatut.priseEnCharge:
        return 'prise_en_charge';
      case ReserveStatut.enCours:
        return 'en_cours';
      case ReserveStatut.corrigee:
        return 'corrigee';
      case ReserveStatut.aVerifier:
        return 'a_verifier';
      case ReserveStatut.validee:
        return 'validee';
      case ReserveStatut.refusee:
        return 'refusee';
      case ReserveStatut.rouverte:
        return 'rouverte';
      case ReserveStatut.enRetard:
        return 'en_retard';
      case ReserveStatut.cloturee:
        return 'cloturee';
    }
  }

  String label(AppLocalizations l10n) {
    switch (this) {
      case ReserveStatut.creee:
        return l10n.statutCreee;
      case ReserveStatut.affectee:
        return l10n.statutAffectee;
      case ReserveStatut.priseEnCharge:
        return l10n.statutPriseEnCharge;
      case ReserveStatut.enCours:
        return l10n.statutEnCours;
      case ReserveStatut.corrigee:
        return l10n.statutCorrigee;
      case ReserveStatut.aVerifier:
        return l10n.statutAVerifier;
      case ReserveStatut.validee:
        return l10n.statutValidee;
      case ReserveStatut.refusee:
        return l10n.statutRefusee;
      case ReserveStatut.rouverte:
        return l10n.statutRouverte;
      case ReserveStatut.enRetard:
        return l10n.statutEnRetard;
      case ReserveStatut.cloturee:
        return l10n.statutCloturee;
    }
  }
}

enum ReserveSeverite { faible, moyenne, haute, critique }

extension ReserveSeveriteX on ReserveSeverite {
  static ReserveSeverite fromString(String? raw) {
    switch (raw) {
      case 'faible':
        return ReserveSeverite.faible;
      case 'haute':
        return ReserveSeverite.haute;
      case 'critique':
        return ReserveSeverite.critique;
      default:
        return ReserveSeverite.moyenne;
    }
  }

  String get raw {
    switch (this) {
      case ReserveSeverite.faible:
        return 'faible';
      case ReserveSeverite.moyenne:
        return 'moyenne';
      case ReserveSeverite.haute:
        return 'haute';
      case ReserveSeverite.critique:
        return 'critique';
    }
  }

  String label(AppLocalizations l10n) {
    switch (this) {
      case ReserveSeverite.faible:
        return l10n.severiteFaible;
      case ReserveSeverite.moyenne:
        return l10n.severiteMoyenne;
      case ReserveSeverite.haute:
        return l10n.severiteHaute;
      case ReserveSeverite.critique:
        return l10n.severiteCritique;
    }
  }
}

/// Catégorie — même liste ENUM que `categorie` côté back
/// (`reserve.validation.js`).
enum ReserveCategorie {
  maconnerie,
  grosOeuvre,
  plomberie,
  electricite,
  carrelage,
  peinture,
  menuiserie,
  etancheite,
  isolation,
  autre,
}

extension ReserveCategorieX on ReserveCategorie {
  static ReserveCategorie fromString(String? raw) {
    switch (raw) {
      case 'maconnerie':
        return ReserveCategorie.maconnerie;
      case 'gros_oeuvre':
        return ReserveCategorie.grosOeuvre;
      case 'plomberie':
        return ReserveCategorie.plomberie;
      case 'electricite':
        return ReserveCategorie.electricite;
      case 'carrelage':
        return ReserveCategorie.carrelage;
      case 'peinture':
        return ReserveCategorie.peinture;
      case 'menuiserie':
        return ReserveCategorie.menuiserie;
      case 'etancheite':
        return ReserveCategorie.etancheite;
      case 'isolation':
        return ReserveCategorie.isolation;
      default:
        return ReserveCategorie.autre;
    }
  }

  String get raw {
    switch (this) {
      case ReserveCategorie.maconnerie:
        return 'maconnerie';
      case ReserveCategorie.grosOeuvre:
        return 'gros_oeuvre';
      case ReserveCategorie.plomberie:
        return 'plomberie';
      case ReserveCategorie.electricite:
        return 'electricite';
      case ReserveCategorie.carrelage:
        return 'carrelage';
      case ReserveCategorie.peinture:
        return 'peinture';
      case ReserveCategorie.menuiserie:
        return 'menuiserie';
      case ReserveCategorie.etancheite:
        return 'etancheite';
      case ReserveCategorie.isolation:
        return 'isolation';
      case ReserveCategorie.autre:
        return 'autre';
    }
  }

  String label(AppLocalizations l10n) {
    switch (this) {
      case ReserveCategorie.maconnerie:
        return l10n.categorieMaconnerie;
      case ReserveCategorie.grosOeuvre:
        return l10n.categorieGrosOeuvre;
      case ReserveCategorie.plomberie:
        return l10n.categoriePlomberie;
      case ReserveCategorie.electricite:
        return l10n.categorieElectricite;
      case ReserveCategorie.carrelage:
        return l10n.categorieCarrelage;
      case ReserveCategorie.peinture:
        return l10n.categoriePeinture;
      case ReserveCategorie.menuiserie:
        return l10n.categorieMenuiserie;
      case ReserveCategorie.etancheite:
        return l10n.categorieEtancheite;
      case ReserveCategorie.isolation:
        return l10n.categorieIsolation;
      case ReserveCategorie.autre:
        return l10n.categorieAutre;
    }
  }
}

class ReserveLocalisationRef extends Equatable {
  final String id;
  final String nom;
  const ReserveLocalisationRef({required this.id, required this.nom});

  factory ReserveLocalisationRef.fromJson(Map<String, dynamic> json) =>
      ReserveLocalisationRef(id: json['id'] as String, nom: json['nom'] as String? ?? '');

  Map<String, dynamic> toJson() => {'id': id, 'nom': nom};

  @override
  List<Object?> get props => [id, nom];
}

class ReserveUtilisateurRef extends Equatable {
  final String id;
  final String nom;
  final String prenom;
  final String? photoProfil;
  const ReserveUtilisateurRef({required this.id, required this.nom, required this.prenom, this.photoProfil});

  factory ReserveUtilisateurRef.fromJson(Map<String, dynamic> json) => ReserveUtilisateurRef(
        id: json['id'] as String,
        nom: json['nom'] as String? ?? '',
        prenom: json['prenom'] as String? ?? '',
        photoProfil: json['photoProfil'] as String?,
      );

  String get nomComplet => '$prenom $nom'.trim();

  Map<String, dynamic> toJson() => {'id': id, 'nom': nom, 'prenom': prenom, 'photoProfil': photoProfil};

  @override
  List<Object?> get props => [id, nom, prenom, photoProfil];
}

/// Média (photo/vidéo) — miroir de `backend/src/models/media.model.js`.
class ReserveMedia extends Equatable {
  final String id;
  final String type;
  final String url;
  final String? thumbnailUrl;
  final DateTime? prisLe;

  const ReserveMedia({required this.id, required this.type, required this.url, this.thumbnailUrl, this.prisLe});

  factory ReserveMedia.fromJson(Map<String, dynamic> json) => ReserveMedia(
        id: json['id'] as String,
        type: json['type'] as String? ?? 'photo',
        url: json['url'] as String,
        thumbnailUrl: json['thumbnail_url'] as String?,
        prisLe: json['pris_le'] != null ? DateTime.tryParse(json['pris_le'] as String) : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'url': url,
        'thumbnail_url': thumbnailUrl,
        'pris_le': prisLe?.toIso8601String(),
      };

  @override
  List<Object?> get props => [id, type, url, thumbnailUrl, prisLe];
}

/// Entrée d'historique — miroir de
/// `backend/src/models/reserveHistorique.model.js`. `action` reste la
/// valeur brute du back (creation/modification/statut/commentaire/
/// validation/refus/suppression) : c'est [ReserveHistoriqueEntry.libelle]
/// qui porte la traduction pour l'affichage.
class ReserveHistoriqueEntry extends Equatable {
  final String id;
  final String action;
  final DateTime? createdAt;
  final ReserveUtilisateurRef? utilisateur;

  const ReserveHistoriqueEntry({required this.id, required this.action, this.createdAt, this.utilisateur});

  factory ReserveHistoriqueEntry.fromJson(Map<String, dynamic> json) => ReserveHistoriqueEntry(
        id: json['id'] as String,
        action: json['action'] as String? ?? '',
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
        utilisateur: json['utilisateur'] != null ? ReserveUtilisateurRef.fromJson(json['utilisateur'] as Map<String, dynamic>) : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'action': action,
        'createdAt': createdAt?.toIso8601String(),
        'utilisateur': utilisateur?.toJson(),
      };

  String libelle(AppLocalizations l10n) {
    switch (action) {
      case 'creation':
        return l10n.historiqueCreation;
      case 'modification':
        return l10n.historiqueModification;
      case 'statut':
        return l10n.historiqueStatut;
      case 'commentaire':
        return l10n.historiqueCommentaire;
      case 'validation':
        return l10n.historiqueValidation;
      case 'refus':
        return l10n.historiqueRefus;
      case 'suppression':
        return l10n.historiqueSuppression;
      default:
        return action;
    }
  }

  @override
  List<Object?> get props => [id, action, createdAt, utilisateur];
}

/// Réserve — miroir de `backend/src/models/reserve.model.js` + des
/// associations chargées par `listReserves`/`getReserve`.
class Reserve extends Equatable {
  /// Marqueur de numéro provisoire posé par `ReserveRepositoryImpl.creerReserve`
  /// en mode hors ligne, en attendant que le serveur attribue le vrai numéro
  /// de séquence (ex. « R-042 ») à la synchronisation. Jamais confondu avec un
  /// vrai numéro serveur — voir [numeroAffiche] pour sa traduction à l'affichage.
  static const numeroEnAttente = '__EN_ATTENTE__';

  final String id;
  final String numero;
  final String chantierId;
  final String titre;
  final String? description;
  final ReserveSeverite severite;
  final ReserveSeverite priorite;
  final ReserveCategorie categorie;
  final ReserveStatut statut;
  final DateTime? dateLimite;
  final DateTime? createdAt;
  final ReserveLocalisationRef? batiment;
  final ReserveLocalisationRef? etage;
  final ReserveLocalisationRef? zone;
  final ReserveLocalisationRef? lot;
  /// Organisation cliente en charge — renseignée seulement quand
  /// l'entreprise possède elle-même un compte dans l'application.
  final ReserveLocalisationRef? entreprise;

  /// « Entreprise concernée » du guide client : la fiche de l'ANNUAIRE du
  /// chantier (table `partenaires`). C'est le cas courant — la plupart des
  /// entreprises n'ont pas de compte. Voir `reserve.model.js#partenaireId`.
  final ReserveLocalisationRef? partenaire;

  /// Chantier porteur — renseigné par la liste TRANSVERSALE
  /// (`GET /reserves`) et par le détail, absent de la liste par chantier
  /// (où il serait redondant : on sait déjà de quel chantier il s'agit).
  final ReserveLocalisationRef? chantier;

  final ReserveUtilisateurRef? assigne;
  final ReserveUtilisateurRef? createur;
  final String? motifRefus;

  /// Première vignette photo (liste seulement — la galerie complète vient
  /// du détail via `/reserves/:id/medias`).
  final String? photoApercu;

  /// Galerie complète — présente seulement sur le détail (`getReserve`
  /// inclut `medias`), vide sur les éléments de liste.
  final List<ReserveMedia> medias;

  /// Historique complet — présent seulement sur le détail.
  final List<ReserveHistoriqueEntry> historiques;

  const Reserve({
    required this.id,
    required this.numero,
    required this.chantierId,
    required this.titre,
    this.description,
    this.severite = ReserveSeverite.moyenne,
    this.priorite = ReserveSeverite.moyenne,
    this.categorie = ReserveCategorie.autre,
    this.statut = ReserveStatut.creee,
    this.dateLimite,
    this.createdAt,
    this.batiment,
    this.etage,
    this.zone,
    this.lot,
    this.entreprise,
    this.partenaire,
    this.chantier,
    this.assigne,
    this.createur,
    this.motifRefus,
    this.photoApercu,
    this.medias = const [],
    this.historiques = const [],
  });

  /// Localisation lisible — concatène bâtiment/étage/zone dans l'ordre,
  /// à défaut « Non localisée » (aucun des trois n'est renseigné).
  String localisationLabel(AppLocalizations l10n) {
    final parts = [batiment?.nom, etage?.nom, zone?.nom].whereType<String>().where((s) => s.isNotEmpty);
    return parts.isEmpty ? l10n.reserveNonLocalisee : parts.join(' · ');
  }

  /// Numéro affiché — traduit le marqueur [numeroEnAttente] si la réserve a
  /// été créée hors ligne et n'a pas encore été synchronisée.
  String numeroAffiche(AppLocalizations l10n) => numero == numeroEnAttente ? l10n.reserveNumeroProvisoire : numero;

  factory Reserve.fromJson(Map<String, dynamic> json) {
    return Reserve(
      id: json['id'] as String,
      numero: json['numero'] as String? ?? '',
      chantierId: json['chantierId'] as String? ?? json['chantier_id'] as String? ?? '',
      titre: json['titre'] as String? ?? '',
      description: json['description'] as String?,
      severite: ReserveSeveriteX.fromString(json['severite'] as String?),
      priorite: ReserveSeveriteX.fromString(json['priorite'] as String?),
      categorie: ReserveCategorieX.fromString(json['categorie'] as String?),
      statut: ReserveStatutX.fromString(json['statut'] as String?),
      dateLimite: json['date_limite'] != null ? DateTime.tryParse(json['date_limite'] as String) : null,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      batiment: json['batiment'] != null ? ReserveLocalisationRef.fromJson(json['batiment'] as Map<String, dynamic>) : null,
      etage: json['etage'] != null ? ReserveLocalisationRef.fromJson(json['etage'] as Map<String, dynamic>) : null,
      zone: json['zone'] != null ? ReserveLocalisationRef.fromJson(json['zone'] as Map<String, dynamic>) : null,
      lot: json['lot'] != null ? ReserveLocalisationRef.fromJson(json['lot'] as Map<String, dynamic>) : null,
      entreprise: json['entreprise'] != null ? ReserveLocalisationRef.fromJson(json['entreprise'] as Map<String, dynamic>) : null,
      partenaire: json['partenaire'] != null ? ReserveLocalisationRef.fromJson(json['partenaire'] as Map<String, dynamic>) : null,
      chantier: json['chantier'] != null ? ReserveLocalisationRef.fromJson(json['chantier'] as Map<String, dynamic>) : null,
      assigne: json['assigne'] != null ? ReserveUtilisateurRef.fromJson(json['assigne'] as Map<String, dynamic>) : null,
      createur: json['createur'] != null ? ReserveUtilisateurRef.fromJson(json['createur'] as Map<String, dynamic>) : null,
      motifRefus: json['motif_refus'] as String?,
      photoApercu: (json['medias'] is List && (json['medias'] as List).isNotEmpty)
          ? ((json['medias'] as List).first as Map<String, dynamic>)['url'] as String?
          : null,
      medias: json['medias'] is List
          ? (json['medias'] as List).map((e) => ReserveMedia.fromJson(e as Map<String, dynamic>)).toList()
          : const [],
      historiques: json['historiques'] is List
          ? (json['historiques'] as List).map((e) => ReserveHistoriqueEntry.fromJson(e as Map<String, dynamic>)).toList()
          : const [],
    );
  }

  /// Miroir exact de [Reserve.fromJson] — mêmes clés, y compris
  /// `date_limite` au format court (jour seul, sans heure) qu'utilise déjà
  /// `ReserveRemoteDataSource.creerReserve`. `photoApercu` n'est PAS
  /// resérialisé : `fromJson` le recalcule depuis `medias`, l'y ajouter
  /// créerait une deuxième source de vérité pour la même information.
  Map<String, dynamic> toJson() => {
        'id': id,
        'numero': numero,
        'chantierId': chantierId,
        'titre': titre,
        'description': description,
        'severite': severite.raw,
        'priorite': priorite.raw,
        'categorie': categorie.raw,
        'statut': statut.raw,
        'date_limite': dateLimite?.toIso8601String().split('T').first,
        'createdAt': createdAt?.toIso8601String(),
        'batiment': batiment?.toJson(),
        'etage': etage?.toJson(),
        'zone': zone?.toJson(),
        'lot': lot?.toJson(),
        'entreprise': entreprise?.toJson(),
        'partenaire': partenaire?.toJson(),
        'chantier': chantier?.toJson(),
        'assigne': assigne?.toJson(),
        'createur': createur?.toJson(),
        'motif_refus': motifRefus,
        'medias': medias.map((m) => m.toJson()).toList(),
        'historiques': historiques.map((h) => h.toJson()).toList(),
      };

  /// Copie avec un nouveau statut — utilisée par la mise à jour OPTIMISTE
  /// hors ligne (`ReserveRepositoryImpl.changerStatut`) : l'écran doit
  /// refléter le changement immédiatement, sans attendre la synchronisation.
  Reserve copierAvecStatut(ReserveStatut nouveauStatut) => Reserve(
        id: id,
        numero: numero,
        chantierId: chantierId,
        titre: titre,
        description: description,
        severite: severite,
        priorite: priorite,
        categorie: categorie,
        statut: nouveauStatut,
        dateLimite: dateLimite,
        createdAt: createdAt,
        batiment: batiment,
        etage: etage,
        zone: zone,
        lot: lot,
        entreprise: entreprise,
        partenaire: partenaire,
        chantier: chantier,
        assigne: assigne,
        createur: createur,
        motifRefus: motifRefus,
        photoApercu: photoApercu,
        medias: medias,
        historiques: historiques,
      );

  @override
  List<Object?> get props => [
        id, numero, chantierId, titre, description, severite, priorite, categorie, statut, dateLimite, createdAt,
        batiment, etage, zone, lot, entreprise, partenaire, chantier, assigne, createur, motifRefus, photoApercu, medias, historiques,
      ];
}

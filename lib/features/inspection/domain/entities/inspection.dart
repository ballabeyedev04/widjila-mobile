import 'package:equatable/equatable.dart';

import '../../../../l10n/generated/app_localizations.dart';

/// Type de visite — miroir de l'ENUM Sequelize
/// (`backend/src/models/inspection.model.js`).
///
/// La distinction n'est pas cosmétique : une OPR (Opérations Préalables à la
/// Réception) et une visite contradictoire ont une portée contractuelle que
/// n'a pas une inspection ordinaire — leur compte rendu fait foi.
enum InspectionType { inspection, opr, visiteContradictoire }

extension InspectionTypeX on InspectionType {
  static InspectionType fromString(String? raw) {
    switch (raw) {
      case 'opr':
        return InspectionType.opr;
      case 'visite_contradictoire':
        return InspectionType.visiteContradictoire;
      default:
        return InspectionType.inspection;
    }
  }

  String get raw {
    switch (this) {
      case InspectionType.inspection:
        return 'inspection';
      case InspectionType.opr:
        return 'opr';
      case InspectionType.visiteContradictoire:
        return 'visite_contradictoire';
    }
  }

  String label(AppLocalizations l10n) {
    switch (this) {
      case InspectionType.inspection:
        return l10n.inspectionTypeInspection;
      case InspectionType.opr:
        return l10n.inspectionTypeOpr;
      case InspectionType.visiteContradictoire:
        return l10n.inspectionTypeVisiteContradictoire;
    }
  }
}

/// Cycle de vie d'une visite : planifiée → en cours → terminée → signée.
enum InspectionStatut { planifiee, enCours, terminee, signee }

extension InspectionStatutX on InspectionStatut {
  static InspectionStatut fromString(String? raw) {
    switch (raw) {
      case 'en_cours':
        return InspectionStatut.enCours;
      case 'terminee':
        return InspectionStatut.terminee;
      case 'signee':
        return InspectionStatut.signee;
      default:
        return InspectionStatut.planifiee;
    }
  }

  String get raw {
    switch (this) {
      case InspectionStatut.planifiee:
        return 'planifiee';
      case InspectionStatut.enCours:
        return 'en_cours';
      case InspectionStatut.terminee:
        return 'terminee';
      case InspectionStatut.signee:
        return 'signee';
    }
  }

  String label(AppLocalizations l10n) {
    switch (this) {
      case InspectionStatut.planifiee:
        return l10n.inspectionStatutPlanifiee;
      case InspectionStatut.enCours:
        return l10n.inspectionStatutEnCours;
      case InspectionStatut.terminee:
        return l10n.inspectionStatutTerminee;
      case InspectionStatut.signee:
        return l10n.inspectionStatutSignee;
    }
  }

  /// Une visite signée est FIGÉE : son compte rendu peut être opposé aux
  /// parties, le modifier après coup n'aurait aucune valeur.
  bool get estFigee => this == InspectionStatut.signee;
}

/// Personne rattachée à une visite (inspecteur, convoqué).
class PersonneInspection extends Equatable {
  final String id;
  final String nom;
  final String prenom;
  final String? photoProfil;

  const PersonneInspection({
    required this.id,
    this.nom = '',
    this.prenom = '',
    this.photoProfil,
  });

  String get nomComplet => '$prenom $nom'.trim();

  factory PersonneInspection.fromJson(Map<String, dynamic> json) => PersonneInspection(
        id: json['id'] as String? ?? '',
        nom: json['nom'] as String? ?? '',
        prenom: json['prenom'] as String? ?? '',
        photoProfil: json['photoProfil'] as String?,
      );

  @override
  List<Object?> get props => [id, nom, prenom, photoProfil];
}

/// Un point à vérifier — miroir de `backend/src/models/checklist.model.js`.
class LigneChecklist extends Equatable {
  final String id;
  final String libelle;
  final bool coche;
  final String? commentaire;

  const LigneChecklist({
    required this.id,
    required this.libelle,
    this.coche = false,
    this.commentaire,
  });

  LigneChecklist copyWith({bool? coche, String? commentaire}) => LigneChecklist(
        id: id,
        libelle: libelle,
        coche: coche ?? this.coche,
        commentaire: commentaire ?? this.commentaire,
      );

  factory LigneChecklist.fromJson(Map<String, dynamic> json) => LigneChecklist(
        id: json['id'] as String,
        libelle: json['libelle'] as String? ?? '',
        coche: json['coche'] as bool? ?? false,
        commentaire: json['commentaire'] as String?,
      );

  @override
  List<Object?> get props => [id, libelle, coche, commentaire];
}

/// Réponse d'un convoqué — miroir de `backend/src/models/convocation.model.js`.
enum StatutConvocation { invite, accepte, decline, present, absent }

extension StatutConvocationX on StatutConvocation {
  static StatutConvocation fromString(String? raw) {
    switch (raw) {
      case 'accepte':
        return StatutConvocation.accepte;
      case 'decline':
        return StatutConvocation.decline;
      case 'present':
        return StatutConvocation.present;
      case 'absent':
        return StatutConvocation.absent;
      default:
        return StatutConvocation.invite;
    }
  }

  String get raw {
    switch (this) {
      case StatutConvocation.invite:
        return 'invite';
      case StatutConvocation.accepte:
        return 'accepte';
      case StatutConvocation.decline:
        return 'decline';
      case StatutConvocation.present:
        return 'present';
      case StatutConvocation.absent:
        return 'absent';
    }
  }

  String label(AppLocalizations l10n) {
    switch (this) {
      case StatutConvocation.invite:
        return l10n.convocationInvite;
      case StatutConvocation.accepte:
        return l10n.convocationAccepte;
      case StatutConvocation.decline:
        return l10n.convocationDecline;
      case StatutConvocation.present:
        return l10n.convocationPresent;
      case StatutConvocation.absent:
        return l10n.convocationAbsent;
    }
  }
}

class Convocation extends Equatable {
  final String id;
  final PersonneInspection? utilisateur;
  final StatutConvocation statut;
  final DateTime? renduLe;

  const Convocation({
    required this.id,
    this.utilisateur,
    this.statut = StatutConvocation.invite,
    this.renduLe,
  });

  factory Convocation.fromJson(Map<String, dynamic> json) => Convocation(
        id: json['id'] as String,
        utilisateur: json['utilisateur'] != null
            ? PersonneInspection.fromJson(json['utilisateur'] as Map<String, dynamic>)
            : null,
        statut: StatutConvocationX.fromString(json['statut'] as String?),
        renduLe: json['repondu_le'] != null ? DateTime.tryParse(json['repondu_le'] as String) : null,
      );

  @override
  List<Object?> get props => [id, utilisateur, statut, renduLe];
}

/// Visite de chantier — miroir de `backend/src/models/inspection.model.js`.
class Inspection extends Equatable {
  final String id;
  final String chantierId;
  final String? chantierNom;
  final InspectionType type;
  final InspectionStatut statut;
  final DateTime? dateVisite;
  final String? compteRendu;
  final String? rapportUrl;
  final PersonneInspection? inspecteur;
  final List<LigneChecklist> checklist;
  final DateTime? createdAt;

  const Inspection({
    required this.id,
    required this.chantierId,
    this.chantierNom,
    this.type = InspectionType.inspection,
    this.statut = InspectionStatut.planifiee,
    this.dateVisite,
    this.compteRendu,
    this.rapportUrl,
    this.inspecteur,
    this.checklist = const [],
    this.createdAt,
  });

  int get nbCoches => checklist.where((l) => l.coche).length;
  int get nbPoints => checklist.length;

  /// Avancement entre 0 et 1. Une visite sans point de contrôle vaut 0 plutôt
  /// que NaN — la division par zéro afficherait une barre cassée.
  double get avancement => nbPoints == 0 ? 0 : nbCoches / nbPoints;

  bool get estComplete => nbPoints > 0 && nbCoches == nbPoints;

  Inspection copyWith({
    InspectionStatut? statut,
    String? compteRendu,
    List<LigneChecklist>? checklist,
  }) =>
      Inspection(
        id: id,
        chantierId: chantierId,
        chantierNom: chantierNom,
        type: type,
        statut: statut ?? this.statut,
        dateVisite: dateVisite,
        compteRendu: compteRendu ?? this.compteRendu,
        rapportUrl: rapportUrl,
        inspecteur: inspecteur,
        checklist: checklist ?? this.checklist,
        createdAt: createdAt,
      );

  factory Inspection.fromJson(Map<String, dynamic> json) {
    final chantier = json['chantier'] as Map<String, dynamic>?;
    return Inspection(
      id: json['id'] as String,
      chantierId: json['chantierId'] as String? ?? chantier?['id'] as String? ?? '',
      chantierNom: chantier?['nom'] as String?,
      type: InspectionTypeX.fromString(json['type'] as String?),
      statut: InspectionStatutX.fromString(json['statut'] as String?),
      // `DATEONLY` côté serveur : la chaîne est « 2026-08-25 », sans fuseau.
      // `DateTime.tryParse` la lit en heure locale, ce qui est le comportement
      // voulu — une date de visite n'a pas d'heure à décaler.
      dateVisite: json['date_visite'] != null ? DateTime.tryParse(json['date_visite'] as String) : null,
      compteRendu: json['compte_rendu'] as String?,
      rapportUrl: json['rapport_url'] as String?,
      inspecteur: json['inspecteur'] != null
          ? PersonneInspection.fromJson(json['inspecteur'] as Map<String, dynamic>)
          : null,
      checklist: (json['checklist'] as List?)
              ?.map((e) => LigneChecklist.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
    );
  }

  @override
  List<Object?> get props =>
      [id, chantierId, chantierNom, type, statut, dateVisite, compteRendu, rapportUrl, inspecteur, checklist, createdAt];
}

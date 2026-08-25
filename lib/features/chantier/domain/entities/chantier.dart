import 'package:equatable/equatable.dart';

import '../../../../l10n/generated/app_localizations.dart';

/// Statut d'un chantier — miroir de l'ENUM Sequelize
/// (`backend/src/models/chantier.model.js`).
enum ChantierStatut { enPreparation, enCours, enPause, archive, cloture }

extension ChantierStatutX on ChantierStatut {
  static ChantierStatut fromString(String? raw) {
    switch (raw) {
      case 'en_preparation':
        return ChantierStatut.enPreparation;
      case 'en_cours':
        return ChantierStatut.enCours;
      case 'en_pause':
        return ChantierStatut.enPause;
      case 'archive':
        return ChantierStatut.archive;
      case 'cloture':
        return ChantierStatut.cloture;
      default:
        return ChantierStatut.enPreparation;
    }
  }

  String get raw {
    switch (this) {
      case ChantierStatut.enPreparation:
        return 'en_preparation';
      case ChantierStatut.enCours:
        return 'en_cours';
      case ChantierStatut.enPause:
        return 'en_pause';
      case ChantierStatut.archive:
        return 'archive';
      case ChantierStatut.cloture:
        return 'cloture';
    }
  }

  String label(AppLocalizations l10n) {
    switch (this) {
      case ChantierStatut.enPreparation:
        return l10n.chantierStatutEnPreparation;
      case ChantierStatut.enCours:
        return l10n.chantierStatutEnCours;
      case ChantierStatut.enPause:
        return l10n.chantierStatutEnPause;
      case ChantierStatut.archive:
        return l10n.chantierStatutArchive;
      case ChantierStatut.cloture:
        return l10n.chantierStatutCloture;
    }
  }
}

class ResponsableChantier extends Equatable {
  final String id;
  final String nom;
  final String prenom;
  final String? email;
  final String? photoProfil;

  const ResponsableChantier({required this.id, required this.nom, required this.prenom, this.email, this.photoProfil});

  factory ResponsableChantier.fromJson(Map<String, dynamic> json) => ResponsableChantier(
        id: json['id'] as String,
        nom: json['nom'] as String? ?? '',
        prenom: json['prenom'] as String? ?? '',
        email: json['email'] as String?,
        photoProfil: json['photoProfil'] as String?,
      );

  String get nomComplet => '$prenom $nom'.trim();

  Map<String, dynamic> toJson() => {
        'id': id,
        'nom': nom,
        'prenom': prenom,
        'email': email,
        'photoProfil': photoProfil,
      };

  @override
  List<Object?> get props => [id, nom, prenom, email, photoProfil];
}

class Chantier extends Equatable {
  final String id;
  final String? code;
  final String nom;
  final String? description;
  final String? adresse;
  final DateTime? dateDebut;
  final DateTime? dateFin;
  final ChantierStatut statut;
  final ResponsableChantier? responsable;

  /// Nombre total de réserves — présent seulement dans la liste (agrégat
  /// calculé côté backend), `null` sur le détail.
  final int? reservesTotal;
  final int? reservesOuvertes;

  const Chantier({
    required this.id,
    this.code,
    required this.nom,
    this.description,
    this.adresse,
    this.dateDebut,
    this.dateFin,
    required this.statut,
    this.responsable,
    this.reservesTotal,
    this.reservesOuvertes,
  });

  factory Chantier.fromJson(Map<String, dynamic> json) {
    return Chantier(
      id: json['id'] as String,
      code: json['code'] as String?,
      nom: json['nom'] as String? ?? '',
      description: json['description'] as String?,
      adresse: json['adresse'] as String?,
      dateDebut: json['date_debut'] != null ? DateTime.tryParse(json['date_debut'] as String) : null,
      dateFin: json['date_fin'] != null ? DateTime.tryParse(json['date_fin'] as String) : null,
      statut: ChantierStatutX.fromString(json['statut'] as String?),
      responsable: json['responsable'] != null
          ? ResponsableChantier.fromJson(json['responsable'] as Map<String, dynamic>)
          : null,
      reservesTotal: (json['reservesStats'] as Map?)?['total'] as int?,
      reservesOuvertes: (json['reservesStats'] as Map?)?['ouvertes'] as int?,
    );
  }

  /// Miroir exact de [Chantier.fromJson] — mêmes clés, y compris le nid
  /// `reservesStats` — pour que la mise en cache locale (voir `CacheChantiers`)
  /// puis la relecture hors ligne redonnent BYTE POUR BYTE le même objet.
  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'nom': nom,
        'description': description,
        'adresse': adresse,
        'date_debut': dateDebut?.toIso8601String(),
        'date_fin': dateFin?.toIso8601String(),
        'statut': statut.raw,
        'responsable': responsable?.toJson(),
        if (reservesTotal != null || reservesOuvertes != null)
          'reservesStats': {
            if (reservesTotal != null) 'total': reservesTotal,
            if (reservesOuvertes != null) 'ouvertes': reservesOuvertes,
          },
      };

  @override
  List<Object?> get props => [
        id, code, nom, description, adresse, dateDebut, dateFin, statut,
        responsable, reservesTotal, reservesOuvertes,
      ];
}

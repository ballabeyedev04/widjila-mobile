import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';

/// Rôles métier — reflète exactement `backend/src/config/roles.js`.
///
/// Le rôle `Admin` (super-admin PLATEFORME, multi-organisation) est
/// volontairement ABSENT ici : le mobile ne couvre que les rôles d'une
/// organisation (cahier des charges — voir la demande explicite "sans la
/// partie admin"). Un compte `Admin` qui se connecterait sur le mobile est
/// traité comme [UserRole.inconnu] par [UserRoleX.fromString] et redirigé
/// vers un écran expliquant d'utiliser l'interface web dédiée.
enum UserRole {
  chefProjet,
  conducteurTravaux,
  bureauControle,
  maitreOuvrage,
  maitreOeuvre,
  entreprise,
  client,
  pilote,
  sousTraitant,
  inconnu,
}

extension UserRoleX on UserRole {
  /// Parse depuis la valeur brute renvoyée par le backend (`utilisateur.role`).
  static UserRole fromString(String? raw) {
    switch (raw) {
      case 'ChefProjet':
        return UserRole.chefProjet;
      case 'ConducteurTravaux':
        return UserRole.conducteurTravaux;
      case 'BureauControle':
        return UserRole.bureauControle;
      case 'MaitreOuvrage':
        return UserRole.maitreOuvrage;
      case 'MaitreOeuvre':
        return UserRole.maitreOeuvre;
      case 'Entreprise':
        return UserRole.entreprise;
      case 'Client':
        return UserRole.client;
      case 'Pilote':
        return UserRole.pilote;
      case 'SousTraitant':
        return UserRole.sousTraitant;
      default:
        return UserRole.inconnu;
    }
  }

  /// Valeur brute à renvoyer au backend (ex: filtres, comparaisons) —
  /// inverse exact de [fromString].
  String get raw {
    switch (this) {
      case UserRole.chefProjet:
        return 'ChefProjet';
      case UserRole.conducteurTravaux:
        return 'ConducteurTravaux';
      case UserRole.bureauControle:
        return 'BureauControle';
      case UserRole.maitreOuvrage:
        return 'MaitreOuvrage';
      case UserRole.maitreOeuvre:
        return 'MaitreOeuvre';
      case UserRole.entreprise:
        return 'Entreprise';
      case UserRole.client:
        return 'Client';
      case UserRole.pilote:
        return 'Pilote';
      case UserRole.sousTraitant:
        return 'SousTraitant';
      case UserRole.inconnu:
        return '';
    }
  }

  /// Prend `l10n` en paramètre plutôt que d'être un simple getter : contrairement
  /// à [raw] (valeur technique fixe, échangée avec le backend), le libellé
  /// affiché doit suivre la langue choisie par l'utilisateur — voir
  /// `LocaleController`.
  String label(AppLocalizations l10n) {
    switch (this) {
      case UserRole.chefProjet:
        return l10n.roleChefProjet;
      case UserRole.conducteurTravaux:
        return l10n.roleConducteurTravaux;
      case UserRole.bureauControle:
        return l10n.roleBureauControle;
      case UserRole.maitreOuvrage:
        return l10n.roleMaitreOuvrage;
      case UserRole.maitreOeuvre:
        return l10n.roleMaitreOeuvre;
      case UserRole.entreprise:
        return l10n.roleEntreprise;
      case UserRole.client:
        return l10n.roleClient;
      case UserRole.pilote:
        return l10n.rolePilote;
      case UserRole.sousTraitant:
        return l10n.roleSousTraitant;
      case UserRole.inconnu:
        return l10n.roleInconnu;
    }
  }

  IconData get icon {
    switch (this) {
      case UserRole.chefProjet:
        return Icons.engineering_outlined;
      case UserRole.conducteurTravaux:
        return Icons.construction_outlined;
      case UserRole.bureauControle:
        return Icons.fact_check_outlined;
      case UserRole.maitreOuvrage:
        return Icons.gavel_outlined;
      case UserRole.maitreOeuvre:
        return Icons.architecture_outlined;
      case UserRole.entreprise:
        return Icons.business_outlined;
      case UserRole.client:
        return Icons.person_outline;
      case UserRole.pilote:
        return Icons.map_outlined;
      case UserRole.sousTraitant:
        return Icons.handyman_outlined;
      case UserRole.inconnu:
        return Icons.help_outline;
    }
  }

  // ── Groupes de permissions — miroir exact de backend/src/config/roles.js ───

  /// GESTION : gère l'organisation, les membres et les équipes.
  bool get peutGererOrganisation =>
      this == UserRole.chefProjet || this == UserRole.maitreOuvrage;

  /// OPERATIONNEL : crée/modifie structure, plans, documents, inspections,
  /// réserves, rapports.
  bool get estOperationnel =>
      this == UserRole.chefProjet ||
      this == UserRole.conducteurTravaux ||
      this == UserRole.maitreOeuvre;

  /// OPERATIONNEL_CONTROLE : opérationnel + bureau de contrôle.
  bool get estOperationnelOuControle => estOperationnel || this == UserRole.bureauControle;

  /// PILOTAGE : valide chaque étape (changements de statut, validation de
  /// réserves, génération de rapports).
  bool get peutPiloter => estOperationnelOuControle || this == UserRole.maitreOuvrage;

  /// RESERVE_INTERVENANTS : peut agir sur les réserves (créer, joindre des
  /// pièces, changer le statut après correction). Inclut `pilote` (même
  /// groupe backend) ; `sousTraitant` en est délibérément absent — il n'a
  /// droit qu'aux deux routes ouvertes pour lui (statut, médias), voir
  /// [estSousTraitant] et `backend/src/config/roles.js#SOUS_TRAITANT`.
  bool get peutIntervenirSurReserves =>
      peutPiloter || this == UserRole.entreprise || this == UserRole.pilote;

  /// SOUS_TRAITANT (backend) : accès restreint aux réserves qui lui sont
  /// assignées — ne crée pas, ne gère pas les affectations. À utiliser pour
  /// filtrer les actions proposées (voir reserve_statut_policy.dart), jamais
  /// pour élargir [peutIntervenirSurReserves].
  bool get estSousTraitant => this == UserRole.sousTraitant;

  /// SENSIBLE : actions très sensibles (ex : supprimer un chantier).
  bool get estSensible => this == UserRole.chefProjet;

  /// Portail d'accueil — Entreprise/Client arrivent directement sur la liste
  /// des chantiers plutôt que le tableau de bord (même logique que le web,
  /// voir admin/src/utils/constants.js#ROLE_HOME).
  bool get accueilEstListeChantiers => this == UserRole.entreprise || this == UserRole.client;
}

import 'package:equatable/equatable.dart';

/// Champ d'identification d'entreprise — SIRET, NINEA, NIF, RCCM…
///
/// Le [motif] est la MÊME expression que celle appliquée par le serveur
/// (`config/pays.js`). Il sert ici à prévenir l'utilisateur pendant qu'il
/// saisit, plutôt qu'après l'envoi ; la vérification qui fait foi reste celle
/// du backend.
class ChampIdentification extends Equatable {
  /// Nom de la colonne côté serveur (`siret`, `ninea`, `nif`…) — c'est cette
  /// clé qui part dans le corps de la requête d'inscription.
  final String cle;
  final String libelle;
  final String motif;
  final String aide;

  const ChampIdentification({
    required this.cle,
    required this.libelle,
    required this.motif,
    required this.aide,
  });

  factory ChampIdentification.fromJson(Map<String, dynamic> json) => ChampIdentification(
        cle: json['cle'] as String,
        libelle: json['libelle'] as String? ?? '',
        motif: json['motif'] as String? ?? '',
        aide: json['aide'] as String? ?? '',
      );

  /// Vrai si la valeur respecte le format attendu. Une valeur VIDE est
  /// acceptée : aucun identifiant n'est obligatoire — une entreprise en cours
  /// d'immatriculation n'a pas encore ses numéros.
  bool valide(String? valeur) {
    final v = (valeur ?? '').trim();
    if (v.isEmpty) return true;
    if (motif.isEmpty) return true;
    return RegExp(motif).hasMatch(v);
  }

  @override
  List<Object?> get props => [cle, libelle, motif, aide];
}

/// Pays proposé à l'inscription, et les identifiants qui lui correspondent.
///
/// ── Pourquoi cette liste vient du SERVEUR ─────────────────────────────────
/// Le formulaire utilisait un sélecteur de ~250 pays, alors que le backend
/// n'accepte que ceux qu'il connaît : choisir la Belgique produisait une
/// inscription refusée, sans que rien à l'écran ne l'ait laissé prévoir.
///
/// Il affichait aussi SIRET, RCCM et NINEA à tout le monde — une entreprise
/// française se voyait demander un identifiant sénégalais.
class Pays extends Equatable {
  /// Code ISO 3166-1 alpha-2 (`FR`, `SN`, `ML`, `CI`).
  final String code;
  final String nom;

  /// Indicatif téléphonique, pour pré-remplir le champ de téléphone.
  final String indicatif;

  /// Identifiants à afficher pour ce pays, dans l'ordre voulu.
  final List<ChampIdentification> champs;

  const Pays({
    required this.code,
    required this.nom,
    this.indicatif = '',
    this.champs = const [],
  });

  factory Pays.fromJson(Map<String, dynamic> json) => Pays(
        code: json['code'] as String,
        nom: json['nom'] as String? ?? '',
        indicatif: json['indicatif'] as String? ?? '',
        champs: (json['champs'] as List? ?? [])
            .map((e) => ChampIdentification.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// Drapeau émoji dérivé du code ISO.
  ///
  /// Calculé plutôt que stocké : les lettres A-Z correspondent aux symboles
  /// indicateurs régionaux Unicode, à décalage constant. Une image par pays
  /// alourdirait l'application pour le même résultat.
  String get drapeau {
    if (code.length != 2) return '';
    const base = 0x1F1E6; // 🇦
    return String.fromCharCodes(
      code.toUpperCase().codeUnits.map((c) => base + (c - 0x41)),
    );
  }

  @override
  List<Object?> get props => [code, nom, indicatif, champs];
}

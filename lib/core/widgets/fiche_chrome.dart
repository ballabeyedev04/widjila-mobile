import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Armature commune aux écrans de FICHE — détail d'un chantier, d'une
/// réserve, tableau de bord, feuilles de détail d'un membre ou d'un
/// intervenant.
///
/// Pendant de `liste_chrome` (écrans de liste) et de `reserves_chrome`
/// (listes de réserves). Ces trois briques — carte blanche, ligne
/// d'information, intertitre — étaient recopiées à l'identique dans cinq
/// fichiers, chacune avec son propre rayon et sa propre ombre. Les réunir ici
/// est ce qui garantit qu'une retouche les touche TOUTES, au lieu de les
/// laisser dériver l'une après l'autre.

/// Carte blanche d'une section de fiche.
///
/// Avec [titre], elle porte un en-tête à tuile d'icône ; sans, c'est un
/// simple conteneur — utile pour empiler des [LigneFiche] sans redire le
/// libellé de la section.
class CarteFiche extends StatelessWidget {
  final IconData? icone;
  final String? titre;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const CarteFiche({
    super.key,
    this.icone,
    this.titre,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 18),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      padding: padding,
      child: titre == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icone != null) ...[
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(icone, size: 18, color: AppColors.primary),
                      ),
                      const SizedBox(width: 11),
                    ],
                    Expanded(
                      child: Text(
                        titre!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                child,
              ],
            ),
    );
  }
}

/// Ligne « libellé + valeur » d'une fiche, précédée d'une tuile d'icône.
///
/// Une valeur absente reste AFFICHÉE mais s'efface en italique gris :
/// l'absence d'information est elle-même une information, et masquer la ligne
/// ferait croire que le champ n'existe pas.
class LigneFiche extends StatelessWidget {
  final IconData icone;
  final String libelle;
  final String? valeur;

  /// Teinte de la tuile — sert à signaler une ligne à part (avertissement,
  /// statut particulier). Orange de marque par défaut.
  final Color? accent;

  /// Texte affiché quand [valeur] est vide.
  final String texteSiVide;

  const LigneFiche({
    super.key,
    required this.icone,
    required this.libelle,
    this.valeur,
    this.accent,
    required this.texteSiVide,
  });

  @override
  Widget build(BuildContext context) {
    final vide = valeur == null || valeur!.isEmpty;
    final couleur = accent ?? AppColors.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icone, size: 17, color: couleur),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  libelle,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  vide ? texteSiVide : valeur!,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: vide ? AppColors.textMuted : AppColors.textPrimary,
                    fontStyle: vide ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Intertitre de section — petites capitales orange suivies d'un filet.
///
/// Le filet qui court jusqu'au bord sépare les sections sans ajouter de trait
/// plein, plus lourd sur un fond clair. L'interlettrage élargi est ce qui, à
/// cette taille, distingue un intertitre d'un libellé de champ en gras.
class TitreSectionFiche extends StatelessWidget {
  final String texte;
  final IconData icone;

  const TitreSectionFiche(this.texte, {super.key, required this.icone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icone, size: 15, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            texte.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: AppColors.border.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

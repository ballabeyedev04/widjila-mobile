import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/reserve.dart';
import 'reserve_statut_badge.dart';

/// Palette des vignettes.
///
/// La couleur est dérivée de l'identifiant de la réserve — donc STABLE d'un
/// affichage à l'autre, contrairement à un index de liste qui changerait au
/// moindre tri ou filtre. Une réserve garde ainsi toujours la même couleur,
/// ce qui aide à la repérer dans une longue liste.
const List<Color> _paletteVignettes = [
  AppColors.primary,
  Color(0xFF4F86F7),
  Color(0xFF34C759),
  Color(0xFF8B5CF6),
  Color(0xFFF5A623),
  Color(0xFF00BCD4),
];

Color _couleurVignette(String id) => _paletteVignettes[id.hashCode.abs() % _paletteVignettes.length];

/// Icône évoquant la CATÉGORIE — un repère visuel plus rapide à lire qu'un
/// texte, surtout dans une liste parcourue au pouce sur un chantier.
IconData _iconeCategorie(ReserveCategorie categorie) {
  switch (categorie) {
    case ReserveCategorie.maconnerie:
      return Icons.dashboard_customize_rounded;
    case ReserveCategorie.grosOeuvre:
      return Icons.foundation_rounded;
    case ReserveCategorie.plomberie:
      return Icons.plumbing_rounded;
    case ReserveCategorie.electricite:
      return Icons.bolt_rounded;
    case ReserveCategorie.carrelage:
      return Icons.grid_on_rounded;
    case ReserveCategorie.peinture:
      return Icons.format_paint_rounded;
    case ReserveCategorie.menuiserie:
      return Icons.carpenter_rounded;
    case ReserveCategorie.etancheite:
      return Icons.water_drop_rounded;
    case ReserveCategorie.isolation:
      return Icons.layers_rounded;
    case ReserveCategorie.autre:
      return Icons.assignment_rounded;
  }
}

/// Carte d'une réserve dans les listes.
///
/// Liseré coloré à gauche, vignette d'icône, puis une colonne de texte :
/// titre et référence sur la première ligne, projet ou localisation, auteur et
/// date, et enfin la pastille de statut avec le bouton « Détail ».
///
/// Les commandes sont SOUS le texte, pas à côté. Dans une `Row`, un enfant non
/// flexible est mesuré avant l'`Expanded` : la colonne de droite d'origine —
/// dont la pastille n'avait aucune largeur maximale — laissait 47 points au
/// titre sur un téléphone de 390. Voir `reserve_card_largeur_test.dart`, qui
/// mesure la largeur réellement peinte.
class ReserveCard extends StatelessWidget {
  final Reserve reserve;
  final VoidCallback onTap;

  /// Affiche le nom du chantier sous le titre — pertinent seulement dans la
  /// liste transversale, où les réserves viennent de plusieurs chantiers.
  final bool avecChantier;

  const ReserveCard({
    super.key,
    required this.reserve,
    required this.onTap,
    this.avecChantier = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final couleur = _couleurVignette(reserve.id);
    final sousTitre = avecChantier && reserve.chantier != null
        ? l10n.reserveProjet(reserve.chantier!.nom)
        : reserve.localisationLabel(l10n);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            // Liseré gauche de la couleur de la vignette : il donne à la liste
            // son rythme vertical et relie la carte à son icône.
            border: Border(left: BorderSide(color: couleur, width: 4)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4)),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: couleur.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(_iconeCategorie(reserve.categorie), color: couleur, size: 25),
              ),
              const SizedBox(width: 13),
              // TOUT le reste de la carte, sur une seule colonne.
              //
              // La pastille de statut et le bouton « Détail » occupaient
              // auparavant une colonne à DROITE du texte, non bornée : dans
              // une `Row`, un enfant non flexible est servi le premier, et
              // l'`Expanded` du texte se contentait du reste — 47 points sur
              // un téléphone de 390. Les commandes descendent donc sous le
              // texte, où elles ont la place de s'écrire en entier au lieu de
              // la lui prendre.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            // Repli sur le numéro si le titre manque : le
                            // serveur impose `titre` NOT NULL, mais une carte
                            // sans AUCUN texte est illisible — on ne peut ni la
                            // reconnaître ni la citer. Mieux vaut « R-0001 »
                            // que rien.
                            reserve.titre.trim().isEmpty ? reserve.numeroAffiche(l10n) : reserve.titre,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: AppColors.textPrimary,
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        // La référence reste en tête de carte, alignée sur le
                        // titre : c'est par elle qu'on cite une réserve à
                        // l'oral. Courte par construction (« R-0007 »), elle ne
                        // menace pas la place du titre.
                        Text(
                          reserve.numeroAffiche(l10n),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    if (sousTitre.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        sousTitre,
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 9),
                    _LigneMeta(reserve: reserve),
                    const SizedBox(height: 11),
                    _LigneActions(reserve: reserve, onTap: onTap),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Auteur et date de création, séparés d'un trait vertical.
class _LigneMeta extends StatelessWidget {
  final Reserve reserve;
  const _LigneMeta({required this.reserve});

  @override
  Widget build(BuildContext context) {
    final auteur = reserve.createur?.nomComplet;
    final date = reserve.createdAt;
    if ((auteur == null || auteur.isEmpty) && date == null) return const SizedBox.shrink();

    const style = TextStyle(fontSize: 12.5, color: AppColors.textSecondary);

    return Row(
      children: [
        if (auteur != null && auteur.isNotEmpty) ...[
          const Icon(Icons.person_outline_rounded, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Flexible(child: Text(auteur, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        if (auteur != null && auteur.isNotEmpty && date != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(width: 1, height: 12, color: AppColors.border),
          ),
        if (date != null) ...[
          const Icon(Icons.calendar_today_rounded, size: 13, color: AppColors.textMuted),
          const SizedBox(width: 5),
          // Flexible comme l'auteur : la date était le seul enfant rigide de
          // la rangée, et « 20 août 2026 » à côté d'un nom long dépassait de
          // 2,3 points sur un écran de 320. Un nom et une date sont tous deux
          // de longueur imprévisible — ni l'un ni l'autre ne peut être rigide.
          Flexible(
            child: Text(
              DateFormat('dd MMM yyyy').format(date),
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

/// Pastille de statut et bouton « Détail », sur la ligne du bas.
///
/// Sous le texte et non à côté : ces deux éléments ont une largeur propre que
/// rien ne borne — le libellé d'un statut peut faire une centaine de points.
/// Placés dans la même `Row` que le texte, ils la lui prenaient.
class _LigneActions extends StatelessWidget {
  final Reserve reserve;
  final VoidCallback onTap;

  const _LigneActions({required this.reserve, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // `Flexible` : sur un écran très étroit ou avec une police agrandie,
        // c'est la pastille qui cède — elle se tronque — jamais le bouton, qui
        // reste entier parce qu'il porte l'action de la carte.
        Flexible(child: ReserveStatutBadge(statut: reserve.statut)),
        const SizedBox(width: 10),
        // Flexible lui aussi : sur 320 points, la pastille et le bouton
        // réunis dépassaient la carte de 2,3 points. Le bouton garde la
        // priorité — il ne cède qu'après la pastille — mais il peut céder,
        // plutôt que de déborder.
        Flexible(
          child: OutlinedButton.icon(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.visibility_outlined, size: 15),
            label: Text(
              l10n.equipeDetailBouton,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

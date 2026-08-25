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
/// Structure alignée sur la maquette : liseré coloré à gauche, vignette
/// d'icône, titre, projet, auteur et date, puis à droite la référence, la
/// pastille de statut et le bouton « Détail ».
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reserve.titre,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _ColonneDroite(reserve: reserve, onTap: onTap),
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
          Text(DateFormat('dd MMM yyyy').format(date), style: style),
        ],
      ],
    );
  }
}

/// Référence, pastille de statut et bouton « Détail », empilés à droite.
class _ColonneDroite extends StatelessWidget {
  final Reserve reserve;
  final VoidCallback onTap;

  const _ColonneDroite({required this.reserve, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          reserve.numeroAffiche(l10n),
          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 7),
        ReserveStatutBadge(statut: reserve.statut),
        const SizedBox(height: 9),
        OutlinedButton.icon(
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
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/reserve.dart';
import '../../domain/repositories/reserve_repository.dart';

/// Armature commune aux DEUX listes de réserves — l'onglet transversal
/// (`toutes_reserves_page`) et la liste d'un chantier (`reserves_list_page`).
///
/// Les deux écrans montrent la même chose à deux échelles : même rangée de
/// puces, mêmes compteurs, même feuille « Filtrer », même barre de recherche.
/// Les pièces vivent donc ici plutôt que d'être recopiées de part et d'autre —
/// c'est ce qui garantit qu'une retouche de style les touche TOUTES LES DEUX,
/// au lieu de les laisser diverger comme elles l'avaient fait (barre Material
/// d'un côté, en-tête de la maquette de l'autre).

/// Statuts proposés en puces, au-dessus de la liste. `null` = « Toutes ».
///
/// Choix de ces quatre entrées : ce sont les états sur lesquels on agit au
/// quotidien (maquette Widjila, écran 2). Les statuts plus rares (refusée,
/// rouverte, clôturée…) restent accessibles par le bouton « Filtrer », qui
/// les liste tous — les empiler ici aurait donné une rangée illisible.
List<({String label, IconData icon, ReserveStatut? statut})> filtresReserve(AppLocalizations l10n) => [
      (label: l10n.reserveFiltreToutes, icon: Icons.grid_view_rounded, statut: null),
      (label: l10n.statutEnCours, icon: Icons.schedule_rounded, statut: ReserveStatut.enCours),
      (label: l10n.statutAVerifier, icon: Icons.verified_outlined, statut: ReserveStatut.aVerifier),
      (label: l10n.statutValidee, icon: Icons.check_circle_outline_rounded, statut: ReserveStatut.validee),
    ];

/// Rangée de puces de statut, chacune avec SON compteur.
///
/// Les compteurs viennent de [statutsCount] — la répartition calculée par le
/// serveur — et non du `total` de la liste, qui ne décrit que le filtre
/// courant. C'est la différence entre « Toutes (12) · En cours · À vérifier »
/// et « Toutes (12) · En cours (5) · À vérifier (3) » : sans les chiffres des
/// autres puces, rien n'indique où le travail s'accumule, et il faut ouvrir
/// chaque onglet pour le découvrir.
class RangeeFiltresReserve extends StatelessWidget {
  final ReserveStatut? filtreCourant;
  final ReserveStatutsCount statutsCount;
  final ValueChanged<ReserveStatut?> onChoix;

  const RangeeFiltresReserve({
    super.key,
    required this.filtreCourant,
    required this.statutsCount,
    required this.onChoix,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ContenuCentre(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              for (final filtre in filtresReserve(context.l10n)) ...[
                ChipFiltre(
                  icon: filtre.icon,
                  label: '${filtre.label} (${_compte(filtre.statut)})',
                  actif: filtreCourant == filtre.statut,
                  onTap: () => onChoix(filtre.statut),
                ),
                const SizedBox(width: 9),
              ],
            ],
          ),
        ),
      ),
    );
  }

  int _compte(ReserveStatut? statut) =>
      statut == null ? statutsCount.total : statutsCount.pour(statut);
}

/// Bouton « Filtrer » — jumeau de celui de l'écran Équipe.
///
/// Il ne remplace pas la rangée de puces : celles-ci donnent l'accès direct
/// aux quatre statuts courants avec leur compteur, ce bouton ouvre la liste
/// COMPLÈTE des statuts (onze côté back, impossibles à tenir dans une rangée
/// lisible).
class BoutonFiltrerReserves extends StatelessWidget {
  final ReserveStatut? filtreCourant;
  final ValueChanged<ReserveStatut?> onChoix;

  const BoutonFiltrerReserves({super.key, required this.filtreCourant, required this.onChoix});

  Future<void> _ouvrir(BuildContext context) async {
    final l10n = context.l10n;

    // Sentinelle : `null` ne doit signifier QUE « feuille abandonnée ». Sans
    // elle, choisir « Toutes » et fermer d'un glissement produiraient la même
    // valeur, et l'abandon réinitialiserait le filtre par surprise.
    const sentinelleToutes = '__toutes__';

    final choix = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 14),
              ListTile(
                title: Text(l10n.reserveFiltreToutes),
                trailing: filtreCourant == null ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                onTap: () => Navigator.of(sheetContext).pop(sentinelleToutes),
              ),
              for (final s in ReserveStatut.values)
                ListTile(
                  title: Text(s.label(l10n)),
                  trailing: filtreCourant == s ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                  onTap: () => Navigator.of(sheetContext).pop(s.raw),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (choix == null || !context.mounted) return;
    onChoix(choix == sentinelleToutes ? null : ReserveStatutX.fromString(choix));
  }

  @override
  Widget build(BuildContext context) {
    final actif = filtreCourant != null;

    return Material(
      color: actif ? AppColors.primary.withValues(alpha: 0.12) : AppColors.background,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: () => _ouvrir(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, size: 19, color: actif ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 7),
              Text(
                context.l10n.reserveFiltrer,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: actif ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barre de recherche des listes de réserves — champ arrondi posé sur le gris
/// de fond, avec le bouton « Filtrer » à sa droite.
///
/// Elle possède SON contrôleur : la croix d'effacement a besoin de vider le
/// champ, et faire porter ce détail par chaque page appelante revenait à
/// dupliquer un `TextEditingController`, son `dispose()` et un `setState` —
/// avec, à la clé, une page qui l'oublie et une croix qui n'efface rien.
class BarreRechercheReserves extends StatefulWidget {
  final ValueChanged<String> onRecherche;
  final ReserveStatut? filtreCourant;
  final ValueChanged<ReserveStatut?> onFiltre;

  const BarreRechercheReserves({
    super.key,
    required this.onRecherche,
    required this.filtreCourant,
    required this.onFiltre,
  });

  @override
  State<BarreRechercheReserves> createState() => _BarreRechercheReservesState();
}

class _BarreRechercheReservesState extends State<BarreRechercheReserves> {
  final _controleur = TextEditingController();

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return ContenuCentre(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controleur,
                textInputAction: TextInputAction.search,
                onChanged: widget.onRecherche,
                decoration: InputDecoration(
                  hintText: l10n.reserveRechercheHint,
                  prefixIcon: const Icon(Icons.search_rounded, size: 21, color: AppColors.textMuted),
                  // La croix n'apparaît QUE si le champ contient quelque
                  // chose : affichée en permanence, elle donnerait à un champ
                  // vide l'air d'un champ rempli.
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controleur,
                    builder: (context, valeur, _) {
                      if (valeur.text.isEmpty) return const SizedBox.shrink();
                      return IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                        tooltip: l10n.chantierPickerEffacer,
                        onPressed: () {
                          _controleur.clear();
                          widget.onRecherche('');
                        },
                      );
                    },
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            BoutonFiltrerReserves(filtreCourant: widget.filtreCourant, onChoix: widget.onFiltre),
          ],
        ),
      ),
    );
  }
}

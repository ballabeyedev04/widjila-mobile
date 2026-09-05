import 'package:flutter/material.dart';

import '../../l10n/l10n_extension.dart';
import '../theme/app_colors.dart';
import 'apparition_en_cascade.dart';
import 'action_rapide.dart';
import 'liste_chrome.dart';

/// Menu de l'onglet « Plus » — une grille de raccourcis dans une feuille.
///
/// ## Pourquoi une feuille, et non l'éventail en arc d'avant
///
/// « Plus » déployait ses entrées en arc de cercle autour de son bouton. C'est
/// lisible jusqu'à trois ou quatre : au-delà, les pastilles se chevauchent,
/// les étiquettes se marchent dessus, et les branches basses de l'arc sortent
/// de l'écran sur un téléphone étroit — l'arc n'a qu'un demi-tour à offrir, et
/// il était déjà plein.
///
/// Le menu compte désormais jusqu'à sept entrées : le tableau de bord chantier
/// et l'envoi de plans ont quitté le bouton central pour le rejoindre. Une
/// grille les accueille toutes, garde le vocabulaire visuel de l'éventail
/// (pastille blanche à ombre teintée, libellé dessous) et continue d'accepter
/// la huitième le jour où elle arrivera.
///
/// Retourne l'entrée choisie, ou `null` si la feuille est refermée.
Future<ActionRapide?> ouvrirMenuPlus(BuildContext context, List<ActionRapide> entrees) {
  return showModalBottomSheet<ActionRapide>(
    context: context,
    backgroundColor: Colors.transparent,
    // La grille peut dépasser la moitié basse de l'écran quand les libellés
    // passent sur deux lignes : sans cela, la feuille se contenterait de la
    // hauteur par défaut et rognerait sa dernière rangée.
    isScrollControlled: true,
    builder: (_) => _MenuPlusSheet(entrees: entrees),
  );
}

class _MenuPlusSheet extends StatelessWidget {
  final List<ActionRapide> entrees;
  const _MenuPlusSheet({required this.entrees});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ContenuCentre(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.menuPlusTitre,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                      tooltip: l10n.commonClose,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                  child: LayoutBuilder(
                    builder: (context, contraintes) {
                      // Trois colonnes sur téléphone, davantage dès que la
                      // largeur le permet : sur tablette, trois pastilles
                      // perdues au milieu d'une feuille large paraîtraient
                      // égarées.
                      final colonnes = colonnesAdaptatives(
                        contraintes.maxWidth,
                        min: 3,
                        max: 5,
                        largeurCible: 120,
                      );
                      return GridView.count(
                        crossAxisCount: colonnes,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: 0.86,
                        children: [
                          for (var i = 0; i < entrees.length; i++)
                            ApparitionEnCascade(
                              rang: i,
                              child: _Entree(
                                action: entrees[i],
                                onTap: () => Navigator.of(context).pop(entrees[i]),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une case de la grille — pastille colorée puis libellé.
///
/// La zone tactile couvre la case ENTIÈRE, pastille et étiquette comprises :
/// viser un disque de 56 px au pouce est déjà juste, exiger de tomber dessus
/// plutôt que sur son texte le serait trop.
class _Entree extends StatelessWidget {
  final ActionRapide action;
  final VoidCallback onTap;

  const _Entree({required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: action.couleur.withValues(alpha: 0.18), width: 1.5),
                  boxShadow: [
                    // Ombre teintée par l'action : elle rattache la pastille à
                    // sa couleur, ce qu'une ombre noire ne ferait pas.
                    BoxShadow(
                      color: action.couleur.withValues(alpha: 0.26),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(action.icon, color: action.couleur, size: 24),
              ),
              const SizedBox(height: 9),
              Flexible(
                child: Text(
                  action.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    height: 1.25,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

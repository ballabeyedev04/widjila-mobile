import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../reserve/domain/entities/reserve.dart';
import '../../domain/entities/dashboard_stats.dart';
import 'carte_tableau_de_bord.dart';

/// Une carte KPI : libellé, valeur, icône et couleur.
typedef KpiItem = ({String label, int valeur, IconData icone, Color couleur});

/// Les cartes du tableau de bord, dans l'ordre : les quatre d'origine (total,
/// ouvertes, levées, en retard) puis les statuts du client. Les nombres
/// viennent TOUS du serveur (`stats.reserves`, `stats.parStatut`) — rien
/// n'est calculé ni supposé ici.
///
/// « Levées » = `reserves.validees`, qui compte les deux verdicts positifs
/// (`validee` + `levee`) côté serveur. « En retard » = `reserves.enRetard`,
/// l'échéance dépassée sur une réserve ouverte — la définition d'origine,
/// conservée telle quelle.
List<KpiItem> cartesKpi(AppLocalizations l10n, DashboardStats stats) => [
      (label: l10n.dashboardKpiTotal, valeur: stats.reserves.total, icone: Icons.inventory_2_outlined, couleur: AppColors.primary),
      (label: l10n.dashboardKpiOuvertes, valeur: stats.reserves.ouvertes, icone: Icons.hourglass_top_rounded, couleur: AppColors.warning),
      (label: l10n.dashboardKpiLevees, valeur: stats.reserves.validees, icone: Icons.check_circle_outline_rounded, couleur: AppColors.success),
      (label: l10n.statutEnRetard, valeur: stats.reserves.enRetard, icone: Icons.error_outline_rounded, couleur: AppColors.danger),
      (
        label: l10n.statutASurveiller,
        valeur: stats.parStatut[ReserveStatut.aSurveiller] ?? 0,
        icone: Icons.visibility_outlined,
        couleur: const Color(0xFFF97316),
      ),
      (
        label: l10n.statutAEcheance,
        valeur: stats.parStatut[ReserveStatut.aEcheance] ?? 0,
        icone: Icons.event_available_outlined,
        couleur: AppColors.info,
      ),
      (
        label: l10n.dashboardKpiTraitees,
        valeur: stats.parStatut[ReserveStatut.traitee] ?? 0,
        icone: Icons.build_circle_outlined,
        couleur: const Color(0xFF7C3AED),
      ),
      (
        label: l10n.dashboardKpiRefusees,
        valeur: stats.parStatut[ReserveStatut.refusee] ?? 0,
        icone: Icons.block_rounded,
        couleur: const Color(0xFF111827),
      ),
    ];

/// Rangée de cartes KPI qui DÉFILE horizontalement, avec une flèche de
/// chaque côté.
///
/// ── Pourquoi défiler plutôt que réduire ───────────────────────────────────
///
/// Quatre cartes tenaient sur une ligne ; les statuts du client en font huit.
/// Les serrer toutes rendait chaque carte illisible sur un téléphone, les
/// empiler sur deux lignes doublait la hauteur de l'en-tête de l'écran. La
/// rangée garde donc SA mise en page — la carte ne change pas de dessin — et
/// laisse le doigt faire le reste. Les flèches disent qu'il y a une suite,
/// et l'apportent d'un appui pour qui ne pense pas à balayer.
///
/// La largeur d'une carte est calculée pour qu'un NOMBRE ENTIER de cartes
/// tienne dans la rangée (quatre sur un téléphone, davantage sur une tablette)
/// : une carte à moitié coupée sur le bord est le seul indice de défilement
/// qui reste quand les flèches ne sont pas regardées — on la laisse
/// délibérément dépasser d'un tiers.
class RangeeKpiDefilante extends StatefulWidget {
  final DashboardStats stats;
  const RangeeKpiDefilante({super.key, required this.stats});

  @override
  State<RangeeKpiDefilante> createState() => _RangeeKpiDefilanteState();
}

class _RangeeKpiDefilanteState extends State<RangeeKpiDefilante> {
  final _controleur = ScrollController();
  bool _peutReculer = false;
  bool _peutAvancer = true;

  static const _espace = 10.0;
  static const _largeurFleche = 28.0;

  @override
  void initState() {
    super.initState();
    _controleur.addListener(_majFleches);
    // Après la première mise en page, la position sait si tout tient.
    WidgetsBinding.instance.addPostFrameCallback((_) => _majFleches());
  }

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  void _majFleches() {
    if (!_controleur.hasClients) return;
    final pos = _controleur.position;
    final recule = pos.pixels > 1;
    final avance = pos.pixels < pos.maxScrollExtent - 1;
    if (recule != _peutReculer || avance != _peutAvancer) {
      setState(() {
        _peutReculer = recule;
        _peutAvancer = avance;
      });
    }
  }

  void _defiler(double delta) {
    if (!_controleur.hasClients) return;
    final pos = _controleur.position;
    final cible = (pos.pixels + delta).clamp(0.0, pos.maxScrollExtent);
    _controleur.animateTo(cible, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = cartesKpi(l10n, widget.stats);

    return LayoutBuilder(
      builder: (context, constraints) {
        final largeurRangee = constraints.maxWidth - 2 * _largeurFleche;
        // Nombre de cartes ENTIÈRES visibles : 4 sur un téléphone, plus large
        // ailleurs (une carte fait ~110 dp). Le tiers ajouté laisse
        // dépasser la suivante.
        final visibles = (largeurRangee / 115).floor().clamp(2, items.length);
        // Tout tient : les cartes se partagent la largeur. Sinon, `visibles`
        // cartes entières, leurs espaces, et un tiers de la suivante.
        final largeurCarte = visibles >= items.length
            ? (largeurRangee - (visibles - 1) * _espace) / visibles
            : (largeurRangee - visibles * _espace) / (visibles + 0.33);
        final pas = largeurCarte + _espace;

        return Row(
          children: [
            _Fleche(
              icone: Icons.chevron_left_rounded,
              tooltip: l10n.dashboardCartesPrecedentes,
              actif: _peutReculer,
              onTap: () => _defiler(-pas * visibles),
            ),
            Expanded(
              child: SizedBox(
                // Hauteur naturelle d'une carte ; un `ListView` horizontal ne
                // sait pas la mesurer lui-même.
                height: _hauteurCarte(context, largeurCarte, items),
                child: ListView.separated(
                  key: const Key('rangee-kpi'),
                  controller: _controleur,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  clipBehavior: Clip.none,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: _espace),
                  itemBuilder: (context, i) => SizedBox(width: largeurCarte, child: CarteKpi(item: items[i])),
                ),
              ),
            ),
            _Fleche(
              icone: Icons.chevron_right_rounded,
              tooltip: l10n.dashboardCartesSuivantes,
              actif: _peutAvancer,
              onTap: () => _defiler(pas * visibles),
            ),
          ],
        );
      },
    );
  }

  /// Hauteur de la carte la plus haute de la rangée, MESURÉE : pastille (30)
  /// + espace (10) + nombre + espace (1) + libellé + marges verticales (14
  /// × 2). Le nombre et le libellé sont mesurés avec la police, l'échelle de
  /// texte du système et la largeur réelle de la carte — un libellé qui passe
  /// sur deux lignes en gros texte est compté, pas deviné. Une hauteur
  /// estimée « à la louche » débordait de quelques points dès 1,6 ×.
  double _hauteurCarte(BuildContext context, double largeurCarte, List<KpiItem> items) {
    final echelle = MediaQuery.textScalerOf(context);
    // Le `Text` de la carte hérite du style ambiant (police du thème, hauteur
    // de ligne) : la mesure doit partir du même style, sinon elle sous-estime.
    final ambiant = DefaultTextStyle.of(context).style;
    final largeurTexte = (largeurCarte - 2 * CarteKpi.margeHorizontale).clamp(1.0, double.infinity);
    double hauteur(String texte, TextStyle style, int maxLines) {
      final peintre = TextPainter(
        text: TextSpan(text: texte, style: ambiant.merge(style)),
        textDirection: TextDirection.ltr,
        textScaler: echelle,
        maxLines: maxLines,
        ellipsis: '…',
      )..layout(maxWidth: largeurTexte);
      final h = peintre.height;
      peintre.dispose();
      return h;
    }

    var max = 0.0;
    for (final item in items) {
      final h = hauteur('${item.valeur}', CarteKpi.styleValeur, 1) + hauteur(item.label, CarteKpi.styleLibelle, CarteKpi.maxLignesLibelle);
      if (h > max) max = h;
    }
    return 2 * CarteKpi.margeVerticale + 30 + 10 + 1 + max + 2;
  }
}

class _Fleche extends StatelessWidget {
  final IconData icone;
  final String tooltip;
  final bool actif;
  final VoidCallback onTap;

  const _Fleche({required this.icone, required this.tooltip, required this.actif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _RangeeKpiDefilanteState._largeurFleche,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 40),
        onPressed: actif ? onTap : null,
        icon: Icon(icone, size: 22, color: actif ? AppColors.textSecondary : AppColors.border),
      ),
    );
  }
}

/// Une carte KPI — dessin INCHANGÉ (badge icône coloré, nombre, libellé).
class CarteKpi extends StatelessWidget {
  final KpiItem item;
  const CarteKpi({super.key, required this.item});

  static const margeVerticale = 14.0;
  static const margeHorizontale = 10.0;
  static const maxLignesLibelle = 2;
  static const styleValeur = TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary);
  static const styleLibelle = TextStyle(fontSize: 10.5, color: AppColors.textSecondary);

  @override
  Widget build(BuildContext context) {
    return CarteTableauDeBord(
      padding: const EdgeInsets.symmetric(vertical: margeVerticale, horizontal: margeHorizontale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: item.couleur.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
            child: Icon(item.icone, size: 16, color: item.couleur),
          ),
          const SizedBox(height: 10),
          Text('${item.valeur}', style: styleValeur, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 1),
          Text(item.label, style: styleLibelle, maxLines: maxLignesLibelle, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

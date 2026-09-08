import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/breakpoints.dart';
import '../../../../core/config/user_role.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/liste_chrome.dart' show colonnesAdaptatives;
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../reserve/domain/entities/reserve.dart';
import '../../../reserve/presentation/widgets/reserve_statut_badge.dart';
import '../../domain/entities/plan.dart';
import '../../domain/usecases/get_plan_detail.dart';
import '../../domain/usecases/get_plans_racines.dart';
import '../../domain/usecases/get_sous_plans.dart';
import '../widgets/fiche_reserve_sheet.dart';
import '../widgets/nouvelle_reserve_sheet.dart';
import '../widgets/plan_interactif.dart';
import '../widgets/plan_vignette.dart';

/// Parcours des plans d'un chantier, UN NIVEAU À LA FOIS.
///
/// ## Ce que cet écran corrige
///
/// Le relevé d'une réserve passait par : choisir un chantier, voir TOUS ses
/// plans à plat — plan global, plans de bâtiment, plans d'étage et plans de
/// détail dans la même liste — puis, au premier appui, tomber directement sur
/// le formulaire de création. Trois défauts en un geste :
///
///  1. l'arborescence était écrasée : sur un chantier de trente plans, plus
///     rien ne disait lequel contenait lequel ;
///  2. appuyer sur un plan ne permettait pas de le CONSULTER, seulement de
///     lancer une création ;
///  3. la localisation se ressaisissait ensuite à la main (bâtiment, étage,
///     zone), alors que le plan la porte déjà.
///
/// ## Le parcours
///
/// ```
/// chantier → plans globaux → sous-plans directs → sous-plans directs → …
///                                                        ↓
///                                          image réelle + réserves posées
///                                                        ↓
///                                   appui sur une zone libre → réserve
/// ```
///
/// À CHAQUE niveau, seuls les enfants DIRECTS du plan ouvert sont affichés —
/// jamais l'arborescence entière. C'est le serveur qui borne la descente
/// (`/chantiers/:id/plans/racines` puis `/plans/:id/sous-plans`), pas un filtre
/// local sur une liste complète : le client ne connaît donc à aucun moment plus
/// d'un cran d'arborescence.
///
/// ## Les trois gestes, distincts
///
///  - appuyer une TUILE de sous-plan → descendre d'un cran ;
///  - appuyer un REPÈRE sur le plan → consulter la réserve ;
///  - appuyer une ZONE LIBRE du plan → créer une réserve à cet endroit exact.
///
/// Ils ne se recouvrent jamais : `PlanInteractif` remet le repère au premier
/// plan de la pile de gestes, un appui dessus n'atteint donc pas l'image.
class PlanExplorerPage extends StatefulWidget {
  final String chantierId;
  final String? chantierNom;

  /// Plan sur lequel OUVRIR directement l'explorateur, au lieu de partir des
  /// plans globaux.
  ///
  /// Sert à la bande « Derniers plans » de l'accueil : on y appuie sur un plan
  /// précis, et on doit arriver dessus — pas au sommet de l'arborescence du
  /// chantier, qu'il faudrait alors redescendre.
  ///
  /// La flèche de retour ramène ensuite aux plans globaux : on remonte
  /// l'arborescence normalement, sans que le point d'entrée change les règles.
  final String? planIdInitial;

  const PlanExplorerPage({
    super.key,
    required this.chantierId,
    this.chantierNom,
    this.planIdInitial,
  });

  @override
  State<PlanExplorerPage> createState() => _PlanExplorerPageState();
}

class _PlanExplorerPageState extends State<PlanExplorerPage> {
  /// Chemin descendu depuis le chantier. Vide = on est au niveau des plans
  /// globaux ; sinon, le dernier élément est le plan ouvert.
  final List<Plan> _chemin = [];

  /// Les plans du niveau COURANT — plans globaux, ou enfants directs du plan
  /// ouvert. Jamais plus d'un cran.
  List<Plan> _niveau = const [];

  /// Détail du plan ouvert : son image et ses réserves positionnées. Nul au
  /// niveau des plans globaux, où aucun plan n'est ouvert.
  Plan? _detail;

  bool _chargement = true;
  String? _erreur;

  Plan? get _planOuvert => _chemin.isEmpty ? null : _chemin.last;

  @override
  void initState() {
    super.initState();
    if (widget.planIdInitial == null) {
      _chargerNiveau();
    } else {
      _ouvrirDirectement(widget.planIdInitial!);
    }
  }

  /// Place l'explorateur directement SUR un plan donné.
  ///
  /// Le plan n'est connu que par son identifiant : on le charge d'abord, puis
  /// on l'empile comme s'il avait été atteint par une descente. Tout le reste
  /// de l'écran — sous-plans, réserves, retour — fonctionne alors à
  /// l'identique.
  ///
  /// Si le plan est introuvable (supprimé entre-temps, identifiant erroné), on
  /// retombe sur les plans globaux du chantier plutôt que sur une page
  /// d'erreur : l'utilisateur voulait voir des plans, il en voit.
  Future<void> _ouvrirDirectement(String planId) async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    final detail = await sl<GetPlanDetail>()(planId);
    if (!mounted) return;

    final plan = detail.fold((_) => null, (p) => p);
    if (plan == null) {
      await _chargerNiveau();
      return;
    }

    setState(() => _chemin.add(plan));
    await _chargerNiveau();
  }

  /// Charge ce qu'il faut afficher pour le niveau courant.
  ///
  /// Deux requêtes au plus, et seulement celles qui servent :
  ///  - à la racine, la liste des plans globaux ;
  ///  - sur un plan ouvert, son détail (image + réserves) et — SI le compteur
  ///    du serveur annonce des enfants — ses sous-plans directs.
  ///
  /// Le compteur évite une requête sur la feuille de l'arborescence, qui est
  /// le cas le plus fréquent : la très grande majorité des plans n'a pas de
  /// sous-plan.
  Future<void> _chargerNiveau() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    final ouvert = _planOuvert;

    if (ouvert == null) {
      final resultat = await sl<GetPlansRacines>()(widget.chantierId);
      if (!mounted) return;
      resultat.fold(
        (echec) => setState(() {
          _erreur = echec.errorMessage;
          _chargement = false;
        }),
        (plans) => setState(() {
          _niveau = plans;
          _detail = null;
          _chargement = false;
        }),
      );
      return;
    }

    final detail = await sl<GetPlanDetail>()(ouvert.id);
    if (!mounted) return;

    // Un échec du DÉTAIL est bloquant : sans image ni réserves, il n'y a rien
    // à montrer de ce plan et rien sur quoi appuyer.
    final echecDetail = detail.fold((e) => e.errorMessage, (_) => null);
    if (echecDetail != null) {
      setState(() {
        _erreur = echecDetail;
        _chargement = false;
      });
      return;
    }

    List<Plan> enfants = const [];
    if (ouvert.aDesSousPlans) {
      final sousPlans = await sl<GetSousPlans>()(ouvert.id);
      if (!mounted) return;
      // Un échec ICI n'est pas bloquant : le plan reste consultable et on peut
      // toujours y poser une réserve. Seule la descente est perdue.
      sousPlans.fold((_) {}, (liste) => enfants = liste);
    }

    setState(() {
      _detail = detail.getOrElse(() => ouvert);
      _niveau = enfants;
      _chargement = false;
    });
  }

  /// Descend d'un cran.
  void _ouvrir(Plan plan) {
    setState(() {
      _chemin.add(plan);
      // Vidés AVANT le chargement : sans cela, le niveau précédent restait à
      // l'écran le temps de la requête, et l'utilisateur voyait brièvement les
      // sous-plans du plan qu'il vient de quitter.
      _niveau = const [];
      _detail = null;
    });
    _chargerNiveau();
  }

  /// Remonte d'un cran ; à la racine, quitte l'écran.
  void _remonter() {
    if (_chemin.isEmpty) {
      context.pop();
      return;
    }
    setState(() {
      _chemin.removeLast();
      _niveau = const [];
      _detail = null;
    });
    _chargerNiveau();
  }

  /// Recharge le DÉTAIL seul — après la création d'une réserve.
  ///
  /// Pas `_chargerNiveau` : celui-ci repasse par l'écran de chargement et
  /// ferait disparaître le plan une seconde, juste après le geste. Ici, seuls
  /// les repères changent.
  Future<void> _rechargerReserves() async {
    final ouvert = _planOuvert;
    if (ouvert == null) return;
    final detail = await sl<GetPlanDetail>()(ouvert.id);
    if (!mounted) return;
    detail.fold((_) {}, (p) => setState(() => _detail = p));
  }

  /// Fil d'Ariane — « Résidence Horizon › Plan de masse › Bâtiment A ».
  ///
  /// Le chantier en tête, puis tous les plans traversés SAUF le dernier, que
  /// le titre affiche déjà juste au-dessus.
  String get _sousTitre {
    final chemin = <String>[
      if (widget.chantierNom != null) widget.chantierNom!,
      for (final p in _chemin) p.nom,
    ];
    if (chemin.length > 1) chemin.removeLast();
    return chemin.join(' › ');
  }

  String get _titre =>
      _planOuvert?.nom ?? widget.chantierNom ?? context.l10n.planExplorerPlansGlobaux;

  @override
  Widget build(BuildContext context) {
    // Le serveur réserve la pose d'une réserve aux rôles d'intervention :
    // rendre le plan actif pour les autres promettrait un 403.
    final peutCreer = context.select(
      (AuthBloc b) => b.state.utilisateur?.role.peutIntervenirSurReserves ?? false,
    );

    return PopScope(
      // Le retour système doit remonter D'UN NIVEAU, comme la flèche de
      // l'écran. Sans cette interception, il refermait tout le parcours depuis
      // le fond de l'arborescence.
      canPop: _chemin.isEmpty,
      onPopInvokedWithResult: (aQuitte, _) {
        if (!aQuitte) _remonter();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _Bandeau(titre: _titre, sousTitre: _sousTitre, onRetour: _remonter),
              Expanded(child: _corps(peutCreer)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _corps(bool peutCreer) {
    if (_chargement) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_erreur != null) {
      return ErrorView(message: _erreur!, onRetry: _chargerNiveau);
    }

    final ouvert = _planOuvert;
    if (ouvert == null) return _racines();

    return _VuePlanOuvert(
      // La clé force un état neuf à chaque changement de plan : sans elle, les
      // octets et le zoom du plan précédent survivaient une frame sur le
      // suivant.
      key: ValueKey(ouvert.id),
      plan: _detail ?? ouvert,
      chantierId: widget.chantierId,
      cheminLisible: [widget.chantierNom, ..._chemin.map((p) => p.nom)]
          .whereType<String>()
          .join(' › '),
      sousPlans: _niveau,
      pointageAutorise: peutCreer,
      onOuvrirSousPlan: _ouvrir,
      onReserveCreee: _rechargerReserves,
    );
  }

  /// Niveau 1 : les plans GLOBAUX du chantier, et rien d'autre.
  Widget _racines() {
    final l10n = context.l10n;

    if (_niveau.isEmpty) {
      return EmptyState(
        icon: Icons.map_outlined,
        title: l10n.planAucunSurChantier,
        subtitle: l10n.planAucunSurChantierAide,
      );
    }

    final estTablette = MediaQuery.sizeOf(context).width >= seuilTablette;

    return RefreshIndicator(
      onRefresh: _chargerNiveau,
      color: AppColors.primary,
      child: ListView(
        padding: EdgeInsets.fromLTRB(estTablette ? 24 : 16, 16, estTablette ? 24 : 16, 24),
        children: [
          Text(
            l10n.planExplorerPlansGlobaux.toUpperCase(),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          _GrillePlans(plans: _niveau, onOuvrir: _ouvrir),
        ],
      ),
    );
  }
}

// ═══════════════════════════ BANDEAU ═══════════════════════════

/// Bandeau de navigation — flèche de retour, tuile d'icône, titre, fil
/// d'Ariane. Même vocabulaire visuel que le reste du module Plans.
class _Bandeau extends StatelessWidget {
  final String titre;
  final String sousTitre;
  final VoidCallback onRetour;

  const _Bandeau({required this.titre, required this.sousTitre, required this.onRetour});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 16, 12),
      color: AppColors.surface,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.primary,
            tooltip: context.l10n.commonBack,
            onPressed: onRetour,
          ),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.map_outlined, color: AppColors.primary, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titre,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (sousTitre.isNotEmpty)
                  Text(
                    sousTitre,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════ TUILES ═══════════════════════════

/// Grille de plans — une tuile par plan, avec l'APERÇU RÉEL du document.
class _GrillePlans extends StatelessWidget {
  final List<Plan> plans;
  final void Function(Plan) onOuvrir;

  const _GrillePlans({required this.plans, required this.onOuvrir});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, contraintes) => GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: colonnesAdaptatives(contraintes.maxWidth, min: 1, max: 3, largeurCible: 260),
          mainAxisSpacing: 10,
          crossAxisSpacing: 12,
          mainAxisExtent: _hauteurTuile(context),
        ),
        children: [for (final p in plans) _TuilePlan(plan: p, onOuvrir: () => onOuvrir(p))],
      ),
    );
  }
}

/// Hauteur d'une tuile, échelle de police système comprise.
///
/// La tuile empile horizontalement un aperçu de 64 px et deux lignes de texte.
/// Aucun des deux ne dépend de la largeur : figer un rapport largeur/hauteur
/// écraserait la tuile dès que la colonne se resserre, et un texte agrandi
/// dans les réglages du téléphone la ferait déborder.
double _hauteurTuile(BuildContext context) {
  const marges = 24.0;
  const contenu = 64.0;
  return marges + MediaQuery.textScalerOf(context).scale(contenu);
}

/// Une tuile de plan : l'aperçu réel du document, son nom, et ce qu'il porte.
///
/// L'APERÇU est le point du correctif : la liste montrait un nom de fichier et
/// une icône, ce qui obligeait à ouvrir chaque plan pour savoir lequel on
/// regardait. `PlanVignette` télécharge le document et en rend la première
/// page — avec cache de session, une seule requête par fichier.
class _TuilePlan extends StatelessWidget {
  final Plan plan;
  final VoidCallback onOuvrir;

  const _TuilePlan({required this.plan, required this.onOuvrir});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // Ce que la tuile ANNONCE : où elle mène, et ce qu'elle porte. Les deux
    // compteurs viennent du serveur — le client ne voit qu'un cran
    // d'arborescence et ne pourrait pas les déduire.
    final meta = <String>[
      if (plan.aDesSousPlans) l10n.planExplorerNSousPlans(plan.nombreSousPlans),
      if (plan.nombreReserves > 0) l10n.planExplorerNReserves(plan.nombreReserves),
      if (plan.version > 1) 'v${plan.version}',
    ].join(' · ');

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOuvrir,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              PlanVignette(
                plan: plan,
                icone: Icons.map_outlined,
                couleur: AppColors.primary,
                taille: 64,
                largeur: 64,
                rayon: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      plan.nom,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta.isEmpty ? l10n.planExplorerAucunSousPlan : meta,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (plan.enAttenteValidation) ...[
                      const SizedBox(height: 4),
                      Text(
                        l10n.planExplorerEnAttenteValidation,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.warning,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════ PLAN OUVERT ═══════════════════════════

/// Télécharge le fichier d'un plan.
///
/// Les octets transitent par le Dio de l'app, qui porte le jeton exigé par
/// `/uploads/*` : un lien direct confié au widget répondrait 401.
Future<Uint8List> _telecharger(String url) async {
  final reponse = await sl<Dio>().get<List<int>>(
    url,
    options: Options(responseType: ResponseType.bytes),
  );
  final data = reponse.data;
  if (data == null) throw Exception('Réponse vide');
  return Uint8List.fromList(data);
}

/// Un plan ouvert : son IMAGE RÉELLE en haut, ses sous-plans et ses réserves
/// dans le panneau du bas.
///
/// Les trois raisons d'ouvrir un plan cohabitent ici sans se gêner :
/// le consulter (on le voit), descendre dedans (les tuiles du bas), y poser
/// une réserve (un appui sur l'image).
///
/// L'image reste affichée MÊME quand le plan a des sous-plans : c'est ce qui
/// distingue « naviguer » de « consulter ». Un plan de bâtiment se regarde
/// aussi, et on peut vouloir y poser une réserve sans descendre à
/// l'appartement.
class _VuePlanOuvert extends StatefulWidget {
  final Plan plan;
  final String chantierId;
  final String cheminLisible;
  final List<Plan> sousPlans;
  final bool pointageAutorise;
  final void Function(Plan) onOuvrirSousPlan;
  final Future<void> Function() onReserveCreee;

  const _VuePlanOuvert({
    super.key,
    required this.plan,
    required this.chantierId,
    required this.cheminLisible,
    required this.sousPlans,
    required this.pointageAutorise,
    required this.onOuvrirSousPlan,
    required this.onReserveCreee,
  });

  @override
  State<_VuePlanOuvert> createState() => _VuePlanOuvertState();
}

class _VuePlanOuvertState extends State<_VuePlanOuvert> {
  Uint8List? _octets;
  String? _erreurImage;

  /// Repère de la réserve dont la fiche est ouverte — mis en évidence sur le
  /// plan pour qu'on sache de quel point parle la feuille.
  String? _reserveActive;

  /// Mode pointage armé par le bouton « Créer une réserve ».
  ///
  /// L'appui sur le plan crée une réserve DE TOUTE FAÇON, sans rien armer —
  /// c'est le geste principal, et il ne doit pas demander de bouton. Le bouton
  /// existe pour ceux qui le cherchent : il ne débloque rien, il ANNONCE. Une
  /// fois appuyé, le bandeau d'aide passe en évidence et dit quoi faire, ce qui
  /// évite de rester devant un plan sans savoir qu'il est actif.
  bool _pointageAnnonce = false;

  /// Le point que l'utilisateur vient de désigner, tant que le formulaire est
  /// ouvert.
  ///
  /// Sans lui, on remplit le formulaire sans plus voir OÙ la réserve va se
  /// poser — et la feuille masque justement la moitié du plan. Le repère
  /// provisoire répond à la seule question qui compte à cet instant : « est-ce
  /// bien là que j'ai visé ? »
  ({double x, double y})? _pointProvisoire;

  /// Page du document affichée, et nombre total — cahier technique § 6.
  /// L'ÉCRAN les garde : la page fait partie de la position d'une réserve.
  int _page = 1;
  int _nombrePages = 1;

  /// Plein écran : le bandeau d'aide et le panneau bas se replient, le plan
  /// prend toute la place.
  bool _pleinEcran = false;

  @override
  void initState() {
    super.initState();
    _chargerImage();
  }

  @override
  void didUpdateWidget(_VuePlanOuvert ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.plan.fichierUrl != widget.plan.fichierUrl) _chargerImage();
  }

  Future<void> _chargerImage() async {
    setState(() {
      _octets = null;
      _erreurImage = null;
    });

    // On télécharge TOUJOURS, quel que soit `plan.format` : ce champ vaut
    // 'pdf' par défaut côté serveur pour tout dépôt sans format explicite,
    // alors que png, jpg, jpeg et webp sont acceptés. C'est `PlanInteractif`
    // qui décide, sur les OCTETS reçus, s'il sait afficher le fichier — un
    // plan photographié sur le chantier était sinon refusé sur l'écran qui EST
    // la zone de travail.
    try {
      final octets = await _telecharger(widget.plan.fichierUrl);
      if (mounted) setState(() => _octets = octets);
    } catch (_) {
      if (mounted) setState(() => _erreurImage = context.l10n.planViewerErreurChargement);
    }
  }

  /// Un appui sur une zone libre : on pose le repère provisoire, puis on ouvre
  /// le formulaire.
  ///
  /// Le formulaire sait REVENIR sans rien créer (bouton « Retour ») : on
  /// efface alors le repère provisoire et le plan reste exactement là où il
  /// était, prêt pour un autre point. C'est le cas fréquent d'un appui à côté.
  Future<void> _ouvrirFormulaire(double x, double y) async {
    // Un plan en attente de validation ne peut pas recevoir de réserve : le
    // serveur la refuse. Le dire ici évite de faire remplir un formulaire pour
    // rien.
    if (widget.plan.enAttenteValidation) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.planExplorerEnAttenteValidation),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    // Posé AVANT l'ouverture : le repère doit être à l'écran au moment où la
    // feuille monte, pas après.
    setState(() => _pointProvisoire = (x: x, y: y));

    final cree = await showModalBottomSheet<Reserve>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NouvelleReserveSheet(
        localisation: LocalisationReserve(
          chantierId: widget.chantierId,
          planId: widget.plan.id,
          // Bâtiment, étage et zone ne sont PLUS envoyés par le client : le
          // serveur les déduit du plan (`_heriterLocalisationDuPlan`). Les
          // renvoyer d'ici ne ferait que risquer de le contredire.
          chemin: widget.cheminLisible,
        ),
        positionX: x,
        positionY: y,
        // La page AFFICHÉE : c'est sur elle que le doigt s'est posé.
        positionPage: _page,
      ),
    );
    if (!mounted) return;

    // Retiré dans tous les cas : la réserve créée revient par le rechargement,
    // avec son identifiant et sa vraie couleur. L'abandon, lui, ne doit rien
    // laisser derrière.
    setState(() {
      _pointProvisoire = null;
      _pointageAnnonce = false;
    });

    // Le nouveau repère doit apparaître IMMÉDIATEMENT, sur CE plan, sans que
    // l'utilisateur ait à refaire le parcours : c'est tout l'intérêt de poser
    // une réserve depuis le plan.
    if (cree != null) await widget.onReserveCreee();
  }

  Future<void> _ouvrirFiche(PlanReserve reserve) async {
    setState(() => _reserveActive = reserve.id);
    await ouvrirFicheReserve(context, reserve);
    if (mounted) setState(() => _reserveActive = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final reserves = widget.plan.reserves;

    final marqueurs = [
      // Seuls les repères de la PAGE AFFICHÉE (cahier § 18) : sans ce filtre,
      // les réserves des douze pages d'un PDF se dessinent toutes sur celle
      // qu'on regarde.
      for (final r in reserves)
        if (r.position != null && r.position!.page == _page)
          MarqueurPlan(
            id: r.id,
            x: r.position!.x,
            y: r.position!.y,
            // Cahier technique § 14 : la pastille dit OÙ EN EST la
            // réserve, pas à quel point elle est grave.
            couleur: couleurStatutReserve(r.statut),
            actif: _reserveActive == r.id,
          ),
      // En DERNIER, donc au-dessus des autres : c'est le point qu'on regarde.
      if (_pointProvisoire != null)
        MarqueurPlan(
          id: _idPointProvisoire,
          x: _pointProvisoire!.x,
          y: _pointProvisoire!.y,
          couleur: AppColors.primary,
          actif: true,
        ),
    ];

    final peutPointer = widget.pointageAutorise && !widget.plan.enAttenteValidation;

    return Column(
      children: [
        // En PLEIN ÉCRAN, tout ce qui n'est pas le plan se replie. La sortie
        // reste à un appui, par le bouton qui y a fait entrer.
        if (peutPointer && !_pleinEcran)
          _BandeauAide(texte: l10n.planPointerAide, insiste: _pointageAnnonce),
        Expanded(child: Container(color: AppColors.surface, child: _image(marqueurs))),
        if (!_pleinEcran)
          _PanneauBas(
            sousPlans: widget.sousPlans,
            reserves: reserves,
          // Proposé à CHAQUE niveau, pas seulement sur une feuille : un défaut
          // de façade se relève sur le plan du bâtiment, un défaut de palier
          // sur celui de l'étage. Limiter la création au dernier niveau
          // obligerait à inventer un sous-plan pour chaque constat.
          //
          // Il est simplement mis en avant quand le plan n'a PAS de sous-plan :
          // il n'y a alors plus rien vers quoi descendre, et c'est la seule
          // action qui reste.
            onCreerReserve: peutPointer ? () => setState(() => _pointageAnnonce = true) : null,
            creationMiseEnAvant: widget.sousPlans.isEmpty,
            onOuvrirSousPlan: widget.onOuvrirSousPlan,
            onOuvrirReserve: _ouvrirFiche,
          ),
      ],
    );
  }

  Widget _image(List<MarqueurPlan> marqueurs) {
    if (_erreurImage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _erreurImage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _chargerImage,
                child: Text(context.l10n.commonRetry),
              ),
            ],
          ),
        ),
      );
    }
    if (_octets == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    return PlanInteractif(
      octets: _octets!,
      page: _page,
      marqueurs: marqueurs,
      controlesZoom: true,
      onPagesDetectees: (n) {
        // Seulement si le nombre CHANGE : le lecteur l'annonce à chaque rendu.
        if (n != _nombrePages && mounted) setState(() => _nombrePages = n);
      },
      onPageChangee: (n) => setState(() => _page = n),
      onPleinEcran: () => setState(() => _pleinEcran = !_pleinEcran),
      pleinEcran: _pleinEcran,
      // Nul quand le rôle ne peut pas poser de réserve : le plan reste alors
      // inerte pour un lecteur, sans lui cacher les repères déjà posés.
      onPointAppuye: widget.pointageAutorise ? _ouvrirFormulaire : null,
      // Un appui sur un repère CONSULTE, il ne crée pas. Les deux gestes ne
      // doivent jamais se confondre.
      onMarqueurAppuye: (m) {
        // Le repère provisoire n'est pas une réserve : il n'a pas de fiche.
        if (m.id == _idPointProvisoire) return;
        final r = widget.plan.reserves.where((x) => x.id == m.id).firstOrNull;
        if (r != null) _ouvrirFiche(r);
      },
    );
  }
}

/// Identifiant du repère provisoire — préfixé pour qu'aucune réserve réelle ne
/// puisse porter le même.
const _idPointProvisoire = '__point_provisoire__';

/// Bandeau d'aide au-dessus du plan — dit en une ligne ce que l'appui fait.
class _BandeauAide extends StatelessWidget {
  final String texte;

  /// Vrai après un appui sur « Créer une réserve » : le bandeau prend les
  /// couleurs pleines de l'action, pour répondre à l'appui. Sans cela, le
  /// bouton semblait ne rien faire — puisque l'appui sur le plan marchait déjà
  /// avant lui.
  final bool insiste;

  const _BandeauAide({required this.texte, this.insiste = false});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        color: insiste ? AppColors.primary : AppColors.primary100,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            Icon(
              Icons.touch_app_outlined,
              size: 16,
              color: insiste ? Colors.white : AppColors.primaryDarker,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                texte,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: insiste ? Colors.white : AppColors.primaryDarker,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Panneau du bas — les sous-plans directs, puis les réserves posées sur CE
/// plan.
///
/// Les deux listes sont distinctes et le restent : une réserve appartient au
/// plan exact sur lequel elle a été posée, jamais à ses sous-plans. Les
/// mélanger ferait apparaître, sur le plan d'un bâtiment, des réserves relevées
/// dans un appartement — sans repère pour les situer.
class _PanneauBas extends StatelessWidget {
  final List<Plan> sousPlans;
  final List<PlanReserve> reserves;
  final void Function(Plan) onOuvrirSousPlan;
  final void Function(PlanReserve) onOuvrirReserve;

  /// Nul quand le rôle ne peut pas poser de réserve, ou quand le plan attend
  /// encore la validation de sa demande de chantier : le bouton disparaît
  /// alors, plutôt que de mener à un refus.
  final VoidCallback? onCreerReserve;

  /// Vrai quand ce plan n'a AUCUN sous-plan : il n'y a plus rien vers quoi
  /// descendre, et créer une réserve est la seule action qui reste. Le bouton
  /// passe alors en pleine largeur, en tête du panneau.
  final bool creationMiseEnAvant;

  const _PanneauBas({
    required this.sousPlans,
    required this.reserves,
    required this.onOuvrirSousPlan,
    required this.onOuvrirReserve,
    required this.onCreerReserve,
    required this.creationMiseEnAvant,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      // Même règle que la visionneuse : un plafond calculé, borné par le bas
      // sur le contenu qui ne défile pas (poignée + bouton).
      constraints: BoxConstraints(
        maxHeight: hauteurPanneauBas(
          context,
          part: 0.38,
          contenuIncompressible: onCreerReserve == null ? 24 : 75,
        ),
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (onCreerReserve != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: creationMiseEnAvant ? 14 : 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    ),
                    onPressed: onCreerReserve,
                    icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                    label: Text(
                      context.l10n.reserveCreerBouton,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  if (sousPlans.isNotEmpty) ...[
                    _TitreSection(l10n.planExplorerSousPlans, sousPlans.length),
                    const SizedBox(height: 8),
                    for (final p in sousPlans) ...[
                      _LigneSousPlan(plan: p, onTap: () => onOuvrirSousPlan(p)),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 6),
                  ],
                  _TitreSection(
                    reserves.isEmpty
                        ? l10n.planViewerAucuneReserve
                        : l10n.planViewerReservesSurPlan(reserves.length),
                    null,
                  ),
                  const SizedBox(height: 8),
                  for (final r in reserves) ...[
                    _LigneReserve(reserve: r, onTap: () => onOuvrirReserve(r)),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitreSection extends StatelessWidget {
  final String texte;
  final int? compte;
  const _TitreSection(this.texte, this.compte);

  @override
  Widget build(BuildContext context) => Text(
        compte == null ? texte.toUpperCase() : '${texte.toUpperCase()} ($compte)',
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: AppColors.textSecondary,
        ),
      );
}

/// Une ligne de sous-plan — l'aperçu réel, le nom, et ce qu'il contient.
class _LigneSousPlan extends StatelessWidget {
  final Plan plan;
  final VoidCallback onTap;

  const _LigneSousPlan({required this.plan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final meta = <String>[
      if (plan.aDesSousPlans) l10n.planExplorerNSousPlans(plan.nombreSousPlans),
      if (plan.nombreReserves > 0) l10n.planExplorerNReserves(plan.nombreReserves),
    ].join(' · ');

    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              PlanVignette(
                plan: plan,
                icone: Icons.layers_outlined,
                couleur: AppColors.primary,
                taille: 40,
                largeur: 40,
                rayon: 10,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      plan.nom,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      meta.isEmpty ? l10n.planExplorerAucunSousPlan : meta,
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une ligne de réserve — ouvre la MÊME fiche qu'un appui sur son repère.
///
/// Deux chemins vers la même chose : on trouve une réserve soit en la voyant
/// sur le plan, soit en la lisant dans la liste. Les faire diverger — l'un vers
/// une feuille, l'autre vers un écran plein — obligerait à apprendre deux
/// comportements pour un seul objet.
class _LigneReserve extends StatelessWidget {
  final PlanReserve reserve;
  final VoidCallback onTap;

  const _LigneReserve({required this.reserve, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // La MÊME couleur que le repère sur le plan : la ligne et le point
    // désignent la même réserve, ils ne peuvent pas se contredire.
    final couleur = couleurStatutReserve(reserve.statut);
    final position = reserve.position;

    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: couleur.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.place_rounded, size: 17, color: couleur),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      reserve.titre,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      position == null
                          ? '#${reserve.numero}'
                          : '#${reserve.numero} · x ${position.x.toStringAsFixed(0)} · '
                              'y ${position.y.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              ReserveStatutBadge(statut: reserve.statut),
            ],
          ),
        ),
      ),
    );
  }
}

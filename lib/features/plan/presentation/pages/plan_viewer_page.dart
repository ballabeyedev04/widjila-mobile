import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/breakpoints.dart';
import '../../../../core/config/user_role.dart';
import '../../../../core/routes/app_router.dart';
import '../../../../core/routes/retour.dart';
import '../../../../core/services/ouverture_fichier.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../reserve/domain/entities/reserve.dart';
import '../../../reserve/presentation/widgets/reserve_statut_badge.dart';
import '../../domain/entities/plan.dart';
import '../cubit/plan_detail_cubit.dart';
import '../widgets/contexte_plan.dart';
import '../widgets/fiche_reserve_sheet.dart';
import '../widgets/nouvelle_reserve_sheet.dart';
import '../widgets/plan_interactif.dart';

/// Le plan, et les réserves qui y sont posées — en VUE INTERACTIVE.
///
/// ## Ce que cet écran affichait, et pourquoi c'était faux
///
/// Le document était rendu par `flutter_pdfview`, une vue NATIVE. On n'y
/// connaît ni le facteur de zoom ni le décalage courants : impossible d'y
/// superposer un repère sans qu'il dérive au premier geste. L'écran renonçait
/// donc à dessiner les réserves et affichait, à la place, une pastille
/// « 5 repères » posée dans un coin — le nombre, jamais les points.
///
/// C'est exactement ce que le client décrit : on lit « 5 réserves » sans
/// jamais voir OÙ elles sont, alors que c'est la seule question qu'on se pose
/// devant un plan.
///
/// ## La correction
///
/// `PlanInteractif` remplace la vue native. La page du PDF y est RASTERISÉE en
/// image (`pdfx`), puis placée dans un `InteractiveViewer` dont la matrice nous
/// appartient. Les repères vivent dans le même conteneur transformé que
/// l'image : ils subissent la même transformation et ne peuvent pas s'en
/// désolidariser. Le zoom et le déplacement restent disponibles, et l'appui
/// devient exploitable — ce qui ouvre du même coup la pose d'une réserve à
/// l'endroit exact du défaut.
///
/// Le même composant sert l'explorateur de plans : les deux écrans se
/// comportent donc à l'identique, ce qui n'était pas le cas.
class PlanViewerPage extends StatelessWidget {
  final String planId;
  const PlanViewerPage({super.key, required this.planId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<PlanDetailCubit>()..charger(planId),
      child: _PlanViewerView(planId: planId),
    );
  }
}

class _PlanViewerView extends StatelessWidget {
  final String planId;
  const _PlanViewerView({required this.planId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: BlocBuilder<PlanDetailCubit, PlanDetailState>(
        builder: (context, state) {
          switch (state.status) {
            case PlanDetailStatus.initial:
            case PlanDetailStatus.chargement:
              return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            case PlanDetailStatus.erreur:
              // Même bandeau que la visionneuse elle-même, plutôt qu'un
              // Scaffold imbriqué coiffé d'une AppBar vide : en cas d'échec,
              // l'écran doit rester le même écran — et garder sa flèche de
              // retour, seule sortie possible.
              return SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _BandeauViewer(titre: context.l10n.navPlans),
                    Expanded(
                      child: ErrorView(
                        message: state.erreur ?? context.l10n.commonErrorUnknown,
                        onRetry: () => context.read<PlanDetailCubit>().charger(planId),
                      ),
                    ),
                  ],
                ),
              );
            case PlanDetailStatus.succes:
              return _Contenu(plan: state.plan!);
          }
        },
      ),
    );
  }
}

/// Le plan à l'écran : bandeau, image interactive, panneau des réserves.
///
/// L'état vit ici et non dans le cubit : les octets du document, le repère
/// provisoire et le repère sélectionné ne concernent QUE l'affichage, et les
/// faire transiter par le cubit obligerait à les invalider à chaque
/// rechargement de la fiche.
class _Contenu extends StatefulWidget {
  final Plan plan;
  const _Contenu({required this.plan});

  @override
  State<_Contenu> createState() => _ContenuState();
}

class _ContenuState extends State<_Contenu> {
  Uint8List? _octets;

  /// Le téléchargement a échoué — un DRAPEAU, pas un message.
  ///
  /// Le libellé traduit était rangé ici, lu depuis `context.l10n` à
  /// l'intérieur du `catch`. Or ce `catch` peut s'exécuter AVANT la fin
  /// d'`initState` — il suffit d'un échec synchrone (URL malformée, dépendance
  /// absente du conteneur) — et Flutter interdit alors de consulter un widget
  /// hérité. L'assertion faisait tomber l'écran entier pour un simple fichier
  /// introuvable.
  ///
  /// Résolu dans `build`, le libellé suit au passage un changement de langue
  /// en cours de route.
  bool _echecTelechargement = false;

  /// Réserve dont la fiche est ouverte — son repère passe en évidence, pour
  /// qu'on sache de quel point parle la feuille.
  String? _reserveActive;

  /// Le point que l'utilisateur vient de désigner, tant que le formulaire est
  /// ouvert. Sans lui, on remplit le formulaire sans plus voir OÙ la réserve
  /// va se poser — et la feuille masque justement la moitié du plan.
  ({double x, double y})? _pointProvisoire;

  /// Page du document actuellement affichée — cahier technique § 6.
  ///
  /// L'ÉCRAN la garde, et non `PlanInteractif` : la page fait partie de la
  /// position d'une réserve (§ 18), et c'est cet écran qui crée la réserve.
  int _page = 1;

  /// Nombre de pages du document, annoncé par le lecteur une fois le fichier
  /// ouvert. Lu du document lui-même et non du champ `page_count` de la base,
  /// qui est facultatif au dépôt et vaut `null` pour l'essentiel des plans
  /// déjà en ligne.
  int _nombrePages = 1;

  /// Plein écran — le bandeau et le panneau bas se replient, le plan prend
  /// tout. Sur un téléphone, c'est la différence entre deviner un plan et le
  /// lire.
  bool _pleinEcran = false;

  /// La structure du chantier et ses plans — l'arborescence du panneau bas,
  /// voir [PanneauContextePlan].
  EtatContexte _contexte = const EtatContexte.enChargement();

  /// Ce qui est déplié dans l'arborescence. Ouvrir un plan depuis elle
  /// EMPILE une visionneuse : celle-ci reste montée dessous, et retrouve donc
  /// son arborescence telle qu'on l'a laissée.
  final EtatDepliage _depliage = EtatDepliage();

  bool _panneauAgrandi = false;

  @override
  void initState() {
    super.initState();
    _telecharger();
    _chargerContexte();
  }

  /// Jamais bloquant : sans structure, le plan reste consultable et on peut y
  /// poser une réserve ; seul le panneau le signale.
  Future<void> _chargerContexte() async {
    final chantierId = widget.plan.chantierId;
    if (chantierId.isEmpty) {
      // Affectation directe : appelée depuis `initState`, où la
      // reconstruction suit de toute façon.
      _contexte = const EtatContexte.echec('');
      return;
    }
    final etat = await chargerContexteChantier(chantierId);
    if (mounted) setState(() => _contexte = etat);
  }

  void _rechargerContexte() {
    setState(() => _contexte = const EtatContexte.enChargement());
    _chargerContexte();
  }

  @override
  void didUpdateWidget(_Contenu ancien) {
    super.didUpdateWidget(ancien);
    // Un rechargement de la fiche (après création d'une réserve) ne doit PAS
    // retélécharger le document : seuls les repères ont changé.
    if (ancien.plan.fichierUrl != widget.plan.fichierUrl) _telecharger();
  }

  Future<void> _telecharger() async {
    // Affectations DIRECTES, sans `setState` : `_telecharger` est appelée
    // depuis `initState` et depuis `didUpdateWidget`, deux moments où une
    // reconstruction suit de toute façon — et où `setState` lèverait.
    _octets = null;
    _echecTelechargement = false;

    // Un plan sans fichier n'est pas une erreur de réseau : c'est un plan sans
    // image, et il a son propre message. Partir en requête sur une URL vide
    // n'aurait produit qu'un échec trompeur.
    if (widget.plan.fichierUrl.isEmpty) return;

    try {
      // Les octets transitent par le Dio de l'app, qui porte le jeton exigé
      // par `/uploads/*` : un lien direct répondrait 401.
      final reponse = await sl<Dio>().get<List<int>>(
        widget.plan.fichierUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final donnees = reponse.data;
      if (donnees == null) throw Exception('Réponse vide');
      if (mounted) setState(() => _octets = Uint8List.fromList(donnees));
    } catch (_) {
      if (mounted) setState(() => _echecTelechargement = true);
    }
  }

  /// Un appui sur une zone libre : repère provisoire, puis formulaire.
  Future<void> _creerIci(double x, double y) async {
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
          chantierId: widget.plan.chantierId,
          planId: widget.plan.id,
          // Ni bâtiment, ni étage, ni zone : le serveur les déduit du plan
          // (`reserve.service.js#_heriterLocalisationDuPlan`). Les envoyer
          // d'ici ne ferait que risquer de le contredire.
          chemin: [widget.plan.chantierNom, ...lieuDuPlan(widget.plan), widget.plan.nom]
              .whereType<String>()
              .join(' › '),
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
    setState(() => _pointProvisoire = null);

    // Le nouveau repère doit apparaître IMMÉDIATEMENT. On recharge la FICHE,
    // pas la page : le document reste en mémoire (voir `didUpdateWidget`), il
    // n'y a donc ni écran de chargement ni clignotement.
    if (cree != null && context.mounted) {
      await context.read<PlanDetailCubit>().charger(widget.plan.id);
    }
  }

  Future<void> _ouvrirFiche(PlanReserve reserve) async {
    setState(() => _reserveActive = reserve.id);
    await ouvrirFicheReserve(context, reserve);
    if (mounted) setState(() => _reserveActive = null);
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    // Le serveur réserve la pose d'une réserve aux rôles d'intervention :
    // rendre le plan actif pour les autres promettrait un 403.
    final peutCreer = context.select(
          (AuthBloc b) => b.state.utilisateur?.role.peutIntervenirSurReserves ?? false,
        ) &&
        !plan.enAttenteValidation;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // En PLEIN ÉCRAN, tout ce qui n'est pas le plan se replie : le
          // bandeau, l'aide et le panneau bas. La sortie reste à un appui, par
          // le même bouton qui y a fait entrer.
          if (!_pleinEcran)
            _BandeauViewer(
              titre: plan.nom,
              // Un plan de la STRUCTURE se situe par sa place dans le
              // chantier — « Océania › Bâtiment A › R+1 › A001 » ; le format
              // et la version passent alors dans la fiche du panneau bas.
              sousTitre: lieuDuPlan(plan).isNotEmpty
                  ? [if (plan.chantierNom != null) plan.chantierNom!, ...lieuDuPlan(plan)]
                      .join(' › ')
                  : [
                      if (plan.chantierNom != null) plan.chantierNom!,
                      '${plan.format.label} · v${plan.version}',
                      if (plan.typePlan != null && plan.typePlan!.isNotEmpty) plan.typePlan!,
                    ].join(' · '),
            ),
          if (!_pleinEcran && peutCreer && _octets != null)
            _BandeauAide(texte: context.l10n.planPointerAide),
          Expanded(child: _zoneDocument(peutCreer)),
          if (!_pleinEcran)
            _PanneauReserves(
              reserves: plan.reserves,
              onOuvrirReserve: _ouvrirFiche,
              contexte: PanneauContextePlan(
                plan: plan,
                chantierNom: plan.chantierNom,
                etat: _contexte,
                onReessayer: _rechargerContexte,
                // Une visionneuse EMPILÉE : la flèche de retour ramène à
                // celle-ci, arborescence dépliée comme on l'a laissée.
                onOuvrirPlan: (p) => context.push('/plans/${p.id}'),
                depliage: _depliage,
              ),
              agrandi: _panneauAgrandi,
              onBasculerTaille: () => setState(() => _panneauAgrandi = !_panneauAgrandi),
            // Le bouton n'ARME rien : l'appui sur le plan fonctionne de toute
            // façon. Il est là pour ceux qui le cherchent, et il dit où
            // appuyer — c'est le bandeau d'aide, juste au-dessus, qui répond.
              onCreerReserve: peutCreer && _octets != null
                  ? () => ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.l10n.planPointerAide),
                          backgroundColor: AppColors.primary,
                          duration: const Duration(seconds: 3),
                        ),
                      )
                  : null,
            ),
        ],
      ),
    );
  }

  /// La zone du document, dans chacun de ses états.
  Widget _zoneDocument(bool peutCreer) {
    final l10n = context.l10n;
    final plan = widget.plan;

    // ── Le plan n'a AUCUN fichier ──────────────────────────────────────────
    if (plan.fichierUrl.isEmpty) {
      return _Message(
        icon: Icons.image_not_supported_outlined,
        titre: l10n.planViewerSansImageTitre,
        texte: l10n.planViewerSansImage,
      );
    }

    // ── Le téléchargement a échoué ─────────────────────────────────────────
    if (_echecTelechargement) {
      return _Message(
        icon: Icons.error_outline_rounded,
        titre: l10n.planViewerIndisponible,
        texte: l10n.planViewerErreurChargement,
        action: OutlinedButton.icon(
          onPressed: _telecharger,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(l10n.commonRetry),
        ),
      );
    }

    // ── Chargement ─────────────────────────────────────────────────────────
    if (_octets == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    // ── Ni PDF ni image reconnue — DWG, IFC ────────────────────────────────
    //
    // Le fichier existe, et une application tierce installée sur l'appareil
    // sait peut-être le lire : constater l'impasse sans proposer la sortie
    // serait gratuit.
    if (!_entetePdf(_octets!) && !_estImage(_octets!)) {
      return _Message(
        icon: Icons.view_in_ar_outlined,
        titre: l10n.planViewerFormatTitre(plan.format.label),
        texte: l10n.planViewerFormatNonSupporte,
        action: _BoutonOuvrirExterne(plan: plan),
      );
    }

    // ── Le plan, avec ses repères ──────────────────────────────────────────
    final marqueurs = [
      // Seuls les repères de la PAGE AFFICHÉE (cahier § 18). Sans ce filtre,
      // les réserves des douze pages d'un PDF se dessinaient toutes sur celle
      // qu'on regarde : chacune à ses bonnes coordonnées, sur la mauvaise
      // page. Un repère faux envoie constater un défaut là où il n'y en a pas.
      for (final r in plan.reserves)
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

    return Container(
      color: AppColors.surface,
      child: PlanInteractif(
        octets: _octets!,
        page: _page,
        marqueurs: marqueurs,
        controlesZoom: true,
        onPagesDetectees: (n) {
          // `setState` seulement si le nombre CHANGE : le lecteur l'annonce à
          // chaque rendu de page, et réagir à chaque fois relancerait une
          // reconstruction pour rien.
          if (n != _nombrePages && mounted) setState(() => _nombrePages = n);
        },
        onPageChangee: (n) => setState(() => _page = n),
        onPleinEcran: () => setState(() => _pleinEcran = !_pleinEcran),
        pleinEcran: _pleinEcran,
        onPointAppuye: peutCreer ? _creerIci : null,
        // Un appui sur un repère CONSULTE, il ne crée pas. Les deux gestes ne
        // doivent jamais se confondre.
        onMarqueurAppuye: (m) {
          // Le repère provisoire n'est pas une réserve : il n'a pas de fiche.
          if (m.id == _idPointProvisoire) return;
          final r = plan.reserves.where((x) => x.id == m.id).firstOrNull;
          if (r != null) _ouvrirFiche(r);
        },
      ),
    );
  }
}

/// Identifiant du repère provisoire — préfixé pour qu'aucune réserve réelle ne
/// puisse porter le même.
const _idPointProvisoire = '__point_provisoire__';

/// Bandeau d'aide au-dessus du plan — dit en une ligne ce que l'appui fait.
class _BandeauAide extends StatelessWidget {
  final String texte;
  const _BandeauAide({required this.texte});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: AppColors.primary100,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            const Icon(Icons.touch_app_outlined, size: 16, color: AppColors.primaryDarker),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                texte,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDarker,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Bandeau de la visionneuse.
///
/// Volontairement PAS un `EnTeteListe` : celui-ci porte un titre de 27 px
/// conçu pour ouvrir une liste, alors qu'ici le document doit occuper l'écran.
/// Le bandeau reprend donc le reste du vocabulaire — flèche arrondie orange,
/// tuile d'icône, titre en w800, ligne méta grise — dans une hauteur réduite.
class _BandeauViewer extends StatelessWidget {
  final String titre;
  final String? sousTitre;

  const _BandeauViewer({required this.titre, this.sousTitre});

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
            // Cet écran est une destination de notification : ouvert par `go`,
            // il n'a alors aucune pile. Repli sur l'onglet Plans.
            onPressed: () => context.retourVers(AppRoutes.plans),
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
                if (sousTitre != null)
                  Text(
                    sousTitre!,
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

/// Ce fichier commence-t-il par l'en-tête d'un PDF (`%PDF-`) ?
///
/// On lit les OCTETS plutôt que l'extension ou le champ `format` : le premier
/// peut mentir, le second vaut 'pdf' par défaut côté serveur pour tout dépôt
/// sans format explicite.
bool _entetePdf(Uint8List o) {
  const entete = [0x25, 0x50, 0x44, 0x46, 0x2D]; // %PDF-
  if (o.length < entete.length) return false;
  for (var i = 0; i < entete.length; i++) {
    if (o[i] != entete[i]) return false;
  }
  return true;
}

/// Ce fichier est-il une image que Flutter sait décoder ?
///
/// PNG, JPEG et WebP — les trois formats acceptés au dépôt à côté du PDF.
/// Reconnus à leur signature, pour la même raison que ci-dessus.
bool _estImage(Uint8List o) {
  if (o.length < 12) return false;
  // PNG : 89 50 4E 47
  if (o[0] == 0x89 && o[1] == 0x50 && o[2] == 0x4E && o[3] == 0x47) return true;
  // JPEG : FF D8 FF
  if (o[0] == 0xFF && o[1] == 0xD8 && o[2] == 0xFF) return true;
  // WebP : « RIFF » .... « WEBP »
  if (o[0] == 0x52 && o[1] == 0x49 && o[2] == 0x46 && o[3] == 0x46 &&
      o[8] == 0x57 && o[9] == 0x45 && o[10] == 0x42 && o[11] == 0x50) {
    return true;
  }
  return false;
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String titre;
  final String texte;

  /// Bouton facultatif — présent quand l'impasse a une sortie.
  final Widget? action;

  const _Message({required this.icon, required this.titre, required this.texte, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: AppColors.textMuted),
            const SizedBox(height: 14),
            Text(
              titre,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              texte,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            ),
            if (action != null) ...[const SizedBox(height: 22), action!],
          ],
        ),
      ),
    );
  }
}

/// Confie le plan à une application tierce de l'appareil.
class _BoutonOuvrirExterne extends StatefulWidget {
  final Plan plan;
  const _BoutonOuvrirExterne({required this.plan});

  @override
  State<_BoutonOuvrirExterne> createState() => _BoutonOuvrirExterneState();
}

class _BoutonOuvrirExterneState extends State<_BoutonOuvrirExterne> {
  bool _enCours = false;

  Future<void> _ouvrir() async {
    if (_enCours) return;
    setState(() => _enCours = true);

    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final resultat = await sl<OuvertureFichier>().ouvrir(
      url: widget.plan.fichierUrl,
      // Le nom du plan n'a pas d'extension : on ajoute celle du format, sans
      // quoi le système ne sait pas à quelle application confier le fichier.
      nomFichier: '${widget.plan.nom}.${widget.plan.format.raw}',
    );
    if (!mounted) return;
    setState(() => _enCours = false);

    resultat.fold(
      (failure) => messenger.showSnackBar(SnackBar(content: Text(AppAlert.messageLisible(l10n, failure.errorMessage)))),
      (issue) {
        if (issue == ResultatOuverture.aucuneApplication) {
          messenger.showSnackBar(SnackBar(content: Text(l10n.documentAucuneApplication)));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: _enCours ? null : _ouvrir,
      icon: _enCours
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
            )
          : const Icon(Icons.open_in_new_rounded, size: 18),
      label: Text(
        context.l10n.planOuvrirExterne,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Bandeau bas — « Créer une réserve », puis les réserves déjà posées.
class _PanneauReserves extends StatelessWidget {
  final List<PlanReserve> reserves;
  final void Function(PlanReserve) onOuvrirReserve;

  /// Nul quand le rôle ne peut pas poser de réserve, quand le plan attend
  /// encore sa validation, ou quand le document n'est pas affichable : le
  /// bouton disparaît plutôt que de mener nulle part.
  final VoidCallback? onCreerReserve;

  /// Ce qui dépend de la PORTÉE du plan — les bâtiments sous un plan global,
  /// la localisation sous celui d'un appartement. Voir [PanneauContextePlan].
  final Widget contexte;

  /// Panneau agrandi par sa poignée — voir [PoigneePanneau].
  final bool agrandi;
  final VoidCallback onBasculerTaille;

  const _PanneauReserves({
    required this.reserves,
    required this.onOuvrirReserve,
    required this.onCreerReserve,
    required this.contexte,
    required this.agrandi,
    required this.onBasculerTaille,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      // Plafond calculé, et non un pourcentage sec — voir `hauteurPanneauBas`.
      //
      // 34 % d'un téléphone COUCHÉ font 108 points, et le panneau doit encore
      // y loger sa poignée et son bouton. Le balayage des formats le mesurait :
      // « RenderFlex overflowed by 3.2 pixels ». La règle borne désormais par
      // le bas ce que le contenu exige réellement, échelle de police comprise.
      constraints: BoxConstraints(
        maxHeight: hauteurPanneauBas(
          context,
          // Agrandi, le panneau monte jusqu'au plafond commun de 70 % : il
          // porte alors l'arborescence d'un bâtiment déplié.
          part: agrandi ? 0.7 : 0.34,
          plafond: agrandi ? double.infinity : 340,
          // Poignée (24) + bouton (51) : tout le reste défile.
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
            PoigneePanneau(agrandi: agrandi, onBasculer: onBasculerTaille),
            if (onCreerReserve != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      // Plus haut quand le plan est vierge : c'est alors la
                      // seule action de l'écran.
                      padding: EdgeInsets.symmetric(vertical: reserves.isEmpty ? 14 : 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    ),
                    onPressed: onCreerReserve,
                    icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                    label: Text(
                      l10n.reserveCreerBouton,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ),
              ),
            // TOUT ce qui suit défile.
            //
            // Le titre était posé hors de la zone défilante : sur un écran
            // court, ses 30 points s'ajoutaient au contenu incompressible et
            // faisaient déborder le panneau. Seuls la poignée et le bouton
            // restent fixes — le bouton parce qu'il est l'action principale et
            // doit rester sous le pouce.
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  contexte,
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                    child: Text(
                      reserves.isEmpty
                          ? l10n.planViewerAucuneReserve
                          : l10n.planViewerReservesSurPlan(reserves.length),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
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
    final position = reserve.position;
    // La MÊME couleur que le repère sur le plan : la ligne et le point
    // désignent la même réserve, ils ne peuvent pas se contredire.
    final couleur = couleurStatutReserve(reserve.statut);

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
              // Pastille BORNÉE : sans plafond, son libellé — « Prise en
              // charge », « Wiedereröffnet » — prenait sa largeur au titre,
              // qui partage la rangée. Un enfant non flexible est mesuré
              // avant l'`Expanded` voisin. Le plafond suit l'échelle de
              // police : un texte agrandi rouvrirait sinon l'écrasement.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.textScalerOf(context).scale(124),
                ),
                child: ReserveStatutBadge(statut: reserve.statut),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

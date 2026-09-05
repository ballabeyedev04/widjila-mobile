import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/ouverture_fichier.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../reserve/domain/entities/reserve.dart';
import '../../../reserve/presentation/widgets/reserve_statut_badge.dart';
import '../../domain/entities/plan.dart';
import '../cubit/plan_detail_cubit.dart';
import '../../../../core/routes/app_router.dart';
import '../../../../core/routes/retour.dart';

/// Écran 5 de la maquette — le plan et les réserves qui y sont rattachées.
///
/// Le document est rendu par `flutter_pdfview` à partir des OCTETS
/// (`pdfData`) et non d'un chemin de fichier : `path_provider` est
/// volontairement absent du projet (voir le commentaire dans `pubspec.yaml`,
/// il faisait planter la compilation), donc écrire le PDF sur disque n'est pas
/// une option. Les octets transitent par le Dio de l'app, qui porte le jeton
/// exigé par `/uploads/*`.
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
              final plan = state.plan!;
              return _Contenu(plan: plan);
          }
        },
      ),
    );
  }
}

class _Contenu extends StatelessWidget {
  final Plan plan;
  const _Contenu({required this.plan});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _BandeauViewer(
            titre: plan.nom,
            sousTitre: [
              if (plan.chantierNom != null) plan.chantierNom!,
              '${plan.format.label} · v${plan.version}',
            ].join(' · '),
          ),
          Expanded(child: _Document(plan: plan)),
          _PanneauReserves(plan: plan),
        ],
      ),
    );
  }
}

/// Bandeau de la visionneuse.
///
/// Volontairement PAS un `EnTeteListe` : celui-ci porte un titre de 27 px
/// conçu pour ouvrir une liste, alors qu'ici le document doit occuper
/// l'écran. Le bandeau reprend donc le reste du vocabulaire — flèche
/// arrondie orange, tuile d'icône, titre en w800, ligne méta grise — dans une
/// hauteur réduite.
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
            // Cet écran est une destination de notification : ouvert par `go`, il
            // n'a alors aucune pile. Repli sur l'onglet Plans.
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
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary),
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

/// Zone d'affichage du document. Les formats DWG et IFC existent en base
/// (import depuis le web) mais aucune visionneuse mobile ne les rend :
/// on le dit franchement plutôt que d'afficher un écran vide.
class _Document extends StatefulWidget {
  final Plan plan;
  const _Document({required this.plan});

  @override
  State<_Document> createState() => _DocumentState();
}

class _DocumentState extends State<_Document> {
  Uint8List? _octets;

  /// Le telechargement a echoue — un DRAPEAU, pas un message.
  ///
  /// La version precedente rangeait ici le libelle traduit, lu depuis
  /// `context.l10n` a l'interieur du `catch`. Or ce `catch` peut s'executer
  /// AVANT que `initState` soit termine : il suffit que l'appel echoue de
  /// maniere synchrone (URL malformee, dependance absente du conteneur), et
  /// Flutter interdit de consulter un widget herite — ce que fait
  /// `AppLocalizations.of` — a ce moment-la. L'assertion qui suit fait
  /// tomber l'ecran entier, alors que le seul incident etait un fichier
  /// introuvable.
  ///
  /// Le libelle est donc resolu dans `build`, ou le contexte est toujours
  /// pret. Au passage, l'ecran suit un changement de langue en cours de
  /// route au lieu de conserver la phrase figee au moment de l'echec.
  bool _echecTelechargement = false;

  @override
  void initState() {
    super.initState();
    if (widget.plan.format.affichableSurMobile) _telecharger();
  }

  Future<void> _telecharger() async {
    try {
      final response = await sl<Dio>().get<List<int>>(
        widget.plan.fichierUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null) throw Exception('Réponse vide');
      if (mounted) setState(() => _octets = Uint8List.fromList(data));
    } catch (_) {
      if (mounted) setState(() => _echecTelechargement = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!widget.plan.format.affichableSurMobile) {
      // DWG et IFC n'ont pas de visionneuse mobile — mais le fichier existe,
      // et une application tierce installée sur l'appareil sait peut-être le
      // lire. Constater l'impasse sans proposer la sortie serait gratuit.
      return _Message(
        icon: Icons.view_in_ar_outlined,
        titre: l10n.planViewerFormatTitre(widget.plan.format.label),
        texte: l10n.planViewerFormatNonSupporte,
        action: _BoutonOuvrirExterne(plan: widget.plan),
      );
    }
    if (_echecTelechargement) {
      return _Message(
        icon: Icons.error_outline_rounded,
        titre: l10n.planViewerIndisponible,
        texte: l10n.planViewerErreurChargement,
      );
    }
    if (_octets == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    return Stack(
      children: [
        // `flutter_pdfview` gère lui-même le zoom et le déplacement (vue
        // native) : pas d'InteractiveViewer par-dessus, qui entrerait en
        // conflit avec ses propres gestes.
        PDFView(pdfData: _octets, enableSwipe: true, swipeHorizontal: false, fitPolicy: FitPolicy.BOTH),
        if (widget.plan.nombreReperes > 0)
          Positioned(
            top: 12,
            right: 12,
            child: _Pastille(nombre: widget.plan.nombreReperes),
          ),
      ],
    );
  }
}

/// Compteur de repères. Les coordonnées (`ReservePosition.x/y`) ne sont pas
/// projetées SUR le PDF : `PDFView` est une vue native dont on ne connaît ni
/// le facteur de zoom ni le décalage courants, donc tout marqueur superposé
/// se décalerait dès le premier geste de l'utilisateur. Un repère faux étant
/// pire que pas de repère, la position est exposée dans la liste du bas,
/// où elle est exacte.
class _Pastille extends StatelessWidget {
  final int nombre;
  const _Pastille({required this.nombre});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.place_rounded, color: Colors.white, size: 15),
          const SizedBox(width: 5),
          Text(
            context.l10n.planViewerReperes(nombre),
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
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
            Text(titre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
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
      (failure) => messenger.showSnackBar(SnackBar(content: Text(failure.errorMessage))),
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

/// Bandeau bas — « N réserves sur ce plan » et leur liste, comme la maquette.
class _PanneauReserves extends StatelessWidget {
  final Plan plan;
  const _PanneauReserves({required this.plan});

  @override
  Widget build(BuildContext context) {
    final reserves = plan.reserves;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.34),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 18, offset: const Offset(0, -4))],
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
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              // Un `Row` a enfant unique et sans contrainte : le libelle
              // « N reserves sur ce plan » debordait de 21 px sur un
              // telephone etroit, en francais comme en allemand. `Expanded`
              // lui rend la largeur disponible, l'ellipse absorbe le reste.
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      reserves.isEmpty
                          ? context.l10n.planViewerAucuneReserve
                          : context.l10n.planViewerReservesSurPlan(reserves.length),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (reserves.isNotEmpty)
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  itemCount: reserves.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _LigneReserve(reserve: reserves[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LigneReserve extends StatelessWidget {
  final PlanReserve reserve;
  const _LigneReserve({required this.reserve});

  Color get _couleurSeverite => switch (reserve.severite) {
        ReserveSeverite.faible => AppColors.info,
        ReserveSeverite.moyenne => AppColors.warning,
        ReserveSeverite.haute => AppColors.danger,
        ReserveSeverite.critique => AppColors.danger,
      };

  @override
  Widget build(BuildContext context) {
    final position = reserve.position;

    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/reserves/${reserve.id}'),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: _couleurSeverite.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(Icons.place_rounded, size: 17, color: _couleurSeverite),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      reserve.titre,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      position == null
                          ? '#${reserve.numero}'
                          : '#${reserve.numero} · x ${position.x.toStringAsFixed(0)} · y ${position.y.toStringAsFixed(0)}',
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

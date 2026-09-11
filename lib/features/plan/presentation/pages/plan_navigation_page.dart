import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/config/breakpoints.dart';
import '../../../referentiel/domain/entities/code_niveau.dart';
import '../../../../core/services/ouverture_fichier.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/liste_chrome.dart' show colonnesAdaptatives;
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../reserve/domain/entities/chantier_structure.dart';
import '../../../reserve/domain/entities/reserve.dart';
import '../../../reserve/domain/usecases/get_chantier_structure.dart';
import '../../../reserve/presentation/widgets/reserve_statut_badge.dart';
import '../../domain/entities/plan.dart';
import '../../domain/usecases/get_plan_detail.dart';
import '../../domain/usecases/get_plans_chantier.dart';
import '../../domain/usecases/uploader_plan.dart';
import '../widgets/fiche_reserve_sheet.dart';
import '../widgets/import_plan_sheet.dart';
import '../widgets/nouvelle_reserve_sheet.dart';
import '../widgets/plan_interactif.dart';

/// Parcours de consultation d'un chantier, tel que décrit par le guide client :
///
///   plan global → bâtiment → étages & sous-sols → appartements → plein écran
///
/// et, au bout, le geste qui justifie tout le reste : un appui n'importe où sur
/// le plan de l'appartement ouvre « Nouvelle réserve », localisation déjà
/// remplie et point appuyé conservé.
///
/// DESCENDRE D'UN NIVEAU se fait de deux façons, volontairement redondantes :
/// en appuyant une zone dessinée sur le plan (hotspot) quand quelqu'un a pris
/// le temps de les tracer, ou en appuyant une tuile de la liste — toujours
/// disponible. Le parcours ne dépend donc jamais d'une mise en place qui
/// n'aurait pas été faite.
class PlanNavigationPage extends StatefulWidget {
  final String chantierId;
  final String? chantierNom;

  const PlanNavigationPage({super.key, required this.chantierId, this.chantierNom});

  @override
  State<PlanNavigationPage> createState() => _PlanNavigationPageState();
}

class _PlanNavigationPageState extends State<PlanNavigationPage> {
  ChantierStructure _structure = const ChantierStructure();
  List<Plan> _plans = const [];
  bool _chargement = true;
  String? _erreur;

  // Position dans l'arborescence — tout à null = niveau chantier.
  BatimentStructure? _batiment;
  EtageStructure? _etage;
  ZoneStructure? _zone;

  /// Les plans de DÉTAIL traversés sous le dernier niveau de structure.
  ///
  /// Vide dans l'immense majorité des cas. Chaque élément est un cran plus
  /// bas : le plan de l'appartement, puis celui de la cuisine, puis celui d'un
  /// mur. C'est ce qui donne une profondeur quelconque là où la structure
  /// s'arrête à la zone.
  final List<Plan> _cheminDetails = [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    final structure = await sl<GetChantierStructure>()(widget.chantierId);
    final plans = await sl<GetPlansChantier>()(widget.chantierId);
    if (!mounted) return;

    structure.fold(
      (failure) => setState(() {
        _erreur = failure.errorMessage;
        _chargement = false;
      }),
      (s) {
        plans.fold(
          (failure) => setState(() {
            _erreur = failure.errorMessage;
            _chargement = false;
          }),
          (liste) => setState(() {
            _structure = s;
            _plans = liste;
            _chargement = false;
          }),
        );
      },
    );
  }

  /// Plans rangés par niveau. Une seule version par niveau — la plus récente :
  /// la liste renvoie toutes les révisions, en afficher plusieurs ferait
  /// apparaître le même appartement deux fois dans la grille.
  ({Plan? global, Map<String, Plan> batiments, Map<String, Plan> etages, Map<String, Plan> zones})
      get _parNiveau {
    Plan? global;
    final batiments = <String, Plan>{};
    final etages = <String, Plan>{};
    final zones = <String, Plan>{};

    void garder(Map<String, Plan> cible, String cle, Plan p) {
      final actuel = cible[cle];
      if (actuel == null || p.version > actuel.version) cible[cle] = p;
    }

    for (final p in _plans) {
      // Un plan de DÉTAIL hérite des rattachements de son parent : le plan de
      // la cuisine porte la même zone que celui de l'appartement A203. Sans
      // cette exclusion, il pourrait être retenu COMME le plan de A203 et
      // s'afficher à sa place — l'appartement disparaîtrait derrière l'un de
      // ses détails.
      //
      // Les détails ne sont atteints que par une descente explicite depuis
      // leur parent (`_detailsDe`).
      if (p.parentId != null) continue;

      if (p.zone != null) {
        garder(zones, p.zone!.id, p);
      } else if (p.etage != null) {
        garder(etages, p.etage!.id, p);
      } else if (p.batiment != null) {
        garder(batiments, p.batiment!.id, p);
      } else if (global == null || p.version > global.version) {
        global = p;
      }
    }
    return (global: global, batiments: batiments, etages: etages, zones: zones);
  }

  /// Descend là où pointe une zone cliquable. Une cible disparue ne fait rien,
  /// plutôt que de casser la navigation.
  void _suivreHotspot(PlanHotspot h) {
    switch (h.cibleType) {
      case PlanCibleType.batiment:
        for (final b in _structure.batiments) {
          if (b.id == h.cibleId) {
            setState(() {
              _batiment = b;
              _etage = null;
              _zone = null;
            });
            return;
          }
        }
      case PlanCibleType.etage:
        for (final b in _structure.batiments) {
          for (final e in b.etages) {
            if (e.id == h.cibleId) {
              setState(() {
                _batiment = b;
                _etage = e;
                _zone = null;
              });
              return;
            }
          }
        }
      case PlanCibleType.zone:
        for (final b in _structure.batiments) {
          for (final e in b.etages) {
            for (final z in e.zones) {
              if (z.id == h.cibleId) {
                setState(() {
                  _batiment = b;
                  _etage = e;
                  _zone = z;
                });
                return;
              }
            }
          }
        }
    }
  }

  String get _titre {
    if (_zone != null) return _zone!.nom;
    if (_etage != null) return _etage!.nom;
    if (_batiment != null) return _batiment!.nom;
    return widget.chantierNom ?? context.l10n.navPlans;
  }

  /// Le plan actuellement à l'écran, s'il y en a un.
  ///
  /// C'est lui qui recevra un éventuel plan de détail. Il suit exactement la
  /// descente : le dernier détail traversé s'il y en a, sinon le plan du
  /// niveau de structure où l'on se trouve.
  Plan? get _planCourant {
    if (_cheminDetails.isNotEmpty) return _cheminDetails.last;
    final niveaux = _parNiveau;
    if (_zone != null) return niveaux.zones[_zone!.id];
    if (_etage != null) return niveaux.etages[_etage!.id];
    if (_batiment != null) return niveaux.batiments[_batiment!.id];
    return niveaux.global;
  }

  /// Ajoute un plan de DÉTAIL sous [parent].
  ///
  /// Le fichier est choisi puis nommé, exactement comme un import de plan
  /// ordinaire — c'en est un, à ceci près qu'il porte un parent. Le serveur
  /// lui fait hériter de la place de celui-ci : le détail reste rattaché au
  /// même appartement, au même étage, au même bâtiment.
  ///
  /// Sans cette action, la profondeur existait en base et dans la navigation
  /// mais n'avait aucune porte d'entrée : on ne pouvait pas créer un détail
  /// depuis l'application.
  /// Verrou de double appui sur « ajouter un plan de détail ».
  ///
  /// Sans lui, deux appuis rapprochés ouvraient deux sélecteurs de fichier et
  /// pouvaient déposer DEUX FOIS le même document. Le serveur ne s'en plaint
  /// pas — il sérialise le calcul de version — mais il crée alors une v2
  /// identique à la v1, que plus rien ne distingue.
  bool _depotEnCours = false;

  Future<void> _ajouterDetail(Plan parent) async {
    if (_depotEnCours) return;
    _depotEnCours = true;
    try {
      await _deposerDetail(parent);
    } finally {
      // Relâché DANS TOUS LES CAS, y compris sur abandon du sélecteur ou
      // erreur réseau : un verrou qui reste posé rend le bouton mort pour le
      // reste de la session.
      _depotEnCours = false;
    }
  }

  Future<void> _deposerDetail(Plan parent) async {
    final choix = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
      withData: false,
    );
    final fichier = choix?.files.singleOrNull;
    final chemin = fichier?.path;
    if (fichier == null || chemin == null || !mounted) return;

    // Le nom du fichier sert de proposition : c'est presque toujours le bon,
    // et le retaper à chaque import serait pénible sur un chantier.
    final detail = await demanderDetailPlan(context, nomPropose: fichier.name);
    if (detail == null || !mounted) return;

    final resultat = await sl<UploaderPlan>()(
      chantierId: widget.chantierId,
      cheminFichier: chemin,
      nom: detail.nom,
      format: detail.format,
      parentId: parent.id,
      typePlan: detail.typePlan,
      datePlan: detail.datePlan,
    );
    if (!mounted) return;

    resultat.fold(
      (echec) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(echec.errorMessage), backgroundColor: AppColors.danger),
      ),
      (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.planDetailAjoute), backgroundColor: AppColors.success),
        );
        // Rechargé pour que le détail apparaisse AUSSITÔT sous son parent.
        _charger();
      },
    );
  }

  /// Les plans de détail rattachés DIRECTEMENT à ce plan.
  ///
  /// Lus dans la liste déjà chargée plutôt que demandés au serveur : tous les
  /// plans du chantier sont en mémoire, et une requête par ouverture ne
  /// rendrait rien de plus sur une connexion de chantier.
  ///
  /// Jamais les détails des détails : la navigation est progressive, et c'est
  /// l'appui suivant qui descendra d'un cran.
  List<Plan> _detailsDe(String planId) =>
      _plans.where((p) => p.parentId == planId).toList()
        ..sort((a, b) => a.nom.compareTo(b.nom));

  /// Fil d'Ariane COMPLET — « Résidence Horizon › Bâtiment A › R+2 ».
  ///
  /// Le chantier en tête, et tous les niveaux traversés SAUF le dernier, que
  /// le titre affiche déjà juste au-dessus. Le répéter ne dirait rien de plus.
  ///
  /// La version précédente perdait le nom du chantier dès qu'on descendait :
  /// après trois appuis, on lisait « A203 » sans savoir de quel chantier.
  String get _sousTitre {
    final chemin = <String>[
      if (widget.chantierNom != null) widget.chantierNom!,
      if (_batiment != null) _batiment!.nom,
      if (_etage != null) _etage!.nom,
      if (_zone != null) _zone!.nom,
      for (final d in _cheminDetails) d.nom,
    ];
    // Le dernier segment EST le titre : on le retire du chemin.
    if (chemin.length > 1) chemin.removeLast();
    return chemin.join(' › ');
  }

  /// Remonte d'un niveau ; à la racine, quitte l'écran.
  void _remonter() {
    // Les détails d'abord : ils sont sous le dernier niveau de structure.
    if (_cheminDetails.isNotEmpty) {
      setState(() => _cheminDetails.removeLast());
    } else if (_zone != null) {
      setState(() => _zone = null);
    } else if (_etage != null) {
      setState(() => _etage = null);
    } else if (_batiment != null) {
      setState(() => _batiment = null);
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final peutCreer = context.select(
      (AuthBloc b) => b.state.utilisateur?.role.peutIntervenirSurReserves ?? false,
    );
    // Miroir du groupe `DEPOSANT` du serveur (`plan.route.js`) : déposer un
    // plan et poser une réserve ne relèvent pas des mêmes rôles.
    final peutDeposer = context.select(
      (AuthBloc b) => b.state.utilisateur?.role.peutDeposerPlans ?? false,
    );

    return PopScope(
      // Le bouton retour du système doit remonter D'UN NIVEAU, comme la flèche
      // de l'écran. Sans cette interception, il refermait tout le parcours
      // depuis le fond de l'arborescence.
      canPop: _batiment == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _remonter();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _Bandeau(
                titre: _titre,
                sousTitre: _sousTitre,
                onRetour: _remonter,
                onListe: () => context.push('/chantiers/${widget.chantierId}/plans'),
                // Proposé seulement quand un plan est à l'écran ET que le rôle
                // peut déposer : c'est le miroir du groupe `DEPOSANT` du
                // serveur (`plan.route.js`).
                onAjouterDetail: (peutDeposer && _planCourant != null)
                    ? () => _ajouterDetail(_planCourant!)
                    : null,
              ),
              Expanded(child: _corps(l10n, peutCreer)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _corps(dynamic l10n, bool peutCreer) {
    if (_chargement) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_erreur != null) {
      return ErrorView(message: _erreur!, onRetry: _charger);
    }

    final niveaux = _parNiveau;

    /// La vue interactive d'un plan, à n'importe quel niveau.
    ///
    /// Un plan SANS enfant est une feuille de l'arborescence : il n'y a plus
    /// rien vers quoi descendre, et c'est là que le plan devient la zone de
    /// travail — image, repères, et pose de réserve à l'appui.
    ///
    /// Cette vue n'existait qu'au niveau de l'appartement. Un bâtiment sans
    /// étage, ou un étage sans appartement, affichait donc « aucun étage » ou
    /// « aucun appartement » au-dessus de son plan, sans jamais permettre d'y
    /// poser quoi que ce soit — alors que c'était une feuille comme une autre.
    Widget vueInteractive(Plan plan) => _VuePlan(
          plan: plan,
          localisation: LocalisationReserve(
            chantierId: widget.chantierId,
            planId: plan.id,
            batimentId: _batiment?.id,
            etageId: _etage?.id,
            zoneId: _zone?.id,
            chemin: [_batiment?.nom, _etage?.nom, _zone?.nom].whereType<String>().join(' › '),
          ),
          pointageAutorise: peutCreer,
        );

    /// Un plan ouvert : son IMAGE, et ses plans de détail s'il en a.
    ///
    /// L'image était auparavant remplacée par la liste des détails dès qu'il y
    /// en avait un. Consulter le plan d'un bâtiment devenait alors impossible,
    /// et y poser une réserve encore moins — alors qu'un défaut de façade se
    /// relève sur le plan du bâtiment, pas sur celui d'un appartement.
    ///
    /// Les deux gestes cohabitent désormais, comme dans l'explorateur de
    /// plans : l'image reçoit l'appui qui pose une réserve, la liste du dessous
    /// reçoit celui qui descend d'un cran.
    Widget planOuvert(Plan plan) {
      final details = _detailsDe(plan.id);
      if (details.isEmpty) return vueInteractive(plan);

      return Column(
        children: [
          Expanded(child: vueInteractive(plan)),
          _SousPlans(
            titre: l10n.planNavSousPlans,
            details: details,
            compte: (d) => _detailsDe(d.id).length,
            onOuvrir: (d) => setState(() => _cheminDetails.add(d)),
          ),
        ],
      );
    }

    // ── Niveau 5 et au-delà : les plans de DÉTAIL ──────────────────────────
    //
    // Traité en PREMIER : dès qu'on est descendu dans un détail, c'est lui le
    // plan courant, quel que soit le niveau de structure d'où l'on vient.
    if (_cheminDetails.isNotEmpty) return planOuvert(_cheminDetails.last);

    // ── Niveau 4 : l'appartement en plein écran ────────────────────────────
    if (_zone != null) {
      final plan = niveaux.zones[_zone!.id];
      if (plan == null) {
        return EmptyState(icon: Icons.map_outlined, title: l10n.planNavSansPlan);
      }
      // `planOuvert` et non directement la vue : l'appartement peut lui aussi
      // avoir des plans de détail — c'est même son cas le plus probable.
      return planOuvert(plan);
    }

    // ── Niveau 3 : les appartements d'un étage ─────────────────────────────
    if (_etage != null) {
      final planEtage = niveaux.etages[_etage!.id];
      if (_etage!.zones.isEmpty && planEtage != null) return planOuvert(planEtage);

      return _Liste(
        planEnTete: niveaux.etages[_etage!.id],
        onHotspot: _suivreHotspot,
        sections: [
          (
            titre: l10n.planNavAppartements,
            elements: [
              for (final z in _etage!.zones)
                (
                  nom: z.nom,
                  meta: '',
                  plan: niveaux.zones[z.id],
                  icone: Icons.meeting_room_outlined,
                  onTap: () => setState(() => _zone = z),
                ),
            ],
          ),
        ],
        messageVide: l10n.planNavAucuneZone,
        sansPlan: l10n.planNavSansPlan,
      );
    }

    // ── Niveau 2 : les étages d'un bâtiment ────────────────────────────────
    if (_batiment != null) {
      final planBatiment = niveaux.batiments[_batiment!.id];
      if (_batiment!.etages.isEmpty && planBatiment != null) return planOuvert(planBatiment);

      final tries = [..._batiment!.etages]..sort((a, b) => a.niveau.compareTo(b.niveau));
      final sousSols = tries.where((e) => sectionDuNiveau(e) == TypeNiveau.sousSol).toList();
      final etages = tries.where((e) => sectionDuNiveau(e) == TypeNiveau.etage).toList();
      final toiture = tries.where((e) => sectionDuNiveau(e) == TypeNiveau.toiture).toList();

      ({String titre, List<({String nom, String meta, Plan? plan, IconData icone, VoidCallback onTap})> elements})
          section(String titre, List<EtageStructure> liste) => (
                titre: titre,
                elements: [
                  for (final e in liste)
                    (
                      nom: e.nom,
                      meta: l10n.planNavNZones(e.zones.length),
                      plan: niveaux.etages[e.id],
                      icone: Icons.layers_outlined,
                      onTap: () => setState(() => _etage = e),
                    ),
                ],
              );

      return _Liste(
        planEnTete: niveaux.batiments[_batiment!.id],
        onHotspot: _suivreHotspot,
        sections: [
          if (sousSols.isNotEmpty) section(l10n.planNavSousSols, sousSols),
          if (etages.isNotEmpty) section(l10n.planNavEtages, etages),
          if (toiture.isNotEmpty) section(l10n.planNavToiture, toiture),
        ],
        messageVide: l10n.planNavAucunEtage,
        sansPlan: l10n.planNavSansPlan,
      );
    }

    // ── Niveau 1 : le plan global du chantier ──────────────────────────────
    //
    // Un chantier sans bâtiment déclaré : le plan global EST la feuille. C'est
    // le cas d'une entreprise qui dépose un plan de masse et vient y poser ses
    // premières réserves avant d'avoir découpé la structure.
    final global = niveaux.global;
    if (_structure.batiments.isEmpty && global != null) return planOuvert(global);

    return _Liste(
      planEnTete: niveaux.global,
      messageAucunPlan: l10n.planNavAucunPlanGlobal,
      onHotspot: _suivreHotspot,
      sections: [
        (
          titre: l10n.planNavBatiments,
          elements: [
            for (final b in _structure.batiments)
              (
                nom: b.nom,
                meta: l10n.planNavNEtages(b.etages.length),
                plan: niveaux.batiments[b.id],
                icone: Icons.apartment_outlined,
                onTap: () => setState(() => _batiment = b),
              ),
          ],
        ),
      ],
      messageVide: l10n.planNavAucunBatiment,
      sansPlan: l10n.planNavSansPlan,
    );
  }
}

/// Mots qui désignent un niveau de toiture, pour les données ANCIENNES.
///
/// « Acrotère » n'y figure pas : c'est un détail de rive, pas un niveau.
final _motsToiture = RegExp(
  'toiture|terrasse|comble|edicule|édicule|local technique',
  caseSensitive: false,
);

/// Sous quelle section ranger ce niveau ?
///
/// La NATURE DÉCLARÉE fait foi. Elle vient du référentiel, saisie au dépôt du
/// plan, et c'est la seule information fiable : une cote ne dit pas qu'un
/// niveau est une toiture, et un nom libre encore moins.
///
/// L'heuristique ne sert qu'en REPLI, pour les niveaux créés avant ce
/// référentiel : la migration leur a donné `etage` par défaut, sans rien
/// deviner de leur nom — c'est donc ici, à l'affichage, qu'on fait de son
/// mieux avec ce qu'on a. Une cote négative est un sous-sol ; un nom qui parle
/// de toiture en est une.
///
/// Conséquence assumée : un niveau ancien nommé « Niveau -1 » avec une cote à
/// 0 restera dans ÉTAGES. On ne peut pas mieux faire sans inventer, et le
/// client peut corriger la nature depuis la fiche du niveau.
@visibleForTesting
TypeNiveau sectionDuNiveau(EtageStructure niveau) {
  if (niveau.typeNiveau != TypeNiveau.etage) return niveau.typeNiveau;
  if (niveau.niveau < 0) return TypeNiveau.sousSol;
  if (_motsToiture.hasMatch(niveau.nom)) return TypeNiveau.toiture;
  return TypeNiveau.etage;
}

/// Bandeau de navigation — même vocabulaire visuel que la visionneuse
/// (flèche orange, tuile d'icône, titre en w800, ligne méta grise).
class _Bandeau extends StatelessWidget {
  final String titre;
  final String sousTitre;
  final VoidCallback onRetour;

  /// Action de droite — la liste à plat des documents du chantier. Sans elle,
  /// l'import de plan et l'historique des versions devenaient inatteignables
  /// depuis le chantier, le parcours ayant pris la place de cette entrée.
  final VoidCallback? onListe;

  /// Ajouter un plan de DÉTAIL sous le plan actuellement ouvert.
  ///
  /// Nul quand il n'y a pas de plan à l'écran, ou quand le rôle n'a pas le
  /// droit de déposer : proposer l'action mènerait à un 403.
  final VoidCallback? onAjouterDetail;

  const _Bandeau({
    required this.titre,
    required this.sousTitre,
    required this.onRetour,
    this.onListe,
    this.onAjouterDetail,
  });

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
            decoration: BoxDecoration(color: AppColors.primary100, borderRadius: BorderRadius.circular(12)),
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
          if (onAjouterDetail != null)
            IconButton(
              icon: const Icon(Icons.add_photo_alternate_outlined),
              color: AppColors.primary,
              tooltip: context.l10n.planAjouterDetail,
              onPressed: onAjouterDetail,
            ),
          if (onListe != null)
            IconButton(
              icon: const Icon(Icons.format_list_bulleted_rounded),
              color: AppColors.textSecondary,
              tooltip: context.l10n.planTousLesPlans,
              onPressed: onListe,
            ),
        ],
      ),
    );
  }
}

typedef _Element = ({String nom, String meta, Plan? plan, IconData icone, VoidCallback onTap});
typedef _Section = ({String titre, List<_Element> elements});

/// Un niveau intermédiaire : le plan de ce niveau (s'il existe) surmontant la
/// liste de ce qu'il contient.
class _Liste extends StatelessWidget {
  final Plan? planEnTete;
  final String? messageAucunPlan;
  final List<_Section> sections;
  final String messageVide;
  final String sansPlan;
  final void Function(PlanHotspot) onHotspot;

  const _Liste({
    required this.planEnTete,
    required this.sections,
    required this.messageVide,
    required this.sansPlan,
    required this.onHotspot,
    this.messageAucunPlan,
  });

  @override
  Widget build(BuildContext context) {
    final vide = sections.every((s) => s.elements.isEmpty);
    // Même seuil que le tableau de bord et la coquille : une tablette ne se
    // définit pas différemment d'un écran à l'autre.
    final estTablette = MediaQuery.sizeOf(context).width >= seuilTablette;

    return ListView(
      padding: EdgeInsets.fromLTRB(estTablette ? 24 : 16, 16, estTablette ? 24 : 16, 24),
      children: [
        if (planEnTete != null)
          SizedBox(
            // Le plan occupe plus de place sur tablette : c'est l'élément
            // qu'on vient regarder, et la largeur disponible n'a d'intérêt que
            // si la hauteur suit.
            height: estTablette ? 460 : 300,
            child: _PlanApercu(plan: planEnTete!, onHotspot: onHotspot),
          )
        else if (messageAucunPlan != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 17, color: AppColors.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(messageAucunPlan!, style: const TextStyle(fontSize: 12.5, color: AppColors.info)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 18),
        if (vide)
          EmptyState(icon: Icons.layers_outlined, title: messageVide)
        else
          for (final s in sections) ...[
            Text(
              s.titre.toUpperCase(),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            // Colonnes derivees de la LARGEUR, hauteur posee explicitement.
            //
            // La version precedente basculait d'un coup — une colonne sous
            // 700 dp, quatre au-dessus — et laissait la hauteur de tuile se
            // deduire d'un rapport largeur/hauteur. Deux consequences :
            //
            //  - une tablette compacte de 600 dp en portrait recevait une
            //    seule colonne de tuiles etirees sur toute sa largeur ;
            //  - sur un telephone de 320 dp, le rapport 5,2 donnait une tuile
            //    de 55 px de haut pour un contenu qui en demande 76 : elle
            //    debordait par le bas de 21 px.
            //
            // Le contenu d'une tuile — pastille d'icone de 42, nom, et une
            // ligne de metadonnees — ne depend pas de la largeur. C'est donc
            // la HAUTEUR qu'on fixe, et les colonnes qu'on laisse varier.
            //
            // `shrinkWrap` : la grille vit dans la `ListView` de la page, elle
            // se dimensionne sur son contenu plutot que de defiler a part —
            // deux zones de defilement imbriquees rendraient le geste
            // imprevisible.
            LayoutBuilder(
              builder: (context, contraintes) => GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: colonnesAdaptatives(
                    contraintes.maxWidth,
                    min: 1,
                    max: 4,
                    largeurCible: 230,
                  ),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 12,
                  mainAxisExtent: _hauteurTuile(context),
                ),
                children: [
                  for (final e in s.elements) _Tuile(element: e, sansPlan: sansPlan),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
      ],
    );
  }
}

/// Hauteur d'une tuile de plan, taille de police systeme comprise.
///
/// La tuile empile horizontalement une pastille d'icone de 42 px et deux
/// lignes de texte. Aucun des deux ne depend de la largeur : figer un rapport
/// largeur/hauteur revenait a ecraser la tuile des que la colonne se
/// resserrait.
///
/// La part de texte suit l'echelle choisie par l'utilisateur dans les
/// reglages de son telephone — sans quoi un texte agrandi rouvrirait le meme
/// debordement.
double _hauteurTuile(BuildContext context) {
  // 24 px de marges verticales ; 52 px de contenu a l'echelle 1 — le nom
  // (14 pt) et sa ligne de metadonnees (11,5 pt), interlignes compris, avec
  // de quoi loger la pastille de 42 px.
  const marges = 24.0;
  const contenu = 52.0;
  return marges + MediaQuery.textScalerOf(context).scale(contenu);
}

class _Tuile extends StatelessWidget {
  final _Element element;
  final String sansPlan;

  const _Tuile({required this.element, required this.sansPlan});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: element.onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: AppColors.primary100, borderRadius: BorderRadius.circular(11)),
                child: Icon(element.icone, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      element.nom,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      element.plan == null
                          ? sansPlan
                          : [element.meta, 'v${element.plan!.version}'].where((t) => t.isNotEmpty).join(' · '),
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                    ),
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

/// Télécharge le fichier d'un plan.
///
/// Les octets transitent par le Dio de l'app, qui porte le jeton exigé par
/// `/uploads/*` : un lien direct confié au widget répondrait 401.
Future<Uint8List> _telecharger(String url) async {
  final reponse = await sl<Dio>().get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
  final data = reponse.data;
  if (data == null) throw Exception('Réponse vide');
  return Uint8List.fromList(data);
}

/// Aperçu d'un plan de niveau intermédiaire — sert surtout à porter ses zones
/// cliquables, qui font descendre d'un cran.
class _PlanApercu extends StatefulWidget {
  final Plan plan;
  final void Function(PlanHotspot) onHotspot;

  const _PlanApercu({required this.plan, required this.onHotspot});

  @override
  State<_PlanApercu> createState() => _PlanApercuState();
}

class _PlanApercuState extends State<_PlanApercu> {
  Uint8List? _octets;
  List<PlanHotspot> _hotspots = const [];
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void didUpdateWidget(_PlanApercu ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.plan.id != widget.plan.id) _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _octets = null;
      _erreur = null;
    });

    // Le DÉTAIL porte les zones cliquables ; la liste des plans ne les
    // contient pas toutes. Un échec ici ne doit pas masquer le plan :
    // il reste consultable, seule la descente par le plan est perdue.
    final detail = await sl<GetPlanDetail>()(widget.plan.id);
    if (!mounted) return;
    detail.fold((_) {}, (p) => setState(() => _hotspots = p.hotspots));

    if (_formatNonAffichable) {
      setState(() => _erreur = context.l10n.planViewerFormatNonSupporte);
      return;
    }

    try {
      final octets = await _telecharger(widget.plan.fichierUrl);
      if (mounted) setState(() => _octets = octets);
    } catch (_) {
      if (mounted) setState(() => _erreur = context.l10n.planViewerErreurChargement);
    }
  }

  /// DWG, IFC : rien à dessiner ici. Le message renvoyait vers l'espace web,
  /// qui ne sait pas davantage les afficher ; une application du téléphone,
  /// elle, le peut peut-être — le bouton la propose, comme la visionneuse.
  bool get _formatNonAffichable => !widget.plan.format.affichableSurMobile;

  Future<void> _ouvrirExterne() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final resultat = await sl<OuvertureFichier>().ouvrir(
      url: widget.plan.fichierUrl,
      // Le nom du plan n'a pas d'extension : sans celle du format, le système
      // ne sait pas à quelle application confier le fichier.
      nomFichier: '${widget.plan.nom}.${widget.plan.format.raw}',
    );
    if (!mounted) return;
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: AppColors.surface,
        child: _erreur != null
            ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _erreur!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                      ),
                      if (_formatNonAffichable) ...[
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: _ouvrirExterne,
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: Text(context.l10n.planOuvrirExterne),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            : _octets == null
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : PlanInteractif(
                    octets: _octets!,
                    hotspots: _hotspots,
                    onHotspotAppuye: widget.onHotspot,
                  ),
      ),
    );
  }
}

/// Le plan de l'appartement en plein écran, avec ses réserves et le mode
/// pointage — l'écran 5 puis 6 du guide client.
class _VuePlan extends StatefulWidget {
  final Plan plan;
  final LocalisationReserve localisation;
  final bool pointageAutorise;

  const _VuePlan({required this.plan, required this.localisation, required this.pointageAutorise});

  @override
  State<_VuePlan> createState() => _VuePlanState();
}

class _VuePlanState extends State<_VuePlan> {
  Uint8List? _octets;
  Plan? _detail;
  String? _erreur;
  bool _modePointage = false;
  String? _reserveActive;

  /// Le point que l'utilisateur vient de désigner, tant que le formulaire est
  /// ouvert.
  ///
  /// Sans lui, on remplissait le formulaire sans plus voir OÙ la réserve
  /// allait se poser — et la feuille masque justement la moitié du plan. Le
  /// repère provisoire répond à la seule question qui compte à cet instant :
  /// « est-ce bien là que j'ai visé ? »
  ({double x, double y})? _pointProvisoire;

  /// Peut-on poser une réserve sur CE plan ?
  ///
  /// Deux conditions, et non une seule : le rôle ([_VuePlan.pointageAutorise])
  /// ET un plan qui n'attend pas sa validation.
  ///
  /// Un plan joint à une demande de chantier encore en attente appartient à un
  /// chantier qui n'existe pas encore : le serveur refuse toute réserve posée
  /// dessus (`reserve.service.js:189` — « Ce plan attend une validation :
  /// aucune réserve ne peut y être posée »). Cet écran était le seul des trois
  /// à ignorer la condition — la visionneuse et l'explorateur la portaient
  /// déjà. On pouvait donc remplir tout le formulaire depuis la fiche
  /// chantier, pour un envoi refusé à l'arrivée.
  bool get _peutPointer =>
      widget.pointageAutorise && !widget.plan.enAttenteValidation;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void didUpdateWidget(_VuePlan ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.plan.id != widget.plan.id) _charger();
  }

  Future<void> _rechargerDetail() async {
    final detail = await sl<GetPlanDetail>()(widget.plan.id);
    if (!mounted) return;
    detail.fold((_) {}, (p) => setState(() => _detail = p));
  }

  Future<void> _charger() async {
    setState(() {
      _octets = null;
      _erreur = null;
    });
    await _rechargerDetail();

    // On télécharge TOUJOURS : c'est `PlanInteractif` qui décide, sur les
    // OCTETS reçus, s'il sait afficher le fichier. `plan.format` ne le dit
    // pas — il vaut 'pdf' par défaut côté serveur pour tout dépôt sans format
    // explicite, alors que png, jpg, jpeg et webp sont acceptés. Un plan
    // photographié sur le chantier était donc refusé ici, sur l'écran qui EST
    // la zone de travail.
    try {
      final octets = await _telecharger(widget.plan.fichierUrl);
      if (mounted) setState(() => _octets = octets);
    } catch (_) {
      if (mounted) setState(() => _erreur = context.l10n.planViewerErreurChargement);
    }
  }

  Future<void> _ouvrirFormulaire(double x, double y) async {
    // Posé AVANT l'ouverture : le repère doit être à l'écran au moment où la
    // feuille monte, pas après.
    setState(() => _pointProvisoire = (x: x, y: y));

    final cree = await showModalBottomSheet<Reserve>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NouvelleReserveSheet(
        localisation: widget.localisation,
        positionX: x,
        positionY: y,
      ),
    );
    if (!mounted) return;
    setState(() {
      _modePointage = false;
      // Retiré dans tous les cas : la réserve créée arrive par le
      // rechargement, avec sa vraie couleur et son identifiant. L'abandon,
      // lui, ne doit rien laisser derrière.
      _pointProvisoire = null;
    });
    // La réserve créée doit apparaître IMMÉDIATEMENT comme repère sur le plan :
    // sans ce rechargement, l'utilisateur ne voyait rien de son geste.
    if (cree != null) await _rechargerDetail();
  }

  /// Ouvre la fiche d'une réserve posée sur le plan.
  ///
  /// Ne montre QUE ce que le plan connaît d'elle — numéro, titre, statut,
  /// gravité. La description, la date et l'auteur ne sont pas chargés à ce
  /// niveau : les inventer serait pire que de ne pas les afficher, et le
  /// bouton mène à l'écran qui les porte.
  Future<void> _ouvrirFiche(PlanReserve reserve) async {
    await ouvrirFicheReserve(context, reserve);
    if (mounted) setState(() => _reserveActive = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            _erreur!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      );
    }
    if (_octets == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    final reserves = _detail?.reserves ?? const <PlanReserve>[];
    final marqueurs = [
      for (final r in reserves)
        if (r.position != null)
          MarqueurPlan(
            id: r.id,
            x: r.position!.x,
            y: r.position!.y,
            // Cahier technique § 14 : la pastille dit OÙ EN EST la réserve.
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

    return Column(
      children: [
        if (_modePointage)
          Container(
            width: double.infinity,
            color: AppColors.primary100,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.place_rounded, size: 16, color: AppColors.primaryDarker),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.planPointerAide,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDarker,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: Container(
            color: AppColors.surface,
            child: PlanInteractif(
              octets: _octets!,
              marqueurs: marqueurs,
              modePointage: _modePointage,
              // Nul quand le rôle ne peut pas poser de réserve : c'est ce qui
              // rend le plan inerte pour un lecteur, sans lui cacher les
              // repères déjà posés. Pour les autres, un appui sur une zone
              // libre ouvre le formulaire — sans mode à armer au préalable.
              onPointAppuye: _peutPointer ? _ouvrirFormulaire : null,
              // Un appui sur un repère CONSULTE, il ne crée pas. Les deux
              // gestes ne doivent jamais se confondre.
              //
              // Une feuille plutôt que l'écran complet : on regarde de quoi il
              // s'agit sans quitter le plan, et le contexte reste visible
              // derrière. L'écran complet reste à un bouton de là, pour tout
              // ce que la feuille ne porte pas.
              onMarqueurAppuye: (m) {
                // Le point provisoire n'est pas une réserve : il n'a pas de
                // fiche à ouvrir.
                if (m.id == _idPointProvisoire) return;
                setState(() => _reserveActive = m.id);
                final r = reserves.where((x) => x.id == m.id).firstOrNull;
                if (r != null) _ouvrirFiche(r);
              },
            ),
          ),
        ),
        _PanneauBas(
          reserves: reserves,
          modePointage: _modePointage,
          pointageAutorise: _peutPointer,
          onBasculerPointage: () => setState(() => _modePointage = !_modePointage),
        ),
      ],
    );
  }
}

/// Identifiant du repère provisoire — préfixé pour qu'aucune réserve réelle
/// ne puisse porter le même.
const _idPointProvisoire = '__point_provisoire__';

/// Bandeau bas — le bouton « Nouvelle réserve » et la liste des réserves déjà
/// posées sur ce plan.
class _PanneauBas extends StatelessWidget {
  final List<PlanReserve> reserves;
  final bool modePointage;
  final bool pointageAutorise;
  final VoidCallback onBasculerPointage;

  const _PanneauBas({
    required this.reserves,
    required this.modePointage,
    required this.pointageAutorise,
    required this.onBasculerPointage,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.34),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 18, offset: const Offset(0, -4)),
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
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      reserves.isEmpty
                          ? l10n.planViewerAucuneReserve
                          : l10n.planViewerReservesSurPlan(reserves.length),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (pointageAutorise)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: modePointage ? AppColors.neutral : AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: onBasculerPointage,
                      icon: Icon(modePointage ? Icons.close_rounded : Icons.add_rounded, size: 17),
                      label: Text(
                        modePointage ? l10n.planAnnulerPointage : l10n.planNouvelleReserve,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
                decoration: BoxDecoration(
                  color: couleurStatutReserve(reserve.statut).withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.place_rounded, size: 17, color: couleurStatutReserve(reserve.statut)),
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
                          : '#${reserve.numero} · x ${position.x.toStringAsFixed(0)} · y ${position.y.toStringAsFixed(0)}',
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


/// Les plans de DÉTAIL d'un plan, sous son image.
///
/// Un bandeau bas et non un écran à part : le plan reste visible au-dessus,
/// et descendre d'un cran ne fait pas perdre de vue d'où l'on vient. Seuls les
/// enfants DIRECTS y figurent — la navigation est progressive, c'est l'appui
/// suivant qui descendra encore.
class _SousPlans extends StatelessWidget {
  final String titre;
  final List<Plan> details;
  final int Function(Plan) compte;
  final void Function(Plan) onOuvrir;

  const _SousPlans({
    required this.titre,
    required this.details,
    required this.compte,
    required this.onOuvrir,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.30),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                // Le titre SEUL, sans compteur : la liste juste en dessous
                // montre déjà ce qu'elle contient, et l'écran est étroit.
                child: Text(
                  titre.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                itemCount: details.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final d = details[i];
                  return Material(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => onOuvrir(d),
                      child: Padding(
                        padding: const EdgeInsets.all(11),
                        child: Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: AppColors.primary100,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: const Icon(
                                Icons.layers_outlined,
                                size: 17,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    d.nom,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: AppColors.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    l10n.planNavNDetails(compte(d)),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.textMuted,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

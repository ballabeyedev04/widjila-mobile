import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../referentiel/domain/entities/code_niveau.dart';
import '../../../reserve/domain/entities/chantier_structure.dart';
import '../../../reserve/domain/usecases/get_chantier_structure.dart';
import '../../domain/entities/plan.dart';
import '../../domain/usecases/get_plans_chantier.dart';
import 'plan_vignette.dart';

/// Ce qui entoure un plan ouvert : sa place dans le chantier, et les plans
/// qu'on atteint depuis lui.
///
/// ## La demande du client
///
/// Ouvrir le plan GLOBAL doit montrer, sous le plan, les bâtiments du
/// chantier ; chaque bâtiment ses trois sections — SOUS-SOLS · ÉTAGES ·
/// TOITURE — et chaque niveau les plans de ses appartements, exactement comme
/// l'écran « Envoi de plans » les range. Ouvrir le plan d'un APPARTEMENT, qui
/// n'a plus rien sous lui, montre à la place où il se trouve : chantier,
/// bâtiment, niveau, et le détail du plan.
///
/// ## Pourquoi la structure, et pas les sous-plans
///
/// Les plans déposés par « Envoi de plans » ne sont PAS des sous-plans du plan
/// global : ils sont rattachés à un bâtiment, un niveau ou un appartement
/// (`plans.batiment_id`, `etage_id`, `zone_id`), sans parent. La descente par
/// `/plans/:id/sous-plans` ne les voyait donc jamais, et le serveur les
/// renvoyait tous À PLAT parmi les « plans globaux » (`parentId IS NULL`).
/// C'est la structure du chantier qui les ordonne — la même que celle de
/// l'écran de dépôt.

// ═══════════════════════════ PORTÉE D'UN PLAN ═══════════════════════════

/// Ce qu'un plan décrit dans le chantier.
enum PorteePlan {
  /// Aucun rattachement : le plan d'ensemble, sur lequel se repèrent les
  /// bâtiments.
  global,
  batiment,
  niveau,
  appartement,

  /// Plan de DÉTAIL d'un autre plan — atteint par ses sous-plans.
  detail,
}

/// La portée d'un plan, lue de ses rattachements.
///
/// Du plus précis au plus large : un plan d'appartement porte aussi son
/// niveau et son bâtiment (la chaîne remontée par le serveur), c'est la zone
/// qui le définit.
PorteePlan porteeDu(Plan plan) {
  if (plan.parentId != null) return PorteePlan.detail;
  if (plan.zone != null) return PorteePlan.appartement;
  if (plan.etage != null) return PorteePlan.niveau;
  if (plan.batiment != null) return PorteePlan.batiment;
  return PorteePlan.global;
}

/// Bâtiment, niveau et appartement que le plan PORTE, du plus large au plus
/// précis — vide pour un plan global.
List<String> lieuDuPlan(Plan plan) => [plan.batiment?.nom, plan.etage?.nom, plan.zone?.nom]
    .whereType<String>()
    .where((n) => n.isNotEmpty)
    .toList();

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
TypeNiveau sectionDuNiveau(EtageStructure niveau) {
  if (niveau.typeNiveau != TypeNiveau.etage) return niveau.typeNiveau;
  if (niveau.niveau < 0) return TypeNiveau.sousSol;
  if (_motsToiture.hasMatch(niveau.nom)) return TypeNiveau.toiture;
  return TypeNiveau.etage;
}

/// Une seule version par plan — la courante.
///
/// `GET /chantiers/:id/plans` renvoie TOUTES les révisions : sans ce tri, un
/// appartement dont le plan a été remplacé deux fois l'afficherait trois fois.
/// `is_current` d'abord, le plus grand numéro en repli — la règle du serveur
/// (`plan.service.js#_derniereVersion`).
///
/// La clé porte le RATTACHEMENT en plus du nom : le dépôt nomme un plan
/// d'après son fichier, et deux appartements peuvent très bien recevoir chacun
/// un « plan.pdf ». Regrouper sur le nom seul en ferait disparaître un.
///
/// Les plans de DÉTAIL sont écartés : ils héritent du rattachement de leur
/// parent et se retrouveraient sinon rangés comme lui. On les atteint par les
/// sous-plans du plan qui les porte.
List<Plan> plansCourants(List<Plan> tous) {
  final parCle = <String, Plan>{};
  for (final p in tous) {
    if (p.parentId != null) continue;
    final cle = '${p.nom}|${p.batiment?.id}|${p.etage?.id}|${p.zone?.id}';
    final actuel = parCle[cle];
    if (actuel == null || _prefere(p, actuel)) parCle[cle] = p;
  }
  return parCle.values.toList()
    ..sort((a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));
}

bool _prefere(Plan candidat, Plan actuel) {
  if (candidat.estVersionCourante != actuel.estVersionCourante) {
    return candidat.estVersionCourante;
  }
  return candidat.version > actuel.version;
}

// ═══════════════════════════ DONNÉES ═══════════════════════════

/// La structure d'un chantier et ses plans courants, rangés pour être
/// retrouvés par bâtiment, par niveau et par appartement.
class ContexteChantier {
  final ChantierStructure structure;

  /// Versions courantes, sans les plans de détail — voir [plansCourants].
  final List<Plan> plans;

  ContexteChantier({required this.structure, required List<Plan> plans})
      : plans = plansCourants(plans);

  List<BatimentStructure> get batiments => structure.batiments;

  /// Les plans qui décrivent le bâtiment LUI-MÊME — ni un de ses niveaux, ni
  /// un de ses appartements.
  List<Plan> plansDuBatiment(String batimentId) =>
      _filtrer(PorteePlan.batiment, (p) => p.batiment?.id == batimentId);

  /// Les plans du niveau lui-même — pas ceux de ses appartements, qui portent
  /// pourtant le même niveau par la chaîne zone → étage.
  List<Plan> plansDuNiveau(String etageId) =>
      _filtrer(PorteePlan.niveau, (p) => p.etage?.id == etageId);

  List<Plan> plansDeAppartement(String zoneId) =>
      _filtrer(PorteePlan.appartement, (p) => p.zone?.id == zoneId);

  /// Le niveau a-t-il au moins un plan, le sien ou celui d'un appartement ?
  ///
  /// C'est ce que dit la pastille verte de l'écran de dépôt : on reconnaît
  /// d'un coup d'œil un niveau encore vide.
  bool niveauAUnPlan(EtageStructure niveau) =>
      plansDuNiveau(niveau.id).isNotEmpty ||
      niveau.zones.any((z) => plansDeAppartement(z.id).isNotEmpty);

  BatimentStructure? batiment(String? id) {
    if (id == null) return null;
    for (final b in batiments) {
      if (b.id == id) return b;
    }
    return null;
  }

  EtageStructure? niveau(String? id) {
    if (id == null) return null;
    for (final b in batiments) {
      for (final e in b.etages) {
        if (e.id == id) return e;
      }
    }
    return null;
  }

  List<Plan> _filtrer(PorteePlan portee, bool Function(Plan) garder) => [
        for (final p in plans)
          if (porteeDu(p) == portee && garder(p)) p,
      ];
}

/// L'état du chargement de ce contexte — il vit à côté du plan, pas avec lui.
///
/// Un échec ICI n'est jamais bloquant : le plan reste consultable et on peut
/// toujours y poser une réserve. Seul le panneau des bâtiments le dit, avec
/// de quoi réessayer.
class EtatContexte {
  final ContexteChantier? contexte;
  final String? erreur;

  const EtatContexte.enChargement()
      : contexte = null,
        erreur = null;

  const EtatContexte.pret(ContexteChantier this.contexte) : erreur = null;

  const EtatContexte.echec(String this.erreur) : contexte = null;

  bool get enChargement => contexte == null && erreur == null;
}

/// Charge la structure du chantier et ses plans, EN PARALLÈLE : ni l'un ni
/// l'autre ne dépend de l'autre, et les enchaîner doublerait l'attente sur un
/// réseau de chantier.
Future<EtatContexte> chargerContexteChantier(String chantierId) async {
  final structureEnCours = sl<GetChantierStructure>()(chantierId);
  final plansEnCours = sl<GetPlansChantier>()(chantierId);
  final structure = await structureEnCours;
  final plans = await plansEnCours;

  return structure.fold(
    (echec) => EtatContexte.echec(echec.errorMessage),
    (s) => plans.fold(
      (echec) => EtatContexte.echec(echec.errorMessage),
      (liste) => EtatContexte.pret(ContexteChantier(structure: s, plans: liste)),
    ),
  );
}

/// Ce qui est déplié dans l'arborescence — gardé par l'ÉCRAN, pas par le
/// panneau.
///
/// On déplie « Bâtiment A », puis « R+1 », on ouvre le plan de A001, on
/// revient : l'arborescence doit être restée ouverte là où on l'a laissée.
/// Le panneau, lui, est reconstruit à chaque plan ouvert et oublierait tout.
class EtatDepliage {
  final Set<String> _deplies = {};

  bool estDeplie(String cle) => _deplies.contains(cle);

  void marquer(String cle, bool deplie) =>
      deplie ? _deplies.add(cle) : _deplies.remove(cle);
}

// ═══════════════════════════ PANNEAU ═══════════════════════════

/// Le contenu du panneau bas qui dépend de la PORTÉE du plan ouvert :
///
///  - plan global  → les bâtiments, dépliables jusqu'aux appartements ;
///  - bâtiment     → sa localisation, puis ses niveaux ;
///  - niveau       → sa localisation, puis ses appartements ;
///  - appartement  → sa localisation et le détail du plan — il n'y a plus
///    rien en dessous ;
///  - détail       → sa localisation, héritée de son parent.
class PanneauContextePlan extends StatelessWidget {
  final Plan plan;
  final String? chantierNom;
  final EtatContexte etat;
  final VoidCallback onReessayer;
  final void Function(Plan) onOuvrirPlan;
  final EtatDepliage depliage;

  const PanneauContextePlan({
    super.key,
    required this.plan,
    required this.chantierNom,
    required this.etat,
    required this.onReessayer,
    required this.onOuvrirPlan,
    required this.depliage,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final portee = porteeDu(plan);
    final contexte = etat.contexte;

    if (portee == PorteePlan.global) {
      return ArborescenceBatiments(
        etat: etat,
        onReessayer: onReessayer,
        onOuvrirPlan: onOuvrirPlan,
        depliage: depliage,
      );
    }

    // Les autres plans du MÊME endroit — un appartement peut en avoir
    // plusieurs (architecte, électricité, plomberie…), et passer de l'un à
    // l'autre ne doit pas obliger à remonter au plan global.
    final memeEndroit = switch (portee) {
      PorteePlan.batiment => contexte?.plansDuBatiment(plan.batiment!.id),
      PorteePlan.niveau => contexte?.plansDuNiveau(plan.etage!.id),
      PorteePlan.appartement => contexte?.plansDeAppartement(plan.zone!.id),
      _ => null,
    };
    final autres = [
      for (final p in memeEndroit ?? const <Plan>[])
        if (p.id != plan.id) p,
    ];

    Widget? suite;
    if (portee == PorteePlan.batiment || portee == PorteePlan.niveau) {
      if (etat.enChargement) {
        suite = const _LigneChargement();
      } else if (etat.erreur != null) {
        suite = _LigneErreur(onReessayer: onReessayer);
      } else if (portee == PorteePlan.batiment) {
        final batiment = contexte!.batiment(plan.batiment!.id);
        if (batiment != null) {
          suite = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final type in TypeNiveau.values)
                _SectionNiveaux(
                  batiment: batiment,
                  type: type,
                  contexte: contexte,
                  onOuvrirPlan: onOuvrirPlan,
                  depliage: depliage,
                ),
            ],
          );
        }
      } else {
        final niveau = contexte!.niveau(plan.etage!.id);
        if (niveau != null) {
          suite = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TitreContexte(l10n.depotAppartementsTitre, compte: niveau.zones.length),
              const SizedBox(height: 8),
              _Appartements(niveau: niveau, contexte: contexte, onOuvrirPlan: onOuvrirPlan),
            ],
          );
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        FicheLocalisationPlan(plan: plan, chantierNom: chantierNom, contexte: contexte),
        if (autres.isNotEmpty) ...[
          const SizedBox(height: 14),
          TitreContexte(l10n.planCtxAutresPlans, compte: autres.length),
          const SizedBox(height: 4),
          for (final p in autres) _LignePlan(plan: p, onOuvrir: onOuvrirPlan),
        ],
        if (suite != null) ...[const SizedBox(height: 14), suite],
      ],
    );
  }
}

/// Les bâtiments du chantier, chacun dépliable sur ses sections, ses niveaux
/// et leurs appartements — la présentation de « Envoi de plans », en
/// consultation.
class ArborescenceBatiments extends StatelessWidget {
  final EtatContexte etat;
  final VoidCallback onReessayer;
  final void Function(Plan) onOuvrirPlan;
  final EtatDepliage depliage;

  const ArborescenceBatiments({
    super.key,
    required this.etat,
    required this.onReessayer,
    required this.onOuvrirPlan,
    required this.depliage,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final contexte = etat.contexte;

    final Widget contenu;
    if (etat.enChargement) {
      contenu = const _LigneChargement();
    } else if (etat.erreur != null) {
      contenu = _LigneErreur(onReessayer: onReessayer);
    } else if (contexte!.batiments.isEmpty) {
      contenu = Text(
        l10n.planNavAucunBatiment,
        style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
      );
    } else {
      contenu = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final b in contexte.batiments)
            _CarteBatiment(
              batiment: b,
              contexte: contexte,
              onOuvrirPlan: onOuvrirPlan,
              depliage: depliage,
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TitreContexte(l10n.planNavBatiments, compte: contexte?.batiments.length),
        const SizedBox(height: 8),
        contenu,
      ],
    );
  }
}

/// Un bâtiment : ses plans propres, puis SOUS-SOLS · ÉTAGES · TOITURE.
class _CarteBatiment extends StatelessWidget {
  final BatimentStructure batiment;
  final ContexteChantier contexte;
  final void Function(Plan) onOuvrirPlan;
  final EtatDepliage depliage;

  const _CarteBatiment({
    required this.batiment,
    required this.contexte,
    required this.onOuvrirPlan,
    required this.depliage,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cle = 'batiment:${batiment.id}';
    final plansBatiment = contexte.plansDuBatiment(batiment.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Le trait de séparation par défaut d'`ExpansionTile` couperait la
        // carte en deux à chaque niveau déplié.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey(cle),
          initiallyExpanded: depliage.estDeplie(cle),
          onExpansionChanged: (v) => depliage.marquer(cle, v),
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 8, 10),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          leading: const Icon(Icons.apartment_outlined, color: AppColors.primary),
          title: Text(
            batiment.nom,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          subtitle: Text(
            l10n.planNavNEtages(batiment.etages.length),
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          children: [
            if (plansBatiment.isNotEmpty) ...[
              _Etiquette(l10n.planCtxPlanBatiment),
              for (final p in plansBatiment) _LignePlan(plan: p, onOuvrir: onOuvrirPlan),
              const SizedBox(height: 4),
            ],
            for (final type in TypeNiveau.values)
              _SectionNiveaux(
                batiment: batiment,
                type: type,
                contexte: contexte,
                onOuvrirPlan: onOuvrirPlan,
                depliage: depliage,
              ),
          ],
        ),
      ),
    );
  }
}

/// Une des trois sections d'un bâtiment — SOUS-SOLS, ÉTAGES ou TOITURE.
///
/// Les trois sont TOUJOURS présentes, vides comprises, comme sur l'écran de
/// dépôt : l'utilisateur retrouve la même carte d'un écran à l'autre.
class _SectionNiveaux extends StatelessWidget {
  final BatimentStructure batiment;
  final TypeNiveau type;
  final ContexteChantier contexte;
  final void Function(Plan) onOuvrirPlan;
  final EtatDepliage depliage;

  const _SectionNiveaux({
    required this.batiment,
    required this.type,
    required this.contexte,
    required this.onOuvrirPlan,
    required this.depliage,
  });

  String _titre(BuildContext context) {
    final l10n = context.l10n;
    return switch (type) {
      TypeNiveau.sousSol => l10n.depotSectionSousSols,
      TypeNiveau.etage => l10n.depotSectionEtages,
      TypeNiveau.toiture => l10n.depotSectionToiture,
    };
  }

  @override
  Widget build(BuildContext context) {
    // Triés par cote : SS2 avant SS1, R+1 avant R+2 — l'ordre de saisie
    // n'a aucune raison d'être celui du bâtiment.
    final niveaux = [
      for (final e in batiment.etages)
        if (sectionDuNiveau(e) == type) e,
    ]..sort((a, b) => a.niveau.compareTo(b.niveau));

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Etiquette(_titre(context)),
          if (niveaux.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                context.l10n.depotAucunNiveau,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
            )
          else
            for (final n in niveaux)
              _TuileNiveau(
                niveau: n,
                contexte: contexte,
                onOuvrirPlan: onOuvrirPlan,
                depliage: depliage,
              ),
        ],
      ),
    );
  }
}

/// Un niveau, dépliable sur son plan et ses appartements.
class _TuileNiveau extends StatelessWidget {
  final EtageStructure niveau;
  final ContexteChantier contexte;
  final void Function(Plan) onOuvrirPlan;
  final EtatDepliage depliage;

  const _TuileNiveau({
    required this.niveau,
    required this.contexte,
    required this.onOuvrirPlan,
    required this.depliage,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cle = 'niveau:${niveau.id}';
    final aUnPlan = contexte.niveauAUnPlan(niveau);
    final plansNiveau = contexte.plansDuNiveau(niveau.id);

    return ExpansionTile(
      key: ValueKey(cle),
      initiallyExpanded: depliage.estDeplie(cle),
      onExpansionChanged: (v) => depliage.marquer(cle, v),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 4, bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      shape: const Border(),
      collapsedShape: const Border(),
      leading: Icon(
        aUnPlan ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
        size: 17,
        color: aUnPlan ? AppColors.success : AppColors.textMuted,
      ),
      title: Text(
        niveau.nom,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
      ),
      subtitle: Text(
        l10n.depotAppartementsCompte(niveau.zones.length),
        style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
      ),
      children: [
        if (plansNiveau.isNotEmpty) ...[
          _Etiquette(l10n.planCtxPlanNiveau),
          for (final p in plansNiveau) _LignePlan(plan: p, onOuvrir: onOuvrirPlan),
          const SizedBox(height: 4),
        ],
        _Etiquette(l10n.depotAppartementsTitre),
        _Appartements(niveau: niveau, contexte: contexte, onOuvrirPlan: onOuvrirPlan),
      ],
    );
  }
}

/// Les appartements d'un niveau, et les plans de chacun.
class _Appartements extends StatelessWidget {
  final EtageStructure niveau;
  final ContexteChantier contexte;
  final void Function(Plan) onOuvrirPlan;

  const _Appartements({
    required this.niveau,
    required this.contexte,
    required this.onOuvrirPlan,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (niveau.zones.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          l10n.planNavAucuneZone,
          style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final z in niveau.zones)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.meeting_room_outlined, size: 17, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        z.nom,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                ..._plans(context, z),
              ],
            ),
          ),
      ],
    );
  }

  List<Widget> _plans(BuildContext context, ZoneStructure zone) {
    final plans = contexte.plansDeAppartement(zone.id);
    if (plans.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(left: 25, top: 2, bottom: 2),
          child: Text(
            context.l10n.depotPlanAucun,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ),
      ];
    }
    return [for (final p in plans) _LignePlan(plan: p, onOuvrir: onOuvrirPlan)];
  }
}

/// Ce qu'un plan porte comme réserves : le total, puis ce qui reste à lever —
/// « 5 réserves · 2 à traiter ». Nul quand le plan n'en porte aucune.
///
/// [urgent] est vrai quand des réserves restent à traiter : c'est la partie
/// que l'arborescence met en rouge, comme les repères sur le plan.
///
/// Un serveur qui ne sert pas encore `nombre_reserves_a_traiter` ne donne que
/// le total : on n'invente pas un « toutes levées » qui serait peut-être faux.
({String total, String? suite, bool urgent})? resumeReserves(BuildContext context, Plan plan) {
  if (plan.nombreReserves <= 0) return null;
  final l10n = context.l10n;
  final aTraiter = plan.nombreReservesATraiter;
  return (
    total: l10n.planExplorerNReserves(plan.nombreReserves),
    suite: aTraiter == null
        ? null
        : (aTraiter > 0 ? l10n.planCtxNATraiter(aTraiter) : l10n.planCtxToutesLevees),
    urgent: aTraiter != null && aTraiter > 0,
  );
}

/// Un plan de l'arborescence : sa vignette, son nom, et l'appui qui l'ouvre.
class _LignePlan extends StatelessWidget {
  final Plan plan;
  final void Function(Plan) onOuvrir;

  const _LignePlan({required this.plan, required this.onOuvrir});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final reserves = resumeReserves(context, plan);
    // (texte, en rouge ?) — seul « N à traiter » est mis en évidence.
    final morceaux = <(String, bool)>[
      if (plan.enAttenteValidation) (l10n.planCtxEnAttente, false),
      if (reserves != null) (reserves.total, false),
      if (reserves?.suite != null) (reserves!.suite!, reserves.urgent),
      if (plan.version > 1) ('v${plan.version}', false),
      if (plan.typePlan != null && plan.typePlan!.isNotEmpty) (plan.typePlan!, false),
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onOuvrir(plan),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
          child: Row(
            children: [
              // La PREMIÈRE PAGE du document : on reconnaît un plan sans
              // l'ouvrir.
              PlanVignette(
                plan: plan,
                icone: Icons.description_outlined,
                couleur: AppColors.primary,
                taille: 44,
                largeur: 44,
                rayon: 10,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      plan.nom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (morceaux.isNotEmpty)
                      Text.rich(
                        TextSpan(
                          children: [
                            for (var i = 0; i < morceaux.length; i++) ...[
                              if (i > 0) const TextSpan(text: ' · '),
                              TextSpan(
                                text: morceaux[i].$1,
                                style: morceaux[i].$2
                                    ? const TextStyle(
                                        color: AppColors.danger,
                                        fontWeight: FontWeight.w700,
                                      )
                                    : null,
                              ),
                            ],
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: plan.enAttenteValidation ? AppColors.warning : AppColors.textMuted,
                        ),
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

// ═══════════════════════════ FICHE DE LOCALISATION ═══════════════════════════

/// Où se trouve ce plan, et ce qu'on sait de lui.
///
/// Lu d'abord sur le PLAN lui-même — le serveur y joint bâtiment, niveau et
/// appartement — pour que la fiche s'affiche même si la structure du chantier
/// n'a pas pu être chargée. La structure, quand elle est là, ne fait
/// qu'enrichir : la section du niveau et sa description.
class FicheLocalisationPlan extends StatelessWidget {
  final Plan plan;
  final String? chantierNom;
  final ContexteChantier? contexte;

  const FicheLocalisationPlan({
    super.key,
    required this.plan,
    required this.chantierNom,
    this.contexte,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final langue = Localizations.localeOf(context).toString();
    String date(DateTime d) => DateFormat.yMd(langue).format(d.toLocal());

    final chantier = (chantierNom?.isNotEmpty ?? false) ? chantierNom : plan.chantierNom;
    final niveau = contexte?.niveau(plan.etage?.id);
    final description = niveau?.description?.trim();

    final fichier = plan.fichierNom;
    final lieu = <Widget>[
      if (chantier != null && chantier.isNotEmpty)
        _Info(icone: Icons.location_city_outlined, libelle: l10n.planCtxChantier, valeur: chantier),
      if (plan.batiment != null)
        _Info(icone: Icons.apartment_outlined, libelle: l10n.planCtxBatiment, valeur: plan.batiment!.nom),
      if (plan.etage != null)
        _Info(
          icone: Icons.layers_outlined,
          libelle: l10n.planCtxNiveau,
          valeur: [
            plan.etage!.nom,
            if (niveau != null) _libelleSection(context, sectionDuNiveau(niveau)),
          ].join(' · '),
          complement: (description != null && description.isNotEmpty) ? description : null,
        ),
      if (plan.zone != null)
        _Info(icone: Icons.meeting_room_outlined, libelle: l10n.planCtxAppartement, valeur: plan.zone!.nom),
    ];

    final details = <Widget>[
      if (fichier != null && fichier.isNotEmpty && fichier != plan.nom)
        _Info(icone: Icons.description_outlined, libelle: l10n.planCtxFichier, valeur: fichier),
      _Info(
        icone: Icons.tag_rounded,
        libelle: l10n.planCtxVersion,
        valeur: '${_formatLisible(plan)} · v${plan.version}',
      ),
      if (plan.typePlan != null && plan.typePlan!.isNotEmpty)
        _Info(icone: Icons.category_outlined, libelle: l10n.planCtxType, valeur: plan.typePlan!),
      if (plan.datePlan != null)
        _Info(icone: Icons.event_outlined, libelle: l10n.planCtxDatePlan, valeur: date(plan.datePlan!)),
      if (plan.createdAt != null)
        _Info(icone: Icons.cloud_upload_outlined, libelle: l10n.planCtxDepose, valeur: date(plan.createdAt!)),
      if (plan.nombrePages != null && plan.nombrePages! > 1)
        _Info(icone: Icons.auto_stories_outlined, libelle: l10n.planCtxPages, valeur: '${plan.nombrePages}'),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lieu.isNotEmpty) ...[
            _Etiquette(l10n.planCtxLocalisation),
            ...lieu,
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(height: 1, color: AppColors.border),
            ),
          ],
          _Etiquette(l10n.planCtxDetails),
          ...details,
          if (plan.enAttenteValidation)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(
                l10n.planExplorerEnAttenteValidation,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.warning,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _libelleSection(BuildContext context, TypeNiveau type) {
    final l10n = context.l10n;
    return switch (type) {
      TypeNiveau.sousSol => l10n.planNavSousSols,
      TypeNiveau.etage => l10n.planNavEtages,
      TypeNiveau.toiture => l10n.planNavToiture,
    };
  }
}

/// Le format RÉEL du fichier, lu de son extension.
///
/// `plan.format` ne le dit pas : le serveur étiquette 'pdf' tout dépôt reçu
/// sans format explicite, photos comprises. Annoncer « PDF » pour un JPEG
/// serait faux ; l'extension du fichier déposé, elle, ne ment pas sur ce point.
String _formatLisible(Plan plan) {
  final nom = (plan.fichierNom?.isNotEmpty ?? false) ? plan.fichierNom! : plan.nom;
  final point = nom.lastIndexOf('.');
  if (point > 0 && point < nom.length - 1) {
    final extension = nom.substring(point + 1);
    if (extension.length <= 5) return extension.toUpperCase();
  }
  return plan.format.label;
}

/// Une ligne de la fiche : icône, libellé au-dessus, valeur en gras.
///
/// Libellé AU-DESSUS plutôt qu'à gauche : sur un téléphone de 320 dp, une
/// colonne de libellés traduits (« Hochgeladen am ») ne laisserait plus de
/// place à la valeur.
class _Info extends StatelessWidget {
  final IconData icone;
  final String libelle;
  final String valeur;
  final String? complement;

  const _Info({
    required this.icone,
    required this.libelle,
    required this.valeur,
    this.complement,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icone, size: 17, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  libelle,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
                Text(
                  valeur,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (complement != null)
                  Text(
                    complement!,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════ PETITS ÉLÉMENTS ═══════════════════════════

/// La poignée du panneau bas — un appui, ou un glissement, l'agrandit ou le
/// réduit.
///
/// Le panneau porte désormais toute l'arborescence du chantier : à un tiers
/// de l'écran, un bâtiment déplié jusqu'à ses appartements ne tient plus. La
/// poignée était déjà dessinée mais ne faisait rien — elle promettait un
/// geste qu'elle ne tenait pas.
///
/// 24 points de haut, exactement la place de l'ancienne barre et de ses
/// marges : les calculs de hauteur des panneaux ne changent pas.
class PoigneePanneau extends StatelessWidget {
  final bool agrandi;
  final VoidCallback onBasculer;

  const PoigneePanneau({super.key, required this.agrandi, required this.onBasculer});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label: agrandi ? l10n.planCtxReduire : l10n.planCtxAgrandir,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onBasculer,
        onVerticalDragEnd: (d) {
          final vitesse = d.primaryVelocity ?? 0;
          // Vers le haut agrandit, vers le bas réduit ; un glissement dans le
          // sens de l'état courant ne fait rien.
          if ((vitesse < -120 && !agrandi) || (vitesse > 120 && agrandi)) onBasculer();
        },
        child: SizedBox(
          width: double.infinity,
          height: 24,
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Titre de section du panneau — MAJUSCULES espacées, compteur facultatif.
class TitreContexte extends StatelessWidget {
  final String texte;
  final int? compte;

  const TitreContexte(this.texte, {super.key, this.compte});

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

/// Sous-titre à l'intérieur d'une carte — plus discret que [TitreContexte].
class _Etiquette extends StatelessWidget {
  final String texte;
  const _Etiquette(this.texte);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 4),
        child: Text(
          texte.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: AppColors.textSecondary,
          ),
        ),
      );
}

class _LigneChargement extends StatelessWidget {
  const _LigneChargement();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
          ),
        ),
      );
}

class _LigneErreur extends StatelessWidget {
  final VoidCallback onReessayer;
  const _LigneErreur({required this.onReessayer});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        const Icon(Icons.error_outline_rounded, size: 17, color: AppColors.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.planCtxErreur,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ),
        TextButton(onPressed: onReessayer, child: Text(l10n.commonRetry)),
      ],
    );
  }
}

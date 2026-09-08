import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../reserve/domain/entities/reserve.dart';
import '../../../reserve/presentation/widgets/reserve_statut_badge.dart';
import '../../domain/entities/plan.dart';

/// Couleur d'une PASTILLE de réserve sur un plan — d'après son STATUT.
///
/// ## Ce que le cahier technique demande (§ 14)
///
/// ```
/// À traiter   : rouge
/// En cours    : orange
/// À contrôler : bleu
/// Levée       : vert
/// Clôturée    : gris/noir
/// ```
///
/// Les pastilles étaient colorées par GRAVITÉ. C'est une autre information, et
/// pas celle qu'on cherche devant un plan : la question posée en arrivant sur
/// un chantier n'est pas « laquelle est grave ? » mais « laquelle reste à
/// faire ? ». Une réserve critique déjà levée s'affichait en rouge vif, au
/// milieu de celles qui attendent encore — exactement l'inverse du signal
/// utile.
///
/// ## Le rattachement des onze statuts aux cinq couleurs
///
/// Le produit compte plus d'états que le cahier n'en nomme ; chacun rejoint la
/// couleur de l'étape à laquelle il appartient réellement :
///
///  - ROUGE, « à traiter » — tout ce qui attend une action de l'entreprise :
///    créée, affectée, rouverte, refusée (le correctif a été rejeté, il est
///    donc à refaire) et en retard ;
///  - ORANGE, « en cours » — prise en charge et en cours ;
///  - BLEU, « à contrôler » — corrigée et à vérifier : l'entreprise a fini,
///    quelqu'un doit passer voir ;
///  - VERT, « levée » — validée ;
///  - GRIS, « clôturée ».
Color couleurStatutReserve(ReserveStatut statut) => switch (statut) {
      ReserveStatut.creee ||
      ReserveStatut.affectee ||
      ReserveStatut.rouverte ||
      ReserveStatut.refusee ||
      ReserveStatut.enRetard =>
        AppColors.danger,
      ReserveStatut.priseEnCharge || ReserveStatut.enCours => AppColors.warning,
      ReserveStatut.corrigee || ReserveStatut.aVerifier => AppColors.info,
      ReserveStatut.validee => AppColors.success,
      ReserveStatut.cloturee => AppColors.neutral,
    };

/// Couleur d'une GRAVITÉ — pour l'étiquette qui l'annonce, jamais pour une
/// pastille.
///
/// Les deux échelles cohabitent volontairement : le plan répond « où en
/// est-on ? » (statut), la fiche précise « à quel point est-ce sérieux ? »
/// (gravité). Les confondre revenait à n'en montrer qu'une.
Color couleurSeverite(ReserveSeverite s) => switch (s) {
      ReserveSeverite.faible => AppColors.info,
      ReserveSeverite.moyenne => AppColors.warning,
      ReserveSeverite.haute => AppColors.danger,
      ReserveSeverite.critique => AppColors.danger,
    };

/// Ouvre la fiche d'une réserve posée sur un plan.
///
/// Feuille basse plutôt qu'écran plein : le plan reste visible derrière, et
/// refermer ramène exactement où l'on était — c'est ce qu'on attend quand on
/// appuie un repère pour savoir ce que c'est. L'animation depuis le bas vient
/// de `showModalBottomSheet` lui-même.
Future<void> ouvrirFicheReserve(BuildContext context, PlanReserve reserve) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    // La description peut être longue : la feuille doit pouvoir dépasser la
    // moitié de l'écran plutôt que de tronquer l'observation.
    isScrollControlled: true,
    builder: (_) => FicheReserveSheet(reserve: reserve),
  );
}

/// Ce que le plan sait d'une réserve : numéro, titre, observation, statut,
/// gravité, auteur, dates de création, de modification et d'échéance, et sa
/// position sur le plan.
///
/// Ce sont les champs que le modèle porte DÉJÀ et que le détail du plan sert
/// en une requête. Rien n'est inventé : chaque ligne disparaît quand sa donnée
/// est absente. L'entreprise concernée, l'historique et les photos ne sont pas
/// chargés à ce niveau — le bouton du bas mène à l'écran qui les porte.
class FicheReserveSheet extends StatelessWidget {
  final PlanReserve reserve;

  const FicheReserveSheet({super.key, required this.reserve});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // La MÊME couleur que le repère appuyé : une pastille rouge qui ouvre une
    // fiche orange ferait douter d'avoir visé le bon point.
    final couleur = couleurStatutReserve(reserve.statut);
    final description = reserve.description?.trim() ?? '';

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poignée : elle dit que la feuille se referme en la tirant, un
            // geste qu'aucun libellé n'a besoin d'expliquer.
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.only(top: 5, right: 10),
                          decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (reserve.numero.isNotEmpty)
                                Text(
                                  reserve.numero,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              Text(
                                reserve.titre.isEmpty ? l10n.reserveDetailTitreDefaut : reserve.titre,
                                style: const TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ReserveStatutBadge(statut: reserve.statut),
                        _Etiquette(
                          texte: '${l10n.planFicheSeverite} · ${reserve.severite.label(l10n)}',
                          // La GRAVITÉ, et donc sa propre couleur : l'étiquette
                          // dirait deux fois le statut si elle reprenait la
                          // sienne.
                          couleur: couleurSeverite(reserve.severite),
                        ),
                        // La date de création a sa propre ligne plus bas :
                        // en étiquette ici, elle ferait doublon.

                      ],
                    ),

                    // L'observation saisie à la création — la raison d'être de
                    // la réserve. Elle manquait : la fiche n'affichait qu'un
                    // titre et un badge, et il fallait quitter le plan pour
                    // lire ce qui avait été constaté.
                    const SizedBox(height: 16),
                    Text(
                      l10n.planFicheObservation,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description.isEmpty ? l10n.planFicheSansObservation : description,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: description.isEmpty ? AppColors.textMuted : AppColors.textSecondary,
                        fontStyle: description.isEmpty ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),

                    // Les champs métier RÉELLEMENT disponibles, et rien
                    // d'autre : chaque ligne disparaît quand sa donnée est
                    // absente, plutôt que d'afficher un tiret qui n'apprend
                    // rien. Une réserve sans échéance est le cas courant.
                    const SizedBox(height: 16),
                    if (reserve.createurNom != null)
                      _Ligne(
                        icone: Icons.person_outline_rounded,
                        libelle: l10n.planFicheCreePar,
                        valeur: reserve.createurNom!,
                      ),
                    if (reserve.createdAt != null)
                      _Ligne(
                        icone: Icons.event_available_outlined,
                        libelle: l10n.planFicheCreeLe,
                        valeur: _dateHeure(context, reserve.createdAt!),
                      ),
                    // La modification n'est affichée que si elle DIFFÈRE de la
                    // création : sur une réserve qu'on vient de poser, les deux
                    // dates sont identiques et la seconde ligne ne dirait rien.
                    if (reserve.updatedAt != null &&
                        reserve.createdAt != null &&
                        reserve.updatedAt!.difference(reserve.createdAt!).inMinutes.abs() >= 1)
                      _Ligne(
                        icone: Icons.update_rounded,
                        libelle: l10n.planFicheModifieLe,
                        valeur: _dateHeure(context, reserve.updatedAt!),
                      ),
                    if (reserve.dateLimite != null)
                      _Ligne(
                        icone: Icons.schedule_rounded,
                        libelle: l10n.reserveDetailEcheance,
                        valeur: _dateSeule(context, reserve.dateLimite!),
                      ),
                    if (reserve.position != null)
                      _Ligne(
                        icone: Icons.place_outlined,
                        libelle: l10n.reserveNouvLocalisation,
                        valeur: 'x ${reserve.position!.x.toStringAsFixed(1)} · '
                            'y ${reserve.position!.y.toStringAsFixed(1)}',
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/reserves/${reserve.id}');
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(
                  l10n.planFicheOuvrir,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Date et heure dans la langue de l'utilisateur.
String _dateHeure(BuildContext context, DateTime d) {
  final langue = Localizations.localeOf(context).toString();
  return '${DateFormat.yMd(langue).format(d)} · ${DateFormat.Hm(langue).format(d)}';
}

/// Date seule — une échéance se compte en jours, pas en minutes.
String _dateSeule(BuildContext context, DateTime d) =>
    DateFormat.yMd(Localizations.localeOf(context).toString()).format(d);

/// Une ligne « icône · libellé · valeur » de la fiche.
///
/// Le libellé à gauche, la valeur à droite : sur un écran étroit, l'œil
/// descend la colonne des libellés pour trouver ce qu'il cherche, sans lire
/// les valeurs au passage.
class _Ligne extends StatelessWidget {
  final IconData icone;
  final String libelle;
  final String valeur;

  const _Ligne({required this.icone, required this.libelle, required this.valeur});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, size: 15, color: AppColors.textMuted),
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
              child: Text(
                libelle,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
            Expanded(
              child: Text(
                valeur,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Une étiquette discrète — la gravité, la date, à côté du badge de statut.
class _Etiquette extends StatelessWidget {
  final String texte;
  final Color couleur;

  const _Etiquette({required this.texte, required this.couleur});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          texte,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: couleur),
        ),
      );
}

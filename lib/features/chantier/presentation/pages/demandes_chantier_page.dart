import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/loading_list.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../../core/config/user_role.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/chantier.dart';
import '../../domain/repositories/chantier_repository.dart';
import '../cubit/demandes_chantier_cubit.dart';
import '../widgets/chantier_statut_badge.dart';

/// Rôles qui tranchent une demande — miroir de `GESTION` côté serveur.
///
/// Sert uniquement à décider si l'onglet « À valider » est affiché : un
/// utilisateur qui ne valide rien n'y verrait jamais que du vide. Le serveur
/// reste seul juge de qui peut réellement valider.
const _rolesValideurs = {UserRole.chefProjet, UserRole.maitreOuvrage};

/// Suivi des demandes de création de chantier.
///
/// Un chantier créé depuis l'application ne naît pas utilisable : il dépose
/// une demande. Cet écran en donne l'état, et surtout le MOTIF d'un refus —
/// sans lui, un refus n'apprend rien de ce qu'il faut reprendre.
///
/// Corriger la demande la renvoie automatiquement à la validation : c'est le
/// serveur qui s'en charge, il n'y a donc pas de bouton « renvoyer ».
class DemandesChantierPage extends StatelessWidget {
  const DemandesChantierPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<DemandesChantierCubit>()..charger(),
      child: const _Vue(),
    );
  }
}

class _Vue extends StatelessWidget {
  const _Vue();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final role = context.select((AuthBloc b) => b.state.utilisateur?.role);
    final peutValider = _rolesValideurs.contains(role);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.demandesTitre),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: BlocBuilder<DemandesChantierCubit, DemandesChantierState>(
        builder: (context, etat) {
          final cubit = context.read<DemandesChantierCubit>();

          return Column(
            children: [
              // Un seul onglet visible ne mérite pas de barre d'onglets :
              // celui qui ne valide rien n'a qu'une vue, et une bascule sans
              // alternative se lit comme un réglage cassé.
              if (peutValider)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SegmentedButton<VueDemandes>(
                    segments: [
                      ButtonSegment(
                        value: VueDemandes.miennes,
                        label: Text(l10n.demandesOngletMiennes),
                      ),
                      ButtonSegment(
                        value: VueDemandes.aValider,
                        label: Text(l10n.demandesOngletAValider),
                      ),
                    ],
                    selected: {etat.vue},
                    onSelectionChanged: (s) => cubit.changerVue(s.first),
                  ),
                ),
              Expanded(child: _Corps(etat: etat)),
            ],
          );
        },
      ),
    );
  }
}

class _Corps extends StatelessWidget {
  final DemandesChantierState etat;

  const _Corps({required this.etat});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<DemandesChantierCubit>();

    if (etat.status == DemandesStatus.chargement && etat.items.isEmpty) {
      return const LoadingList();
    }
    if (etat.status == DemandesStatus.erreur) {
      // Une panne réseau ne doit PAS s'afficher « aucune demande » : le
      // demandeur croirait la sienne disparue.
      return ErrorView(message: etat.erreur ?? '', onRetry: cubit.charger);
    }
    if (etat.items.isEmpty) {
      final mesDemandes = etat.vue == VueDemandes.miennes;
      return EmptyState(
        icon: Icons.assignment_outlined,
        title: mesDemandes ? l10n.demandesAucuneMienne : l10n.demandesAucuneAValider,
        subtitle: mesDemandes
            ? l10n.demandesAucuneMienneMessage
            : l10n.demandesAucuneAValiderMessage,
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: cubit.charger,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: etat.items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _Carte(chantier: etat.items[i]),
      ),
    );
  }
}

class _Carte extends StatelessWidget {
  final Chantier chantier;

  const _Carte({required this.chantier});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final refusee = chantier.statut == ChantierStatut.rejete;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        // La demande mène au chantier : on ne juge pas — et on ne corrige
        // pas — une demande sans pouvoir en regarder le contenu.
        onTap: () => context.push(AppRoutes.chantierDetail.replaceFirst(':id', chantier.id)),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      chantier.nom,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ChantierStatutBadge(statut: chantier.statut),
                ],
              ),
              if (chantier.code != null) ...[
                const SizedBox(height: 3),
                Text(
                  chantier.code!,
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
              if (chantier.adresse != null && chantier.adresse!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  chantier.adresse!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ],

              // ── Le motif du refus ────────────────────────────────────────
              //
              // Mis en avant plutôt que replié derrière un appui : c'est la
              // seule indication dont dispose le demandeur pour reprendre son
              // dossier, et la cacher revient à refuser sans expliquer.
              if (refusee && (chantier.motifRejet ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.dangerBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.demandesMotifRefus,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.danger,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        chantier.motifRejet!,
                        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.4),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.demandesCorrigerAide,
                        style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

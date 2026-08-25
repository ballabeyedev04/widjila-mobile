import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/couleurs_avatar.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/loading_list.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../organisation/domain/entities/partenaire.dart';
import '../../../organisation/presentation/cubit/membres_cubit.dart';
import '../../../organisation/presentation/cubit/membres_state.dart';
import '../../../organisation/presentation/cubit/partenaires_cubit.dart';
import '../cubit/reserve_detail_cubit.dart';

/// Choix de l'intervenant à affecter à une réserve.
///
/// Deux onglets parce que le serveur accepte deux natures de destinataire —
/// un UTILISATEUR de l'organisation ou une ENTREPRISE partenaire
/// (`affecterReserveSchema` exige l'un ou l'autre). Les mélanger dans une
/// seule liste aurait obligé à deviner, à la lecture d'un nom, lequel des
/// deux champs partirait dans la requête.
Future<void> ouvrirAffectationReserve(BuildContext context) {
  final cubit = context.read<ReserveDetailCubit>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: cubit),
        BlocProvider(create: (_) => sl<MembresCubit>()..charger()),
        BlocProvider(create: (_) => sl<PartenairesCubit>()..charger()),
      ],
      child: const _AffecterReserveSheet(),
    ),
  );
}

class _AffecterReserveSheet extends StatefulWidget {
  const _AffecterReserveSheet();

  @override
  State<_AffecterReserveSheet> createState() => _AffecterReserveSheetState();
}

class _AffecterReserveSheetState extends State<_AffecterReserveSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _onglets = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _onglets.dispose();
    super.dispose();
  }

  Future<void> _affecter({String? utilisateurId, String? entrepriseId}) async {
    final cubit = context.read<ReserveDetailCubit>();
    final l10n = context.l10n;
    final ok = await cubit.affecter(utilisateurId: utilisateurId, entrepriseId: entrepriseId);
    if (!mounted || !context.mounted) return;

    if (ok) {
      Navigator.of(context).pop();
      AppAlert.success(context, message: l10n.reserveAffectationAjoutee);
    } else {
      AppAlert.error(context, message: cubit.state.erreur ?? l10n.commonUneErreurSurvenue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
              ContenuFormulaire(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 12, 4),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary100,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.reserveAffectationChoisir,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              ),
              // Onglets en pilules — même vocabulaire que la médiathèque et
              // que les puces de filtre des listes.
              ContenuFormulaire(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: TabBar(
                      controller: _onglets,
                      indicator: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelColor: Colors.white,
                      unselectedLabelColor: AppColors.textSecondary,
                      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      splashBorderRadius: BorderRadius.circular(26),
                      tabs: [
                        Tab(height: 38, text: l10n.reserveAffectationOngletMembres),
                        Tab(height: 38, text: l10n.reserveAffectationOngletIntervenants),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _onglets,
                  children: [
                    _ListeMembres(onChoix: (id) => _affecter(utilisateurId: id)),
                    _ListeIntervenants(onChoix: (id) => _affecter(entrepriseId: id)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ListeMembres extends StatelessWidget {
  final ValueChanged<String> onChoix;
  const _ListeMembres({required this.onChoix});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocBuilder<MembresCubit, MembresState>(
      builder: (context, state) {
        if (state.status == MembresStatus.chargement || state.status == MembresStatus.initial) {
          return const LoadingList(itemHeight: 68);
        }
        // Seuls les membres ACTIFS : affecter une réserve à un compte
        // désactivé produirait un responsable qui ne peut plus se connecter.
        final membres = state.membres.where((m) => m.estActif).toList();
        if (membres.isEmpty) {
          return EmptyState(
            icon: Icons.groups_outlined,
            title: l10n.membreAucun,
            subtitle: l10n.membreAucunDescription,
          );
        }
        return ContenuFormulaire(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            itemCount: membres.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final membre = membres[i];
              return _Choix(
                initiales: membre.initiales,
                couleur: couleurAvatar(membre.id),
                titre: membre.nomComplet,
                sousTitre: membre.fonction?.isNotEmpty == true ? membre.fonction! : membre.email,
                onTap: () => onChoix(membre.id),
              );
            },
          ),
        );
      },
    );
  }
}

class _ListeIntervenants extends StatelessWidget {
  final ValueChanged<String> onChoix;
  const _ListeIntervenants({required this.onChoix});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocBuilder<PartenairesCubit, PartenairesState>(
      builder: (context, state) {
        if (state.status == PartenairesStatus.chargement || state.status == PartenairesStatus.initial) {
          return const LoadingList(itemHeight: 68);
        }
        // Un intervenant archivé n'a plus vocation à recevoir du travail.
        final items = state.items.where((p) => p.actif).toList();
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.handshake_outlined,
            title: l10n.partenaireAucun,
            subtitle: l10n.partenaireAucunDescription,
          );
        }
        return ContenuFormulaire(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final partenaire = items[i];
              return _Choix(
                initiales: partenaire.initiales,
                couleur: couleurAvatar(partenaire.id),
                titre: partenaire.nom,
                sousTitre: partenaire.type.label(l10n),
                onTap: () => onChoix(partenaire.id),
              );
            },
          ),
        );
      },
    );
  }
}

class _Choix extends StatelessWidget {
  final String initiales;
  final Color couleur;
  final String titre;
  final String sousTitre;
  final VoidCallback onTap;

  const _Choix({
    required this.initiales,
    required this.couleur,
    required this.titre,
    required this.sousTitre,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(shape: BoxShape.circle, color: couleur),
                alignment: Alignment.center,
                child: Text(
                  initiales,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      titre,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sousTitre,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
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

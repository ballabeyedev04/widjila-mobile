import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/loading_list.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/notification.dart';
import '../cubit/notifications_cubit.dart';
import '../widgets/notification_card.dart';

/// Filtres de la rangée de puces.
enum _Filtre { toutes, nonLues, lues }

/// Écran Notifications — même armature que Réserves et Plans.
///
/// Il réutilise le chrome partagé ([EnTeteListe], [ChampRecherche],
/// [ChipFiltre], [EtatVideIllustre]) : c'est ce qui garantit que les trois
/// écrans de liste restent jumelles au fil des retouches, au lieu de diverger
/// chacun de son côté.
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<NotificationsCubit>()..charger(),
      child: const _NotificationsView(),
    );
  }
}

class _NotificationsView extends StatefulWidget {
  const _NotificationsView();

  @override
  State<_NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<_NotificationsView> {
  _Filtre _filtre = _Filtre.toutes;
  String _recherche = '';

  /// Filtrage LOCAL : le serveur ne propose qu'un filtre `nonLues` et aucune
  /// recherche sur cette route, et la liste rapatriée tient en une page.
  /// Ajouter des paramètres au back pour trier quelques dizaines d'éléments
  /// déjà en mémoire serait disproportionné.
  List<NotificationItem> _filtrer(List<NotificationItem> items) {
    final motif = _recherche.trim().toLowerCase();
    return items.where((n) {
      final passeFiltre = switch (_filtre) {
        _Filtre.toutes => true,
        _Filtre.nonLues => n.nonLue,
        _Filtre.lues => !n.nonLue,
      };
      if (!passeFiltre) return false;
      if (motif.isEmpty) return true;
      return n.titre.toLowerCase().contains(motif) ||
          (n.message ?? '').toLowerCase().contains(motif);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      // Blanc, comme Réserves et Plans. La LISTE repose sur le gris de fond
      // (voir _Liste) : des cartes blanches sur page blanche perdraient tout
      // relief.
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ContenuCentre(child: EnTeteListe(titre: l10n.navNotifications)),
            ContenuCentre(
              child: ChampRecherche(
                hint: l10n.notificationRechercheHint,
                onChanged: (v) => setState(() => _recherche = v),
              ),
            ),
            _RangeeFiltres(
              actif: _filtre,
              onChoix: (f) => setState(() => _filtre = f),
            ),
            Expanded(
              child: BlocBuilder<NotificationsCubit, NotificationsState>(
                builder: (context, state) {
                  switch (state.status) {
                    case NotificationsStatus.initial:
                    case NotificationsStatus.chargement:
                      return const LoadingList();
                    case NotificationsStatus.erreur:
                      return ErrorView(
                        message: state.erreur ?? l10n.commonErrorUnknown,
                        onRetry: () => context.read<NotificationsCubit>().charger(),
                      );
                    case NotificationsStatus.succes:
                      final visibles = _filtrer(state.items);
                      if (visibles.isEmpty) {
                        return _EtatVide(
                          filtreActif: _recherche.isNotEmpty || _filtre != _Filtre.toutes,
                        );
                      }
                      return _Liste(items: visibles);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeeFiltres extends StatelessWidget {
  final _Filtre actif;
  final ValueChanged<_Filtre> onChoix;

  const _RangeeFiltres({required this.actif, required this.onChoix});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotificationsCubit, NotificationsState>(
      buildWhen: (a, b) => a.nonLues != b.nonLues || a.items.length != b.items.length,
      builder: (context, state) {
        final l10n = context.l10n;
        final lues = state.items.length - state.nonLues;

        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: ContenuCentre(
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        ChipFiltre(
                          icon: Icons.grid_view_rounded,
                          label: l10n.notificationFiltreToutes(state.items.length),
                          actif: actif == _Filtre.toutes,
                          onTap: () => onChoix(_Filtre.toutes),
                        ),
                        const SizedBox(width: 9),
                        ChipFiltre(
                          icon: Icons.mark_email_unread_outlined,
                          label: l10n.notificationFiltreNonLues(state.nonLues),
                          actif: actif == _Filtre.nonLues,
                          onTap: () => onChoix(_Filtre.nonLues),
                        ),
                        const SizedBox(width: 9),
                        ChipFiltre(
                          icon: Icons.drafts_outlined,
                          label: l10n.notificationFiltreLues(lues < 0 ? 0 : lues),
                          actif: actif == _Filtre.lues,
                          onTap: () => onChoix(_Filtre.lues),
                        ),
                        const SizedBox(width: 9),
                      ],
                    ),
                  ),
                ),
                // Ne s'affiche que s'il y a quelque chose à marquer : un bouton
                // en permanence, inactif la plupart du temps, encombrerait la
                // rangée pour rien.
                if (state.nonLues > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: TextButton.icon(
                      onPressed: () => context.read<NotificationsCubit>().toutMarquerLu(),
                      icon: const Icon(Icons.done_all_rounded, size: 17),
                      label: Text(l10n.notificationToutLire, style: const TextStyle(fontSize: 12.5)),
                      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EtatVide extends StatelessWidget {
  final bool filtreActif;
  const _EtatVide({required this.filtreActif});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (filtreActif) {
      return EtatVideIllustre(
        motif: MotifVide.recherche,
        titre: l10n.commonNoResults,
        description: l10n.reserveEssayerAutreFiltre,
      );
    }

    return EtatVideIllustre(
      motif: MotifVide.notification,
      titre: l10n.notificationAucune,
      description: l10n.notificationAucuneDescription,
    );
  }
}

class _Liste extends StatelessWidget {
  final List<NotificationItem> items;
  const _Liste({required this.items});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => context.read<NotificationsCubit>().charger(),
        child: ContenuCentre(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => NotificationCard(notification: items[i]),
          ),
        ),
      ),
    );
  }
}

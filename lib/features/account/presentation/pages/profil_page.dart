import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../../core/widgets/liste_chrome.dart';
import 'modifier_profil_sheet.dart';
import '../../../auth/presentation/bloc/auth_state.dart';

/// Écran Profil minimal (phase 1) — informations du compte + déconnexion.
/// Édition du profil / MFA / sessions actives : voir `features/account`
/// (phase 3).
class ProfilPage extends StatelessWidget {
  const ProfilPage({super.key});

  Future<void> _confirmerDeconnexion(BuildContext context) async {
    final l10n = context.l10n;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.profilDeconnexion),
        content: Text(l10n.profilConfirmerDeconnexion),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(l10n.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.profilDeconnexion),
          ),
        ],
      ),
    );
    if (confirme == true && context.mounted) {
      context.read<AuthBloc>().add(const AuthLogoutRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      // Blanc, comme les autres écrans. Le CONTENU repose sur le gris de fond :
      // des cartes blanches sur une page blanche perdraient tout relief.
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Écran de la coquille : la cloche y trouve bien son cubit.
            ContenuCentre(
              child: EnTeteListe(
                titre: l10n.profilTitre,
                avecRetour: true,
                // Le crayon prend la place de la cloche : sur SA propre fiche,
                // l'action attendue est de la corriger, pas d'aller lire ses
                // notifications.
                action: BlocBuilder<AuthBloc, AuthState>(
                  buildWhen: (a, b) => a.utilisateur != b.utilisateur,
                  builder: (context, state) {
                    final user = state.utilisateur;
                    if (user == null) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                      tooltip: l10n.profilModifierTitre,
                      onPressed: () => ouvrirModificationProfil(context, user),
                    );
                  },
                ),
              ),
            ),
            Expanded(
              child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          final user = state.utilisateur;
          if (user == null) return const SizedBox.shrink();

          // `ContenuCentre` : sans lui, l'avatar et les cartes d'infos
          // s'étirent sur toute la largeur d'une tablette, au lieu de rester
          // lisibles comme sur un téléphone.
          return ColoredBox(
            color: AppColors.background,
            child: ContenuCentre(
            child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            children: [
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                      child: Text(
                        user.initiales,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      user.nomComplet,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(user.role.label(l10n), style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    children: [
                      ListTile(leading: const Icon(Icons.mail_outline), title: Text(l10n.authChampEmail), subtitle: Text(user.email)),
                      if (user.telephone != null && user.telephone!.isNotEmpty)
                        ListTile(
                          leading: const Icon(Icons.phone_outlined),
                          title: Text(l10n.profilTelephone),
                          subtitle: Text(user.telephone!),
                        ),
                      if (user.fonction != null && user.fonction!.isNotEmpty)
                        ListTile(
                          leading: const Icon(Icons.work_outline),
                          title: Text(l10n.profilFonction),
                          subtitle: Text(user.fonction!),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => _confirmerDeconnexion(context),
                icon: const Icon(Icons.logout, color: AppColors.danger),
                label: Text(l10n.profilDeconnexion, style: const TextStyle(color: AppColors.danger)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.danger)),
              ),
            ],
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

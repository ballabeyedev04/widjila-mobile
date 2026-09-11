import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/offline/file_attente.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/l10n_extension.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';

/// Vérifie qu'une déconnexion volontaire ne détruit pas du travail pas encore
/// envoyé, et demande confirmation si c'est le cas.
///
/// ## Le défaut corrigé (audit synchronisation)
///
/// La déconnexion volontaire purge TOUTES les données locales, file d'attente
/// comprise (`SessionLocale.purger`) — c'est voulu : un téléphone de chantier
/// partagé ne doit rien laisser au compte suivant. Mais elle le faisait sans
/// un mot. Une journée de relevés faits au sous-sol, pas encore synchronisés,
/// disparaissait sur un simple « Déconnexion » — depuis le menu du tableau de
/// bord, sans même une confirmation.
///
/// Retourne `true` si la déconnexion peut avoir lieu : rien en attente, ou
/// perte acceptée EN CONNAISSANCE DE CAUSE.
Future<bool> confirmerPerteTravailNonEnvoye(BuildContext context, {required FileAttente file}) async {
  final total = await file.nombreEnAttente() + await file.nombreEnEchec();
  if (total == 0) return true;
  if (!context.mounted) return false;

  final l10n = context.l10n;
  final confirme = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.cloud_off_rounded, color: AppColors.danger),
      title: Text(l10n.deconnexionTravailNonEnvoyeTitre),
      content: Text(l10n.deconnexionTravailNonEnvoyeMessage(total)),
      actions: [
        // L'action sûre en premier, et c'est elle que le retour arrière
        // déclenche (`null` → pas de déconnexion).
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(l10n.commonCancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.deconnexionTravailNonEnvoyeConfirmer),
        ),
      ],
    ),
  );
  return confirme == true;
}

/// Déconnexion volontaire, protégée par [confirmerPerteTravailNonEnvoye].
Future<void> deconnecterAvecGarde(BuildContext context, {required FileAttente file}) async {
  final autorise = await confirmerPerteTravailNonEnvoye(context, file: file);
  if (autorise && context.mounted) {
    context.read<AuthBloc>().add(const AuthLogoutRequested());
  }
}

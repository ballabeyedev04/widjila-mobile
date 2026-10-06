import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../cubit/hors_ligne_cubit.dart';

/// Carte « Disponible hors connexion » de la fiche chantier.
///
/// Télécharge le paquet complet du chantier AVANT de partir sur le terrain et
/// affiche, sans ambiguïté, s'il est prêt et depuis quand (guide hors
/// connexion §3 : « Chantier disponible hors connexion — dernière
/// synchronisation : date/heure »).
class CarteHorsLigne extends StatelessWidget {
  final String chantierId;
  const CarteHorsLigne({super.key, required this.chantierId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HorsLigneCubit(sl(), chantierId: chantierId)..charger(),
      child: const _Contenu(),
    );
  }
}

class _Contenu extends StatelessWidget {
  const _Contenu();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<HorsLigneCubit, HorsLigneState>(
      builder: (context, s) {
        final pret = s.derniereSynchro != null;
        final couleur = pret ? AppColors.success : AppColors.primary;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: couleur.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: couleur.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(pret ? Icons.cloud_done_rounded : Icons.cloud_download_outlined, color: couleur),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      pret ? l10n.horsLigneDisponible : l10n.horsLigneTitre,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                pret
                    ? l10n.horsLigneDerniereSynchro(DateFormat('dd/MM/yyyy HH:mm').format(s.derniereSynchro!.toLocal()))
                    : l10n.horsLigneDescription,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
              ),
              if (s.enCours) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: s.progression.total == 0 ? null : s.progression.ratio,
                  color: AppColors.primary,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.horsLigneEnCours(s.progression.fait, s.progression.total),
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ] else ...[
                if (s.erreur != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${l10n.horsLigneIncomplet} — ${s.erreur}',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.danger, height: 1.35),
                  ),
                ],
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () => context.read<HorsLigneCubit>().telecharger(),
                    icon: Icon(pret ? Icons.refresh_rounded : Icons.download_rounded, size: 18),
                    label: Text(s.erreur != null
                        ? l10n.horsLigneReessayer
                        : (pret ? l10n.horsLigneMettreAJour : l10n.horsLigneBouton)),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

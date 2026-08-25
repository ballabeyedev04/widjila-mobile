import 'package:flutter/material.dart';

import '../../../../core/services/preferences_notification.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/l10n_extension.dart';

/// Réglage des alertes reçues sur CET appareil.
///
/// Le backend n'expose aucune route de préférences : ce panneau ne demande
/// donc pas au serveur de cesser d'envoyer, il décide de ce que l'appareil
/// affiche. La nuance est dite à l'écran — laisser croire qu'on coupe la
/// source alors qu'on coupe l'affichage exposerait à une mauvaise surprise
/// sur un second téléphone.
class SectionNotifications extends StatefulWidget {
  const SectionNotifications({super.key});

  @override
  State<SectionNotifications> createState() => _SectionNotificationsState();
}

class _SectionNotificationsState extends State<SectionNotifications> {
  final PreferencesNotification _prefs = sl<PreferencesNotification>();

  String _libelleFamille(AppLocalizations l10n, FamilleAlerte famille) => switch (famille) {
        FamilleAlerte.reserve => l10n.navReserves,
        FamilleAlerte.chantier => l10n.actionChantiers,
        FamilleAlerte.inspection => l10n.dashboardApercuInspections,
      };

  String _descriptionFamille(AppLocalizations l10n, FamilleAlerte famille) => switch (famille) {
        FamilleAlerte.reserve => l10n.notifFamilleReserveDescription,
        FamilleAlerte.chantier => l10n.notifFamilleChantierDescription,
        FamilleAlerte.inspection => l10n.notifFamilleInspectionDescription,
      };

  IconData _icone(FamilleAlerte famille) => switch (famille) {
        FamilleAlerte.reserve => Icons.report_gmailerrorred_outlined,
        FamilleAlerte.chantier => Icons.construction_rounded,
        FamilleAlerte.inspection => Icons.fact_check_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final toutes = _prefs.toutesActives;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: toutes,
          activeTrackColor: AppColors.primary,
          onChanged: (v) async {
            await _prefs.definirToutesActives(v);
            if (mounted) setState(() {});
          },
          title: Text(
            l10n.notifToutesTitre,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            l10n.notifToutesDescription,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ),
        const Divider(height: 24),

        // Les familles restent VISIBLES mais inertes quand tout est coupé :
        // les masquer ferait croire que le réglage a disparu, et obligerait à
        // rallumer pour retrouver ses choix.
        Opacity(
          opacity: toutes ? 1 : 0.45,
          child: IgnorePointer(
            ignoring: !toutes,
            child: Column(
              children: [
                for (final famille in FamilleAlerte.values)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _prefs.familleActive(famille),
                    activeTrackColor: AppColors.primary,
                    onChanged: (v) async {
                      await _prefs.definirFamille(famille, v);
                      if (mounted) setState(() {});
                    },
                    secondary: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_icone(famille), size: 18, color: AppColors.primary),
                    ),
                    title: Text(
                      _libelleFamille(l10n, famille),
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _descriptionFamille(l10n, famille),
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.info.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.info),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.notifPorteeLocale,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

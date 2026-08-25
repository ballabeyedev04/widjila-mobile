import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/notification.dart';

/// Icône et couleur d'une notification, d'après son type.
///
/// Les types émis par le serveur sont POINTÉS — `reserve.affectee`,
/// `reserve.en_retard`, `chantier.affectation`, `inspection.convocation`…
/// (voir les appels à `NotificationService.notifier` côté back). D'où un
/// filtrage par PRÉFIXE et non par égalité : une première version comparait
/// des mots simples (`'reserve'`) et ne reconnaissait donc AUCUN type réel,
/// renvoyant tout sur l'icône neutre. Le préfixe a l'avantage d'accueillir un
/// futur `reserve.commentee` sans redéploiement du mobile.
///
/// Les cas urgents (retard, escalade) sont sortis du lot et passent en rouge :
/// c'est l'information à voir en premier en parcourant la liste.
(IconData, Color) apparenceNotification(String type) {
  if (type == 'reserve.en_retard' || type == 'reserve.escalade') {
    return (Icons.warning_amber_rounded, AppColors.danger);
  }
  if (type == 'reserve.echeance_proche') {
    return (Icons.hourglass_bottom_rounded, AppColors.warning);
  }

  return switch (type.split('.').first) {
    'reserve' => (Icons.assignment_rounded, AppColors.primary),
    'inspection' => (Icons.fact_check_outlined, AppColors.info),
    'chantier' => (Icons.construction_rounded, AppColors.accentDark),
    'plan' => (Icons.map_outlined, AppColors.info),
    'document' => (Icons.folder_open_rounded, AppColors.success),
    _ => (Icons.notifications_none_rounded, AppColors.neutral),
  };
}

/// Date relative, en clair. Au-delà d'une semaine, la date exacte est plus
/// parlante que « il y a 23 jours ».
String quandLisible(AppLocalizations l10n, DateTime? date) {
  if (date == null) return '';
  final ecart = DateTime.now().difference(date);
  if (ecart.isNegative) return l10n.notificationInstant; // horloge d'appareil en avance
  if (ecart.inMinutes < 1) return l10n.notificationInstant;
  if (ecart.inMinutes < 60) return l10n.notificationIlYAMinutes(ecart.inMinutes);
  if (ecart.inHours < 24) return l10n.notificationIlYAHeures(ecart.inHours);
  if (ecart.inDays < 7) return l10n.notificationIlYAJours(ecart.inDays);
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

/// Carte d'une notification — même langage visuel que les cartes de réserve et
/// de plan : fond blanc, coins à 18, ombre douce.
class NotificationCard extends StatelessWidget {
  final NotificationItem notification;
  final VoidCallback? onTap;

  const NotificationCard({super.key, required this.notification, this.onTap});

  @override
  Widget build(BuildContext context) {
    final (icone, couleur) = apparenceNotification(notification.type);
    final nonLue = notification.nonLue;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            // Les non-lues portent un liseré de leur couleur de catégorie
            // plutôt qu'un fond teinté : plus discret, et lisible en plein
            // soleil sur un chantier.
            border: nonLue ? Border.all(color: couleur.withValues(alpha: 0.45), width: 1.4) : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: couleur.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icone, color: couleur, size: 22),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.titre,
                            style: TextStyle(
                              fontWeight: nonLue ? FontWeight.w800 : FontWeight.w600,
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (nonLue) ...[
                          const SizedBox(width: 8),
                          // Pastille pleine : repère de balayage vertical, on
                          // repère les non-lues sans lire les titres.
                          Container(
                            width: 9,
                            height: 9,
                            margin: const EdgeInsets.only(top: 4),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (notification.message != null && notification.message!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        notification.message!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded, size: 13, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          quandLisible(context.l10n, notification.creeLe),
                          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../errors/error_codes.dart';
import '../routes/app_router.dart';
import '../theme/app_colors.dart';
import '../../l10n/l10n_extension.dart';

/// Raison pour laquelle le serveur a refusé, telle qu'il la nomme.
enum RefusAbonnement {
  /// Aucune formule active — essai terminé, ou jamais souscrit.
  aucunAbonnement,

  /// La formule en cours n'inclut pas cette fonctionnalité.
  fonctionnaliteAbsente,

  /// Le plafond de la formule est atteint (utilisateurs, chantiers).
  limiteAtteinte,
}

/// Message d'un refus d'abonnement, décomposé.
class RefusAbonnementDecode {
  final RefusAbonnement raison;

  /// Le texte du SERVEUR, intact. Il nomme la formule en cours et le plafond
  /// atteint — bien plus utile qu'un texte générique écrit ici.
  final String message;

  const RefusAbonnementDecode({required this.raison, required this.message});

  /// Décode un message préfixé par [ErrCodes.prefixeAbonnement], ou `null` si
  /// ce n'en est pas un.
  ///
  /// Forme attendue : `__ERR_ABONNEMENT__|CODE_SERVEUR|message`.
  static RefusAbonnementDecode? tenter(String message) {
    if (!message.startsWith(ErrCodes.prefixeAbonnement)) return null;

    final reste = message.substring(ErrCodes.prefixeAbonnement.length);
    final separateur = reste.indexOf('|');
    // Sans séparateur, on garde tout le reste comme message : mieux vaut un
    // titre générique qu'un message perdu.
    if (separateur < 0) {
      return RefusAbonnementDecode(
        raison: RefusAbonnement.aucunAbonnement,
        message: reste,
      );
    }

    return RefusAbonnementDecode(
      raison: switch (reste.substring(0, separateur)) {
        'SUBSCRIPTION_LIMIT_REACHED' => RefusAbonnement.limiteAtteinte,
        'SUBSCRIPTION_FEATURE_UNAVAILABLE' => RefusAbonnement.fonctionnaliteAbsente,
        _ => RefusAbonnement.aucunAbonnement,
      },
      message: reste.substring(separateur + 1),
    );
  }
}

/// Invitation à s'abonner, présentée à la place d'une alerte d'erreur.
///
/// ## Pourquoi un écran à part
///
/// Un refus d'abonnement n'est pas une panne : c'est la seule catégorie de
/// refus que l'utilisateur peut lever lui-même, en quelques secondes. Le
/// présenter en rouge avec un simple « OK » revenait à annoncer un échec et à
/// laisser la personne sans issue — alors que la porte est juste à côté.
///
/// Le message du serveur est repris tel quel : lui seul connaît la formule en
/// cours et le plafond exact.
Future<void> afficherModaleAbonnement(
  BuildContext context,
  RefusAbonnementDecode refus,
) {
  return showGeneralDialog<void>(
    context: context,
    barrierLabel: context.l10n.abonnementRequisTitre,
    barrierDismissible: true,
    barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
    transitionBuilder: (contexteDialogue, animation, _, _) {
      final courbe = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(courbe),
          child: _CarteAbonnement(refus: refus),
        ),
      );
    },
  );
}

class _CarteAbonnement extends StatelessWidget {
  final RefusAbonnementDecode refus;

  const _CarteAbonnement({required this.refus});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final titre = switch (refus.raison) {
      RefusAbonnement.limiteAtteinte => l10n.abonnementLimiteTitre,
      RefusAbonnement.fonctionnaliteAbsente => l10n.abonnementFonctionnaliteTitre,
      RefusAbonnement.aucunAbonnement => l10n.abonnementRequisTitre,
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Bandeau de marque plutôt qu'un badge rouge : on invite, on ne
              // sanctionne pas.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  size: 44,
                  color: Colors.white,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      titre,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      refus.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          // On referme AVANT de naviguer : la modale reposait
                          // sur la route quittée, elle resterait suspendue
                          // au-dessus de l'écran d'abonnement.
                          Navigator.of(context).pop();
                          context.push(AppRoutes.abonnement);
                        },
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: Text(l10n.abonnementVoirFormules),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        l10n.abonnementPlusTard,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
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

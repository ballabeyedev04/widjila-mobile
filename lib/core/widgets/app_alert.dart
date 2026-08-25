import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../l10n/l10n_extension.dart';
import '../errors/error_codes.dart';
import '../theme/app_colors.dart';

/// Style d'alerte centralisé — succès / erreur — utilisé PARTOUT dans l'app
/// à la place des `SnackBar` (bannière plate en bas d'écran, peu visible).
/// Ici, la carte est centrée à l'écran, avec un badge coloré selon le type
/// (vert = succès, rouge = erreur), dans l'esprit SweetAlert2. Elle se ferme
/// sur le bouton OK, ou automatiquement après 8 secondes si l'utilisateur
/// ne fait rien.
///
/// Un seul point d'entrée pour toute l'app : changer l'apparence (couleurs,
/// rayons, animation) se fait ici une seule fois plutôt que dans chaque page
/// qui affichait sa propre `SnackBar`.
///
/// Usage :
/// ```dart
/// AppAlert.error(context, message: state.erreur!);
/// AppAlert.success(context, message: 'Réserve créée.');
/// ```
enum _AppAlertType { succes, erreur }

class AppAlert {
  AppAlert._();

  static Future<void> success(
    BuildContext context, {
    required String message,
    String? title,
    String? bouton,
  }) {
    final l10n = context.l10n;
    return _show(
      context,
      type: _AppAlertType.succes,
      title: title ?? l10n.alertSuccessTitle,
      message: message,
      bouton: bouton ?? l10n.commonOk,
    );
  }

  static Future<void> error(
    BuildContext context, {
    required String message,
    String? title,
    String? bouton,
  }) {
    final l10n = context.l10n;
    return _show(
      context,
      type: _AppAlertType.erreur,
      title: title ?? l10n.alertErrorTitle,
      message: _resoudreMarqueur(l10n, message),
      bouton: bouton ?? l10n.commonOk,
    );
  }

  /// Traduit un marqueur [ErrCodes] posé par la couche réseau (qui n'a pas
  /// accès à `BuildContext`/`AppLocalizations` — voir `dio_client_factory
  /// .dart`) en message localisé. Tout `message` qui n'est pas un marqueur
  /// connu (message backend déjà exploitable, texte déjà composé par
  /// l'appelant…) passe inchangé : ce mécanisme est un point de traduction
  /// additionnel, pas un filtre.
  static String _resoudreMarqueur(AppLocalizations l10n, String message) {
    return switch (message) {
      ErrCodes.forbidden => l10n.errForbidden,
      ErrCodes.rateLimit => l10n.errRateLimit,
      ErrCodes.serviceUnavailable => l10n.errServiceUnavailable,
      ErrCodes.generic => l10n.commonErrorUnknown,
      _ => message,
    };
  }

  static Future<void> _show(
    BuildContext context, {
    required _AppAlertType type,
    required String title,
    required String message,
    required String bouton,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierLabel: title,
      // Pas de fermeture par tap en dehors — seuls le bouton OK ou le
      // minuteur de 8 s (voir `_AppAlertCard`) referment la carte.
      barrierDismissible: false,
      barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 320),
      // Construite une seule fois — `AnimatedBuilder` ci-dessous la réutilise
      // via son paramètre `child`, sans la reconstruire à chaque frame.
      pageBuilder: (context, animation, secondaryAnimation) =>
          _AppAlertCard(type: type, title: title, message: message, bouton: bouton),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            // Rebond léger (dépasse 1.0 puis se stabilise) sur l'échelle —
            // c'est ce qui donne le petit « pop » à l'arrivée plutôt qu'un
            // simple fondu mécanique. Le fondu, lui, reste sans rebond
            // (`easeOut`) : un alpha hors [0, 1] serait invalide.
            final rebond = Curves.easeOutBack.transform(animation.value);
            final fondu = Curves.easeOut.transform(animation.value).clamp(0.0, 1.0);
            return Opacity(
              opacity: fondu,
              child: Transform.scale(scale: 0.78 + (0.22 * rebond), child: child),
            );
          },
        );
      },
    );
  }
}

class _AppAlertCard extends StatefulWidget {
  final _AppAlertType type;
  final String title;
  final String message;
  final String bouton;

  const _AppAlertCard({required this.type, required this.title, required this.message, required this.bouton});

  @override
  State<_AppAlertCard> createState() => _AppAlertCardState();
}

class _AppAlertCardState extends State<_AppAlertCard> {
  static const _dureeAuto = Duration(seconds: 8);
  Timer? _minuteur;

  @override
  void initState() {
    super.initState();
    // Fermeture automatique après 8 s — l'utilisateur garde la main pour
    // fermer plus tôt via le bouton OK, qui annule alors ce minuteur.
    _minuteur = Timer(_dureeAuto, () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    super.dispose();
  }

  bool get _succes => widget.type == _AppAlertType.succes;
  Color get _couleur => _succes ? AppColors.success : AppColors.danger;
  Color get _couleurFond => _succes ? AppColors.successBg : AppColors.dangerBg;
  IconData get _icone => _succes ? Icons.check_rounded : Icons.close_rounded;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 44, offset: const Offset(0, 22)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Badge à deux cercles : anneau tinté large + disque plein —
              // c'est ce double contraste qui donne le côté « pastille »
              // reconnaissable des alertes modernes (SweetAlert2, iOS…).
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(color: _couleurFond, shape: BoxShape.circle),
                child: Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: _couleur, shape: BoxShape.circle),
                    child: Icon(_icone, color: Colors.white, size: 30),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14.5, height: 1.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _couleur,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  child: Text(widget.bouton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

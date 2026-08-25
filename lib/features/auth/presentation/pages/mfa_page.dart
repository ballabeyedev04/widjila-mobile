import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../l10n/l10n_extension.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

/// Saisie du code TOTP (double authentification) après un login qui l'exige
/// — voir `AuthStatus.mfaRequis`.
class MfaPage extends StatefulWidget {
  const MfaPage({super.key});

  @override
  State<MfaPage> createState() => _MfaPageState();
}

class _MfaPageState extends State<MfaPage> {
  final _codeCtrl = TextEditingController();

  /// Verrou synchrone anti double-tap — voir le commentaire équivalent dans
  /// `register_page.dart`.
  bool _envoiEnCours = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _submit(AuthState state) {
    if (_envoiEnCours) return;
    if (_codeCtrl.text.trim().length != 6) {
      AppAlert.error(context, message: context.l10n.mfaCode6Chiffres);
      return;
    }
    _envoiEnCours = true;
    context.read<AuthBloc>().add(AuthMfaSubmitted(code: _codeCtrl.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      // Pas d'`EnTeteListe` ici : l'écran porte DÉJÀ son titre dans le corps,
      // sous le bouclier (« Vérification en deux étapes »). Un second titre
      // en tête ferait doublon. Il ne manquait que la sortie — d'où cette
      // simple flèche, dans le style des autres écrans.
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (!state.enCours) _envoiEnCours = false;
          if (state.erreur != null) {
            AppAlert.error(context, message: state.erreur!);
          }
        },
        builder: (context, state) {
          final l10n = context.l10n;
          final prenom = state.utilisateur?.prenom ?? '';
          return SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: AppColors.primary),
                    tooltip: l10n.commonBack,
                    // Annule la session MFA en cours plutôt que de dépiler :
                    // revenir en arrière ici, c'est renoncer à se connecter.
                    onPressed: () => context.read<AuthBloc>().add(const AuthMfaCancelled()),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
            // `ContenuFormulaire` : sans lui, le champ à 6 chiffres et le bouton
            // s'étiraient sur toute la largeur d'une tablette — les seuls
            // écrans d'auth qui n'utilisaient pas déjà un plafond de largeur.
            child: ContenuFormulaire(
              child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_outlined, color: AppColors.primary, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    l10n.mfaTitre,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    prenom.isNotEmpty ? l10n.mfaInstructionsAvecPrenom(prenom) : l10n.mfaInstructionsSansPrenom,
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _codeCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 28, letterSpacing: 12, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(counterText: ''),
                    onSubmitted: (_) => _submit(state),
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: l10n.mfaBoutonVerifier,
                    enCours: state.enCours,
                    onPressed: () => _submit(state),
                  ),
                ],
              ),
              ),
            ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

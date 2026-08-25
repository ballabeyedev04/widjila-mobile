import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../l10n/l10n_extension.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import '../widgets/auth_chrome.dart';

// MIROIR EXACT du backend — voir `backend/src/validations/common.js#motDePasse`
// et `resetPasswordSchema` (`backend/src/modules/auth/validation/auth.validation.js`).
final _regexMotDePasse = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)');

class ResetPasswordPage extends StatefulWidget {
  final String? emailPrerempli;
  const ResetPasswordPage({super.key, this.emailPrerempli});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailCtrl;
  final _otpCtrl = TextEditingController();
  final _motDePasseCtrl = TextEditingController();
  bool _motDePasseVisible = false;

  /// Verrou synchrone anti double-tap — voir le commentaire équivalent dans
  /// `register_page.dart`.
  bool _envoiEnCours = false;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.emailPrerempli ?? '');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage(authBackgroundImage), context);
    precacheImage(const AssetImage(authLogoImage), context);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _motDePasseCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_envoiEnCours) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    _envoiEnCours = true;
    context.read<AuthBloc>().add(AuthResetPasswordRequested(
          email: _emailCtrl.text.trim(),
          otp: _otpCtrl.text.trim(),
          nouveauMotDePasse: _motDePasseCtrl.text,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: BlocConsumer<AuthBloc, AuthState>(
          listener: (context, state) {
            if (!state.enCours) _envoiEnCours = false;

            if (state.erreur != null) {
              AppAlert.error(context, message: state.erreur!);
              return;
            }
            if (state.messageSucces != null) {
              // Message du backend, jamais reformulé (voir AuthBloc).
              showAuthNoticeSheet(
                context,
                message: state.messageSucces!,
                bouton: context.l10n.authSeConnecter,
                icone: Icons.check_circle_outline_rounded,
                onFerme: () {
                  if (mounted) context.go('/login');
                },
              );
            }
          },
          builder: (context, state) {
            return AuthBackdrop(
              onRetour: () => context.pop(),
              contenu: (context, m) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AuthMarque(hauteurLogo: m.hauteurLogo),
                  SizedBox(height: m.espaceMarqueCarte),
                  _carte(m, state),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _carte(AuthMesures m, AuthState state) {
    final l10n = context.l10n;
    return AuthGlassCard(
      mesures: m,
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AuthCardHeader(
              titre: l10n.resetNouveauMotDePasse,
              sousTitre: l10n.resetSousTitre,
              mesures: m,
            ),
            SizedBox(height: m.hauteurSerree ? 22 : 30),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              style: authFieldTextStyle,
              cursorColor: AppColors.primaryLight,
              decoration: authFieldDecoration(label: l10n.authChampEmail, icone: Icons.mail_outline_rounded),
              maxLength: authEmailLongueurMax,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              validator: (v) => authValidateurEmail(l10n, v),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _otpCtrl,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              inputFormatters: [
                // Alphabet du code — MIROIR de `_generateOtp` côté backend
                // (`account.service.js`) : lettres capitales et chiffres,
                // sans les caractères ambigus (0/O, 1/I).
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                LengthLimitingTextInputFormatter(6),
                TextInputFormatter.withFunction(
                  (oldValue, newValue) => newValue.copyWith(text: newValue.text.toUpperCase()),
                ),
              ],
              style: authFieldTextStyle.copyWith(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 10),
              cursorColor: AppColors.primaryLight,
              decoration: authFieldDecoration(
                label: l10n.resetChampCode,
                icone: Icons.pin_outlined,
              ).copyWith(counterText: ''),
              validator: (v) => (v == null || v.trim().length != 6) ? l10n.resetCode6Requis : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _motDePasseCtrl,
              obscureText: !_motDePasseVisible,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              onFieldSubmitted: (_) => _submit(),
              style: authFieldTextStyle,
              cursorColor: AppColors.primaryLight,
              decoration: authFieldDecoration(
                label: l10n.resetNouveauMotDePasse,
                icone: Icons.lock_outline_rounded,
                texteAide: l10n.authAideMotDePasse,
                suffixe: IconButton(
                  icon: Icon(
                    _motDePasseVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 20,
                    color: Colors.white.withValues(alpha: 0.70),
                  ),
                  onPressed: () => setState(() => _motDePasseVisible = !_motDePasseVisible),
                ),
              ),
              validator: (v) {
                final val = v ?? '';
                if (val.isEmpty) return l10n.authMotDePasseRequis;
                if (val.length < 8 || val.length > 128) return l10n.authMotDePasse8a128;
                if (!_regexMotDePasse.hasMatch(val)) {
                  return l10n.authMotDePasseComplexite;
                }
                return null;
              },
            ),
            SizedBox(height: m.hauteurSerree ? 20 : 26),
            AuthActionButton(
              label: l10n.resetBouton,
              icone: Icons.check_rounded,
              enCours: state.enCours,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

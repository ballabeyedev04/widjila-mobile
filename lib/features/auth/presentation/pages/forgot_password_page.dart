import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../l10n/l10n_extension.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import '../widgets/auth_chrome.dart';
import '../../../../core/routes/retour.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  /// Verrou synchrone anti double-tap — voir le commentaire équivalent dans
  /// `register_page.dart`.
  bool _envoiEnCours = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage(authBackgroundImage), context);
    precacheImage(const AssetImage(authLogoImage), context);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_envoiEnCours) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    _envoiEnCours = true;
    context.read<AuthBloc>().add(AuthForgotPasswordRequested(email: _emailCtrl.text.trim()));
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
            // Le popup affiche le message TEL QUE reçu du backend — celui-ci
            // est volontairement identique que le compte existe ou non (anti
            // énumération, voir AccountService.forgotPassword côté backend) :
            // le mobile ne doit donc jamais le reformuler ni le remplacer par
            // un texte codé en dur, qui romprait cette garantie de sécurité.
            // La navigation vers la saisie du code n'a lieu qu'à la fermeture
            // du popup (bouton OK) — voir `showAuthNoticeSheet`.
            if (state.messageSucces != null) {
              final email = _emailCtrl.text.trim();
              showAuthNoticeSheet(
                context,
                message: state.messageSucces!,
                icone: Icons.mark_email_read_outlined,
                onFerme: () {
                  if (mounted) context.push(AppRoutes.resetPassword, extra: email);
                },
              );
            }
          },
          builder: (context, state) {
            final l10n = context.l10n;
            return AuthBackdrop(
              onRetour: () => context.retourVers(AppRoutes.login),
              contenu: (context, m) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AuthMarque(hauteurLogo: m.hauteurLogo),
                  SizedBox(height: m.espaceMarqueCarte),
                  _carte(m, state),
                  const SizedBox(height: 20),
                  AuthFooterLink(
                    question: l10n.forgotVousSouvenez,
                    action: l10n.authSeConnecter,
                    onPressed: () => context.retourVers(AppRoutes.login),
                  ),
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
              titre: l10n.forgotTitre,
              sousTitre: l10n.forgotSousTitre,
              mesures: m,
            ),
            SizedBox(height: m.hauteurSerree ? 22 : 30),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              onFieldSubmitted: (_) => _submit(),
              style: authFieldTextStyle,
              cursorColor: AppColors.primaryLight,
              decoration: authFieldDecoration(label: l10n.authChampEmail, icone: Icons.mail_outline_rounded),
              maxLength: authEmailLongueurMax,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              validator: (v) => authValidateurEmail(l10n, v),
            ),
            SizedBox(height: m.hauteurSerree ? 20 : 26),
            AuthActionButton(label: l10n.forgotBoutonEnvoyer, enCours: state.enCours, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

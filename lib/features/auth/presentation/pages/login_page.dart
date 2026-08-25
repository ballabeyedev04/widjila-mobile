import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/routes/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../l10n/l10n_extension.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import '../widgets/auth_chrome.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _identifiantCtrl = TextEditingController();
  final _motDePasseCtrl = TextEditingController();
  bool _motDePasseVisible = false;

  /// Verrou synchrone anti double-tap — voir le commentaire équivalent dans
  /// `register_page.dart`.
  bool _envoiEnCours = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Décode les images avant le premier rendu : sans cela, l'écran s'affiche
    // une fraction de seconde en noir avant que le fond n'apparaisse.
    precacheImage(const AssetImage(authBackgroundImage), context);
    precacheImage(const AssetImage(authLogoImage), context);
  }

  @override
  void dispose() {
    _identifiantCtrl.dispose();
    _motDePasseCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_envoiEnCours) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    _envoiEnCours = true;
    context.read<AuthBloc>().add(AuthLoginRequested(
          identifiant: _identifiantCtrl.text.trim(),
          motDePasse: _motDePasseCtrl.text,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Fond sombre en haut de l'écran → icônes de la barre d'état en clair.
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        // `resizeToAvoidBottomInset` reste à true (défaut) : le corps se
        // réduit à l'ouverture du clavier, donc le viewport du
        // SingleChildScrollView aussi — c'est ce qui permet à Flutter de
        // faire défiler automatiquement jusqu'au champ qui prend le focus.
        // Le cadrage de la photo est préservé autrement (voir AuthBackdrop).
        body: BlocConsumer<AuthBloc, AuthState>(
          listener: (context, state) {
            if (!state.enCours) _envoiEnCours = false;
            if (state.erreur != null && state.status != AuthStatus.mfaRequis) {
              AppAlert.error(context, message: state.erreur!);
            }
          },
          builder: (context, state) {
            return AuthBackdrop(
              contenu: (context, m) => m.deuxColonnes
                  ? _dispositionRangee(m, state)
                  : _dispositionColonne(m, state),
            );
          },
        ),
      ),
    );
  }

  /// Disposition verticale — téléphones (portrait) et tablettes en portrait :
  /// la marque surmonte le formulaire.
  Widget _dispositionColonne(AuthMesures m, AuthState state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AuthMarque(hauteurLogo: m.hauteurLogo),
        SizedBox(height: m.espaceMarqueCarte),
        _carte(m, state),
        const SizedBox(height: 20),
        _piedDePage(),
      ],
    );
  }

  /// Disposition en deux colonnes — écrans larges en paysage (tablette posée
  /// à l'horizontale, téléphone tourné).
  ///
  /// Ce n'est pas cosmétique : en paysage, la hauteur utile tombe sous la
  /// taille du bloc marque + formulaire, et la disposition verticale impose
  /// alors de faire défiler l'écran pour atteindre le bouton. Réparties sur
  /// deux colonnes, marque et formulaire tiennent sans défilement.
  Widget _dispositionRangee(AuthMesures m, AuthState state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AuthMarque(hauteurLogo: m.hauteurLogo),
              if (!m.hauteurSerree) ...[
                const SizedBox(height: 28),
                Text(
                  context.l10n.loginHeroTitre,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.25,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  context.l10n.loginHeroSousTitre,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.45,
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 44),
        SizedBox(
          width: m.largeurCarteEnRangee,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _carte(m, state),
              const SizedBox(height: 18),
              _piedDePage(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _carte(AuthMesures m, AuthState state) {
    final l10n = context.l10n;
    return AuthGlassCard(
      mesures: m,
      child: Form(
        key: _formKey,
        child: Column(
          // `stretch` : les enfants occupent toute la largeur de la carte —
          // c'est ce qui permet à l'en-tête d'être réellement centré (un Text
          // calé à gauche se contente de sa largeur intrinsèque, où
          // `textAlign` n'a aucun effet visible).
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AuthCardHeader(
              titre: l10n.authSeConnecter,
              // Pas de retour à la ligne forcé : la coupure dépend de la
              // largeur de l'écran, un « \n » y créait une ligne orpheline.
              sousTitre: l10n.loginSousTitre,
              mesures: m,
            ),
            SizedBox(height: m.hauteurSerree ? 20 : 28),
            TextFormField(
              controller: _identifiantCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              style: authFieldTextStyle,
              cursorColor: AppColors.primaryLight,
              decoration: authFieldDecoration(
                label: l10n.loginChampIdentifiant,
                icone: Icons.person_outline_rounded,
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? l10n.loginIdentifiantRequis : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _motDePasseCtrl,
              obscureText: !_motDePasseVisible,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _submit(),
              style: authFieldTextStyle,
              cursorColor: AppColors.primaryLight,
              decoration: authFieldDecoration(
                label: l10n.authChampMotDePasse,
                icone: Icons.lock_outline_rounded,
                suffixe: IconButton(
                  icon: Icon(
                    _motDePasseVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 20,
                    color: Colors.white.withValues(alpha: 0.70),
                  ),
                  tooltip: _motDePasseVisible ? l10n.authMasquerMotDePasse : l10n.authAfficherMotDePasse,
                  onPressed: () => setState(() => _motDePasseVisible = !_motDePasseVisible),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? l10n.authMotDePasseRequis : null,
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context.push(AppRoutes.forgotPassword),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white.withValues(alpha: 0.88),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  l10n.loginMotDePasseOublie,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                ),
              ),
            ),
            const SizedBox(height: 20),
            AuthActionButton(label: l10n.authSeConnecter, enCours: state.enCours, onPressed: _submit),
          ],
        ),
      ),
    );
  }

  Widget _piedDePage() {
    final l10n = context.l10n;
    return AuthFooterLink(
      question: l10n.loginPasEncoreDeCompte,
      action: l10n.authCreerUnCompte,
      onPressed: () => context.push(AppRoutes.register),
    );
  }
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/env.dart';
import '../../../../core/routes/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../injection_container.dart';
import '../../../referentiel/domain/entities/pays.dart';
import '../../../referentiel/presentation/cubit/pays_cubit.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/l10n_extension.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import '../widgets/auth_chrome.dart';

// ── Règles de validation — MIROIR EXACT des contraintes Joi du backend ──────
// (`backend/src/modules/auth/validation/auth.validation.js#registerSchema`
// et `backend/src/validations/common.js`). Toute divergence ici fait
// accepter côté mobile une saisie que le serveur rejettera ensuite en 400,
// ou au contraire bloque localement une saisie que le serveur accepterait.
final _regexTelephone = RegExp(r'^\+?[0-9\s\-\.]{7,20}$');
// Email : voir `authRegexEmail`/`authValidateurEmail` dans `auth_chrome.dart`
// — partagés par tous les écrans d'authentification.
// (?=.*[a-z])(?=.*[A-Z])(?=.*\d) — minuscule, majuscule, chiffre. Le backend
// n'exige PAS de caractère spécial ; en exiger un côté mobile bloquerait une
// saisie que le serveur accepterait.
final _regexMotDePasse = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)');

List<String> _libellesEtapes(AppLocalizations l10n) => [l10n.registerEtapeInfos, l10n.registerEtapeOrganisation];

/// Inscription en deux étapes (« Vos informations » puis « Votre
/// organisation ») plutôt qu'un unique formulaire de 16 champs à faire
/// défiler — chaque étape ne valide que ses propres champs (formulaires
/// distincts), les valeurs déjà saisies restent en mémoire d'une étape à
/// l'autre puisque les contrôleurs vivent dans ce State, pas dans les
/// widgets `Form` (retirés/recréés à chaque changement d'étape).
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKeyEtape1 = GlobalKey<FormState>();
  final _formKeyEtape2 = GlobalKey<FormState>();
  int _etape = 0;

  // ── Utilisateur (étape 1) ──
  final _prenomCtrl = TextEditingController();
  final _nomCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telephoneCtrl = TextEditingController();
  final _fonctionCtrl = TextEditingController();
  final _motDePasseCtrl = TextEditingController();
  final _confirmMotDePasseCtrl = TextEditingController();

  // ── Organisation (étape 2 — créée avec le compte : voir
  //    AuthService.register côté backend, l'inscription crée TOUJOURS
  //    l'organisation et son premier utilisateur en devient l'administrateur ;
  //    il n'existe pas de parcours « rejoindre une organisation existante »
  //    via cet endpoint) ──
  final _organisationNomCtrl = TextEditingController();
  final _raisonSocialeCtrl = TextEditingController();
  /// Un contrôleur par identifiant, créé à la volée selon le pays choisi.
  ///
  /// Trois champs figés (SIRET, RCCM, NINEA) ne pouvaient pas couvrir quatre
  /// pays : le Mali a un NIF, la Côte d'Ivoire un NCC et un IDU. La carte est
  /// indexée par la clé attendue par le serveur.
  final Map<String, TextEditingController> _identifiantsCtrl = {};

  /// Catalogue des pays, chargé depuis l'API — voir [PaysCubit].
  late final PaysCubit _paysCubit = sl<PaysCubit>()..charger();
  final _organisationTelephoneCtrl = TextEditingController();
  final _organisationEmailCtrl = TextEditingController();
  final _organisationAdresseCtrl = TextEditingController();
  final _organisationVilleCtrl = TextEditingController();
  /// Aucun pays présélectionné : forcer « France » ferait passer des
  /// inscriptions sous un pays que l'utilisateur n'a jamais choisi, et
  /// afficherait d'emblée des champs qui ne le concernent peut-être pas.

  bool _motDePasseVisible = false;
  bool _confirmMotDePasseVisible = false;

  /// RGPD art. 7 — consentement explicite, actif et bloquant (miroir de
  /// `admin/src/pages/auth/Register.jsx`). Champ purement client : aucune
  /// colonne ne l'accueille côté backend, donc jamais transmis dans
  /// [AuthRegisterRequested] — voir le commentaire équivalent côté web.
  bool _consentement = false;
  bool _consentementTente = false;

  /// Verrou synchrone anti double-tap — posé AU MOMENT du tap, avant tout
  /// aller-retour avec le bloc. `state.enCours` (déjà utilisé pour désactiver
  /// visuellement le bouton) ne suffit pas seul : entre le tap et le premier
  /// état émis par le bloc, il reste une fenêtre où un second tap peut encore
  /// passer, ce qui pouvait déclencher deux inscriptions concurrentes.
  bool _envoiEnCours = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage(authBackgroundImage), context);
    precacheImage(const AssetImage(authLogoImage), context);
  }

  @override
  void dispose() {
    for (final c in [
      _prenomCtrl, _nomCtrl, _emailCtrl, _telephoneCtrl, _fonctionCtrl,
      _motDePasseCtrl, _confirmMotDePasseCtrl,
      _organisationNomCtrl, _raisonSocialeCtrl,
      _organisationTelephoneCtrl, _organisationEmailCtrl, _organisationAdresseCtrl,
      _organisationVilleCtrl,
      // Les contrôleurs d'identifiants sont créés à la volée selon le pays :
      // les oublier ici laisserait fuir un objet par champ affiché.
      ..._identifiantsCtrl.values,
    ]) {
      c.dispose();
    }
    _paysCubit.close();
    super.dispose();
  }

  String? _videSi(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  /// Champ Pays — première question du formulaire d'entreprise.
  Widget _champPays(AppLocalizations l10n) {
    return BlocBuilder<PaysCubit, PaysState>(
      bloc: _paysCubit,
      builder: (context, etat) {
        final choisi = etat.choisi;

        return TextFormField(
          key: ValueKey(etat.codeChoisi),
          // `initialValue` et non un contrôleur : la valeur est entièrement
          // dérivée de l'état du cubit, un contrôleur ferait doublon.
          initialValue: choisi?.nom ?? '',
          readOnly: true,
          showCursor: false,
          onTap: etat.items.isEmpty ? null : _choisirPays,
          style: authFieldTextStyle,
          decoration: authFieldDecoration(
            label: l10n.registerChampPays,
            icone: Icons.public_outlined,
            suffixe: Icon(
              Icons.arrow_drop_down_rounded,
              color: Colors.white.withValues(alpha: 0.70),
            ),
          ).copyWith(
            prefixIcon: choisi != null
                ? SizedBox(
                    width: 48,
                    child: Center(
                      child: Text(choisi.drapeau, style: const TextStyle(fontSize: 22)),
                    ),
                  )
                : null,
          ),
          // Le pays est OBLIGATOIRE : sans lui, aucun identifiant n'est
          // proposé et le serveur ne saurait pas lesquels vérifier.
          validator: (_) => etat.codeChoisi == null ? l10n.registerPaysRequis : null,
        );
      },
    );
  }

  /// Champs d'identification du pays choisi, deux par ligne.
  ///
  /// Rien tant qu'aucun pays n'est sélectionné : afficher des champs avant
  /// de savoir lesquels s'appliquent est précisément ce qu'on corrige.
  List<Widget> _champsIdentification(AppLocalizations l10n) {
    final champs = _paysCubit.state.champs;
    if (champs.isEmpty) return const [];

    final widgets = <Widget>[];
    for (var i = 0; i < champs.length; i += 2) {
      final paire = champs.skip(i).take(2).toList();
      widgets
        ..add(const SizedBox(height: 14))
        ..add(AuthFieldRow(
          children: [
            for (final champ in paire) _champIdentifiant(champ, l10n),
            // `AuthFieldRow` attend deux enfants : un champ seul en dernière
            // ligne serait sinon étiré sur toute la largeur, en rupture avec
            // le reste du formulaire.
            if (paire.length == 1) const SizedBox.shrink(),
          ],
        ));
    }
    return widgets;
  }

  Widget _champIdentifiant(ChampIdentification champ, AppLocalizations l10n) {
    return TextFormField(
      controller: _identifiantsCtrl[champ.cle],
      textInputAction: TextInputAction.next,
      style: authFieldTextStyle,
      cursorColor: AppColors.primaryLight,
      maxLength: 50,
      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
      decoration: authFieldDecoration(
        label: champ.libelle,
        icone: Icons.pin_outlined,
      ).copyWith(
        // L'aide dit à quoi correspond le sigle : « NINEA » seul ne parle
        // qu'à ceux qui le connaissent déjà.
        helperText: champ.aide,
        helperMaxLines: 2,
        helperStyle: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.55)),
      ),
      validator: (v) {
        // Aucun identifiant n'est obligatoire : une entreprise en cours
        // d'immatriculation n'a pas encore ses numéros.
        if ((v ?? '').trim().isEmpty) return null;
        return champ.valide(v) ? null : l10n.registerIdentifiantInvalide(champ.aide);
      },
    );
  }

  void _etapeSuivante() {
    FocusScope.of(context).unfocus();
    if (!_formKeyEtape1.currentState!.validate()) return;
    setState(() => _etape = 1);
  }

  void _etapePrecedente() {
    FocusScope.of(context).unfocus();
    setState(() => _etape = 0);
  }

  void _submit() {
    if (_envoiEnCours) return;
    FocusScope.of(context).unfocus();
    setState(() => _consentementTente = true);
    final formValide = _formKeyEtape2.currentState!.validate();
    if (!formValide || !_consentement) return;

    _envoiEnCours = true;
    context.read<AuthBloc>().add(AuthRegisterRequested(
          nom: _nomCtrl.text.trim(),
          prenom: _prenomCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          motDePasse: _motDePasseCtrl.text,
          telephone: _videSi(_telephoneCtrl),
          fonction: _videSi(_fonctionCtrl),
          organisationNom: _organisationNomCtrl.text.trim(),
          raisonSociale: _videSi(_raisonSocialeCtrl),
          // Seuls les identifiants du pays choisi sont envoyés : le
          // serveur REFUSE ceux qui n'ont pas de sens pour ce pays.
          identifiants: {
            for (final e in _identifiantsCtrl.entries)
              if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
          },
          organisationTelephone: _videSi(_organisationTelephoneCtrl),
          organisationEmail: _videSi(_organisationEmailCtrl),
          organisationAdresse: _videSi(_organisationAdresseCtrl),
          organisationVille: _videSi(_organisationVilleCtrl),
          // Code ISO, jamais le libellé : c'est ce que le serveur valide.
          organisationPays: _paysCubit.state.codeChoisi,
        ));
  }

  /// Sélecteur de pays — limité aux pays RÉELLEMENT couverts.
  ///
  /// L'ancien sélecteur en proposait environ 250, alors que le serveur n'en
  /// accepte que quatre : choisir la Belgique menait à un refus que rien à
  /// l'écran n'avait laissé prévoir. Quatre entrées tiennent dans une feuille,
  /// sans champ de recherche.
  void _choisirPays() {
    final pays = _paysCubit.state.items;
    if (pays.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (feuille) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Container(
              width: 42, height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 18),
            for (final p in pays)
              ListTile(
                leading: Text(p.drapeau, style: const TextStyle(fontSize: 26)),
                title: Text(
                  p.nom,
                  style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  // Les identifiants attendus, annoncés AVANT le choix :
                  // l'utilisateur sait ce qu'on va lui demander.
                  p.champs.map((c) => c.libelle).join(' · '),
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                trailing: _paysCubit.state.codeChoisi == p.code
                    ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                    : null,
                onTap: () {
                  _choisirCode(p);
                  Navigator.of(feuille).pop();
                },
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  /// Applique le pays choisi et reconstruit les champs d'identification.
  ///
  /// Les contrôleurs des champs qui DISPARAISSENT sont libérés : garder la
  /// saisie d'un NINEA après un passage en France l'aurait envoyée au serveur,
  /// qui l'aurait refusée — pour une valeur devenue invisible à l'écran.
  void _choisirCode(Pays pays) {
    setState(() {
      _paysCubit.choisir(pays.code);

      final cles = pays.champs.map((c) => c.cle).toSet();
      for (final cle in _identifiantsCtrl.keys.toList()) {
        if (!cles.contains(cle)) _identifiantsCtrl.remove(cle)!.dispose();
      }
      for (final champ in pays.champs) {
        _identifiantsCtrl.putIfAbsent(champ.cle, TextEditingController.new);
      }
    });
  }

  Future<void> _ouvrirLien(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        AppAlert.error(context, message: context.l10n.registerLienEchec);
      }
    }
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

            // `else if` plutôt que deux `if` indépendants : un seul de ces
            // deux messages a un sens pour un même état émis, jamais les
            // deux — évite qu'une incohérence d'état ouvre le popup de
            // succès (et sa navigation vers /login) juste après celui
            // d'erreur.
            if (state.erreur != null) {
              AppAlert.error(context, message: state.erreur!);
            } else if (state.messageSucces != null) {
              // Navigation reportée à la fermeture du popup (bouton OK) —
              // partir vers /login pendant que la boîte de dialogue est
              // encore affichée la ferait disparaître de façon abrupte.
              AppAlert.success(context, message: state.messageSucces!).then((_) {
                if (context.mounted) context.go(AppRoutes.login);
              });
            }
          },
          builder: (context, state) {
            // Toujours en une seule colonne verticale (la marque au-dessus de
            // la carte) : avec deux étapes courtes, une disposition en deux
            // colonnes façon connexion n'apporterait rien. Seule la LARGEUR
            // de la carte s'élargit sur tablette (les couples de champs
            // passent alors sur une même ligne, voir [AuthFieldRow]).
            return AuthBackdrop(
              largeurCompacte: 460,
              largeurTablette: 560,
              largeurDeuxColonnes: 620,
              contenu: (context, m) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AuthMarque(hauteurLogo: m.hauteurLogo * 0.82),
                  SizedBox(height: m.espaceMarqueCarte),
                  _carte(m, state),
                  const SizedBox(height: 20),
                  AuthFooterLink(
                    question: context.l10n.registerDejaUnCompte,
                    action: context.l10n.authSeConnecter,
                    onPressed: () => context.go(AppRoutes.login),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthCardHeader(
            titre: l10n.authCreerUnCompte,
            sousTitre: _etape == 0 ? l10n.registerSousTitreEtape1 : l10n.registerSousTitreEtape2,
            mesures: m,
          ),
          SizedBox(height: m.hauteurSerree ? 16 : 22),
          AuthStepIndicator(etapeCourante: _etape, libelles: _libellesEtapes(l10n)),
          SizedBox(height: m.hauteurSerree ? 18 : 26),

          // `AnimatedSwitcher` : transition douce entre étapes. Les
          // contrôleurs ne sont PAS recréés (ils vivent dans ce State), donc
          // aucune saisie n'est perdue quand un `Form` quitte l'arbre.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: Offset(_etape == 0 ? -0.05 : 0.05, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            // `AnimatedSwitcher` détecte le changement via la clé du widget
            // enfant DIRECT (ici, celle du `Form` — `_formKeyEtape1` /
            // `_formKeyEtape2`, déjà uniques et stables), pas besoin d'une
            // clé supplémentaire à l'intérieur.
            child: _etape == 0 ? _etapeInformations() : _etapeOrganisation(m, state),
          ),
        ],
      ),
    );
  }

  Widget _etapeInformations() {
    final l10n = context.l10n;
    return Form(
      key: _formKeyEtape1,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthFieldRow(children: [
            TextFormField(
              controller: _prenomCtrl,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              style: authFieldTextStyle,
              cursorColor: AppColors.primaryLight,
              decoration: authFieldDecoration(label: l10n.registerChampPrenom, icone: Icons.badge_outlined),
              validator: (v) {
                final val = (v ?? '').trim();
                if (val.isEmpty) return l10n.registerPrenomRequis;
                if (val.length < 2) return l10n.commonMin2Caracteres;
                if (val.length > 50) return l10n.commonMax50Caracteres;
                return null;
              },
            ),
            TextFormField(
              controller: _nomCtrl,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              style: authFieldTextStyle,
              cursorColor: AppColors.primaryLight,
              decoration: authFieldDecoration(label: l10n.registerChampNom, icone: Icons.badge_outlined),
              validator: (v) {
                final val = (v ?? '').trim();
                if (val.isEmpty) return l10n.registerNomRequis;
                if (val.length < 2) return l10n.commonMin2Caracteres;
                if (val.length > 50) return l10n.commonMax50Caracteres;
                return null;
              },
            ),
          ]),
          const SizedBox(height: 14),
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
          const SizedBox(height: 14),
          AuthFieldRow(children: [
            TextFormField(
              controller: _telephoneCtrl,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              style: authFieldTextStyle,
              cursorColor: AppColors.primaryLight,
              decoration: authFieldDecoration(label: l10n.registerChampTelephoneOpt, icone: Icons.phone_outlined),
              validator: (v) {
                final val = (v ?? '').trim();
                if (val.isEmpty) return null;
                return _regexTelephone.hasMatch(val) ? null : l10n.commonNumeroInvalide;
              },
            ),
            TextFormField(
              controller: _fonctionCtrl,
              textInputAction: TextInputAction.next,
              style: authFieldTextStyle,
              cursorColor: AppColors.primaryLight,
              decoration: authFieldDecoration(label: l10n.registerChampFonctionOpt, icone: Icons.work_outline_rounded),
              maxLength: 100,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
            ),
          ]),
          const SizedBox(height: 14),
          TextFormField(
            controller: _motDePasseCtrl,
            obscureText: !_motDePasseVisible,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            style: authFieldTextStyle,
            cursorColor: AppColors.primaryLight,
            decoration: authFieldDecoration(
              label: l10n.authChampMotDePasse,
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
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirmMotDePasseCtrl,
            obscureText: !_confirmMotDePasseVisible,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _etapeSuivante(),
            style: authFieldTextStyle,
            cursorColor: AppColors.primaryLight,
            decoration: authFieldDecoration(
              label: l10n.registerChampConfirmerMotDePasse,
              icone: Icons.lock_outline_rounded,
              suffixe: IconButton(
                icon: Icon(
                  _confirmMotDePasseVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20,
                  color: Colors.white.withValues(alpha: 0.70),
                ),
                onPressed: () => setState(() => _confirmMotDePasseVisible = !_confirmMotDePasseVisible),
              ),
            ),
            validator: (v) {
              if ((v ?? '').isEmpty) return l10n.registerConfirmezMotDePasse;
              return v == _motDePasseCtrl.text ? null : l10n.registerMotsDePasseDiff;
            },
          ),
          const SizedBox(height: 22),
          AuthActionButton(label: l10n.commonNext, enCours: false, onPressed: _etapeSuivante),
        ],
      ),
    );
  }

  Widget _etapeOrganisation(AuthMesures m, AuthState state) {
    final l10n = context.l10n;
    return Form(
      key: _formKeyEtape2,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.registerAdminNotice,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.70), fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _organisationNomCtrl,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            style: authFieldTextStyle,
            cursorColor: AppColors.primaryLight,
            decoration: authFieldDecoration(label: l10n.registerChampNomOrg, icone: Icons.apartment_outlined),
            validator: (v) {
              final val = (v ?? '').trim();
              if (val.isEmpty) return l10n.registerNomOrgRequis;
              if (val.length < 2) return l10n.commonMin2Caracteres;
              if (val.length > 150) return l10n.commonMax150Caracteres;
              return null;
            },
          ),
          const SizedBox(height: 14),
          // ── Le PAYS d'abord ──────────────────────────────────────────
          //
          // Il commande les identifiants demandés plus bas : le placer après
          // eux obligeait l'utilisateur à ressaisir, et laissait afficher des
          // champs sans rapport avec son pays.
          _champPays(l10n),
          const SizedBox(height: 14),
          TextFormField(
            controller: _raisonSocialeCtrl,
            textInputAction: TextInputAction.next,
            style: authFieldTextStyle,
            cursorColor: AppColors.primaryLight,
            decoration: authFieldDecoration(label: l10n.registerChampRaisonSociale, icone: Icons.apartment_outlined),
            maxLength: 255,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
          ),
          // ── Identifiants d'entreprise, selon le PAYS ────────────────
          //
          // Construits d'après le catalogue servi par l'API : ni SIRET pour
          // une entreprise sénégalaise, ni NINEA pour une française. Deux par
          // ligne, comme le reste du formulaire.
          ..._champsIdentification(l10n),

          const SizedBox(height: 14),
          AuthFieldRow(children: [
            TextFormField(
              controller: _organisationTelephoneCtrl,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              style: authFieldTextStyle,
              cursorColor: AppColors.primaryLight,
              decoration: authFieldDecoration(label: l10n.registerChampTelephoneOpt, icone: Icons.phone_outlined),
              validator: (v) {
                final val = (v ?? '').trim();
                if (val.isEmpty) return null;
                return _regexTelephone.hasMatch(val) ? null : l10n.commonNumeroInvalide;
              },
            ),
          ]),
          const SizedBox(height: 14),
          TextFormField(
            controller: _organisationEmailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            style: authFieldTextStyle,
            cursorColor: AppColors.primaryLight,
            decoration: authFieldDecoration(
              label: l10n.registerChampEmailOrg,
              icone: Icons.mail_outline_rounded,
            ),
            maxLength: authEmailLongueurMax,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
            validator: (v) => authValidateurEmail(l10n, v, requis: false),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _organisationAdresseCtrl,
            textInputAction: TextInputAction.next,
            style: authFieldTextStyle,
            cursorColor: AppColors.primaryLight,
            decoration: authFieldDecoration(label: l10n.registerChampAdresse, icone: Icons.place_outlined),
            maxLength: 200,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
          ),
          const SizedBox(height: 14),
          AuthFieldRow(children: [
            TextFormField(
              controller: _organisationVilleCtrl,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              style: authFieldTextStyle,
              cursorColor: AppColors.primaryLight,
              decoration: authFieldDecoration(label: l10n.registerChampVille, icone: Icons.location_city_outlined),
              maxLength: 100,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
            ),
          ]),

          SizedBox(height: m.hauteurSerree ? 18 : 24),
          _consentementCheckbox(),

          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                flex: 4,
                child: AuthSecondaryButton(label: l10n.commonPrevious, onPressed: _etapePrecedente),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 6,
                child: AuthActionButton(
                  label: l10n.registerBoutonCreerCompte,
                  icone: Icons.check_rounded,
                  enCours: state.enCours,
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// RGPD art. 7 : consentement explicite, actif (décoché par défaut) et
  /// bloquant. Les liens ouvrent les pages légales de l'admin web dans le
  /// navigateur (aucune vue native équivalente côté mobile) — voir
  /// `Env.cguUrl` / `Env.politiqueConfidentialiteUrl`.
  Widget _consentementCheckbox() {
    final l10n = context.l10n;
    final enErreur = _consentementTente && !_consentement;
    final styleTexte = TextStyle(color: Colors.white.withValues(alpha: 0.80), fontSize: 12.5, height: 1.5);
    final styleLien = const TextStyle(
      color: AppColors.accentLight,
      fontSize: 12.5,
      height: 1.5,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.accentLight,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: _consentement,
                  onChanged: (v) => setState(() => _consentement = v ?? false),
                  fillColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? AppColors.primary
                        : Colors.white.withValues(alpha: 0.12),
                  ),
                  side: BorderSide(
                    color: enErreur ? authDangerColor : Colors.white.withValues(alpha: 0.55),
                    width: 1.4,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: styleTexte,
                  children: [
                    TextSpan(text: l10n.registerConsentementPrefix),
                    TextSpan(
                      text: l10n.registerConditionsUtilisation,
                      style: styleLien,
                      recognizer: TapGestureRecognizer()..onTap = () => _ouvrirLien(Env.cguUrl),
                    ),
                    TextSpan(text: l10n.registerConsentementEt),
                    TextSpan(
                      text: l10n.registerPolitiqueConfidentialite,
                      style: styleLien,
                      recognizer: TapGestureRecognizer()..onTap = () => _ouvrirLien(Env.politiqueConfidentialiteUrl),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (enErreur)
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 6),
            child: Text(
              l10n.registerConsentementErreur,
              style: TextStyle(color: authDangerColor, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/env.dart';
import '../../../../core/offline/base_locale.dart';
import '../../../../core/offline/cache_chantiers.dart';
import '../../../../core/offline/cache_reserves.dart';
import '../../../../core/services/locale_controller.dart';
import '../../../../core/services/verrou_biometrique.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../domain/entities/connexion_log_entry.dart';
import '../../domain/entities/session_active.dart';
import '../cubit/settings_cubit.dart';
import '../widgets/section_notifications.dart';
import 'changer_mot_de_passe_sheet.dart';
import '../cubit/settings_state.dart';
import '../widgets/mfa_setup_sheet.dart';

/// Écran Paramètres — accessible depuis le menu de compte
/// (`_MenuCompte` de `DashboardPage`), à côté de « Mon profil ».
///
/// Regroupe : la langue de l'application (déclencheur historique de tout le
/// chantier i18n — voir `LocaleController`), la sécurité (MFA, sessions,
/// historique de connexion), le stockage hors ligne local, et les droits
/// RGPD (export, suppression de compte).
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<SettingsCubit>()..charger(),
      child: const _SettingsView(),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      // Blanc, comme les autres écrans. Le CONTENU repose sur le gris de fond.
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Écran de la coquille : la cloche y trouve bien son cubit.
            ContenuCentre(child: EnTeteListe(titre: l10n.settingsTitre, avecRetour: true)),
            Expanded(
              child: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          return ColoredBox(
            color: AppColors.background,
            child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => context.read<SettingsCubit>().charger(),
            child: ContenuCentre(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                children: [
                  const _SectionLangue(),
                  const SizedBox(height: 20),
                  _SectionCard(
                    titre: l10n.settingsSectionNotifications,
                    children: const [SectionNotifications()],
                  ),
                  const SizedBox(height: 20),
                  _SectionSecurite(state: state),
                  const SizedBox(height: 20),
                  const _SectionStockage(),
                  const SizedBox(height: 20),
                  _SectionRgpd(state: state),
                  const SizedBox(height: 20),
                  const _SectionAPropos(),
                ],
              ),
            ),
            ),
          );
        },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte de section — même apparat (fond blanc, coins 18, titre) pour les
/// cinq sections de l'écran.
class _SectionCard extends StatelessWidget {
  final String titre;
  final String? description;
  final List<Widget> children;

  const _SectionCard({required this.titre, this.description, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titre, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(description!, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4)),
          ],
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

// ═══════════════════════════════════ LANGUE ═══════════════════════════════

class _SectionLangue extends StatelessWidget {
  const _SectionLangue();

  static const _langues = ['fr', 'en', 'de', 'es'];

  String _libelle(AppLocalizations l10n, String code) => switch (code) {
        'fr' => l10n.settingsLangueFr,
        'en' => l10n.settingsLangueEn,
        'de' => l10n.settingsLangueDe,
        _ => l10n.settingsLangueEs,
      };

  Future<void> _choisir(BuildContext context, String code) async {
    final localeController = sl<LocaleController>();
    if (localeController.value.languageCode == code) return;

    await localeController.changer(code);
    if (!context.mounted) return;
    final cubit = context.read<SettingsCubit>();
    final ok = await cubit.changerLangue(code);
    if (!context.mounted) return;

    if (ok) {
      final auth = context.read<AuthBloc>();
      final user = auth.state.utilisateur;
      if (user != null) auth.add(AuthUserUpdated(user.copyWith(langue: code)));
    } else {
      AppAlert.error(context, message: context.l10n.settingsLangueErreur);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _SectionCard(
      titre: l10n.settingsSectionLangue,
      description: l10n.settingsLangueDescription,
      children: [
        ValueListenableBuilder<Locale>(
          valueListenable: sl<LocaleController>(),
          builder: (context, locale, _) {
            return Column(
              children: [
                for (final code in _langues)
                  RadioListTile<String>(
                    value: code,
                    // ignore: deprecated_member_use
                    groupValue: locale.languageCode,
                    // ignore: deprecated_member_use
                    onChanged: (v) => v == null ? null : _choisir(context, v),
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.primary,
                    title: Text(_libelle(l10n, code), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ═══════════════════════════════════ SÉCURITÉ ═════════════════════════════

class _SectionSecurite extends StatelessWidget {
  final SettingsState state;
  const _SectionSecurite({required this.state});

  Future<void> _basculerMfa(BuildContext context, bool active) async {
    if (active) {
      await ouvrirProvisionnementMfa(context);
      return;
    }
    final l10n = context.l10n;
    final codeCtrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l10n.settingsMfaDesactiverTitre),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settingsMfaDesactiverDescription, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            TextField(
              controller: codeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              autofocus: true,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 5),
              decoration: InputDecoration(labelText: l10n.settingsMfaCodeLabel, counterText: ''),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(l10n.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(codeCtrl.text.trim()),
            child: Text(l10n.settingsMfaDesactiverBouton),
          ),
        ],
      ),
    );
    codeCtrl.dispose();
    if (code == null || code.length != 6 || !context.mounted) return;
    await context.read<SettingsCubit>().desactiverMfa(code);
  }

  Future<void> _revoquer(BuildContext context, String sessionId) =>
      context.read<SettingsCubit>().revoquerSession(sessionId);

  Future<void> _revoquerTout(BuildContext context) async {
    final l10n = context.l10n;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.settingsSessionRevoquerToutConfirmTitre),
        content: Text(l10n.settingsSessionRevoquerToutConfirmMessage),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.settingsSessionRevoquerTout),
          ),
        ],
      ),
    );
    if (confirme != true || !context.mounted) return;
    final ok = await context.read<SettingsCubit>().revoquerToutesSessions();
    if (ok && context.mounted) {
      context.read<AuthBloc>().add(const AuthLogoutRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocListener<SettingsCubit, SettingsState>(
      listenWhen: (a, b) => a.mfaActionStatus != b.mfaActionStatus || a.sessionActionStatus != b.sessionActionStatus,
      listener: (context, s) {
        if (s.mfaActionStatus == ActionStatus.succes && !s.mfaActive) {
          AppAlert.success(context, message: l10n.settingsMfaDesactiveeMessage);
          context.read<SettingsCubit>().accuserReceptionMfa();
        } else if (s.mfaActionStatus == ActionStatus.erreur && s.mfaErreur != null) {
          AppAlert.error(context, message: s.mfaErreur!);
        }
        if (s.sessionActionStatus == ActionStatus.erreur && s.sessionErreur != null) {
          AppAlert.error(context, message: s.sessionErreur!);
        }
      },
      child: _SectionCard(
        titre: l10n.settingsSectionSecurite,
        children: [
          const _LigneMotDePasse(),
          const Divider(height: 24),
          const _LigneBiometrie(),
          const Divider(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: state.mfaActive,
            activeTrackColor: AppColors.primary,
            onChanged: (v) => _basculerMfa(context, v),
            title: Text(l10n.settingsMfaTitre, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            subtitle: Text(
              state.mfaActive ? l10n.settingsMfaActif : l10n.settingsMfaInactif,
              style: TextStyle(fontSize: 12.5, color: state.mfaActive ? AppColors.success : AppColors.textSecondary),
            ),
          ),
          const Divider(height: 24),
          Text(l10n.settingsSessionsTitre, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (state.sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(l10n.settingsSessionsAucune, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            )
          else
            for (final session in state.sessions) _LigneSession(session: session, onRevoquer: () => _revoquer(context, session.id)),
          if (state.sessions.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _revoquerTout(context),
              icon: const Icon(Icons.logout_rounded, size: 17, color: AppColors.danger),
              label: Text(l10n.settingsSessionRevoquerTout, style: const TextStyle(fontSize: 12.5, color: AppColors.danger)),
            ),
          ],
          const Divider(height: 24),
          Text(l10n.settingsConnexionsTitre, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (state.connexions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(l10n.settingsConnexionsAucune, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            )
          else
            for (final entree in state.connexions.take(10)) _LigneConnexion(entree: entree),
        ],
      ),
    );
  }
}

/// Entrée « Mot de passe » — en TÊTE de la section Sécurité.
///
/// Placée avant le MFA volontairement : c'est l'action la plus courante, et
/// surtout la seule qui solde un mot de passe provisoire. Elle manquait
/// entièrement à l'application, alors que `PUT /account/change-password`
/// existe côté serveur depuis toujours — un membre créé avec un mot de passe
/// temporaire n'avait aucun moyen de le remplacer, sinon en passant par
/// « mot de passe oublié » et sa boucle par email.
class _LigneMotDePasse extends StatelessWidget {
  const _LigneMotDePasse();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // `mdp_temporaire` est renvoyé par le serveur dans l'utilisateur courant ;
    // `changePassword` est justement ce qui le remet à faux.
    final provisoire = context.select((AuthBloc b) => b.state.utilisateur?.mdpTemporaire ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (provisoire) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.motDePasseProvisoireAvertissement,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: () => ouvrirChangementMotDePasse(context),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: (provisoire ? AppColors.warning : AppColors.primary).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.lock_outline_rounded,
              size: 19,
              color: provisoire ? AppColors.warning : AppColors.primary,
            ),
          ),
          title: Text(
            l10n.motDePasseChangerTitre,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            l10n.motDePasseChangerDescription,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

/// Interrupteur du déverrouillage biométrique.
///
/// L'entrée est MASQUÉE quand l'appareil ne propose aucune biométrie
/// enregistrée : proposer un réglage qui échouera systématiquement est pire
/// que ne rien proposer.
class _LigneBiometrie extends StatefulWidget {
  const _LigneBiometrie();

  @override
  State<_LigneBiometrie> createState() => _LigneBiometrieState();
}

class _LigneBiometrieState extends State<_LigneBiometrie> {
  final VerrouBiometrique _verrou = sl<VerrouBiometrique>();
  bool? _disponible;

  @override
  void initState() {
    super.initState();
    _verifier();
  }

  Future<void> _verifier() async {
    final dispo = await _verrou.disponible;
    if (mounted) setState(() => _disponible = dispo);
  }

  Future<void> _basculer(bool valeur) async {
    final l10n = context.l10n;
    // Activer ET désactiver demandent la biométrie : sans quoi le verrou se
    // contournerait en deux taps sur un téléphone trouvé déverrouillé.
    final ok = await _verrou.definirActif(valeur, motif: l10n.bioInvite);
    if (!mounted) return;
    if (!ok) {
      AppAlert.error(context, message: l10n.bioEchec);
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // Vérification en cours : on n'affiche rien plutôt qu'un interrupteur qui
    // sauterait de place une fraction de seconde plus tard.
    if (_disponible == null) return const SizedBox.shrink();

    if (_disponible == false) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        enabled: false,
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.neutralBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.fingerprint_rounded, size: 19, color: AppColors.textMuted),
        ),
        title: Text(l10n.bioTitre, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        subtitle: Text(
          l10n.bioIndisponible,
          style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
        ),
      );
    }

    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: _verrou.actif,
      activeTrackColor: AppColors.primary,
      onChanged: _basculer,
      secondary: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.fingerprint_rounded, size: 19, color: AppColors.primary),
      ),
      title: Text(l10n.bioTitre, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      subtitle: Text(
        l10n.bioDescription,
        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
      ),
    );
  }
}

class _LigneSession extends StatelessWidget {
  final SessionActive session;
  final VoidCallback onRevoquer;
  const _LigneSession({required this.session, required this.onRevoquer});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final format = DateFormat('dd/MM/yyyy HH:mm');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.smartphone_rounded, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.settingsSessionOuverteLe(format.format(session.createdAt)), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text(l10n.settingsSessionExpireLe(format.format(session.expiresAt)), style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.danger),
            onPressed: onRevoquer,
            tooltip: l10n.commonDelete,
          ),
        ],
      ),
    );
  }
}

class _LigneConnexion extends StatelessWidget {
  final ConnexionLogEntry entree;
  const _LigneConnexion({required this.entree});

  String _libelleType(AppLocalizations l10n) => switch (entree.type) {
        'mfa' => l10n.settingsConnexionTypeMfa,
        'refresh' => l10n.settingsConnexionTypeRefresh,
        _ => l10n.settingsConnexionTypePassword,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final format = DateFormat('dd/MM/yyyy HH:mm');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            entree.succes ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
            size: 18,
            color: entree.succes ? AppColors.success : AppColors.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entree.succes ? l10n.settingsConnexionSucces : l10n.settingsConnexionEchec} · ${_libelleType(l10n)}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${format.format(entree.createdAt)}${entree.ip != null ? ' · ${entree.ip}' : ''}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════ STOCKAGE ═════════════════════════════

class _SectionStockage extends StatefulWidget {
  const _SectionStockage();

  @override
  State<_SectionStockage> createState() => _SectionStockageState();
}

class _SectionStockageState extends State<_SectionStockage> {
  late Future<(int, int)> _compteurs = _compter();

  Future<(int, int)> _compter() async {
    final chantiers = await sl<CacheChantiers>().listerTout();
    final reserves = await sl<CacheReserves>().listerTout();
    return (chantiers.length, reserves.length);
  }

  Future<void> _viderCache(BuildContext context) async {
    final l10n = context.l10n;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.settingsViderCacheConfirmTitre),
        content: Text(l10n.settingsViderCacheConfirmMessage),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.settingsViderCacheBouton),
          ),
        ],
      ),
    );
    if (confirme != true || !context.mounted) return;
    await sl<BaseLocale>().viderTout();
    if (!context.mounted) return;
    AppAlert.success(context, message: l10n.settingsViderCacheSucces);
    setState(() => _compteurs = _compter());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _SectionCard(
      titre: l10n.settingsSectionStockage,
      description: l10n.settingsStockageDescription,
      children: [
        FutureBuilder<(int, int)>(
          future: _compteurs,
          builder: (context, snapshot) {
            final donnees = snapshot.data;
            return Text(
              donnees == null ? '…' : l10n.settingsStockageResume(donnees.$1, donnees.$2),
              style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            );
          },
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _viderCache(context),
          icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: AppColors.danger),
          label: Text(l10n.settingsViderCacheBouton, style: const TextStyle(color: AppColors.danger)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.danger)),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════ RGPD ═════════════════════════════════

class _SectionRgpd extends StatelessWidget {
  final SettingsState state;
  const _SectionRgpd({required this.state});

  int _nombre(Map<String, dynamic>? bloc) => (bloc?['nombre'] as num?)?.toInt() ?? 0;

  Future<void> _afficherResumeExport(BuildContext context, Map<String, dynamic> donnees) async {
    final l10n = context.l10n;
    final activite = donnees['activite'] as Map<String, dynamic>?;
    final contenus = donnees['contenus'] as Map<String, dynamic>?;
    final communications = donnees['communications'] as Map<String, dynamic>?;
    final securite = donnees['securite'] as Map<String, dynamic>?;

    final lignes = <(String, int)>[
      (l10n.settingsExportReservesCreees, _nombre(activite?['reservesCreees'] as Map<String, dynamic>?)),
      (l10n.settingsExportReservesAssignees, _nombre(activite?['reservesAssignees'] as Map<String, dynamic>?)),
      (l10n.settingsExportCommentaires, _nombre(activite?['commentaires'] as Map<String, dynamic>?)),
      (l10n.settingsExportMedias, _nombre(contenus?['medias'] as Map<String, dynamic>?)),
      (l10n.settingsExportNotifications, _nombre(communications?['notifications'] as Map<String, dynamic>?)),
      (l10n.settingsExportConnexions, _nombre(securite?['connexions'] as Map<String, dynamic>?)),
    ];

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l10n.settingsExporterSucces),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settingsExporterResumeIntro, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            for (final (libelle, nombre) in lignes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(libelle, style: const TextStyle(fontSize: 13)),
                    Text('$nombre', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text(l10n.settingsExporterNote, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.4)),
          ],
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(l10n.commonOk)),
        ],
      ),
    );
  }

  Future<void> _exporter(BuildContext context) async {
    final cubit = context.read<SettingsCubit>();
    await cubit.exporterDonnees();
    if (!context.mounted) return;
    final resultat = cubit.state;
    if (resultat.exportStatus == ActionStatus.succes && resultat.exportResume != null) {
      await _afficherResumeExport(context, resultat.exportResume!);
    } else if (resultat.exportErreur != null) {
      AppAlert.error(context, message: resultat.exportErreur!);
    }
  }

  Future<void> _supprimerCompte(BuildContext context) async {
    final l10n = context.l10n;
    final motAttendu = l10n.settingsSupprimerCompteConfirmMot;
    final saisieCtrl = TextEditingController();
    final confirme = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final valide = saisieCtrl.text.trim().toUpperCase() == motAttendu;
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(l10n.settingsSupprimerCompteTitre),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.settingsSupprimerCompteDescription, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
                const SizedBox(height: 14),
                TextField(
                  controller: saisieCtrl,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(labelText: l10n.settingsSupprimerCompteConfirmHint(motAttendu)),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.commonCancel)),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: valide ? () => Navigator.of(dialogContext).pop(true) : null,
                child: Text(l10n.settingsSupprimerCompteConfirmBouton),
              ),
            ],
          );
        },
      ),
    );
    saisieCtrl.dispose();
    if (confirme != true || !context.mounted) return;

    final ok = await context.read<SettingsCubit>().supprimerCompte();
    if (ok && context.mounted) {
      context.read<AuthBloc>().add(const AuthLogoutRequested());
    } else if (context.mounted && context.read<SettingsCubit>().state.suppressionErreur != null) {
      AppAlert.error(context, message: context.read<SettingsCubit>().state.suppressionErreur!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final exportEnCours = state.exportStatus == ActionStatus.enCours;
    final suppressionEnCours = state.suppressionStatus == ActionStatus.enCours;

    return _SectionCard(
      titre: l10n.settingsSectionRgpd,
      description: l10n.settingsRgpdDescription,
      children: [
        OutlinedButton.icon(
          onPressed: exportEnCours ? null : () => _exporter(context),
          icon: exportEnCours
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download_outlined, size: 18, color: AppColors.primary),
          label: Text(l10n.settingsExporterBouton, style: const TextStyle(color: AppColors.primary)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.primary)),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: suppressionEnCours ? null : () => _supprimerCompte(context),
          icon: suppressionEnCours
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.danger))
              : const Icon(Icons.delete_forever_outlined, size: 18, color: AppColors.danger),
          label: Text(l10n.settingsSupprimerCompteBouton, style: const TextStyle(color: AppColors.danger)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.danger)),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════ À PROPOS ═════════════════════════════

class _SectionAPropos extends StatelessWidget {
  const _SectionAPropos();

  /// Même stratégie d'ouverture que `register_page.dart#_ouvrirLien` : lien
  /// externe, message d'erreur générique si l'appareil n'a pas de navigateur
  /// capable de l'ouvrir.
  Future<void> _ouvrirLien(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      AppAlert.error(context, message: context.l10n.registerLienEchec);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _SectionCard(
      titre: l10n.settingsSectionAPropos,
      children: [
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snapshot) {
            final info = snapshot.data;
            return Text(
              info == null ? '…' : l10n.settingsAProposVersion('${info.version} (${info.buildNumber})'),
              style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            );
          },
        ),
        const Divider(height: 24),
        _LigneAPropos(
          icone: Icons.description_outlined,
          titre: l10n.settingsAProposCgu,
          onTap: () => _ouvrirLien(context, Env.cguUrl),
        ),
        _LigneAPropos(
          icone: Icons.privacy_tip_outlined,
          titre: l10n.settingsAProposConfidentialite,
          onTap: () => _ouvrirLien(context, Env.politiqueConfidentialiteUrl),
        ),
        // Pas d'adresse ou d'URL de support réelle configurée pour l'instant
        // (voir `Env` — seules CGU/politique de confidentialité y figurent) :
        // affiché de façon non interactive plutôt qu'un lien mort, dans le
        // même esprit que les autres contenus différés de l'app (voir
        // `documents_list_page.dart#_ouvrirDocument`).
        _LigneAPropos(icone: Icons.support_agent_outlined, titre: l10n.settingsAProposSupport),
      ],
    );
  }
}

class _LigneAPropos extends StatelessWidget {
  final IconData icone;
  final String titre;
  final VoidCallback? onTap;
  const _LigneAPropos({required this.icone, required this.titre, this.onTap});

  @override
  Widget build(BuildContext context) {
    final contenu = Row(
      children: [
        Icon(icone, size: 18, color: AppColors.textMuted),
        const SizedBox(width: 10),
        Expanded(child: Text(titre, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        if (onTap != null)
          const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textMuted)
        else
          Text(context.l10n.settingsAProposBientotDisponible, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
      ],
    );

    if (onTap == null) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: contenu);
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: contenu),
    );
  }
}

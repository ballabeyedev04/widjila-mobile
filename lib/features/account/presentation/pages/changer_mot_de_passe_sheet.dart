import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../l10n/l10n_extension.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';

// ── Bornes MIROIR du schéma serveur ──────────────────────────────────────────
// `backend/src/validations/common.js` → `motDePasse` :
//   min(8), max(128), pattern (?=.*[a-z])(?=.*[A-Z])(?=.*\d)
//
// Les reproduire ici n'est pas décoratif : sans elles, un mot de passe trop
// faible part sur le réseau et revient en 422 — après que l'utilisateur a
// saisi trois champs, dont son mot de passe ACTUEL, qu'il devra ressaisir.
const int _minMotDePasse = 8;
const int _maxMotDePasse = 128;
final _regexMotDePasse = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)');

/// Ouvre le formulaire de changement de mot de passe.
///
/// Réutilise le [SettingsCubit] de l'écran appelant (passé par
/// `BlocProvider.value`), comme les autres feuilles de l'application.
Future<void> ouvrirChangementMotDePasse(BuildContext context) {
  final cubit = context.read<SettingsCubit>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BlocProvider.value(value: cubit, child: const _ChangerMotDePasseSheet()),
  );
}

class _ChangerMotDePasseSheet extends StatefulWidget {
  const _ChangerMotDePasseSheet();

  @override
  State<_ChangerMotDePasseSheet> createState() => _ChangerMotDePasseSheetState();
}

class _ChangerMotDePasseSheetState extends State<_ChangerMotDePasseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _ancienCtrl = TextEditingController();
  final _nouveauCtrl = TextEditingController();
  final _confirmationCtrl = TextEditingController();

  bool _ancienVisible = false;
  bool _nouveauVisible = false;

  @override
  void dispose() {
    for (final c in [_ancienCtrl, _nouveauCtrl, _confirmationCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _soumettre() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final cubit = context.read<SettingsCubit>();
    final l10n = context.l10n;
    final sessionsRevoquees = await cubit.changerMotDePasse(
      ancienMotDePasse: _ancienCtrl.text,
      nouveauMotDePasse: _nouveauCtrl.text,
    );
    if (!mounted || !context.mounted) return;

    if (sessionsRevoquees == null) {
      AppAlert.error(context, message: cubit.state.motDePasseErreur ?? l10n.commonUneErreurSurvenue);
      return;
    }

    Navigator.of(context).pop();
    // Le message dit ce qui s'est RÉELLEMENT passé : annoncer des appareils
    // déconnectés alors qu'il n'y en avait aucun inquiéterait pour rien.
    AppAlert.success(
      context,
      message: sessionsRevoquees == 0
          ? l10n.motDePasseChangeMessage
          : l10n.motDePasseChangeAvecSessions(sessionsRevoquees),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.82,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                ),
                ContenuFormulaire(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 12, 4),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary100,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(Icons.lock_outline_rounded, color: AppColors.primary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.motDePasseChangerTitre,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: ContenuFormulaire(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                        children: [
                          TextFormField(
                            controller: _ancienCtrl,
                            obscureText: !_ancienVisible,
                            autofillHints: const [AutofillHints.password],
                            decoration: InputDecoration(
                              labelText: '${l10n.motDePasseActuel} *',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                icon: Icon(_ancienVisible
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined),
                                onPressed: () => setState(() => _ancienVisible = !_ancienVisible),
                              ),
                            ),
                            // Aucune règle de complexité ici : c'est un mot de
                            // passe DÉJÀ en place, éventuellement provisoire et
                            // généré avant les règles actuelles. Le valider
                            // localement reviendrait à refuser une saisie que
                            // le serveur accepterait.
                            validator: (v) => (v == null || v.isEmpty) ? l10n.commonRequiredField : null,
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: _nouveauCtrl,
                            obscureText: !_nouveauVisible,
                            maxLength: _maxMotDePasse,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: InputDecoration(
                              labelText: '${l10n.motDePasseNouveau} *',
                              prefixIcon: const Icon(Icons.key_outlined),
                              helperText: l10n.membreFormMdpHelper,
                              helperMaxLines: 2,
                              counterText: '',
                              suffixIcon: IconButton(
                                icon: Icon(_nouveauVisible
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined),
                                onPressed: () => setState(() => _nouveauVisible = !_nouveauVisible),
                              ),
                            ),
                            validator: (v) {
                              final val = v ?? '';
                              if (val.isEmpty) return l10n.membreFormMdpRequis;
                              if (val.length < _minMotDePasse || val.length > _maxMotDePasse) {
                                return l10n.authMotDePasse8a128;
                              }
                              if (!_regexMotDePasse.hasMatch(val)) return l10n.authMotDePasseComplexite;
                              // Le serveur accepterait un mot de passe
                              // identique à l'ancien ; le refuser ici évite un
                              // « changement » qui ne change rien.
                              if (val == _ancienCtrl.text) return l10n.motDePasseIdentiqueAncien;
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _confirmationCtrl,
                            obscureText: !_nouveauVisible,
                            maxLength: _maxMotDePasse,
                            decoration: InputDecoration(
                              labelText: '${l10n.motDePasseConfirmation} *',
                              prefixIcon: const Icon(Icons.check_circle_outline_rounded),
                              counterText: '',
                            ),
                            // Le champ de confirmation n'existe que pour
                            // attraper une faute de frappe sur un texte masqué :
                            // il ne redit donc pas les règles de complexité,
                            // déjà signalées au-dessus.
                            validator: (v) =>
                                (v != _nouveauCtrl.text) ? l10n.motDePasseConfirmationErreur : null,
                          ),
                          const SizedBox(height: 20),
                          BlocBuilder<SettingsCubit, SettingsState>(
                            buildWhen: (a, b) => a.motDePasseStatus != b.motDePasseStatus,
                            builder: (context, state) {
                              final enCours = state.motDePasseStatus == ActionStatus.enCours;
                              return SizedBox(
                                height: 54,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                  onPressed: enCours ? null : _soumettre,
                                  icon: enCours
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.check_rounded, size: 20),
                                  label: Text(
                                    l10n.motDePasseChangerBouton,
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
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

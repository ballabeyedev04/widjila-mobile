import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../l10n/l10n_extension.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';

/// Feuille de provisionnement MFA — affiche le QR déjà encodé par le
/// back (`MfaProvisionnement.qrDataUrl`), le secret en repli pour une saisie
/// manuelle, et un champ pour le code à 6 chiffres qui confirme
/// l'activation. Reste ouverte tant que [SettingsCubit.state.mfaActionStatus]
/// n'est pas `succes` — l'appelant (`SettingsPage`) ferme la feuille sur ce
/// signal.
Future<void> ouvrirProvisionnementMfa(BuildContext context) {
  final cubit = context.read<SettingsCubit>();
  cubit.demarrerProvisionnementMfa();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => BlocProvider.value(value: cubit, child: const _MfaSetupSheet()),
  ).whenComplete(() => cubit.annulerProvisionnementMfa());
}

class _MfaSetupSheet extends StatefulWidget {
  const _MfaSetupSheet();

  @override
  State<_MfaSetupSheet> createState() => _MfaSetupSheetState();
}

class _MfaSetupSheetState extends State<_MfaSetupSheet> {
  final _codeCtrl = TextEditingController();

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Uint8List? _decoderQr(String dataUrl) {
    final virgule = dataUrl.indexOf(',');
    if (virgule < 0) return null;
    try {
      return base64Decode(dataUrl.substring(virgule + 1));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocConsumer<SettingsCubit, SettingsState>(
      listenWhen: (a, b) => a.mfaActionStatus != b.mfaActionStatus,
      listener: (context, state) {
        if (state.mfaActionStatus == ActionStatus.succes) {
          Navigator.of(context).pop();
          AppAlert.success(context, message: l10n.settingsMfaActiveMessage);
        }
      },
      builder: (context, state) {
        final qr = state.provisionnement != null ? _decoderQr(state.provisionnement!.qrDataUrl) : null;
        final enCours = state.mfaActionStatus == ActionStatus.enCours;

        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: ContenuFormulaire(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        l10n.settingsMfaActiverTitre,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.settingsMfaActiverDescription,
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                      ),
                      const SizedBox(height: 18),
                      if (state.provisionnement == null)
                        const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
                      else ...[
                        if (qr != null)
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Image.memory(qr, width: 180, height: 180),
                            ),
                          ),
                        const SizedBox(height: 14),
                        Text(
                          l10n.settingsMfaSecretIntro,
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          state.provisionnement!.secret,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _codeCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 6),
                          decoration: InputDecoration(
                            labelText: l10n.settingsMfaCodeLabel,
                            counterText: '',
                          ),
                        ),
                        if (state.mfaErreur != null) ...[
                          const SizedBox(height: 6),
                          Text(state.mfaErreur!, style: const TextStyle(fontSize: 12.5, color: AppColors.danger)),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 50,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: enCours || _codeCtrl.text.trim().length != 6
                                ? null
                                : () => context.read<SettingsCubit>().confirmerActivationMfa(_codeCtrl.text.trim()),
                            child: enCours
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                                  )
                                : Text(l10n.settingsMfaConfirmerBouton, style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

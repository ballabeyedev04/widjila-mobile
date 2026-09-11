import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/errors/exception_to_failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/liste_chrome.dart' show ContenuFormulaire;
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/datasources/support_remote_datasource.dart';

/// Ouvre le formulaire « Contacter le support ».
///
/// La ligne des Paramètres affichait « Bientôt disponible » faute d'adresse
/// de support configurée. La demande part désormais d'ici : le serveur la
/// transmet au support par email, et la réponse revient dans la boîte de
/// l'utilisateur.
Future<void> ouvrirContactSupport(BuildContext context) async {
  // L'email est lu ICI : la feuille monte sur le Navigator racine.
  final email = context.read<AuthBloc>().state.utilisateur?.email;
  final envoye = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FeuilleSupport(email: email),
  );
  if (envoye == true && context.mounted) {
    AppAlert.success(context, message: context.l10n.supportEnvoye);
  }
}

class _FeuilleSupport extends StatefulWidget {
  final String? email;
  const _FeuilleSupport({required this.email});

  @override
  State<_FeuilleSupport> createState() => _FeuilleSupportState();
}

class _FeuilleSupportState extends State<_FeuilleSupport> {
  final _cle = GlobalKey<FormState>();
  final _sujet = TextEditingController();
  final _message = TextEditingController();
  bool _envoi = false;

  @override
  void dispose() {
    _sujet.dispose();
    _message.dispose();
    super.dispose();
  }

  /// Application et version, joints à la demande : c'est la première
  /// question que pose le support.
  Future<Map<String, String>> _contexte() async {
    final contexte = <String, String>{'plateforme': defaultTargetPlatform.name};
    try {
      final info = await PackageInfo.fromPlatform();
      contexte['version'] = '${info.version} (${info.buildNumber})';
    } catch (_) {
      // Version illisible : la demande part quand même.
    }
    return contexte;
  }

  Future<void> _envoyer() async {
    if (!(_cle.currentState?.validate() ?? false)) return;
    setState(() => _envoi = true);
    try {
      await sl<SupportRemoteDataSource>().envoyerMessage(
        sujet: _sujet.text.trim(),
        message: _message.text.trim(),
        contexte: await _contexte(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _envoi = false);
      AppAlert.error(context, message: exceptionToFailure(e).errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final email = widget.email;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: ContenuFormulaire(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: Form(
                key: _cle,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(99)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.support_agent_outlined, color: AppColors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l10n.supportTitre,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                    if (email != null && email.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        l10n.supportDescription(email),
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _sujet,
                      maxLength: 150,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(labelText: l10n.supportSujet),
                      validator: (v) => (v?.trim().length ?? 0) < 3 ? l10n.supportSujetRequis : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _message,
                      minLines: 5,
                      maxLines: 10,
                      maxLength: 5000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(labelText: l10n.supportMessage, alignLabelWithHint: true),
                      validator: (v) => (v?.trim().length ?? 0) < 10 ? l10n.supportMessageRequis : null,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _envoi ? null : _envoyer,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: _envoi
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(l10n.supportEnvoyer, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

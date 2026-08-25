import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/reserve.dart';
import '../../domain/entities/reserve_collaboration.dart';
import '../cubit/reserve_detail_cubit.dart';

/// QR code d'une réserve, à imprimer et poser sur site.
///
/// C'est l'usage terrain par excellence : un ouvrier scanne l'étiquette collée
/// sur le mur et tombe directement sur la fiche, sans chercher dans une liste
/// de deux cents réserves. La route existait depuis toujours côté serveur.
Future<void> ouvrirQrReserve(BuildContext context, Reserve reserve) {
  final cubit = context.read<ReserveDetailCubit>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: _QrReserveSheet(reserve: reserve),
    ),
  );
}

class _QrReserveSheet extends StatefulWidget {
  final Reserve reserve;
  const _QrReserveSheet({required this.reserve});

  @override
  State<_QrReserveSheet> createState() => _QrReserveSheetState();
}

class _QrReserveSheetState extends State<_QrReserveSheet> {
  QrReserve? _qr;
  bool _enCours = true;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final qr = await context.read<ReserveDetailCubit>().chargerQr();
    if (!mounted) return;
    setState(() {
      _qr = qr;
      _enCours = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final base64Image = _qr?.base64;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.92,
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
                        child: const Icon(Icons.qr_code_2_rounded, color: AppColors.primary, size: 21),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.reserveQrTitre,
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
                child: ContenuFormulaire(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                    children: [
                      Text(
                        widget.reserve.numeroAffiche(l10n),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.reserve.titre,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 20),
                      if (_enCours)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 60),
                          child: Center(
                            child: CircularProgressIndicator(color: AppColors.primary),
                          ),
                        )
                      else if (base64Image == null)
                        _Indisponible(onReessayer: () {
                          setState(() => _enCours = true);
                          _charger();
                        })
                      else
                        _Vignette(base64Image: base64Image),

                      if (!_enCours && _qr != null) ...[
                        const SizedBox(height: 18),
                        Text(
                          l10n.reserveQrDescription,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        _LigneUrl(url: _qr!.url),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Le code lui-même, sur fond blanc.
///
/// Le fond blanc n'est pas décoratif : un QR code posé sur le gris de
/// l'application perd du contraste, et les lecteurs les plus simples cessent
/// de le reconnaître.
class _Vignette extends StatelessWidget {
  final String base64Image;
  const _Vignette({required this.base64Image});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4)),
          ],
        ),
        child: Image.memory(
          base64Decode(base64Image),
          width: 220,
          height: 220,
          fit: BoxFit.contain,
          // Un base64 tronqué ne doit pas faire tomber tout l'écran.
          errorBuilder: (context, _, _) => SizedBox(
            width: 220,
            height: 220,
            child: Center(
              child: Text(
                context.l10n.reserveQrIndisponible,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Indisponible extends StatelessWidget {
  final VoidCallback onReessayer;
  const _Indisponible({required this.onReessayer});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.qr_code_2_rounded, size: 48, color: AppColors.textMuted.withValues(alpha: 0.6)),
          const SizedBox(height: 14),
          Text(
            l10n.reserveQrIndisponible,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onReessayer,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(l10n.commonRetry),
          ),
        ],
      ),
    );
  }
}

/// L'adresse encodée, copiable.
///
/// Affichée parce qu'un QR code est illisible à l'œil : sans elle, impossible
/// de vérifier ce que le scan ouvrira, ni de partager le lien autrement.
class _LigneUrl extends StatelessWidget {
  final String url;
  const _LigneUrl({required this.url});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: url));
          if (context.mounted) AppAlert.success(context, message: l10n.commonDone);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.link_rounded, size: 18, color: AppColors.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ),
              const Icon(Icons.copy_rounded, size: 17, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

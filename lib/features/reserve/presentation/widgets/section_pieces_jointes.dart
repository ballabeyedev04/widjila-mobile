import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../../../core/config/user_role.dart';
import '../../../../core/services/capture_photo.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../document/domain/formats_document.dart';
import '../../../document/presentation/widgets/actions_document.dart';
import '../../domain/entities/piece_jointe.dart';
import '../cubit/pieces_jointes_cubit.dart';
import '../cubit/pieces_jointes_state.dart';

/// Pièces jointes d'une réserve — devis, PV, fiches techniques, photos.
///
/// Elles n'existaient pas sur mobile : les routes du serveur étaient là,
/// l'espace web les affichait, mais un intervenant sur le chantier ne pouvait
/// ni les consulter ni en ajouter. Consultation, téléchargement et ouverture
/// dans une autre application passent par les mêmes gestes que la
/// médiathèque (`actions_document.dart`).
class SectionPiecesJointes extends StatelessWidget {
  final String reserveId;
  const SectionPiecesJointes({super.key, required this.reserveId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<PiecesJointesCubit>(param1: reserveId)..charger(),
      child: const _ContenuPieces(),
    );
  }
}

class _ContenuPieces extends StatelessWidget {
  const _ContenuPieces();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final role = context.select((AuthBloc b) => b.state.utilisateur?.role);
    // Miroir de `requireRole(...RESERVE_INTERVENANTS)` sur l'ajout et de
    // `...OPERATIONNEL` sur la suppression (`reserve.route.js`).
    final peutAjouter = role?.peutIntervenirSurReserves ?? false;
    final peutSupprimer = role?.estOperationnel ?? false;

    return BlocBuilder<PiecesJointesCubit, PiecesJointesState>(
      builder: (context, state) {
        final progression = state.progression;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    l10n.pieceJointeTitre(state.pieces.length),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary),
                  ),
                ),
                if (peutAjouter)
                  TextButton.icon(
                    onPressed: state.envoiEnCours ? null : () => _ajouter(context),
                    style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                    icon: state.envoiEnCours
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(value: progression, strokeWidth: 2, color: AppColors.primary),
                          )
                        : const Icon(Icons.attach_file_rounded, size: 18),
                    label: Text(
                      !state.envoiEnCours
                          ? l10n.commonAdd
                          : progression == null
                              ? l10n.documentEnvoiEnCours
                              : l10n.documentEnvoiProgression((progression * 100).floor()),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _corps(context, state, peutSupprimer),
          ],
        );
      },
    );
  }

  Widget _corps(BuildContext context, PiecesJointesState state, bool peutSupprimer) {
    final l10n = context.l10n;
    switch (state.status) {
      case PiecesJointesStatus.chargement:
        return const SizedBox(
          height: 70,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary),
            ),
          ),
        );
      case PiecesJointesStatus.erreur:
        return _Cadre(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  state.erreur ?? l10n.commonErrorUnknown,
                  style: const TextStyle(fontSize: 13, color: AppColors.danger),
                ),
              ),
              TextButton(
                onPressed: () => context.read<PiecesJointesCubit>().charger(),
                child: Text(l10n.commonRetry),
              ),
            ],
          ),
        );
      case PiecesJointesStatus.succes:
        if (state.pieces.isEmpty) {
          return _Cadre(
            child: Center(
              child: Text(l10n.pieceJointeAucune, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
          );
        }
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < state.pieces.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 60),
                _LignePiece(piece: state.pieces[i], peutSupprimer: peutSupprimer),
              ],
            ],
          ),
        );
    }
  }
}

class _Cadre extends StatelessWidget {
  final Widget child;
  const _Cadre({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 70),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _LignePiece extends StatelessWidget {
  final PieceJointe piece;
  final bool peutSupprimer;
  const _LignePiece({required this.piece, required this.peutSupprimer});

  IconData _icone(String extension) => switch (extension) {
        'pdf' => Icons.picture_as_pdf_rounded,
        'doc' || 'docx' => Icons.article_rounded,
        'xls' || 'xlsx' || 'csv' => Icons.table_chart_rounded,
        'ppt' || 'pptx' => Icons.slideshow_rounded,
        'dwg' => Icons.architecture_rounded,
        'jpg' || 'jpeg' || 'png' || 'webp' => Icons.image_rounded,
        _ => Icons.insert_drive_file_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final document = piece.commeDocument;
    final taille = document.tailleLisible(l10n);
    final details = [
      ?taille,
      if (piece.createdAt != null) DateFormat('dd/MM/yyyy').format(piece.createdAt!),
    ].join(' · ');

    return InkWell(
      onTap: () => voirDocument(context, document),
      onLongPress: () => _actions(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: AppColors.primary100, borderRadius: BorderRadius.circular(10)),
              child: Icon(_icone(document.extension), size: 19, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    piece.nomFichier,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                  if (details.isNotEmpty)
                    Text(details, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                ],
              ),
            ),
            IconButton(
              tooltip: l10n.documentPlusActions,
              icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.textMuted),
              onPressed: () => _actions(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _actions(BuildContext context) {
    return afficherActionsDocument(
      context,
      piece.commeDocument,
      onSupprimer: peutSupprimer ? () => _supprimer(context) : null,
    );
  }

  Future<void> _supprimer(BuildContext context) async {
    final cubit = context.read<PiecesJointesCubit>();
    final l10n = context.l10n;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l10n.commonSupprimerNom(piece.nomFichier)),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirme != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final erreur = await cubit.supprimer(piece.id);
    if (!context.mounted) return;
    if (erreur != null) {
      AppAlert.error(context, message: erreur);
    } else {
      messenger.showSnackBar(SnackBar(content: Text(l10n.pieceJointeSupprimee)));
    }
  }
}

enum _SourcePiece { camera, galerie, fichier }

/// Ajout d'une pièce : photo prise sur place, photo de la galerie, ou fichier
/// de l'appareil (PDF, Word, Excel, DWG…).
Future<void> _ajouter(BuildContext context) async {
  final cubit = context.read<PiecesJointesCubit>();
  final l10n = context.l10n;

  final source = await showModalBottomSheet<_SourcePiece>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined, color: AppColors.primary),
            title: Text(l10n.reserveDetailPrendrePhoto),
            onTap: () => Navigator.of(sheetContext).pop(_SourcePiece.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
            title: Text(l10n.reserveDetailChoisirGalerie),
            onTap: () => Navigator.of(sheetContext).pop(_SourcePiece.galerie),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file_rounded, color: AppColors.primary),
            title: Text(l10n.pieceJointeChoisirFichier),
            onTap: () => Navigator.of(sheetContext).pop(_SourcePiece.fichier),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return;

  String? chemin;
  String? nom;
  if (source == _SourcePiece.fichier) {
    // `FileType.any` : Android grise les formats métier (DWG) qu'il ne
    // connaît pas. Le format est contrôlé après le choix.
    final choix = await FilePicker.platform.pickFiles(type: FileType.any, withData: false);
    final fichier = choix?.files.singleOrNull;
    if (fichier == null || fichier.path == null || !context.mounted) return;
    if (!FormatsDocument.estPieceJointeAcceptee(fichier.name)) {
      AppAlert.error(context, message: l10n.pieceJointeFormatNonSupporte);
      return;
    }
    if (fichier.size > FormatsDocument.tailleMaxDocument) {
      AppAlert.error(
        context,
        message: l10n.documentFichierTropVolumineux(
          l10n.documentTailleMo('${FormatsDocument.tailleMaxDocument ~/ (1024 * 1024)}'),
        ),
      );
      return;
    }
    chemin = fichier.path;
    nom = fichier.name;
  } else {
    // `capturerPhoto` : reprend le cliché quand Android détruit l'activité
    // pendant la prise de vue, et plafonne à 1920 px (voir capture_photo.dart).
    final File? photo;
    try {
      photo = await capturerPhoto(source == _SourcePiece.camera ? ImageSource.camera : ImageSource.gallery);
    } on PhotoIndisponible {
      if (context.mounted) AppAlert.error(context, message: l10n.reserveNouvPhotoIndisponible);
      return;
    }
    if (photo == null) return;
    chemin = photo.path;
    nom = p.basename(photo.path);
  }
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final erreur = await cubit.ajouter(cheminFichier: chemin!, nomFichier: nom);
  if (!context.mounted) return;
  if (erreur != null) {
    AppAlert.error(context, message: erreur);
  } else {
    messenger.showSnackBar(SnackBar(content: Text(l10n.pieceJointeAjoutee)));
  }
}

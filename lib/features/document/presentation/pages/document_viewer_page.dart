import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../../../core/services/ouverture_fichier.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/document.dart';
import '../widgets/actions_document.dart';

/// Aperçu d'un fichier de la médiathèque DANS l'application — PDF et photos.
///
/// « Voir sans télécharger » : les octets transitent par le Dio applicatif
/// (seul porteur du jeton qu'exige `/uploads/*`) et restent EN MÉMOIRE le
/// temps de l'écran. Rien n'est écrit sur le téléphone ; le bouton
/// « Télécharger » de la barre en fait une copie durable, à la demande.
///
/// Le PDF est rendu par `pdfx`, déjà utilisé pour les plans : pages à la
/// suite, zoom au pincement. Une photo passe dans un `InteractiveViewer`.
///
/// Un format que l'application ne sait pas afficher (Word, DWG…) n'arrive
/// normalement pas ici — voir `voirDocument` — mais l'écran le gère quand
/// même : il propose de l'ouvrir ailleurs ou de le télécharger.
class DocumentViewerPage extends StatefulWidget {
  final ChantierDocument document;
  const DocumentViewerPage({super.key, required this.document});

  @override
  State<DocumentViewerPage> createState() => _DocumentViewerPageState();
}

enum _Apercu { pdf, image, indisponible }

class _DocumentViewerPageState extends State<DocumentViewerPage> {
  Uint8List? _octets;
  _Apercu? _apercu;
  String? _erreur;
  double? _progression;
  PdfControllerPinch? _pdf;
  int _page = 1;
  int _pages = 0;

  /// Le fichier a été reçu mais son rendu a échoué (PDF abîmé, image
  /// illisible) — distinct d'un format simplement non pris en charge.
  bool _renduEchoue = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _pdf?.dispose();
    super.dispose();
  }

  /// En-tête `%PDF` : on regarde les OCTETS, pas l'extension — un type MIME
  /// générique ou un fichier renommé ne doit pas faire échouer l'aperçu.
  static bool _estPdf(Uint8List o) =>
      o.length > 4 && o[0] == 0x25 && o[1] == 0x50 && o[2] == 0x44 && o[3] == 0x46;

  Future<void> _charger() async {
    final ancien = _pdf;
    setState(() {
      _octets = null;
      _apercu = null;
      _erreur = null;
      _progression = null;
      _pdf = null;
      _page = 1;
      _pages = 0;
      _renduEchoue = false;
    });
    // Libéré après la frame : la vue qui s'en sert est encore montée.
    if (ancien != null) WidgetsBinding.instance.addPostFrameCallback((_) => ancien.dispose());

    final resultat = await sl<OuvertureFichier>().telecharger(
      url: widget.document.fichierUrl,
      onProgression: _surProgression,
    );
    if (!mounted) return;

    resultat.fold(
      (failure) => setState(() => _erreur = failure.errorMessage),
      (octets) => setState(() {
        _octets = octets;
        if (_estPdf(octets)) {
          _apercu = _Apercu.pdf;
          _pdf = PdfControllerPinch(document: PdfDocument.openData(octets));
        } else if (widget.document.estImage) {
          _apercu = _Apercu.image;
        } else {
          _apercu = _Apercu.indisponible;
        }
      }),
    );
  }

  /// Une mise à jour par point de pourcentage au plus : chaque paquet reçu
  /// reconstruirait sinon l'écran, des centaines de fois pour un seul PDF.
  void _surProgression(double? valeur) {
    if (!mounted) return;
    final avant = _progression;
    if (valeur == avant) return;
    if (valeur != null && avant != null && (valeur - avant).abs() < 0.01) return;
    setState(() => _progression = valeur);
  }

  Future<void> _ouvrirAvec(Uint8List octets) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final resultat = await sl<OuvertureFichier>().ouvrirOctets(
      octets: octets,
      nomFichier: widget.document.nomFichier,
    );
    if (!mounted) return;

    resultat.fold(
      (failure) => AppAlert.error(context, title: widget.document.nomFichier, message: failure.errorMessage),
      (issue) {
        if (issue == ResultatOuverture.aucuneApplication) {
          messenger.showSnackBar(SnackBar(content: Text(l10n.documentAucuneApplication)));
        }
      },
    );
  }

  void _telecharger(Uint8List octets) =>
      enregistrerSurAppareil(context, octets: octets, nomFichier: widget.document.nomFichier);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final octets = _octets;
    // Une photo se regarde sur fond noir ; un PDF sur le gris de
    // l'application, où ses pages blanches se détachent.
    final sombre = _apercu == _Apercu.image && !_renduEchoue;
    final premierPlan = sombre ? Colors.white : AppColors.textPrimary;

    return Scaffold(
      backgroundColor: sombre ? Colors.black : AppColors.background,
      appBar: AppBar(
        backgroundColor: sombre ? Colors.black : AppColors.surface,
        foregroundColor: premierPlan,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: Text(
          widget.document.nomFichier,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: premierPlan),
        ),
        actions: [
          IconButton(
            tooltip: l10n.documentActionTelecharger,
            icon: const Icon(Icons.download_rounded),
            onPressed: octets == null ? null : () => _telecharger(octets),
          ),
          IconButton(
            tooltip: l10n.documentActionOuvrirAvec,
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: octets == null ? null : () => _ouvrirAvec(octets),
          ),
        ],
      ),
      body: SafeArea(top: false, child: _corps(context)),
    );
  }

  Widget _corps(BuildContext context) {
    final l10n = context.l10n;

    final erreur = _erreur;
    if (erreur != null) return ErrorView(message: erreur, onRetry: _charger);

    final octets = _octets;
    final apercu = _apercu;
    if (octets == null || apercu == null) return _Chargement(progression: _progression);

    final indisponible = _ApercuIndisponible(
      document: widget.document,
      message: _renduEchoue ? l10n.documentApercuImpossible : l10n.documentApercuIndisponible,
      onOuvrir: () => _ouvrirAvec(octets),
      onTelecharger: () => _telecharger(octets),
    );
    if (_renduEchoue) return indisponible;

    switch (apercu) {
      case _Apercu.pdf:
        return Stack(
          fit: StackFit.expand,
          children: [
            PdfViewPinch(
              controller: _pdf!,
              backgroundDecoration: const BoxDecoration(color: AppColors.background),
              onDocumentLoaded: (document) {
                if (mounted) setState(() => _pages = document.pagesCount);
              },
              onPageChanged: (page) {
                if (mounted) setState(() => _page = page);
              },
              onDocumentError: (_) {
                if (mounted) setState(() => _renduEchoue = true);
              },
            ),
            if (_pages > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(child: _PastillePage(texte: '$_page / $_pages')),
              ),
          ],
        );
      case _Apercu.image:
        return InteractiveViewer(
          minScale: 1,
          maxScale: 6,
          child: Center(
            child: Image.memory(
              octets,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) {
                // Signalé après la frame : on ne change pas l'état pendant
                // la construction.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_renduEchoue) setState(() => _renduEchoue = true);
                });
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      case _Apercu.indisponible:
        return indisponible;
    }
  }
}

class _Chargement extends StatelessWidget {
  final double? progression;
  const _Chargement({required this.progression});

  @override
  Widget build(BuildContext context) {
    final texte = context.l10n.documentOuvertureEnCours;
    final valeur = progression;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(value: valeur, strokeWidth: 3, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              valeur == null ? texte : '$texte ${(valeur * 100).round()} %',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// « 3 / 12 » posé sur le PDF.
class _PastillePage extends StatelessWidget {
  final String texte;
  const _PastillePage({required this.texte});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texte,
        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Pas d'aperçu possible : les deux issues restent à portée de pouce.
class _ApercuIndisponible extends StatelessWidget {
  final ChantierDocument document;
  final String message;
  final VoidCallback onOuvrir;
  final VoidCallback onTelecharger;

  const _ApercuIndisponible({
    required this.document,
    required this.message,
    required this.onOuvrir,
    required this.onTelecharger,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(Icons.insert_drive_file_rounded, color: AppColors.primary, size: 34),
              ),
              const SizedBox(height: 16),
              Text(
                document.nomFichier,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: onOuvrir,
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(l10n.documentActionOuvrirAvec),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onTelecharger,
                icon: const Icon(Icons.download_rounded),
                label: Text(l10n.documentActionTelecharger),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                  side: const BorderSide(color: AppColors.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

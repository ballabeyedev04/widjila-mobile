import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/plan.dart';

/// Repère à dessiner sur le plan — une réserve, ou le point que
/// l'utilisateur vient de désigner.
class MarqueurPlan {
  final String id;
  final double x;
  final double y;
  final Color couleur;
  final bool actif;

  const MarqueurPlan({
    required this.id,
    required this.x,
    required this.y,
    this.couleur = AppColors.primary,
    this.actif = false,
  });
}

/// Plan affiché de façon INTERACTIVE : zoom, déplacement, repères posés au bon
/// endroit, et appui qui remonte un point exploitable.
///
/// POURQUOI PAS `flutter_pdfview` (toujours utilisé pour la simple lecture) :
/// c'est une vue NATIVE, dont on ne connaît ni le zoom ni le décalage courants.
/// Aucun repère ne peut y être superposé sans dériver au premier geste, et
/// aucun appui n'en ressort avec des coordonnées utilisables — c'est
/// exactement ce que constatait le commentaire de `plan_viewer_page.dart`,
/// qui renonçait à afficher les repères pour cette raison.
///
/// Ici la page est RENDUE EN IMAGE par `pdfx`, puis placée dans un
/// `InteractiveViewer` dont la matrice nous appartient. Les repères vivent
/// dans le même conteneur transformé que l'image : ils subissent donc
/// exactement la même transformation et ne peuvent pas s'en désolidariser.
///
/// COORDONNÉES : tout ce qui entre et sort est en POURCENTAGES (0-100) de la
/// page, jamais en pixels — convention de `ReservePosition` et `PlanHotspot`
/// côté backend. Un pourcentage reste juste quels que soient l'écran, la
/// densité de pixels et le zoom ; un pixel, non.
class PlanInteractif extends StatefulWidget {
  final Uint8List octets;
  final int page;
  final List<MarqueurPlan> marqueurs;
  final List<PlanHotspot> hotspots;

  /// En mode pointage, l'appui remonte un point au lieu d'être ignoré.
  final bool modePointage;

  final void Function(double x, double y)? onPointAppuye;
  final void Function(MarqueurPlan marqueur)? onMarqueurAppuye;
  final void Function(PlanHotspot hotspot)? onHotspotAppuye;

  const PlanInteractif({
    super.key,
    required this.octets,
    this.page = 1,
    this.marqueurs = const [],
    this.hotspots = const [],
    this.modePointage = false,
    this.onPointAppuye,
    this.onMarqueurAppuye,
    this.onHotspotAppuye,
  });

  @override
  State<PlanInteractif> createState() => _PlanInteractifState();
}

class _PlanInteractifState extends State<PlanInteractif> {
  final TransformationController _transformation = TransformationController();

  Uint8List? _image;
  double _ratio = 1.414; // A4 portrait, en attendant la vraie page
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _rendre();
  }

  @override
  void didUpdateWidget(PlanInteractif ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.octets != widget.octets || ancien.page != widget.page) _rendre();
  }

  @override
  void dispose() {
    _transformation.dispose();
    super.dispose();
  }

  Future<void> _rendre() async {
    PdfDocument? document;
    try {
      document = await PdfDocument.openData(widget.octets);
      final numero = widget.page.clamp(1, document.pagesCount);
      final page = await document.getPage(numero);

      try {
        // Rendu à une résolution FIXE et généreuse plutôt qu'à la taille
        // d'affichage : le zoom est ensuite purement géométrique
        // (`InteractiveViewer`). Re-rendre à chaque cran relancerait un rendu
        // natif sous le doigt et saccaderait le geste.
        final largeur = page.width * 2;
        final hauteur = page.height * 2;
        final rendu = await page.render(
          width: largeur,
          height: hauteur,
          format: PdfPageImageFormat.png,
          // Sans fond blanc explicite, un PDF sans calque de fond est rendu
          // sur du transparent : le plan apparaissait en traits noirs sur le
          // fond sombre du conteneur, illisible.
          backgroundColor: '#FFFFFF',
        );
        if (!mounted) return;
        setState(() {
          _image = rendu?.bytes;
          _ratio = page.height / page.width;
          _erreur = null;
        });
      } finally {
        await page.close();
      }
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      await document?.close();
    }
  }

  /// Convertit un appui en pourcentages de la page.
  ///
  /// `details.localPosition` est déjà exprimée dans le repère de l'enfant du
  /// `InteractiveViewer` — c'est-à-dire APRÈS annulation du zoom et du
  /// déplacement. Il n'y a donc aucune matrice à inverser à la main : la
  /// division par la taille de l'enfant donne directement le ratio cherché.
  void _appui(TapDownDetails details, Size taille) {
    if (!widget.modePointage) return;
    if (taille.width <= 0 || taille.height <= 0) return;

    final x = (details.localPosition.dx / taille.width * 100).clamp(0.0, 100.0);
    final y = (details.localPosition.dy / taille.height * 100).clamp(0.0, 100.0);
    widget.onPointAppuye?.call(
      double.parse(x.toStringAsFixed(2)),
      double.parse(y.toStringAsFixed(2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _erreur!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      );
    }
    if (_image == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    return LayoutBuilder(
      builder: (context, contraintes) {
        // La page occupe toute la largeur disponible, sa hauteur suit le
        // rapport réel du document — jamais une hauteur arbitraire, qui
        // déformerait le plan et fausserait toutes les coordonnées.
        final largeur = contraintes.maxWidth;
        final hauteur = largeur * _ratio;
        final taille = Size(largeur, hauteur);

        return ClipRect(
          child: InteractiveViewer(
            transformationController: _transformation,
            minScale: 1,
            maxScale: 8,
            // Le plan doit pouvoir être amené sous le pouce, y compris ses
            // bords : sans marge, les coins restaient inatteignables une fois
            // zoomé.
            boundaryMargin: const EdgeInsets.all(double.infinity),
            constrained: false,
            child: SizedBox(
              width: largeur,
              height: hauteur,
              child: Stack(
                children: [
                  // L'image et les repères partagent ce même Stack : ils
                  // subissent donc la MÊME transformation, ce qui garantit
                  // qu'un repère ne dérive jamais du plan.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => _appui(d, taille),
                      child: Image.memory(_image!, fit: BoxFit.fill, gaplessPlayback: true),
                    ),
                  ),

                  for (final h in widget.hotspots)
                    _Hotspot(
                      hotspot: h,
                      taille: taille,
                      onAppui: () => widget.onHotspotAppuye?.call(h),
                    ),

                  for (final m in widget.marqueurs)
                    _Repere(
                      marqueur: m,
                      taille: taille,
                      onAppui: () => widget.onMarqueurAppuye?.call(m),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Pastille d'une réserve. Ancrée par sa POINTE (bas-centre) sur le point
/// enregistré : c'est la pointe qui désigne le défaut, pas le centre de la
/// goutte.
class _Repere extends StatelessWidget {
  static const double _taillePastille = 30;

  final MarqueurPlan marqueur;
  final Size taille;
  final VoidCallback onAppui;

  const _Repere({required this.marqueur, required this.taille, required this.onAppui});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: marqueur.x / 100 * taille.width - _taillePastille / 2,
      top: marqueur.y / 100 * taille.height - _taillePastille,
      width: _taillePastille,
      height: _taillePastille,
      child: GestureDetector(
        onTap: onAppui,
        child: Container(
          decoration: BoxDecoration(
            color: marqueur.couleur,
            shape: BoxShape.circle,
            border: Border.all(
              color: marqueur.actif ? AppColors.accent : Colors.white,
              width: marqueur.actif ? 3 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(Icons.place_rounded, size: 16, color: Colors.white),
        ),
      ),
    );
  }
}

/// Zone cliquable qui fait descendre d'un niveau. Deux formes : un rectangle
/// tracé sur le plan, ou — quand aucune surface n'a été dessinée — une simple
/// étiquette posée au point indiqué.
class _Hotspot extends StatelessWidget {
  final PlanHotspot hotspot;
  final Size taille;
  final VoidCallback onAppui;

  const _Hotspot({required this.hotspot, required this.taille, required this.onAppui});

  @override
  Widget build(BuildContext context) {
    final aUneSurface = hotspot.largeur > 0 && hotspot.hauteur > 0;

    final etiquette = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 5, offset: const Offset(0, 2)),
        ],
      ),
      child: Text(
        hotspot.libelle ?? '',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
      ),
    );

    if (!aUneSurface) {
      return Positioned(
        left: hotspot.x / 100 * taille.width,
        top: hotspot.y / 100 * taille.height,
        child: FractionalTranslation(
          translation: const Offset(-0.5, -1),
          child: GestureDetector(onTap: onAppui, child: etiquette),
        ),
      );
    }

    return Positioned(
      left: hotspot.x / 100 * taille.width,
      top: hotspot.y / 100 * taille.height,
      width: hotspot.largeur / 100 * taille.width,
      height: hotspot.hauteur / 100 * taille.height,
      child: GestureDetector(
        onTap: onAppui,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            border: Border.all(color: AppColors.primary, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.topLeft,
          padding: const EdgeInsets.all(4),
          child: hotspot.libelle == null ? null : FittedBox(child: etiquette),
        ),
      ),
    );
  }
}

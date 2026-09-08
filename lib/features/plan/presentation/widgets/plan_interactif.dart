import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/l10n_extension.dart';
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

  /// Affiche les commandes de zoom posées sur le plan.
  ///
  /// Le pincement à deux doigts reste la façon naturelle de zoomer, mais il
  /// n'est pas toujours praticable sur un chantier — une main tient le
  /// téléphone, l'autre un outil, et des gants rendent le geste incertain.
  /// Surtout, RIEN ne ramenait à la vue d'ensemble une fois le plan agrandi :
  /// il fallait dézoomer à tâtons jusqu'à retrouver ses repères.
  ///
  /// Masquées sur les aperçus de petite taille, où trois boutons prendraient
  /// plus de place que le plan lui-même.
  final bool controlesZoom;

  /// Appelé quand le document a été ouvert et que son NOMBRE DE PAGES est
  /// connu.
  ///
  /// Le nombre de pages vient du document lui-même, jamais du champ
  /// `page_count` de la base : celui-ci est facultatif au dépôt et vaut `null`
  /// pour l'immense majorité des plans déjà en ligne. S'y fier ferait
  /// disparaître la barre de pages sur les documents qui en ont le plus
  /// besoin.
  final void Function(int nombrePages)? onPagesDetectees;

  /// Demande le passage en plein écran, ou la sortie (cahier technique § 6).
  ///
  /// Nul quand l'écran hôte n'a rien à replier — l'aperçu d'une liste, par
  /// exemple. Le bouton disparaît alors, plutôt que de ne rien faire.
  final VoidCallback? onPleinEcran;

  /// Vrai quand l'hôte EST déjà en plein écran : l'icône devient « réduire ».
  final bool pleinEcran;

  /// Demande l'affichage d'une autre page du document.
  ///
  /// C'est l'HÔTE qui garde la page courante, pas ce widget : la page fait
  /// partie de la position d'une réserve, et l'écran qui crée la réserve doit
  /// donc la connaître. Nul, la barre de pages n'apparaît pas.
  final void Function(int page)? onPageChangee;

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
    this.controlesZoom = false,
    this.onPagesDetectees,
    this.onPleinEcran,
    this.pleinEcran = false,
    this.onPageChangee,
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

  /// Nombre de pages du document ouvert — 1 tant qu'on ne sait pas.
  int _nombrePages = 1;

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

  /// Ce fichier commence-t-il par l'en-tête d'un PDF (`%PDF-`) ?
  ///
  /// On lit les OCTETS, jamais l'extension ni le champ `format` : celui-ci
  /// vaut 'pdf' par défaut côté serveur pour tout dépôt sans format explicite,
  /// alors que png, jpg, jpeg et webp sont acceptés.
  static bool _estPdf(Uint8List o) {
    const entete = [0x25, 0x50, 0x44, 0x46, 0x2D]; // %PDF-
    if (o.length < entete.length) return false;
    for (var i = 0; i < entete.length; i++) {
      if (o[i] != entete[i]) return false;
    }
    return true;
  }

  Future<void> _rendre() async {
    // Une IMAGE est déjà sa propre page : rien à rasteriser.
    //
    // Sans cette branche, `PdfDocument.openData` échouait sur des octets PNG
    // et l'écran affichait un message d'erreur à la place du plan — sur
    // l'écran qui EST la zone de travail. C'est ce que le client décrit :
    // « l'image du plan n'est pas visible ».
    if (!_estPdf(widget.octets)) {
      final image = await decodeImageFromList(widget.octets);
      if (!mounted) return;
      // Une image est un document d'UNE page : on le dit à l'hôte, pour qu'il
      // n'affiche pas une barre de pages inutile.
      widget.onPagesDetectees?.call(1);
      setState(() {
        _nombrePages = 1;
        _image = widget.octets;
        // Le ratio vient des dimensions réelles : le forcer à 1 déformerait
        // un plan panoramique, et les repères posés dessus seraient décalés.
        _ratio = image.height / image.width;
        _erreur = null;
      });
      return;
    }

    PdfDocument? document;
    try {
      document = await PdfDocument.openData(widget.octets);
      final total = document.pagesCount;
      if (mounted) widget.onPagesDetectees?.call(total);
      // `clamp` : l'hôte peut demander une page qui n'existe pas — un plan
      // remplacé par une version plus courte, une réserve posée page 9 d'un
      // document qui n'en compte plus que 4. On affiche alors la dernière
      // plutôt que d'échouer.
      final numero = widget.page.clamp(1, total);
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
          _nombrePages = total;
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
  /// Un appui sur une zone libre pose une réserve — sans mode préalable.
  ///
  /// Il fallait auparavant armer un « mode pointage » depuis le bandeau bas
  /// avant que l'appui ne fasse quoi que ce soit. Le client l'a tranché :
  /// « l'utilisateur n'a pas besoin de chercher un bouton pour choisir
  /// l'emplacement d'une réserve ». Le plan EST la zone de travail.
  ///
  /// C'est désormais `onPointAppuye` qui décide : nul quand le rôle n'a pas le
  /// droit de poser une réserve, l'appui reste alors sans effet. Le mode
  /// pointage, lui, ne sert plus qu'à afficher l'aide — c'est la seconde
  /// méthode décrite par le client, le bouton puis le choix de l'emplacement.
  ///
  /// `InteractiveViewer` distingue déjà l'appui du glissement : zoomer et
  /// déplacer le plan n'ouvre pas le formulaire.
  void _appui(TapDownDetails details, Size taille) {
    if (widget.onPointAppuye == null) return;
    if (taille.width <= 0 || taille.height <= 0) return;

    final x = (details.localPosition.dx / taille.width * 100).clamp(0.0, 100.0);
    final y = (details.localPosition.dy / taille.height * 100).clamp(0.0, 100.0);
    widget.onPointAppuye?.call(
      double.parse(x.toStringAsFixed(2)),
      double.parse(y.toStringAsFixed(2)),
    );
  }

  /// Échelle courante du plan — 1 = vue d'ensemble.
  double get _echelle => _transformation.value.getMaxScaleOnAxis();

  /// Zoome autour du CENTRE DE L'ÉCRAN, et non autour de l'origine du plan.
  ///
  /// Zoomer sur l'origine ferait fuir hors de l'écran ce que l'utilisateur
  /// était en train de regarder : il devrait le rattraper au doigt après
  /// chaque appui. On ramène donc le centre visible en coordonnées du plan, on
  /// change l'échelle autour de ce point, et on le remet où il était.
  ///
  /// Les bornes sont celles de l'`InteractiveViewer` juste en dessous : les
  /// dépasser par les boutons créerait un état que le pincement ne sait pas
  /// reproduire.
  void _zoomer(double facteur, Size viewport) {
    final cible = (_echelle * facteur).clamp(1.0, 8.0);
    if ((cible - _echelle).abs() < 0.001) return;

    final centre = _transformation.toScene(
      Offset(viewport.width / 2, viewport.height / 2),
    );
    final rapport = cible / _echelle;

    final matrice = _transformation.value.clone()
      ..translateByDouble(centre.dx, centre.dy, 0, 1)
      ..scaleByDouble(rapport, rapport, 1, 1)
      ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
    setState(() => _transformation.value = matrice);
  }

  /// Retour à la vue initiale — le plan entier, sans déplacement.
  void _reinitialiserVue() => setState(() => _transformation.value = Matrix4.identity());

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

        final vue = ClipRect(
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

        if (!widget.controlesZoom) return vue;

        return Stack(
          children: [
            Positioned.fill(child: vue),
            // Posées HORS du `InteractiveViewer` : dedans, elles subiraient le
            // zoom et deviendraient minuscules au moment précis où l'on veut
            // s'en servir.
            Positioned(
              right: 10,
              bottom: 10,
              child: _CommandesZoom(
                echelle: _echelle,
                onZoomAvant: () => _zoomer(1.6, Size(largeur, contraintes.maxHeight)),
                onZoomArriere: () => _zoomer(1 / 1.6, Size(largeur, contraintes.maxHeight)),
                onVueInitiale: _reinitialiserVue,
                onPleinEcran: widget.onPleinEcran,
                pleinEcran: widget.pleinEcran,
              ),
            ),
            // Barre de pages — cahier technique § 6, « changement de page si le
            // PDF en contient plusieurs ». Posée EN BAS À GAUCHE, à l'opposé du
            // zoom : les deux se manipulent au pouce, chacun de son côté.
            if (_nombrePages > 1 && widget.onPageChangee != null)
              Positioned(
                left: 10,
                bottom: 10,
                child: _BarrePages(
                  page: widget.page.clamp(1, _nombrePages),
                  total: _nombrePages,
                  onPage: (n) => widget.onPageChangee?.call(n),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Zoom avant, zoom arrière, vue initiale — empilés en bas à droite du plan.
///
/// « Vue initiale » n'apparaît QUE lorsqu'elle sert à quelque chose : proposer
/// un retour à la vue d'ensemble alors qu'on y est déjà n'est qu'un bouton de
/// plus à lire.
class _CommandesZoom extends StatelessWidget {
  final double echelle;
  final VoidCallback onZoomAvant;
  final VoidCallback onZoomArriere;
  final VoidCallback onVueInitiale;
  final VoidCallback? onPleinEcran;
  final bool pleinEcran;

  const _CommandesZoom({
    required this.echelle,
    required this.onZoomAvant,
    required this.onZoomArriere,
    required this.onVueInitiale,
    this.onPleinEcran,
    this.pleinEcran = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final agrandi = echelle > 1.01;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // PLEIN ÉCRAN — cahier technique § 6. En tête de colonne : c'est le
        // premier geste de qui veut vraiment lire un plan sur un téléphone.
        if (onPleinEcran != null) ...[
          _Bouton(
            icone: pleinEcran ? Icons.close_fullscreen_rounded : Icons.open_in_full_rounded,
            tooltip: pleinEcran ? l10n.planQuitterPleinEcran : l10n.planPleinEcran,
            onAppui: onPleinEcran,
          ),
          const SizedBox(height: 8),
        ],
        if (agrandi)
          _Bouton(
            icone: Icons.fullscreen_exit_rounded,
            tooltip: l10n.planVueInitiale,
            onAppui: onVueInitiale,
          ),
        if (agrandi) const SizedBox(height: 8),
        _Bouton(icone: Icons.add_rounded, tooltip: l10n.planZoomAvant, onAppui: onZoomAvant),
        const SizedBox(height: 8),
        _Bouton(
          icone: Icons.remove_rounded,
          tooltip: l10n.planZoomArriere,
          // Inerte à l'échelle 1 : on ne peut pas dézoomer sous la vue
          // d'ensemble, l'`InteractiveViewer` a `minScale: 1`.
          onAppui: agrandi ? onZoomArriere : null,
        ),
      ],
    );
  }
}

class _Bouton extends StatelessWidget {
  final IconData icone;
  final String tooltip;
  final VoidCallback? onAppui;

  const _Bouton({required this.icone, required this.tooltip, this.onAppui});

  @override
  Widget build(BuildContext context) {
    final actif = onAppui != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onAppui,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              icone,
              size: 20,
              color: actif ? AppColors.textPrimary : AppColors.textMuted,
            ),
          ),
        ),
      ),
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

/// Navigation entre les pages d'un document — cahier technique § 6.
///
/// N'apparaît QUE si le document en compte plusieurs : une barre « 1 / 1 » ne
/// dirait rien et prendrait la place du plan.
///
/// Les flèches de bout de course sont INERTES mais VISIBLES, contrairement au
/// zoom : ici, la position dans le document est elle-même une information — on
/// veut voir qu'on est à la première page, pas voir un bouton disparaître.
class _BarrePages extends StatelessWidget {
  final int page;
  final int total;
  final void Function(int) onPage;

  const _BarrePages({required this.page, required this.total, required this.onPage});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(19),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Fleche(
              icone: Icons.chevron_left_rounded,
              tooltip: l10n.planPagePrecedente,
              onAppui: page > 1 ? () => onPage(page - 1) : null,
            ),
            ConstrainedBox(
              // Largeur minimale : sans elle, la barre saute d'un pixel à
              // chaque changement de page — « 9/12 » puis « 10/12 ».
              constraints: const BoxConstraints(minWidth: 46),
              child: Text(
                '$page / $total',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            _Fleche(
              icone: Icons.chevron_right_rounded,
              tooltip: l10n.planPageSuivante,
              onAppui: page < total ? () => onPage(page + 1) : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Flèche de la barre de pages — carrée, 38 points, comme les boutons de zoom.
class _Fleche extends StatelessWidget {
  final IconData icone;
  final String tooltip;
  final VoidCallback? onAppui;

  const _Fleche({required this.icone, required this.tooltip, this.onAppui});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onAppui,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(
            icone,
            size: 22,
            color: onAppui == null ? AppColors.textMuted : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

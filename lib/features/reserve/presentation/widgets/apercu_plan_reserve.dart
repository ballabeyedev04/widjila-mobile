import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../plan/presentation/widgets/plan_interactif.dart';
import '../../domain/entities/reserve.dart';

/// Télécharge les octets d'un plan — injectable pour les tests.
typedef TelechargerPlan = Future<Uint8List?> Function(String url);

/// Le plan d'une réserve, AFFICHÉ, avec un repère sur l'endroit du défaut.
///
/// La fiche ne donnait que le NOM du fichier (« arkada_13_2np3.jpg · v3 ») :
/// pour savoir où aller, il fallait ouvrir le plan, retrouver la bonne
/// pastille parmi toutes les autres, et deviner laquelle était la sienne. Ici
/// le plan est montré tel quel, et seule CETTE réserve y est marquée.
///
/// Un appui agrandit le plan en plein écran (zoom, déplacement), repère
/// compris ; « Voir le plan » ouvre la visionneuse complète, avec toutes les
/// réserves du plan.
///
/// Les coordonnées sont des POURCENTAGES de la page (voir
/// [ReservePositionRef]) : le plan est affiché ici avec ses proportions
/// réelles et étiré exactement sur sa boîte, comme dans `PlanInteractif` qui a
/// produit le point — le repère tombe donc au même endroit, à n'importe quelle
/// taille.
class ApercuPlanReserve extends StatefulWidget {
  final ReservePlanRef plan;
  final ReservePositionRef? position;

  /// Numéro affiché sur l'étiquette du repère (« R-0003 »).
  final String libelle;

  /// Couleur du repère — celle du STATUT, comme les pastilles du plan.
  final Color couleur;

  /// Ouvre la visionneuse complète du plan. Nul : le lien n'apparaît pas.
  final VoidCallback? onOuvrirPlan;

  /// Remplace le téléchargement par le Dio de l'application (tests).
  final TelechargerPlan? telecharger;

  const ApercuPlanReserve({
    super.key,
    required this.plan,
    required this.position,
    required this.libelle,
    required this.couleur,
    this.onOuvrirPlan,
    this.telecharger,
  });

  @override
  State<ApercuPlanReserve> createState() => _ApercuPlanReserveState();
}

/// Un plan prêt à afficher : l'image rendue et ses proportions, plus le
/// document d'origine pour le plein écran (il y est re-rendu en haute
/// résolution par `PlanInteractif`, au lieu d'agrandir un aperçu flou).
class _Rendu {
  final Uint8List octets;
  final Uint8List image;

  /// Hauteur / largeur de la page.
  final double ratio;

  const _Rendu({required this.octets, required this.image, required this.ratio});
}

/// Rendus de la session, indexés par fichier et page.
///
/// Revenir sur une fiche — ou passer d'une réserve à sa voisine sur le même
/// plan — ne retélécharge rien. Plafond bas : une entrée peut porter un PDF de
/// plusieurs mégaoctets.
final Map<String, _Rendu> _cache = <String, _Rendu>{};
const int _cacheMax = 6;

String _cle(String url, int page) => '$url#$page';

/// L'en-tête `%PDF-`. On lit les OCTETS, jamais l'extension ni `format` —
/// même règle que `PlanInteractif` : un plan photographié arrive étiqueté
/// « pdf » par défaut.
bool _estPdf(Uint8List o) {
  const entete = [0x25, 0x50, 0x44, 0x46, 0x2D];
  if (o.length < entete.length) return false;
  for (var i = 0; i < entete.length; i++) {
    if (o[i] != entete[i]) return false;
  }
  return true;
}

Future<Uint8List?> _telechargerParDefaut(String url) async {
  // Par le Dio de l'application, qui porte le jeton exigé par `/uploads/*` —
  // un lien direct répondrait 401.
  final reponse = await sl<Dio>().get<List<int>>(
    url,
    options: Options(responseType: ResponseType.bytes),
  );
  final donnees = reponse.data;
  if (donnees == null || donnees.isEmpty) return null;
  return Uint8List.fromList(donnees);
}

Future<_Rendu> _rendre(Uint8List octets, int numeroPage) async {
  if (!_estPdf(octets)) {
    // Une image est sa propre page : seules ses proportions sont à lire.
    final image = await decodeImageFromList(octets);
    return _Rendu(octets: octets, image: octets, ratio: image.height / image.width);
  }

  final document = await PdfDocument.openData(octets);
  try {
    // `clamp` : un plan remplacé par une version plus courte ne doit pas faire
    // échouer la fiche — on montre la dernière page plutôt que rien.
    final page = await document.getPage(numeroPage.clamp(1, document.pagesCount));
    try {
      // Largeur FIXE, assez fine pour un écran de téléphone en haute densité
      // sans produire l'image de 100 Mo qu'un A0 donnerait à l'échelle 2.
      const largeur = 1400.0;
      final rendu = await page.render(
        width: largeur,
        height: page.height * largeur / page.width,
        format: PdfPageImageFormat.jpeg,
        // Sans fond explicite, un PDF sans calque de fond sort en traits noirs
        // sur du transparent.
        backgroundColor: '#FFFFFF',
      );
      final image = rendu?.bytes;
      if (image == null || image.isEmpty) throw StateError('rendu vide');
      return _Rendu(octets: octets, image: image, ratio: page.height / page.width);
    } finally {
      await page.close();
    }
  } finally {
    await document.close();
  }
}

class _ApercuPlanReserveState extends State<ApercuPlanReserve> {
  _Rendu? _rendu;
  bool _echec = false;

  int get _page => widget.position?.page ?? 1;

  @override
  void initState() {
    super.initState();
    _rendu = _cache[_cle(widget.plan.fichierUrl, _page)];
    if (_rendu == null) _charger();
  }

  @override
  void didUpdateWidget(ApercuPlanReserve ancien) {
    super.didUpdateWidget(ancien);
    final page = widget.position?.page ?? 1;
    if (ancien.plan.fichierUrl != widget.plan.fichierUrl || (ancien.position?.page ?? 1) != page) {
      _rendu = _cache[_cle(widget.plan.fichierUrl, page)];
      _echec = false;
      if (_rendu == null) _charger();
    }
  }

  Future<void> _charger() async {
    final url = widget.plan.fichierUrl;
    final page = _page;
    if (url.isEmpty) {
      _echec = true;
      return;
    }
    _Rendu? rendu;
    try {
      final octets = await (widget.telecharger ?? _telechargerParDefaut)(url);
      if (octets != null) rendu = await _rendre(octets, page);
    } catch (_) {
      // Réseau coupé, format sans visionneuse, fichier illisible : la fiche
      // reste utilisable, l'aperçu cède la place à un message.
      rendu = null;
    }
    if (!mounted) return;
    // La fiche a pu changer de plan pendant le téléchargement.
    if (url != widget.plan.fichierUrl || page != _page) return;
    if (rendu != null) {
      if (_cache.length >= _cacheMax) _cache.remove(_cache.keys.first);
      _cache[_cle(url, page)] = rendu;
    }
    setState(() {
      _rendu = rendu;
      _echec = rendu == null;
    });
  }

  void _agrandir() {
    final rendu = _rendu;
    if (rendu == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _PlanPleinEcran(
        titre: widget.plan.nom,
        octets: rendu.octets,
        page: _page,
        position: widget.position,
        couleur: widget.couleur,
        onOuvrirPlan: widget.onOuvrirPlan,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final plan = widget.plan;
    final rendu = _rendu;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.map_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.reserveEmplacementTitre,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
              ),
              if (widget.onOuvrirPlan != null)
                TextButton(
                  onPressed: widget.onOuvrirPlan,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 36),
                  ),
                  child: Text(l10n.reserveVoirPlan, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          Text(
            plan.version > 1 ? '${plan.nom} · v${plan.version}' : plan.nom,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
          if (rendu != null)
            _ImageAvecRepere(
              rendu: rendu,
              position: widget.position,
              libelle: widget.libelle,
              couleur: widget.couleur,
              onAppui: _agrandir,
            )
          else
            Container(
              height: _echec ? 90 : 190,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _echec
                  ? Text(
                      l10n.reserveApercuPlanIndisponible,
                      style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                    )
                  : const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
                    ),
            ),
          if (rendu != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.position == null ? l10n.reserveEmplacementNonPrecise : l10n.reserveEmplacementAgrandir,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Le plan à ses proportions réelles, et le repère de la réserve par-dessus.
class _ImageAvecRepere extends StatelessWidget {
  final _Rendu rendu;
  final ReservePositionRef? position;
  final String libelle;
  final Color couleur;
  final VoidCallback onAppui;

  const _ImageAvecRepere({
    required this.rendu,
    required this.position,
    required this.libelle,
    required this.couleur,
    required this.onAppui,
  });

  @override
  Widget build(BuildContext context) {
    // Hauteur plafonnée : un plan en long occuperait sinon tout l'écran. La
    // largeur se réduit alors d'autant — les proportions, elles, ne bougent
    // jamais, sans quoi le repère ne tomberait plus au bon endroit.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: Align(
        heightFactor: 1,
        child: AspectRatio(
          aspectRatio: 1 / rendu.ratio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GestureDetector(
              onTap: onAppui,
              child: LayoutBuilder(
                builder: (context, contraintes) {
                  final taille = Size(contraintes.maxWidth, contraintes.maxHeight);
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(border: Border.all(color: AppColors.border)),
                          child: Image.memory(
                            rendu.image,
                            key: const ValueKey('apercu-plan-image'),
                            fit: BoxFit.fill,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                      if (position != null)
                        ..._repere(context, taille, position!),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Le repère : un halo CENTRÉ sur le point, et une épingle dont la POINTE
  /// est sur le point — c'est la pointe qui désigne le défaut. Au-dessus,
  /// l'étiquette porte le numéro, pour qu'on ne la confonde avec rien d'autre.
  List<Widget> _repere(BuildContext context, Size taille, ReservePositionRef p) {
    const halo = 46.0;
    const epingle = 36.0;
    final px = p.x / 100 * taille.width;
    final py = p.y / 100 * taille.height;

    return [
      Positioned(
        left: px - halo / 2,
        top: py - halo / 2,
        width: halo,
        height: halo,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: couleur.withValues(alpha: 0.22),
              border: Border.all(color: couleur.withValues(alpha: 0.7), width: 2),
            ),
          ),
        ),
      ),
      Positioned(
        key: const ValueKey('repere-reserve'),
        left: px - epingle / 2,
        top: py - epingle,
        width: epingle,
        height: epingle,
        child: Semantics(
          label: context.l10n.reserveEmplacementIci,
          child: Icon(
            Icons.location_on,
            size: epingle,
            color: couleur,
            shadows: const [Shadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2))],
          ),
        ),
      ),
      Positioned(
        left: px,
        top: py - epingle - 24,
        child: FractionalTranslation(
          translation: const Offset(-0.5, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: couleur,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))],
            ),
            child: Text(
              libelle,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    ];
  }
}

/// Le plan en plein écran — zoom et déplacement, avec le seul repère de cette
/// réserve, actif.
class _PlanPleinEcran extends StatelessWidget {
  final String titre;
  final Uint8List octets;
  final int page;
  final ReservePositionRef? position;
  final Color couleur;
  final VoidCallback? onOuvrirPlan;

  const _PlanPleinEcran({
    required this.titre,
    required this.octets,
    required this.page,
    required this.position,
    required this.couleur,
    this.onOuvrirPlan,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = position;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(titre, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        actions: [
          if (onOuvrirPlan != null)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onOuvrirPlan!();
              },
              child: Text(l10n.reserveVoirPlan, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: SafeArea(
        child: PlanInteractif(
          octets: octets,
          page: page,
          controlesZoom: true,
          marqueurs: [
            if (p != null) MarqueurPlan(id: 'reserve', x: p.x, y: p.y, couleur: couleur, actif: true),
          ],
        ),
      ),
    );
  }
}

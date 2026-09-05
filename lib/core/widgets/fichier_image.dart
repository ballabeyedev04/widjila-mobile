import 'dart:collection';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../injection_container.dart';
import '../theme/app_colors.dart';

/// Charge une image stockée côté serveur — photos de réserves, pièces
/// jointes, logos privés.
///
/// POURQUOI PAS `Image.network` : les fichiers privés ne sont plus servis
/// publiquement (voir `backend/src/app.js`, montage `/uploads`). Ils passent
/// par `auth → checkActiveUser → checkFileAccess`, donc exigent l'en-tête
/// `Authorization`. Les URL stockées en base sont en outre RELATIVES
/// (`/uploads/medias/x.jpg`) : sans hôte ni jeton, `Image.network` ne peut
/// que échouer. On passe donc par le Dio de l'application, qui porte déjà
/// l'intercepteur d'authentification et la `baseUrl`.
///
/// Les octets sont mémorisés le temps de la session : une vignette qui
/// réapparaît en remontant une liste ne redéclenche pas de requête.
class FichierImage extends StatefulWidget {
  /// Vide le cache d'octets téléchargés — à appeler à la DÉCONNEXION.
  ///
  /// Le cache est un `static`, partagé par toute l'application et non lié à
  /// un compte : sans ce nettoyage, les photos d'un chantier restent
  /// décodées en mémoire après la déconnexion, prêtes à réapparaître si un
  /// second utilisateur se connecte sur le même appareil avant que le
  /// plafond de 24 Mo ne les évince naturellement. Sur un téléphone partagé
  /// par une équipe de chantier, ce n'est pas hypothétique.
  static void viderCache() => _CacheOctets.vider();

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;

  /// Décoder à la pleine résolution du fichier, au lieu de la taille
  /// d'affichage.
  ///
  /// À réserver à la vue plein écran zoomable : c'est le seul endroit où l'on
  /// a besoin des pixels d'origine. Partout ailleurs, décoder une photo de
  /// 4000 px pour l'afficher dans une vignette de 52 gaspille une centaine de
  /// méga-octets — voir [_LargeurDecodage].
  final bool pleineResolution;

  const FichierImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.pleineResolution = false,
  });

  @override
  State<FichierImage> createState() => _FichierImageState();
}

/// Cache des octets TÉLÉCHARGÉS, borné en MÉMOIRE.
///
/// ## Pourquoi en octets et non en nombre d'entrées
///
/// Le plafond était de 80 entrées, sans regarder leur poids. Or ce ne sont pas
/// des vignettes : ce sont les fichiers d'origine, pris avec l'appareil photo
/// d'un téléphone — trois à cinq méga-octets pièce. Quatre-vingts de ces
/// fichiers, c'est de l'ordre de 300 Mo de mémoire retenue pour des images que
/// l'utilisateur a fait défiler une fois. Sur un téléphone d'entrée de gamme,
/// c'est le système qui tranche : il tue l'application.
///
/// Compter les octets borne le vrai coût. Vingt-quatre méga-octets laissent
/// largement de quoi remonter une liste sans re-télécharger, et tiennent dans
/// n'importe quel appareil.
class _CacheOctets {
  static final LinkedHashMap<String, Uint8List> _entrees = LinkedHashMap();
  static int _retenus = 0;

  static const int plafond = 24 * 1024 * 1024;

  static Uint8List? lire(String url) => _entrees[url];

  static void memoriser(String url, Uint8List octets) {
    final poids = octets.lengthInBytes;
    // Un fichier plus gros que le plafond entier ne serait retenu qu'au prix
    // de tout vider : on préfère le re-télécharger.
    if (poids > plafond) return;

    while (_retenus + poids > plafond && _entrees.isNotEmpty) {
      final plusAncienne = _entrees.keys.first;
      _retenus -= _entrees.remove(plusAncienne)!.lengthInBytes;
    }

    _entrees[url] = octets;
    _retenus += poids;
  }

  /// Téléchargements EN COURS, pour qu'une même URL affichée par plusieurs
  /// vignettes ne parte qu'une fois.
  ///
  /// Sans cela, faire défiler vite une liste où la même photo revient — le cas
  /// d'un plan de masse repris sur plusieurs cartes — lançait autant de
  /// requêtes que d'apparitions, toutes pour le même fichier.
  static final Map<String, Future<Uint8List?>> enVol = {};

  static void vider() {
    _entrees.clear();
    _retenus = 0;
    // Les téléchargements déjà en vol ne sont PAS annulés : ils sont sans
    // rapport avec le compte connecté (une URL ne se recoupe pas entre
    // organisations) et les interrompre ferait échouer un widget qui les
    // attend encore à l'écran, au milieu d'une transition d'écran.
  }
}

class _FichierImageState extends State<FichierImage> {
  Uint8List? _octets;
  bool _echec = false;

  @override
  void initState() {
    super.initState();
    // Le cache est consulté DÈS la première construction : une image déjà
    // connue s'affiche sans passer par le gabarit gris.
    final url = widget.url;
    if (url != null) _octets = _CacheOctets.lire(url);
    if (_octets == null) _charger();
  }

  @override
  void didUpdateWidget(covariant FichierImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _octets = widget.url == null ? null : _CacheOctets.lire(widget.url!);
      _echec = false;
      if (_octets == null) _charger();
    }
  }

  Future<void> _charger() async {
    final url = widget.url;
    if (url == null || url.isEmpty) return;

    final enCours = _CacheOctets.enVol[url];
    final future = enCours ?? _telecharger(url);
    if (enCours == null) _CacheOctets.enVol[url] = future;

    final octets = await future;
    if (!mounted) return;
    setState(() {
      _octets = octets;
      _echec = octets == null;
    });
  }

  static Future<Uint8List?> _telecharger(String url) async {
    try {
      final response = await sl<Dio>().get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null) return null;
      final octets = Uint8List.fromList(data);
      _CacheOctets.memoriser(url, octets);
      return octets;
    } catch (_) {
      return null;
    } finally {
      _CacheOctets.enVol.remove(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final octets = _octets;
    if (octets == null) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: widget.placeholder ??
            Container(
              color: AppColors.neutralBg,
              child: Icon(
                _echec ? Icons.broken_image_outlined : Icons.image_outlined,
                color: AppColors.textMuted,
                size: 22,
              ),
            ),
      );
    }

    return _LargeurDecodage(
      pleineResolution: widget.pleineResolution,
      largeurDemandee: widget.width,
      builder: (largeurCible) => Image.memory(
        octets,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        // Décodage à la taille d'AFFICHAGE.
        //
        // C'est la seule ligne qui sépare une liste fluide d'une application
        // qui se fait tuer par le système : sans elle, une photo de 4000×3000
        // occupe 48 Mo une fois décodée en mémoire, qu'on l'affiche en plein
        // écran ou dans un carré de 52 points.
        cacheWidth: largeurCible,
        // `filterQuality` bas : l'image est déjà décodée à la bonne taille,
        // un rééchantillonnage coûteux au moment de peindre n'apporterait
        // plus rien.
        filterQuality: FilterQuality.low,
      ),
    );
  }
}

/// Détermine à quelle largeur décoder, d'après la place réellement occupée.
///
/// La taille d'affichage n'est pas toujours passée en paramètre : la plupart
/// des vignettes se laissent dimensionner par leur parent. Elle n'est donc
/// connue qu'à la mise en page, d'où ce [LayoutBuilder].
class _LargeurDecodage extends StatelessWidget {
  final bool pleineResolution;
  final double? largeurDemandee;
  final Widget Function(int? largeurCible) builder;

  const _LargeurDecodage({
    required this.pleineResolution,
    required this.largeurDemandee,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    if (pleineResolution) return builder(null);

    final densite = MediaQuery.devicePixelRatioOf(context);

    // Taille explicite : pas besoin de mesurer.
    final demandee = largeurDemandee;
    if (demandee != null && demandee.isFinite && demandee > 0) {
      return builder((demandee * densite).ceil());
    }

    return LayoutBuilder(
      builder: (context, contraintes) {
        final largeur = contraintes.maxWidth;
        // Largeur non bornée (dans une rangée qui défile horizontalement, par
        // exemple) : on ne peut rien déduire, on décode tel quel plutôt que
        // d'inventer une taille et de rendre l'image floue.
        if (!largeur.isFinite || largeur <= 0) return builder(null);
        return builder((largeur * densite).ceil());
      },
    );
  }
}

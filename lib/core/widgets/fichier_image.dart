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
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;

  const FichierImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  @override
  State<FichierImage> createState() => _FichierImageState();
}

class _FichierImageState extends State<FichierImage> {
  /// Cache mémoire borné — au-delà de [_tailleMaxCache] entrées, la plus
  /// ancienne est évincée (LinkedHashMap conserve l'ordre d'insertion).
  static final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  static const _tailleMaxCache = 80;

  Uint8List? _octets;
  bool _echec = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void didUpdateWidget(covariant FichierImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _octets = null;
      _echec = false;
      _charger();
    }
  }

  Future<void> _charger() async {
    final url = widget.url;
    if (url == null || url.isEmpty) return;

    final enCache = _cache[url];
    if (enCache != null) {
      setState(() => _octets = enCache);
      return;
    }

    try {
      final response = await sl<Dio>().get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null) throw Exception('Réponse vide');
      final octets = Uint8List.fromList(data);

      if (_cache.length >= _tailleMaxCache) _cache.remove(_cache.keys.first);
      _cache[url] = octets;

      if (mounted) setState(() => _octets = octets);
    } catch (_) {
      if (mounted) setState(() => _echec = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final octets = _octets;
    if (octets != null) {
      return Image.memory(octets, width: widget.width, height: widget.height, fit: widget.fit);
    }
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
}

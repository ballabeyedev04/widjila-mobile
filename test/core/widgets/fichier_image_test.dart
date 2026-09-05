import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/widgets/fichier_image.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

/// Un PNG 1×1 valide — assez pour que `Image.memory` décode sans erreur.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

class _Adaptateur implements HttpClientAdapter {
  final List<String> appels = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    appels.add(options.uri.path);
    return ResponseBody.fromBytes(_png, 200);
  }

  @override
  void close({bool force = false}) {}
}

/// Chargement des images privées du serveur.
///
/// ## Ce que ces tests protègent
///
/// Une photo prise avec un téléphone fait couramment 4000×3000. Décodée, elle
/// occupe une cinquantaine de méga-octets EN MÉMOIRE — que l'on veuille
/// l'afficher en plein écran ou dans un carré de 52 points. Une liste de
/// réserves en affiche des dizaines : c'est la façon la plus rapide de faire
/// tuer une application par le système sur un téléphone d'entrée de gamme.
///
/// `cacheWidth` demande au décodeur de produire directement l'image à la
/// taille utile. Le test vérifie que cette instruction est bien posée, et
/// qu'elle est bien LEVÉE là où l'on zoome — sinon la vue plein écran
/// deviendrait floue, ce qui serait passé pour un problème d'appareil photo.
void main() {
  late _Adaptateur adaptateur;

  setUp(() {
    adaptateur = _Adaptateur();
    if (sl.isRegistered<Dio>()) sl.unregister<Dio>();
    sl.registerSingleton<Dio>(
      Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adaptateur,
    );
  });

  tearDown(() {
    if (sl.isRegistered<Dio>()) sl.unregister<Dio>();
  });

  Future<Image> pomper(WidgetTester tester, Widget enfant) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: enfant)),
    ));
    await tester.pumpAndSettle();
    return tester.widget<Image>(find.byType(Image));
  }

  testWidgets('une vignette est décodée à sa taille d’affichage', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final image = await pomper(
      tester,
      const FichierImage(url: '/uploads/photo-1.jpg', width: 52, height: 52),
    );

    // 52 points × densité 2 = 104 pixels. Pas 4000.
    expect(image.width, 52);
    expect(
      (image.image as ResizeImage).width,
      104,
      reason: 'sans cela, chaque vignette décode la photo entière en mémoire',
    );
  });

  testWidgets('sans taille explicite, la place réellement occupée fait foi', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final image = await pomper(
      tester,
      const SizedBox(
        width: 120,
        height: 80,
        child: FichierImage(url: '/uploads/photo-2.jpg'),
      ),
    );

    expect((image.image as ResizeImage).width, 120);
  });

  testWidgets('la vue zoomable garde la pleine résolution', (tester) async {
    final image = await pomper(
      tester,
      const SizedBox(
        width: 200,
        height: 200,
        // Réduire ici rendrait le zoom flou — et l'utilisateur croirait que
        // c'est sa photo qui est mauvaise.
        child: FichierImage(url: '/uploads/photo-3.jpg', pleineResolution: true),
      ),
    );

    expect(image.image, isNot(isA<ResizeImage>()));
  });

  testWidgets('la même image affichée deux fois ne part qu’une fois sur le réseau',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: const [
            SizedBox(width: 40, height: 40, child: FichierImage(url: '/uploads/meme.jpg')),
            SizedBox(width: 40, height: 40, child: FichierImage(url: '/uploads/meme.jpg')),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Deux vignettes montées dans la même image : sans regroupement des
    // téléchargements en cours, chacune lançait sa propre requête.
    expect(adaptateur.appels, hasLength(1));
  });

  group('viderCache', () {
    // Le cache est un `static`, partagé par toute l'application — donc
    // toujours en place après une déconnexion si personne ne le vide. Sur un
    // téléphone de chantier partagé par une équipe, les photos du compte
    // précédent resteraient prêtes à réapparaître pour le suivant.
    //
    // Entre chaque affichage, on démonte le widget (un écran vide) plutôt que
    // de remonter directement le même : `pumpWidget` réconcilie un arbre
    // structurellement identique sur le MÊME State (`didUpdateWidget`, qui ne
    // recharge à juste titre pas quand l'URL n'a pas changé), ce qui ne
    // représenterait pas le cas réel visé — une déconnexion navigue vers un
    // tout autre écran, démontant réellement l'ancien `FichierImage`.
    Future<void> demonter(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }

    testWidgets('force un nouveau téléchargement au lieu de servir le cache', (tester) async {
      const url = '/uploads/a-vider.jpg';

      await pomper(tester, const SizedBox(width: 40, height: 40, child: FichierImage(url: url)));
      expect(adaptateur.appels, hasLength(1));
      await demonter(tester);

      // Remonter en widget NEUF sans vider entre-temps ne redéclenche rien :
      // vérifie que le test observe bien le cache, pas un hasard de timing.
      await pomper(tester, const SizedBox(width: 40, height: 40, child: FichierImage(url: url)));
      expect(adaptateur.appels, hasLength(1), reason: 'le cache aurait dû servir cette seconde image');
      await demonter(tester);

      FichierImage.viderCache();

      await pomper(tester, const SizedBox(width: 40, height: 40, child: FichierImage(url: url)));
      expect(adaptateur.appels, hasLength(2), reason: 'le cache vidé doit forcer un re-téléchargement');
    });
  });
}

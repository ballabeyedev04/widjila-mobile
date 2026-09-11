import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/services/capture_photo.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/fichier_image.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/loading_list.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/document.dart';
import '../../domain/formats_document.dart';
import '../cubit/documents_list_cubit.dart';
import '../cubit/documents_list_state.dart';
import '../widgets/actions_document.dart';
import '../../../../core/network/forcer_reseau.dart';

/// Écran 6 de la maquette — « Photos & documents » d'un chantier.
///
/// Les trois onglets viennent d'une SEULE source (la GED du chantier,
/// `GET /chantiers/:id/documents`) répartie par format côté client : le back
/// n'expose pas de route « médias du chantier » distincte, et les photos de
/// réserves appartiennent à leur réserve, pas au chantier.
///
/// Chaque onglet a son geste d'ajout — appareil photo, caméra, fichiers de
/// l'appareil — et chaque fichier se VOIT dans l'application (PDF, photo),
/// se TÉLÉCHARGE ou s'OUVRE dans une autre application : voir
/// `widgets/actions_document.dart`.
class DocumentsListPage extends StatelessWidget {
  final String chantierId;
  const DocumentsListPage({super.key, required this.chantierId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<DocumentsListCubit>(param1: chantierId)..charger(),
      child: const _MediathequeView(),
    );
  }
}

class _MediathequeView extends StatefulWidget {
  const _MediathequeView();

  @override
  State<_MediathequeView> createState() => _MediathequeViewState();
}

class _MediathequeViewState extends State<_MediathequeView> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this)
    ..addListener(_surChangementOnglet);

  /// Onglet courant, gardé à part pour ne reconstruire qu'au CHANGEMENT :
  /// le contrôleur notifie aussi pendant l'animation de balayage.
  int _onglet = 0;

  void _surChangementOnglet() {
    if (_tabController.index != _onglet) setState(() => _onglet = _tabController.index);
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_surChangementOnglet)
      ..dispose();
    super.dispose();
  }

  /// Le geste d'ajout dépend de l'onglet courant : photo et vidéo passent par
  /// `image_picker` (caméra ou galerie), un document par le sélecteur de
  /// fichiers de l'appareil.
  Future<void> _deposer(BuildContext context) async {
    final cubit = context.read<DocumentsListCubit>();
    final onglet = _tabController.index;

    if (onglet == 2) {
      await _deposerDocument(context, cubit);
      return;
    }

    final source = await _choisirSource(context);
    if (source == null || !context.mounted) return;

    // PHOTO : `capturerPhoto`, qui récupère le cliché mis en attente quand
    // Android détruit l'activité pendant la prise de vue — sans quoi la photo
    // semble perdue au retour (voir `core/services/capture_photo.dart`).
    //
    // Le plafond de 1920 px reste : à sa résolution native, une photo de
    // document pèse 3 à 8 Mo pour un rendu qui ne dépasse jamais l'écran, et
    // 1920 px suffit largement à en relire le texte.
    //
    // VIDÉO : `pickVideo` est laissé tel quel. La reprise d'`image_picker` ne
    // couvre que les images, et une vidéo ne se recompresse pas ici.
    String? chemin;
    if (onglet == 0) {
      try {
        chemin = (await capturerPhoto(source))?.path;
      } on PhotoIndisponible {
        if (context.mounted) {
          AppAlert.error(context, message: context.l10n.reserveNouvPhotoIndisponible);
        }
        return;
      }
    } else {
      chemin = (await ImagePicker().pickVideo(source: source))?.path;
      if (chemin != null) {
        // Refusée AVANT l'envoi si elle dépasse le plafond du serveur : sinon
        // l'utilisateur attend la fin d'un long envoi pour apprendre l'échec.
        if (!context.mounted) return;
        if (!await _videoAcceptable(context, chemin)) return;
      }
    }
    if (chemin == null) return;

    await cubit.deposer(
      cheminFichier: chemin,
      type: onglet == 0 ? DocumentType.photo : DocumentType.autre,
    );
  }

  /// Dépôt d'un document (PDF, Word, Excel, PowerPoint, DWG) choisi dans les
  /// fichiers de l'appareil.
  ///
  /// `FileType.any` plutôt qu'un filtre par extension : Android ne connaît pas
  /// de type MIME pour certains formats métier (DWG) et les grise alors dans
  /// le sélecteur, sans explication. Le format est donc contrôlé APRÈS le
  /// choix, avec un message qui dit ce qui est accepté.
  Future<void> _deposerDocument(BuildContext context, DocumentsListCubit cubit) async {
    final choix = await FilePicker.platform.pickFiles(type: FileType.any, withData: false);
    final fichier = choix?.files.singleOrNull;
    final chemin = fichier?.path;
    if (fichier == null || chemin == null || !context.mounted) return;

    final l10n = context.l10n;
    if (!FormatsDocument.estDocumentAccepte(fichier.name)) {
      AppAlert.error(context, message: l10n.documentFormatNonSupporte);
      return;
    }
    if (fichier.size > FormatsDocument.tailleMaxDocument) {
      AppAlert.error(
        context,
        message: l10n.documentFichierTropVolumineux(_plafondLisible(context, FormatsDocument.tailleMaxDocument)),
      );
      return;
    }

    final type = await _choisirTypeDocument(context);
    if (type == null) return;

    // Le nom d'origine part avec le fichier : le sélecteur travaille sur une
    // copie en cache, dont le nom n'a rien à faire dans la GED.
    await cubit.deposer(cheminFichier: chemin, type: type, nomFichier: fichier.name);
  }

  Future<bool> _videoAcceptable(BuildContext context, String chemin) async {
    final int taille;
    try {
      taille = await File(chemin).length();
    } on FileSystemException {
      // Taille illisible : le serveur tranchera.
      return true;
    }
    if (taille <= FormatsDocument.tailleMaxVideo) return true;
    if (context.mounted) {
      AppAlert.error(
        context,
        message: context.l10n.documentFichierTropVolumineux(
          _plafondLisible(context, FormatsDocument.tailleMaxVideo),
        ),
      );
    }
    return false;
  }

  String _plafondLisible(BuildContext context, int octets) =>
      context.l10n.documentTailleMo('${octets ~/ (1024 * 1024)}');

  /// Nature métier du document déposé : c'est elle qui s'affiche sous son nom
  /// et sert au filtre de la GED, sur le web comme ici.
  Future<DocumentType?> _choisirTypeDocument(BuildContext context) {
    final l10n = context.l10n;
    const types = [
      DocumentType.contrat,
      DocumentType.doe,
      DocumentType.pv,
      DocumentType.compteRendu,
      DocumentType.rapport,
      DocumentType.notice,
      DocumentType.plan,
      DocumentType.autre,
    ];

    return showModalBottomSheet<DocumentType>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Text(
                  l10n.documentTypeChoixTitre,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final type in types)
                      ListTile(
                        leading: const Icon(Icons.description_outlined, color: AppColors.primary),
                        title: Text(type.label(l10n)),
                        onTap: () => Navigator.of(sheetContext).pop(type),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<ImageSource?> _choisirSource(BuildContext context) {
    final l10n = context.l10n;
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (context) => SafeArea(
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
              title: Text(l10n.documentPrendrePhoto),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
              title: Text(l10n.documentChoisirGalerie),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Icône du bouton d'ajout : elle dit ce que le bouton va ouvrir.
  IconData get _iconeAjout => switch (_onglet) {
        0 => Icons.add_a_photo_outlined,
        1 => Icons.video_call_outlined,
        _ => Icons.upload_file_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final role = context.select((AuthBloc b) => b.state.utilisateur?.role);
    // Miroir de `requireRole(...OPERATIONNEL_CONTROLE)` sur
    // POST /chantiers/:chantierId/documents.
    final peutDeposer = role?.estOperationnelOuControle ?? false;

    final l10n = context.l10n;

    return BlocConsumer<DocumentsListCubit, DocumentsListState>(
      listenWhen: (a, b) => a.depotStatus != b.depotStatus,
      listener: (context, state) {
        if (state.depotStatus == DepotStatus.succes) {
          AppAlert.success(context, message: l10n.documentFichierAjoute);
          context.read<DocumentsListCubit>().accuserReceptionDepot();
        } else if (state.depotStatus == DepotStatus.erreur) {
          AppAlert.error(context, message: state.depotErreur ?? l10n.documentEnvoiEchec);
          context.read<DocumentsListCubit>().accuserReceptionDepot();
        }
      },
      builder: (context, state) {
        final enDepot = state.depotStatus == DepotStatus.enCours;
        final progression = state.depotProgression;

        return Scaffold(
          // Blanc, comme Réserves et Plans. Les grilles et listes reposent,
          // elles, sur le gris de fond : des vignettes blanches sur une page
          // blanche perdraient tout relief.
          backgroundColor: AppColors.surface,
          floatingActionButton: peutDeposer
              ? FloatingActionButton.extended(
                  onPressed: enDepot ? null : () => _deposer(context),
                  backgroundColor: enDepot ? AppColors.textMuted : AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 6,
                  shape: const StadiumBorder(),
                  icon: enDepot
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            value: progression,
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(_iconeAjout),
                  label: Text(
                    !enDepot
                        ? l10n.commonAdd
                        : progression == null
                            ? l10n.documentEnvoiEnCours
                            : l10n.documentEnvoiProgression((progression * 100).floor()),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                )
              : null,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                ContenuCentre(
                  child: EnTeteListe(
                    titre: l10n.documentPageTitre,
                    avecRetour: true,
                    // Écran plein hors coquille : le NotificationsCubit dont
                    // dépend la cloche n'y est pas fourni.
                    avecCloche: false,
                  ),
                ),
                _BarreOnglets(controleur: _tabController, state: state),
                Expanded(child: _corps(context, state)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _corps(BuildContext context, DocumentsListState state) {
    final l10n = context.l10n;
    switch (state.status) {
      case DocumentsListStatus.initial:
      case DocumentsListStatus.chargement:
        return const LoadingList();
      case DocumentsListStatus.erreur:
        return ErrorView(
          message: state.erreur ?? l10n.commonErrorUnknown,
          onRetry: () => context.read<DocumentsListCubit>().charger(),
        );
      case DocumentsListStatus.succes:
        return TabBarView(
          controller: _tabController,
          children: [
            _GrilleMedias(
              items: state.photos,
              vide: l10n.documentAucunePhoto,
              sousTitreVide: l10n.documentAucunePhotoDescription,
            ),
            _GrilleMedias(
              items: state.videos,
              estVideo: true,
              vide: l10n.documentAucuneVideo,
              sousTitreVide: l10n.documentAucuneVideoDescription,
            ),
            _ListeDocuments(items: state.autresDocuments),
          ],
        );
    }
  }
}

/// Barre des trois onglets, posée sous l'en-tête.
///
/// Détachée de l'`AppBar` supprimée : l'écran suit désormais l'armature de la
/// maquette (titre 27 px + flèche), et une `TabBar` Material y serait restée
/// le seul élément à trahir l'ancienne barre. Les compteurs collés au libellé
/// disent d'un coup d'œil ce que chaque onglet contient.
class _BarreOnglets extends StatelessWidget {
  final TabController controleur;
  final DocumentsListState state;

  const _BarreOnglets({required this.controleur, required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return ContenuCentre(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(30),
          ),
          padding: const EdgeInsets.all(4),
          child: TabBar(
            controller: controleur,
            // Indicateur en pilule pleine plutôt qu'un trait sous le libellé :
            // même vocabulaire que les puces de filtre des autres listes.
            indicator: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.30),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
            splashBorderRadius: BorderRadius.circular(26),
            tabs: [
              Tab(height: 38, text: l10n.documentOngletPhotos(state.photos.length)),
              Tab(height: 38, text: l10n.documentOngletVideos(state.videos.length)),
              Tab(height: 38, text: l10n.documentOngletDocuments(state.autresDocuments.length)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grille de vignettes — photos et vidéos.
class _GrilleMedias extends StatelessWidget {
  final List<ChantierDocument> items;
  final bool estVideo;
  final String vide;
  final String sousTitreVide;

  const _GrilleMedias({
    required this.items,
    required this.vide,
    required this.sousTitreVide,
    this.estVideo = false,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return EtatVideIllustre(
        motif: MotifVide.document,
        titre: vide,
        description: sousTitreVide,
      );
    }

    return ColoredBox(
      color: AppColors.background,
      child: RefreshIndicator(
      color: AppColors.primary,
      onRefresh: forcerReseau(() => context.read<DocumentsListCubit>().charger()),
      child: ContenuCentre(
        // `LayoutBuilder` : le nombre de colonnes suit la largeur RESTANTE
        // après le plafond de `ContenuCentre`, pas la largeur brute de
        // l'écran — sinon une tablette calculerait ses colonnes sur 1000 px
        // alors que la grille elle-même ne fait que 560 px de large.
        child: LayoutBuilder(
          builder: (context, constraints) => GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              // 2 colonnes fixes laissaient les vignettes minuscules sur
              // tablette ; adaptatif, la grille en ajoute à mesure que la
              // largeur augmente, jusqu'à 5.
              crossAxisCount: colonnesAdaptatives(constraints.maxWidth),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => _Vignette(document: items[i], estVideo: estVideo),
          ),
        ),
      ),
      ),
    );
  }
}

class _Vignette extends StatelessWidget {
  final ChantierDocument document;
  final bool estVideo;
  const _Vignette({required this.document, required this.estVideo});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Photo : aperçu plein écran dans l'application. Vidéo : lecteur du
      // téléphone — voir `voirDocument`.
      onTap: () => voirDocument(context, document),
      onLongPress: () => afficherActionsDocument(context, document),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Une vidéo n'a pas de vignette exploitable côté back : fond
            // neutre plutôt qu'une image cassée.
            if (estVideo)
              Container(
                color: AppColors.textPrimary.withValues(alpha: 0.85),
                child: const Center(
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.white70,
                    child: Icon(Icons.play_arrow_rounded, color: AppColors.textPrimary),
                  ),
                ),
              )
            else
              FichierImage(url: document.fichierUrl, fit: BoxFit.cover),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withValues(alpha: 0.65), Colors.transparent],
                  ),
                ),
                child: Text(
                  document.nomFichier,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: _BoutonActions(document: document, surVignette: true),
            ),
          ],
        ),
      ),
    );
  }
}

/// Liste des documents « bureautiques » — PDF, Word, Excel, DWG…
class _ListeDocuments extends StatelessWidget {
  final List<ChantierDocument> items;
  const _ListeDocuments({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return EtatVideIllustre(
        motif: MotifVide.document,
        titre: context.l10n.documentAucunDocument,
        description: context.l10n.documentAucunDocumentDescription,
      );
    }

    return ColoredBox(
      color: AppColors.background,
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: forcerReseau(() => context.read<DocumentsListCubit>().charger()),
        child: ContenuCentre(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _LigneDocument(document: items[i]),
          ),
        ),
      ),
    );
  }
}

class _LigneDocument extends StatelessWidget {
  final ChantierDocument document;
  const _LigneDocument({required this.document});

  /// Icône et teinte déduites de l'EXTENSION : le `mime_type` peut valoir
  /// `application/octet-stream` pour les formats métier (DWG, IFC) déposés
  /// avant que le serveur ne le déduise du contenu.
  ({IconData icon, Color couleur}) get _apparence {
    switch (document.extension) {
      case 'pdf':
        return (icon: Icons.picture_as_pdf_rounded, couleur: AppColors.danger);
      case 'dwg':
      case 'dxf':
        return (icon: Icons.architecture_rounded, couleur: AppColors.info);
      case 'xls':
      case 'xlsx':
      case 'csv':
        return (icon: Icons.table_chart_rounded, couleur: AppColors.success);
      case 'doc':
      case 'docx':
        return (icon: Icons.article_rounded, couleur: AppColors.info);
      case 'ppt':
      case 'pptx':
        return (icon: Icons.slideshow_rounded, couleur: AppColors.warning);
      default:
        return (icon: Icons.insert_drive_file_rounded, couleur: AppColors.neutral);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final apparence = _apparence;
    final tailleLisible = document.tailleLisible(l10n);
    final details = [
      document.type.label(l10n),
      ?tailleLisible,
      if (document.createdAt != null) DateFormat('dd/MM/yyyy').format(document.createdAt!),
    ].join(' · ');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => voirDocument(context, document),
        onLongPress: () => afficherActionsDocument(context, document),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: apparence.couleur.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(apparence.icon, color: apparence.couleur, size: 22),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      document.nomFichier,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(details, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              _BoutonActions(document: document),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bouton « ⋮ » : Voir, Télécharger, Ouvrir avec une autre application.
class _BoutonActions extends StatelessWidget {
  final ChantierDocument document;
  final bool surVignette;
  const _BoutonActions({required this.document, this.surVignette = false});

  @override
  Widget build(BuildContext context) {
    final bouton = IconButton(
      tooltip: context.l10n.documentPlusActions,
      onPressed: () => afficherActionsDocument(context, document),
      icon: const Icon(Icons.more_vert_rounded),
      iconSize: 20,
      color: surVignette ? Colors.white : AppColors.textMuted,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
    if (!surVignette) return bouton;

    // Pastille sombre : le bouton doit rester lisible sur une photo claire.
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
      child: bouton,
    );
  }
}

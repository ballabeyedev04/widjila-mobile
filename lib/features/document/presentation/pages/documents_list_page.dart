import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/ouverture_fichier.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/fichier_image.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/loading_list.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/document.dart';
import '../cubit/documents_list_cubit.dart';
import '../cubit/documents_list_state.dart';
import '../../../../core/network/forcer_reseau.dart';

/// Écran 6 de la maquette — « Photos & documents » d'un chantier.
///
/// Les trois onglets viennent d'une SEULE source (la GED du chantier,
/// `GET /chantiers/:id/documents`) répartie par type MIME côté client : le
/// back n'expose pas de route « médias du chantier » distincte, et les photos
/// de réserves appartiennent à leur réserve, pas au chantier.
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
  late final TabController _tabController = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// La source dépend de l'onglet courant : photo/vidéo passent par
  /// `image_picker` (galerie ou caméra). L'onglet Documents n'a pas de
  /// sélecteur de fichiers — `file_picker` n'est pas dans le projet — donc on
  /// le dit plutôt que d'afficher un bouton sans effet.
  Future<void> _deposer(BuildContext context) async {
    final cubit = context.read<DocumentsListCubit>();
    final onglet = _tabController.index;

    if (onglet == 2) {
      AppAlert.error(context, message: context.l10n.documentAjoutDepuisWeb);
      return;
    }

    final source = await _choisirSource(context);
    if (source == null) return;

    final picker = ImagePicker();
    // `maxWidth: 1920` — même plafond que les photos de réserve
    // (`nouvelle_reserve_sheet.dart`) : sans lui, une photo de document prise
    // à l'appareil part à sa résolution native (souvent 3 à 8 Mo) pour un
    // rendu qui ne dépasse jamais l'écran. 1920 px reste largement suffisant
    // pour relire le texte d'un document photographié.
    final fichier = onglet == 0
        ? await picker.pickImage(source: source, imageQuality: 85, maxWidth: 1920)
        : await picker.pickVideo(source: source);
    if (fichier == null) return;

    await cubit.deposer(
      cheminFichier: fichier.path,
      type: onglet == 0 ? DocumentType.photo : DocumentType.autre,
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
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                        )
                      : const Icon(Icons.add_a_photo_outlined),
                  label: Text(
                    enDepot ? l10n.documentEnvoiEnCours : l10n.commonAdd,
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
      onTap: () => _ouvrirDocument(context, document),
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
          ],
        ),
      ),
    );
  }
}

/// Liste des documents « bureautiques » — PDF, DWG, tableurs…
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

  /// Icône et teinte déduites de l'EXTENSION : le `mime_type` est renseigné
  /// par la détection de magic bytes côté back et vaut souvent
  /// `application/octet-stream` pour les formats métier (DWG, IFC).
  ({IconData icon, Color couleur}) get _apparence {
    final nom = document.nomFichier.toLowerCase();
    if (nom.endsWith('.pdf')) return (icon: Icons.picture_as_pdf_rounded, couleur: AppColors.danger);
    if (nom.endsWith('.dwg') || nom.endsWith('.dxf')) return (icon: Icons.architecture_rounded, couleur: AppColors.info);
    if (nom.endsWith('.xlsx') || nom.endsWith('.csv')) return (icon: Icons.table_chart_rounded, couleur: AppColors.success);
    if (nom.endsWith('.doc') || nom.endsWith('.docx')) return (icon: Icons.article_rounded, couleur: AppColors.info);
    return (icon: Icons.insert_drive_file_rounded, couleur: AppColors.neutral);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final apparence = _apparence;
    final tailleLisible = document.tailleLisible(l10n);
    final details = [
      document.type.label(l10n),
      if (tailleLisible != null) tailleLisible,
      if (document.createdAt != null) DateFormat('dd/MM/yyyy').format(document.createdAt!),
    ].join(' · ');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _ouvrirDocument(context, document),
        child: Container(
          padding: const EdgeInsets.all(14),
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
              const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ouverture d'un fichier.
///
/// `/uploads/*` exige le jeton d'authentification : un lien direct confié au
/// navigateur système répondrait 401. Les octets transitent donc par le Dio
/// applicatif, sont écrits dans un dossier temporaire, puis confiés à
/// l'application système capable de les lire — voir [OuvertureFichier].
///
/// Un indicateur modal couvre l'attente : sur un chantier, un PDF de plusieurs
/// mégaoctets en 3G prend plusieurs secondes, et un écran qui ne réagit pas
/// donne l'impression que le tap n'a pas été pris en compte.
Future<void> _ouvrirDocument(BuildContext context, ChantierDocument document) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _DialogueTelechargement(),
  );

  final resultat = await sl<OuvertureFichier>().ouvrir(
    url: document.fichierUrl,
    nomFichier: document.nomFichier,
  );

  navigator.pop(); // referme l'indicateur
  if (!context.mounted) return;

  resultat.fold(
    (failure) => AppAlert.error(context, title: document.nomFichier, message: failure.errorMessage),
    (issue) {
      // Fichier bien téléchargé mais illisible par l'appareil (un DWG sur un
      // téléphone nu) : ce n'est pas une panne réseau, le message doit le dire.
      if (issue == ResultatOuverture.aucuneApplication) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.documentAucuneApplication)));
      }
    },
  );
}

/// Indicateur d'attente pendant le téléchargement.
class _DialogueTelechargement extends StatelessWidget {
  const _DialogueTelechargement();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Text(
                context.l10n.documentOuvertureEnCours,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

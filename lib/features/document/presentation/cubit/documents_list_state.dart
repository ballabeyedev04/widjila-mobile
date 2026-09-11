import 'package:equatable/equatable.dart';
import '../../domain/entities/document.dart';

enum DocumentsListStatus { initial, chargement, succes, erreur }

/// Statut du DÉPÔT d'un fichier, distinct de celui de la liste : un échec
/// d'envoi ne doit pas effacer la médiathèque déjà affichée.
enum DepotStatus { inactif, enCours, succes, erreur }

class DocumentsListState extends Equatable {
  final DocumentsListStatus status;
  final List<ChantierDocument> items;
  final String recherche;
  final DocumentType? filtreType;
  final String? erreur;

  final DepotStatus depotStatus;
  final String? depotErreur;

  /// Part déjà envoyée du dépôt en cours, de 0 à 1 — `null` tant que rien
  /// n'a été signalé. Une vidéo de chantier met plusieurs dizaines de
  /// secondes à partir : sans chiffre, le bouton semble figé.
  final double? depotProgression;

  const DocumentsListState({
    this.status = DocumentsListStatus.initial,
    this.items = const [],
    this.recherche = '',
    this.filtreType,
    this.erreur,
    this.depotStatus = DepotStatus.inactif,
    this.depotErreur,
    this.depotProgression,
  });

  /// Répartition par nature de fichier — les trois onglets de l'écran
  /// « Photos & documents ». Le tri se fait sur le FORMAT (type MIME, et
  /// l'extension à défaut) plutôt que sur `DocumentType` : ce dernier décrit
  /// la NATURE MÉTIER du document (DOE, PV, contrat…) et ne dit rien de son
  /// format, alors que les onglets séparent bien images / vidéos / le reste.
  List<ChantierDocument> get photos => itemsFiltres.where((d) => d.estImage).toList();
  List<ChantierDocument> get videos => itemsFiltres.where((d) => d.estVideo).toList();
  List<ChantierDocument> get autresDocuments =>
      itemsFiltres.where((d) => !d.estImage && !d.estVideo).toList();

  /// La recherche est déjà appliquée côté serveur ; ce filtre local ne sert
  /// qu'à masquer les documents archivés, que le back renvoie mais qui n'ont
  /// pas leur place dans la médiathèque courante.
  List<ChantierDocument> get itemsFiltres => items.where((d) => !d.archive).toList();

  DocumentsListState copyWith({
    DocumentsListStatus? status,
    List<ChantierDocument>? items,
    String? recherche,
    DocumentType? filtreType,
    bool effacerFiltreType = false,
    String? erreur,
    DepotStatus? depotStatus,
    String? depotErreur,
    bool effacerDepotErreur = false,
    double? depotProgression,
    bool effacerDepotProgression = false,
  }) {
    return DocumentsListState(
      status: status ?? this.status,
      items: items ?? this.items,
      recherche: recherche ?? this.recherche,
      filtreType: effacerFiltreType ? null : (filtreType ?? this.filtreType),
      erreur: erreur,
      depotStatus: depotStatus ?? this.depotStatus,
      depotErreur: effacerDepotErreur ? null : (depotErreur ?? this.depotErreur),
      depotProgression: effacerDepotProgression ? null : (depotProgression ?? this.depotProgression),
    );
  }

  @override
  List<Object?> get props =>
      [status, items, recherche, filtreType, erreur, depotStatus, depotErreur, depotProgression];
}

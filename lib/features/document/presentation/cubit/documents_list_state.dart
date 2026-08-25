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

  const DocumentsListState({
    this.status = DocumentsListStatus.initial,
    this.items = const [],
    this.recherche = '',
    this.filtreType,
    this.erreur,
    this.depotStatus = DepotStatus.inactif,
    this.depotErreur,
  });

  /// Répartition par nature de fichier — les trois onglets de l'écran
  /// « Photos & documents ». Le tri se fait sur le `mime_type` renvoyé par le
  /// back plutôt que sur `DocumentType` : ce dernier décrit la NATURE MÉTIER
  /// du document (DOE, PV, contrat…) et ne dit rien de son format, alors que
  /// les onglets de la maquette séparent bien images / vidéos / le reste.
  List<ChantierDocument> get photos => _parMime('image/');
  List<ChantierDocument> get videos => _parMime('video/');
  List<ChantierDocument> get autresDocuments => itemsFiltres
      .where((d) => !(d.mimeType ?? '').startsWith('image/') && !(d.mimeType ?? '').startsWith('video/'))
      .toList();

  List<ChantierDocument> _parMime(String prefixe) =>
      itemsFiltres.where((d) => (d.mimeType ?? '').startsWith(prefixe)).toList();

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
  }) {
    return DocumentsListState(
      status: status ?? this.status,
      items: items ?? this.items,
      recherche: recherche ?? this.recherche,
      filtreType: effacerFiltreType ? null : (filtreType ?? this.filtreType),
      erreur: erreur,
      depotStatus: depotStatus ?? this.depotStatus,
      depotErreur: effacerDepotErreur ? null : (depotErreur ?? this.depotErreur),
    );
  }

  @override
  List<Object?> get props => [status, items, recherche, filtreType, erreur, depotStatus, depotErreur];
}

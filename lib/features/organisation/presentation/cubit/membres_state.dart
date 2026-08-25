import 'package:equatable/equatable.dart';

import '../../domain/entities/membre.dart';

enum MembresStatus { initial, chargement, succes, erreur }

enum SoumissionStatus { inactif, enCours, succes, erreur }

class MembresState extends Equatable {
  final MembresStatus status;
  final List<Membre> membres;
  final String? erreur;

  // ── Soumission du formulaire d'ajout — état séparé du chargement de la
  //    liste : les deux peuvent être vrais en même temps (ex. la liste est
  //    déjà affichée pendant qu'on ajoute un nouveau membre par-dessus).
  final SoumissionStatus soumissionStatus;
  final String? soumissionErreur;

  /// Résultat du DERNIER ajout réussi — porte le mot de passe temporaire
  /// (s'il a été généré) à afficher une seule fois. Remis à `null` par
  /// [MembresCubit.accuserReceptionAjout] une fois affiché, pour ne pas le
  /// montrer à nouveau à la prochaine reconstruction de l'écran.
  final AjouterMembreResult? dernierAjout;

  /// Recherche locale sur l'annuaire — `GET /organisation/membres` ne propose
  /// pas de paramètre de recherche et l'effectif d'une organisation tient en
  /// une page (plafond serveur à 100). Filtrer en mémoire évite un
  /// aller-retour réseau à chaque frappe.
  final String recherche;

  /// Filtre de statut : `null` = tous.
  final String? filtreStatut;

  /// Identifiant du membre dont le statut est en cours de changement — sert à
  /// n'afficher l'indicateur que sur la fiche concernée, pas sur toute la
  /// liste.
  final String? membreEnCoursDeMaj;

  final String? statutErreur;

  const MembresState({
    this.status = MembresStatus.initial,
    this.membres = const [],
    this.erreur,
    this.soumissionStatus = SoumissionStatus.inactif,
    this.soumissionErreur,
    this.dernierAjout,
    this.recherche = '',
    this.filtreStatut,
    this.membreEnCoursDeMaj,
    this.statutErreur,
  });

  /// Membres après application de la recherche et du filtre de statut.
  List<Membre> get membresFiltres {
    final motif = recherche.trim().toLowerCase();
    return membres.where((m) {
      final correspondStatut = filtreStatut == null || m.statut == filtreStatut;
      final correspondTexte = motif.isEmpty ||
          m.nomComplet.toLowerCase().contains(motif) ||
          m.email.toLowerCase().contains(motif) ||
          (m.fonction ?? '').toLowerCase().contains(motif);
      return correspondStatut && correspondTexte;
    }).toList();
  }

  MembresState copyWith({
    MembresStatus? status,
    List<Membre>? membres,
    String? erreur,
    SoumissionStatus? soumissionStatus,
    String? soumissionErreur,
    AjouterMembreResult? dernierAjout,
    String? recherche,
    String? filtreStatut,
    String? membreEnCoursDeMaj,
    String? statutErreur,
    bool effacerErreur = false,
    bool effacerSoumissionErreur = false,
    bool effacerDernierAjout = false,
    bool effacerFiltreStatut = false,
    bool effacerMembreEnCoursDeMaj = false,
    bool effacerStatutErreur = false,
  }) {
    return MembresState(
      status: status ?? this.status,
      membres: membres ?? this.membres,
      erreur: effacerErreur ? null : (erreur ?? this.erreur),
      soumissionStatus: soumissionStatus ?? this.soumissionStatus,
      soumissionErreur: effacerSoumissionErreur ? null : (soumissionErreur ?? this.soumissionErreur),
      dernierAjout: effacerDernierAjout ? null : (dernierAjout ?? this.dernierAjout),
      recherche: recherche ?? this.recherche,
      filtreStatut: effacerFiltreStatut ? null : (filtreStatut ?? this.filtreStatut),
      membreEnCoursDeMaj:
          effacerMembreEnCoursDeMaj ? null : (membreEnCoursDeMaj ?? this.membreEnCoursDeMaj),
      statutErreur: effacerStatutErreur ? null : (statutErreur ?? this.statutErreur),
    );
  }

  @override
  List<Object?> get props => [
        status,
        membres,
        erreur,
        soumissionStatus,
        soumissionErreur,
        dernierAjout,
        recherche,
        filtreStatut,
        membreEnCoursDeMaj,
        statutErreur,
      ];
}

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/pays.dart';
import '../../domain/usecases/get_pays.dart';

enum PaysStatus { initial, chargement, succes, erreur }

class PaysState extends Equatable {
  final PaysStatus status;
  final List<Pays> items;

  /// Code ISO du pays choisi. `null` tant que rien n'est sélectionné.
  final String? codeChoisi;

  final String? erreur;

  const PaysState({
    this.status = PaysStatus.initial,
    this.items = const [],
    this.codeChoisi,
    this.erreur,
  });

  PaysState copyWith({
    PaysStatus? status,
    List<Pays>? items,
    String? codeChoisi,
    String? erreur,
  }) {
    return PaysState(
      status: status ?? this.status,
      items: items ?? this.items,
      codeChoisi: codeChoisi ?? this.codeChoisi,
      erreur: erreur,
    );
  }

  /// Pays actuellement sélectionné, ou `null`.
  Pays? get choisi {
    if (codeChoisi == null) return null;
    for (final p in items) {
      if (p.code == codeChoisi) return p;
    }
    return null;
  }

  /// Identifiants à afficher pour le pays choisi.
  ///
  /// Vide tant qu'aucun pays n'est sélectionné : c'est voulu, le pays est la
  /// première question du formulaire et commande tout ce qui suit.
  List<ChampIdentification> get champs => choisi?.champs ?? const [];

  @override
  List<Object?> get props => [status, items, codeChoisi, erreur];
}

/// Catalogue des pays du formulaire d'inscription.
///
/// ── Ce qu'il corrige ──────────────────────────────────────────────────────
/// Le formulaire offrait un sélecteur de ~250 pays et affichait SIRET, RCCM et
/// NINEA à tout le monde. Deux conséquences : une entreprise française se
/// voyait demander un identifiant sénégalais, et choisir un pays non couvert
/// produisait une inscription refusée par le serveur sans que rien à l'écran
/// ne l'ait laissé prévoir.
class PaysCubit extends Cubit<PaysState> {
  final GetPays getPays;

  PaysCubit({required this.getPays}) : super(const PaysState());

  Future<void> charger() async {
    if (state.items.isNotEmpty) return;
    emit(state.copyWith(status: PaysStatus.chargement));

    final resultat = await getPays();
    if (isClosed) return;

    emit(resultat.fold(
      (echec) => state.copyWith(status: PaysStatus.erreur, erreur: echec.errorMessage),
      (liste) => state.copyWith(
        status: PaysStatus.succes,
        items: liste,
        // Aucune présélection : forcer un pays par défaut ferait passer des
        // inscriptions sous un pays que l'utilisateur n'a jamais choisi.
        codeChoisi: state.codeChoisi,
      ),
    ));
  }

  void choisir(String code) => emit(state.copyWith(codeChoisi: code));
}

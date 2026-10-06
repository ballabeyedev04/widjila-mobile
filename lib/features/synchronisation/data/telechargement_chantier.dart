import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../../../core/errors/failure.dart';
import '../../../core/offline/base_locale.dart';
import '../../chantier/domain/repositories/chantier_repository.dart';
import '../../corps_etat/domain/repositories/corps_etat_repository.dart';
import '../../phase/domain/repositories/phase_repository.dart';
import '../../plan/domain/entities/plan.dart';
import '../../plan/domain/repositories/plan_repository.dart';
import '../../reserve/domain/repositories/reserve_repository.dart';

/// Avancement du téléchargement d'un chantier — alimente la barre de progression.
class ProgressionTelechargement extends Equatable {
  final int fait;
  final int total;
  const ProgressionTelechargement(this.fait, this.total);

  double get ratio => total == 0 ? 0 : (fait / total).clamp(0.0, 1.0);

  @override
  List<Object?> get props => [fait, total];
}

class ResultatTelechargement extends Equatable {
  /// `true` si TOUT ce qui sert au travail de terrain est maintenant sur
  /// l'appareil.
  final bool complet;

  /// Éléments qui n'ont pas pu être téléchargés (plan, fichier…).
  final int echecs;

  /// Date de la dernière synchronisation complète, `null` si le téléchargement
  /// n'est pas complet.
  final DateTime? date;

  /// Raison, quand [complet] est faux.
  final String? message;

  const ResultatTelechargement({required this.complet, this.echecs = 0, this.date, this.message});

  @override
  List<Object?> get props => [complet, echecs, date, message];
}

/// Rend un chantier « disponible hors connexion » : télécharge d'un coup tout
/// ce qu'il faut pour travailler sur le terrain, AVANT de perdre le réseau.
///
/// Guide hors connexion, §3 : « Il ne faut pas attendre que l'utilisateur
/// ouvre chaque écran. » Sans ce paquet, un chantier ne marchait hors ligne
/// que pour les écrans déjà visités en ligne.
///
/// ## Ce qui est téléchargé
///
///  1. la fiche du chantier ;
///  2. sa structure (bâtiments, niveaux, zones, appartements) ;
///  3. les référentiels du formulaire de réserve (corps d'état, phases) ;
///  4. les plans : liste à plat, plans racines, sous-plans de chaque plan,
///     détail (réserves positionnées) ET fichier du plan ;
///  5. les réserves (tirage incrémental, avec suppressions).
///
/// ## Comment
///
/// Par les MÊMES dépôts que les écrans, donc les mêmes requêtes : la copie
/// locale (`CacheReponsesLocales`) mémorise chaque réponse sous la clé que
/// l'écran redemandera plus tard. Aucune seconde copie, aucun format parallèle.
///
/// La date de dernière synchronisation n'est écrite que si TOUT a réussi : un
/// paquet à moitié téléchargé ne doit jamais s'afficher comme « disponible ».
class TelechargementChantier {
  final BaseLocale _base;
  final ChantierRepository _chantiers;
  final ReserveRepository _reserves;
  final PlanRepository _plans;
  final CorpsEtatRepository _corpsEtat;
  final PhaseRepository _phases;
  final Dio _dio;
  final bool Function() _enLigne;
  final Future<void> Function() _tirerReserves;
  final DateTime Function() _maintenant;

  TelechargementChantier({
    required BaseLocale base,
    required ChantierRepository chantiers,
    required ReserveRepository reserves,
    required PlanRepository plans,
    required CorpsEtatRepository corpsEtat,
    required PhaseRepository phases,
    required Dio dio,
    required bool Function() enLigne,
    required Future<void> Function() tirerReserves,
    DateTime Function()? maintenant,
  })  : _base = base,
        _chantiers = chantiers,
        _reserves = reserves,
        _plans = plans,
        _corpsEtat = corpsEtat,
        _phases = phases,
        _dio = dio,
        _enLigne = enLigne,
        _tirerReserves = tirerReserves,
        _maintenant = maintenant ?? DateTime.now;

  static String cleMeta(String chantierId) => 'hors_ligne:$chantierId';

  /// Date du dernier téléchargement COMPLET, `null` s'il n'y en a jamais eu.
  Future<DateTime?> derniereSynchro(String chantierId) async {
    final brut = await _base.lireMeta(cleMeta(chantierId));
    return brut == null ? null : DateTime.tryParse(brut);
  }

  Future<ResultatTelechargement> telecharger(
    String chantierId, {
    void Function(ProgressionTelechargement)? surProgression,
  }) async {
    if (!_enLigne()) {
      return const ResultatTelechargement(
        complet: false,
        message: 'Connexion Internet requise pour rendre ce chantier disponible hors connexion.',
      );
    }

    var fait = 0;
    var total = 5; // fiche, structure, référentiels, liste des plans, réserves
    var echecs = 0;
    void avancer() => surProgression?.call(ProgressionTelechargement(++fait, total));
    surProgression?.call(ProgressionTelechargement(0, total));

    /// Étapes INDISPENSABLES : sans elles le chantier n'est pas utilisable
    /// hors ligne, on s'arrête et on le dit.
    Future<String?> indispensable<T>(Future<Either<Failure, T>> Function() appel, String nom) async {
      final r = await appel();
      return r.fold((f) => '$nom : ${f.errorMessage}', (_) => null);
    }

    for (final etape in <Future<String?> Function()>[
      () => indispensable(() => _chantiers.getChantierDetail(chantierId), 'Fiche du chantier'),
      () => indispensable(() => _reserves.getStructure(chantierId), 'Structure du chantier'),
    ]) {
      final erreur = await etape();
      if (erreur != null) return ResultatTelechargement(complet: false, message: erreur);
      avancer();
    }

    final erreurCorps = await indispensable(() => _corpsEtat.getCorpsEtatActifs(), "Corps d'état");
    final erreurPhases = await indispensable(() => _phases.getPhasesActives(), 'Phases');
    if (erreurCorps != null || erreurPhases != null) {
      return ResultatTelechargement(complet: false, message: erreurCorps ?? erreurPhases);
    }
    avancer();

    final listePlans = await _plans.getPlansChantier(chantierId);
    final plans = listePlans.fold<List<Plan>?>((_) => null, (l) => l);
    if (plans == null) {
      return ResultatTelechargement(
        complet: false,
        message: 'Plans : ${listePlans.fold((f) => f.errorMessage, (_) => '')}',
      );
    }
    // Racines : le point d'entrée de la navigation par niveau.
    await _plans.getPlansRacines(chantierId);
    avancer();

    total += plans.length;
    surProgression?.call(ProgressionTelechargement(fait, total));

    // Trois plans à la fois : un chantier peut en compter des centaines, et
    // les fichiers pèsent plusieurs méga-octets.
    const parallele = 3;
    for (var i = 0; i < plans.length; i += parallele) {
      final lot = plans.skip(i).take(parallele);
      final resultats = await Future.wait(lot.map(_telechargerPlan));
      for (final ok in resultats) {
        if (!ok) echecs++;
        avancer();
      }
    }

    try {
      await _tirerReserves();
    } catch (e) {
      debugPrint('[hors-ligne] Tirage des réserves échoué : $e');
      return ResultatTelechargement(
        complet: false,
        echecs: echecs,
        message: 'Réserves : téléchargement interrompu. Réessayez.',
      );
    }
    avancer();

    if (echecs > 0) {
      return ResultatTelechargement(
        complet: false,
        echecs: echecs,
        message: '$echecs plan(s) n\'ont pas pu être téléchargés. Réessayez.',
      );
    }

    final maintenant = _maintenant();
    await _base.ecrireMeta(cleMeta(chantierId), maintenant.toIso8601String());
    return ResultatTelechargement(complet: true, date: maintenant);
  }

  /// Détail, sous-plans et FICHIER d'un plan. `true` si tout est sur l'appareil.
  Future<bool> _telechargerPlan(Plan plan) async {
    try {
      final detail = await _plans.getPlanDetail(plan.id);
      final sous = await _plans.getSousPlans(plan.id);
      if (detail.isLeft() || sous.isLeft()) return false;

      final url = detail.fold((_) => plan.fichierUrl, (p) => p.fichierUrl);
      if (url.isNotEmpty) {
        // Même appel que la visionneuse : la copie locale mémorise les octets
        // sous la clé qu'elle redemandera.
        final reponse = await _dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
        if (reponse.data == null || reponse.data!.isEmpty) return false;
      }
      return true;
    } catch (e) {
      debugPrint('[hors-ligne] Plan ${plan.id} non téléchargé : $e');
      return false;
    }
  }
}

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/errors/failure.dart';
import '../../../core/offline/cache_reserves.dart';
import '../../chantier/domain/repositories/chantier_repository.dart';
import '../../dashboard/domain/repositories/dashboard_repository.dart';
import '../../document/domain/repositories/document_repository.dart';
import '../../inspection/domain/repositories/inspection_repository.dart';
import '../../notification/domain/repositories/notification_repository.dart';
import '../../organisation/domain/repositories/organisation_repository.dart';
import '../../rapport/domain/repositories/rapport_repository.dart';
import '../../reserve/domain/entities/reserve.dart';
import '../../reserve/domain/repositories/reserve_repository.dart';

/// Ce que l'on télécharge EN PLUS du socle (fiche, structure, plans,
/// référentiels, réserves) pour qu'AUCUN écran du chantier ne tombe en
/// « erreur réseau » une fois sur le terrain.
///
/// Chaque étape est « au mieux » : elle renvoie `true` si tout est sur
/// l'appareil. Un échec ici n'empêche PAS le chantier d'être déclaré
/// disponible — le socle suffit pour relever des réserves — mais il est
/// compté et signalé.
///
/// Toutes passent par les dépôts des écrans, donc par les mêmes requêtes : la
/// copie locale mémorise chaque réponse sous la clé que l'écran redemandera.
class ComplementsHorsLigne {
  final ChantierRepository chantiers;
  final DocumentRepository documents;
  final RapportRepository rapports;
  final InspectionRepository inspections;
  final ReserveRepository reserves;
  final DashboardRepository dashboard;
  final OrganisationRepository organisation;
  final NotificationRepository notifications;
  final CacheReserves reservesLocales;
  final Dio dio;

  /// Au-delà, les réserves les plus récentes seules sont préparées : chaque
  /// réserve coûte une dizaine de requêtes (photos, commentaires, historique,
  /// affectations).
  static const int reservesMax = 300;

  ComplementsHorsLigne({
    required this.chantiers,
    required this.documents,
    required this.rapports,
    required this.inspections,
    required this.reserves,
    required this.dashboard,
    required this.organisation,
    required this.notifications,
    required this.reservesLocales,
    required this.dio,
  });

  static Future<bool> _ok<T>(Future<Either<Failure, T>> appel) async => (await appel).isRight();

  /// Les étapes, dans l'ordre. Chacune prend l'identifiant du chantier.
  List<Future<bool> Function(String chantierId)> get etapes => [
        (id) => _ok(documents.getDocuments(chantierId: id)),
        (id) => _ok(rapports.getRapports(id)),
        (id) => _ok(inspections.getInspections(chantierId: id)),
        (id) => _ok(chantiers.getMembresChantier(id)),
        // Tableau de bord du chantier et compteurs.
        (id) async {
          final r = await Future.wait([
            _ok(reserves.getStatutsCount(id)),
            _ok(reserves.getEvolution(id)),
            _ok(reserves.getStatutsCountGlobal()),
            _ok(dashboard.getStatsGlobales()),
            _ok(dashboard.getEvolution()),
          ]);
          return r.every((b) => b);
        },
        // Annuaire de l'organisation : entreprises, équipe, notifications.
        (_) async {
          final r = await Future.wait([
            _ok(organisation.getMonOrganisation()),
            _ok(organisation.getMembres()),
            _ok(organisation.getPartenaires()),
            _ok(notifications.lister()),
            _ok(notifications.compterNonLues()),
          ]);
          return r.every((b) => b);
        },
        sousRessourcesDesReserves,
      ];

  /// Photos, commentaires, historique et affectations de chaque réserve —
  /// ce que sa fiche affiche et qui n'est PAS dans sa base locale.
  Future<bool> sousRessourcesDesReserves(String chantierId) async {
    final locales = await reservesLocales.listerParChantier(chantierId);
    // Une réserve encore en attente d'envoi n'existe pas sur le serveur : rien
    // à y télécharger.
    final cibles = locales
        .where((r) => r.statut != ReserveStatut.cloturee && r.numero != Reserve.numeroEnAttente)
        .take(reservesMax)
        .toList();
    var tout = true;

    const parallele = 4;
    for (var i = 0; i < cibles.length; i += parallele) {
      final lot = cibles.skip(i).take(parallele);
      final resultats = await Future.wait(lot.map(_preparerReserve));
      if (resultats.any((ok) => !ok)) tout = false;
    }
    return tout;
  }

  Future<bool> _preparerReserve(Reserve reserve) async {
    try {
      final medias = await reserves.getMedias(reserve.id);
      final autres = await Future.wait([
        _ok(reserves.getCommentaires(reserve.id)),
        _ok(reserves.getHistorique(reserve.id)),
        _ok(reserves.getAffectations(reserve.id)),
      ]);
      var tout = medias.isRight() && autres.every((b) => b);

      // Les photos : la vignette d'abord (listes), l'image d'origine ensuite
      // (plein écran). Le plafond de la copie locale évince les plus anciennes
      // si le stockage se remplit.
      final liste = medias.fold((_) => const <ReserveMedia>[], (l) => l);
      for (final m in liste.where((m) => m.type == 'photo')) {
        for (final url in {m.thumbnailUrl, m.url}.whereType<String>()) {
          try {
            await dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
          } catch (_) {
            tout = false;
          }
        }
      }
      return tout;
    } catch (e) {
      debugPrint('[hors-ligne] Réserve ${reserve.id} non préparée : $e');
      return false;
    }
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/offline/base_locale.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/entities/chantier.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/repositories/chantier_repository.dart';
import 'package:suivie_chantier_mobile/features/corps_etat/domain/entities/corps_etat.dart';
import 'package:suivie_chantier_mobile/features/corps_etat/domain/repositories/corps_etat_repository.dart';
import 'package:suivie_chantier_mobile/features/phase/domain/entities/phase_referentiel.dart';
import 'package:suivie_chantier_mobile/features/phase/domain/repositories/phase_repository.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/entities/plan.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/repositories/plan_repository.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/chantier_structure.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/repositories/reserve_repository.dart';
import 'package:suivie_chantier_mobile/features/synchronisation/data/telechargement_chantier.dart';

class _Chantiers extends Mock implements ChantierRepository {}

class _Reserves extends Mock implements ReserveRepository {}

class _Plans extends Mock implements PlanRepository {}

class _Corps extends Mock implements CorpsEtatRepository {}

class _Phases extends Mock implements PhaseRepository {}

class _FauxChantier extends Fake implements Chantier {}

class _FauxStructure extends Fake implements ChantierStructure {}

class _FauxPlan extends Fake implements Plan {
  @override
  final String id;
  @override
  final String fichierUrl;
  _FauxPlan(this.id, this.fichierUrl);
}

/// Adaptateur : sert un fichier, ou échoue pour une URL donnée.
class _Fichiers implements HttpClientAdapter {
  final Set<String> enEchec = {};
  final List<String> demandes = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    demandes.add(options.uri.path);
    if (enEchec.contains(options.uri.path)) {
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
    }
    return ResponseBody.fromBytes(List<int>.filled(64, 7), 200);
  }

  @override
  void close({bool force = false}) {}
}

/// « Disponible hors connexion » : un paquet à moitié téléchargé ne doit
/// JAMAIS s'afficher comme prêt (guide hors connexion, §3).
void main() {
  late _Chantiers chantiers;
  late _Reserves reserves;
  late _Plans plans;
  late _Corps corps;
  late _Phases phases;
  late _Fichiers fichiers;
  late TelechargementChantier service;
  var enLigne = true;
  var reservesTirees = 0;
  final instant = DateTime(2026, 10, 6, 14, 32);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    BaseLocale.surchargeNomFichier = 'test_telechargement.db';
  });

  setUp(() async {
    await BaseLocale.instance.fermer();
    await databaseFactory.deleteDatabase('${await getDatabasesPath()}/test_telechargement.db');
    enLigne = true;
    reservesTirees = 0;
    chantiers = _Chantiers();
    reserves = _Reserves();
    plans = _Plans();
    corps = _Corps();
    phases = _Phases();
    fichiers = _Fichiers();

    when(() => chantiers.getChantierDetail(any())).thenAnswer((_) async => Right(_FauxChantier()));
    when(() => reserves.getStructure(any())).thenAnswer((_) async => Right(_FauxStructure()));
    when(() => corps.getCorpsEtatActifs()).thenAnswer((_) async => const Right(<CorpsEtat>[]));
    when(() => phases.getPhasesActives()).thenAnswer((_) async => const Right(<PhaseReferentiel>[]));
    final liste = [_FauxPlan('p1', 'https://cdn.test/p1.pdf'), _FauxPlan('p2', 'https://cdn.test/p2.pdf')];
    when(() => plans.getPlansChantier(any())).thenAnswer((_) async => Right<Failure, List<Plan>>(liste));
    when(() => plans.getPlansRacines(any())).thenAnswer((_) async => Right<Failure, List<Plan>>(liste));
    when(() => plans.getSousPlans(any())).thenAnswer((_) async => const Right<Failure, List<Plan>>([]));
    when(() => plans.getPlanDetail(any())).thenAnswer((i) async {
      final id = i.positionalArguments.first as String;
      return Right(liste.firstWhere((p) => p.id == id));
    });

    service = TelechargementChantier(
      base: BaseLocale.instance,
      chantiers: chantiers,
      reserves: reserves,
      plans: plans,
      corpsEtat: corps,
      phases: phases,
      dio: Dio()..httpClientAdapter = fichiers,
      enLigne: () => enLigne,
      tirerReserves: () async => reservesTirees++,
      maintenant: () => instant,
    );
  });

  tearDown(() => BaseLocale.instance.fermer());

  test('tout réussit : paquet complet, date enregistrée, fichiers de plans téléchargés', () async {
    final progressions = <ProgressionTelechargement>[];
    final r = await service.telecharger('c1', surProgression: progressions.add);

    expect(r.complet, isTrue);
    expect(r.date, instant);
    expect(await service.derniereSynchro('c1'), instant);
    expect(fichiers.demandes, containsAll(['/p1.pdf', '/p2.pdf']));
    expect(reservesTirees, 1);
    expect(progressions.last.fait, progressions.last.total);
  });

  test('hors ligne : refusé tout de suite, rien n\'est marqué disponible', () async {
    enLigne = false;
    final r = await service.telecharger('c1');
    expect(r.complet, isFalse);
    expect(r.message, contains('Internet'));
    expect(await service.derniereSynchro('c1'), isNull);
  });

  test('un fichier de plan en échec : PAS de date « disponible »', () async {
    fichiers.enEchec.add('/p2.pdf');
    final r = await service.telecharger('c1');
    expect(r.complet, isFalse);
    expect(r.echecs, 1);
    expect(await service.derniereSynchro('c1'), isNull);
  });

  test('la structure indisponible interrompt le téléchargement', () async {
    when(() => reserves.getStructure(any())).thenAnswer((_) async => const Left(NetworkFailure()));
    final r = await service.telecharger('c1');
    expect(r.complet, isFalse);
    expect(r.message, contains('Structure'));
    expect(fichiers.demandes, isEmpty);
    expect(await service.derniereSynchro('c1'), isNull);
  });

  test('les phases indisponibles interrompent : sans elles, aucune réserve ne se crée hors ligne', () async {
    when(() => phases.getPhasesActives()).thenAnswer((_) async => const Left(NetworkFailure()));
    final r = await service.telecharger('c1');
    expect(r.complet, isFalse);
    expect(await service.derniereSynchro('c1'), isNull);
  });

  test('le tirage des réserves échoue : pas de date', () async {
    final s2 = TelechargementChantier(
      base: BaseLocale.instance,
      chantiers: chantiers,
      reserves: reserves,
      plans: plans,
      corpsEtat: corps,
      phases: phases,
      dio: Dio()..httpClientAdapter = fichiers,
      enLigne: () => true,
      tirerReserves: () async => throw Exception('coupure'),
    );
    final r = await s2.telecharger('c1');
    expect(r.complet, isFalse);
    expect(await s2.derniereSynchro('c1'), isNull);
  });
}

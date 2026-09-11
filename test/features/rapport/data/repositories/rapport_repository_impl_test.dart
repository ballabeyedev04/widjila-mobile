import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/offline/detecteur_connexion.dart';
import 'package:suivie_chantier_mobile/core/offline/file_attente.dart';
import 'package:suivie_chantier_mobile/features/rapport/data/datasources/rapport_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/rapport/data/repositories/rapport_repository_impl.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/envoi_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/option_filtre.dart';

class _MockSource extends Mock implements RapportRemoteDataSource {}

class _MockFile extends Mock implements FileAttente {}

class _MockDetecteur extends Mock implements DetecteurConnexion {}

/// Le dépôt des rapports — et le § 22 du cahier des charges :
///
/// « L'envoi d'un rapport nécessite une connexion. Widjila peut mettre
/// l'action en file d'attente et la transmettre lorsque le réseau revient. »
///
/// Ce qui est verrouillé : une COUPURE réseau met l'envoi en file ; un REFUS
/// du serveur, lui, n'y est jamais mis — le rejouer échouerait toujours, et
/// bloquerait la file derrière lui.
void main() {
  late _MockSource source;
  late _MockFile file;
  late _MockDetecteur detecteur;
  late RapportRepositoryImpl repository;

  const demande = DemandeEnvoiRapport(exclure: ['a@ex.fr'], objet: 'OPR');

  setUpAll(() {
    registerFallbackValue(const DemandeEnvoiRapport());
    registerFallbackValue(TypeAction.envoyerRapport);
  });

  setUp(() {
    source = _MockSource();
    file = _MockFile();
    detecteur = _MockDetecteur();
    repository = RapportRepositoryImpl(source, fileAttente: file, detecteur: detecteur);
    when(() => detecteur.estEnLigne).thenReturn(true);
    when(() => file.deposer(type: any(named: 'type'), charge: any(named: 'charge')))
        .thenAnswer((_) async => 'action-1');
  });

  group('§ 22 — envoi hors ligne', () {
    // L'envoi porte désormais une clé d'idempotence (audit synchronisation) :
    // les stubs l'acceptent quelle qu'elle soit, et les tests dédiés plus bas
    // vérifient sa valeur.
    void envoiRepond(Future<String> Function() reponse) =>
        when(() => source.envoyerRapport(any(), any(), cleIdempotence: any(named: 'cleIdempotence')))
            .thenAnswer((_) => reponse());

    Map<String, dynamic> chargeDeposee() => verify(() => file.deposer(
          type: TypeAction.envoyerRapport,
          charge: captureAny(named: 'charge'),
        )).captured.single as Map<String, dynamic>;

    test('hors ligne CONSTATÉ : mis en file, sans tenter le réseau', () async {
      when(() => detecteur.estEnLigne).thenReturn(false);

      final r = await repository.envoyerRapport('r1', demande);

      expect(r.getOrElse(() => throw 'échec'), const ResultatEnvoiRapport(message: '', enFileAttente: true));
      verifyNever(() => source.envoyerRapport(any(), any(), cleIdempotence: any(named: 'cleIdempotence')));
      final charge = chargeDeposee();
      expect(charge['rapportId'], 'r1');
      expect(charge['demande'], demande.toJson());
      expect(charge['cleIdempotence'], isA<String>().having((c) => c.length, 'longueur', greaterThanOrEqualTo(8)));
    });

    test('coupure PENDANT l’envoi : mis en file', () async {
      envoiRepond(() async => throw const NetworkException());

      final r = await repository.envoyerRapport('r1', demande);

      expect(r.isRight(), isTrue);
      expect(r.getOrElse(() => throw 'échec').enFileAttente, isTrue);
    });

    test('coupure PENDANT l’envoi : l’action rejouée porte la MÊME clé que la tentative', () async {
      // La tentative a pu aboutir côté serveur avant que la réponse ne se
      // perde : c'est la même clé qui empêche le rejeu de réexpédier.
      envoiRepond(() async => throw const NetworkException());

      await repository.envoyerRapport('r1', demande);

      final cleTentative = verify(() => source.envoyerRapport(
            'r1', demande,
            cleIdempotence: captureAny(named: 'cleIdempotence'),
          )).captured.single as String;
      expect(chargeDeposee()['cleIdempotence'], cleTentative);
    });

    test('deux envois DISTINCTS ont deux clés distinctes', () async {
      final cles = <String?>[];
      when(() => source.envoyerRapport(any(), any(), cleIdempotence: any(named: 'cleIdempotence')))
          .thenAnswer((i) async {
        cles.add(i.namedArguments[#cleIdempotence] as String?);
        return 'ok';
      });

      await repository.envoyerRapport('r1', demande);
      await repository.envoyerRapport('r1', demande);

      expect(cles, hasLength(2));
      expect(cles.toSet(), hasLength(2), reason: 'un second envoi voulu ne doit pas passer pour un rejeu');
    });

    test('un REFUS du serveur n’est jamais mis en file', () async {
      envoiRepond(() async =>
          throw const ServerException(statusCode: 400, message: 'Adresse étrangère au chantier'));

      final r = await repository.envoyerRapport('r1', demande);

      expect(r.isLeft(), isTrue);
      verifyNever(() => file.deposer(type: any(named: 'type'), charge: any(named: 'charge')));
    });

    test('en ligne : le message du serveur est rendu tel quel', () async {
      envoiRepond(() async => 'Rapport envoyé à 2 destinataire(s).');

      final r = await repository.envoyerRapport('r1', demande);

      expect(r.getOrElse(() => throw 'échec'), const ResultatEnvoiRapport(message: 'Rapport envoyé à 2 destinataire(s).'));
    });

    test('sans file d’attente disponible, une coupure est une ERREUR RÉSEAU', () async {
      final sansFile = RapportRepositoryImpl(source);
      envoiRepond(() async => throw const NetworkException());

      final r = await sansFile.envoyerRapport('r1', demande);

      r.fold((f) => expect(f, isA<NetworkFailure>()), (_) => fail('un échec était attendu'));
    });
  });

  test('les options des filtres sont lues ENSEMBLE', () async {
    when(() => source.getEntreprisesChantier('c1'))
        .thenAnswer((_) async => const [OptionFiltre(id: 'p1', nom: 'ABC')]);
    when(() => source.getCorpsEtat()).thenAnswer((_) async => const [OptionFiltre(id: 'ce1', nom: 'Carrelage')]);

    final r = await repository.getOptionsFiltres('c1');

    final options = r.getOrElse(() => throw 'échec');
    expect(options.entreprises.single.nom, 'ABC');
    expect(options.corpsEtat.single.nom, 'Carrelage');
  });
}

import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/regles_store.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/abonnement/domain/entities/abonnement.dart';
import 'package:suivie_chantier_mobile/features/abonnement/domain/usecases/creer_code_transfert_web.dart';
import 'package:suivie_chantier_mobile/features/abonnement/domain/usecases/devis_usecases.dart';
import 'package:suivie_chantier_mobile/features/abonnement/domain/usecases/get_droits.dart';
import 'package:suivie_chantier_mobile/features/abonnement/domain/usecases/get_etat_paiement.dart';
import 'package:suivie_chantier_mobile/features/abonnement/domain/usecases/get_formules.dart';
import 'package:suivie_chantier_mobile/features/abonnement/domain/usecases/get_historique_abonnement.dart';
import 'package:suivie_chantier_mobile/features/abonnement/presentation/cubit/abonnement_cubit.dart';

/// Le parcours « Premium sur devis », côté mobile (cahier des charges du
/// 04/10/2026).
///
/// Ce qui est verrouillé ici :
///
///  1. la demande ne porte AUCUN montant — le client décrit un besoin ;
///  2. les drapeaux du SERVEUR (`peutEtreAccepte`, `peutEtrePaye`) sont repris
///     tels quels : l'application ne recalcule jamais la règle de validité ;
///  3. une action réussie remplace la ligne par ce que rend le serveur ;
///  4. un refus du serveur s'affiche, sans rien changer d'autre ;
///  5. le paiement rend une ADRESSE — rien n'est activé localement ;
///  6. sur iOS, la section n'existe pas (paiement hors achat intégré).

class MockGetFormules extends Mock implements GetFormules {}

class MockGetDroits extends Mock implements GetDroits {}

class MockGetHistorique extends Mock implements GetHistoriqueAbonnement {}

class MockCreerCode extends Mock implements CreerCodeTransfertWeb {}

class MockGetEtatPaiement extends Mock implements GetEtatPaiement {}

class MockListerDevis extends Mock implements ListerDevis {}

class MockDemanderDevis extends Mock implements DemanderDevis {}

class MockAccepterDevis extends Mock implements AccepterDevis {}

class MockRefuserDevis extends Mock implements RefuserDevis {}

class MockPayerDevis extends Mock implements PayerDevis {}

/// Devis tel que le serveur le renvoie — ce sont SES drapeaux qui décident.
Devis devis({
  String id = 'dev-1',
  StatutDevis statut = StatutDevis.envoye,
  bool chiffre = true,
  bool peutEtreAccepte = true,
  bool peutEtrePaye = false,
  DateTime? payeLe,
}) =>
    Devis(
      id: id,
      numero: 'WDJ-2026-0001',
      statut: statut,
      planNom: 'Entreprise',
      montantHt: 6500,
      tauxTva: 20,
      montantTva: 1300,
      montantTtc: 7800,
      devise: 'EUR',
      dureeMois: 12,
      limiteUtilisateurs: 25,
      chiffre: chiffre,
      peutEtreAccepte: peutEtreAccepte,
      peutEtrePaye: peutEtrePaye,
      payeLe: payeLe,
    );

void main() {
  late MockListerDevis lister;
  late MockDemanderDevis demander;
  late MockAccepterDevis accepter;
  late MockRefuserDevis refuser;
  late MockPayerDevis payer;

  setUpAll(() => registerFallbackValue(const DemandeDevis()));

  setUp(() {
    lister = MockListerDevis();
    demander = MockDemanderDevis();
    accepter = MockAccepterDevis();
    refuser = MockRefuserDevis();
    payer = MockPayerDevis();
  });

  AbonnementCubit construire() {
    final formules = MockGetFormules();
    final droits = MockGetDroits();
    final historique = MockGetHistorique();
    when(() => formules()).thenAnswer((_) async => const Right([]));
    when(() => droits()).thenAnswer((_) async => const Right(DroitsAbonnement()));
    when(() => historique()).thenAnswer((_) async => const Right([]));

    return AbonnementCubit(
      getFormules: formules,
      getDroits: droits,
      getHistorique: historique,
      creerCodeTransfertWeb: MockCreerCode(),
      getEtatPaiement: MockGetEtatPaiement(),
      listerDevis: lister,
      demanderDevis: demander,
      accepterDevis: accepter,
      refuserDevis: refuser,
      payerDevis: payer,
      dormir: (_) async {},
    );
  }

  group('la demande', () {
    test('ne transmet AUCUN montant — le client décrit un besoin', () {
      const demande = DemandeDevis(
        contact: 'Balla', nbUtilisateurs: 25, dureeSouhaitee: 12, besoins: 'Multi-agences',
      );

      final json = demande.toJson();

      expect(json.keys, containsAll(['contact', 'nbUtilisateurs', 'dureeSouhaitee', 'besoins']));
      for (final interdit in ['montantHt', 'montantTtc', 'prix', 'remise', 'tauxTva']) {
        expect(json.containsKey(interdit), isFalse, reason: '« $interdit » n’a rien à faire ici');
      }
    });

    test('ajoute le devis créé en tête de liste', () async {
      when(() => demander(any())).thenAnswer((_) async => Right(
            devis(statut: StatutDevis.brouillon, chiffre: false, peutEtreAccepte: false),
          ));
      final cubit = construire();

      final ok = await cubit.demander(const DemandeDevis(nbUtilisateurs: 25));

      expect(ok, isTrue);
      expect(cubit.state.devis, hasLength(1));
      expect(cubit.state.devis.first.chiffre, isFalse);
      expect(cubit.state.devisEnCours, isFalse);
    });

    test('un refus du serveur s’affiche, et la liste ne bouge pas', () async {
      when(() => demander(any())).thenAnswer(
        (_) async => const Left(ServerFailure(errorMessage: 'Un devis vous a déjà été transmis.')),
      );
      final cubit = construire();

      final ok = await cubit.demander(const DemandeDevis());

      expect(ok, isFalse);
      expect(cubit.state.erreurDevis, 'Un devis vous a déjà été transmis.');
      expect(cubit.state.devis, isEmpty);
    });

    test('un 403 (rôle sans facturation) laisse l’écran utilisable', () async {
      when(() => lister()).thenAnswer(
        (_) async => const Left(ServerFailure(errorMessage: 'Accès refusé')),
      );
      final cubit = construire();

      await cubit.chargerDevis();

      expect(cubit.state.devis, isEmpty);
      expect(cubit.state.erreurDevis, isNull, reason: 'un refus de rôle n’est pas une panne');
    });
  });

  group('acceptation et refus', () {
    test('remplace la ligne par ce que rend le SERVEUR', () async {
      when(() => lister()).thenAnswer((_) async => Right([devis()]));
      when(() => accepter('dev-1')).thenAnswer((_) async => Right(
            devis(statut: StatutDevis.accepte, peutEtreAccepte: false, peutEtrePaye: true),
          ));
      final cubit = construire();
      await cubit.chargerDevis();

      await cubit.accepter('dev-1');

      expect(cubit.state.devis, hasLength(1));
      final maj = cubit.state.devis.single;
      expect(maj.statut, StatutDevis.accepte);
      // C'est le serveur qui ouvre le paiement, pas un calcul local.
      expect(maj.peutEtrePaye, isTrue);
      expect(maj.peutEtreAccepte, isFalse);
    });

    test('le motif de refus part tel quel, et `null` quand il est vide', () async {
      when(() => refuser(any(), any())).thenAnswer((_) async => Right(
            devis(statut: StatutDevis.refuse, peutEtreAccepte: false),
          ));
      final cubit = construire();

      await cubit.refuser('dev-1', 'Budget 2027');
      verify(() => refuser('dev-1', 'Budget 2027')).called(1);

      await cubit.refuser('dev-1', null);
      verify(() => refuser('dev-1', null)).called(1);
    });

    test('un refus du serveur laisse le devis inchangé', () async {
      when(() => lister()).thenAnswer((_) async => Right([devis()]));
      when(() => accepter(any())).thenAnswer(
        (_) async => const Left(ServerFailure(errorMessage: 'Ce devis a expiré.')),
      );
      final cubit = construire();
      await cubit.chargerDevis();

      await cubit.accepter('dev-1');

      expect(cubit.state.erreurDevis, 'Ce devis a expiré.');
      expect(cubit.state.devis.single.statut, StatutDevis.envoye);
    });
  });

  group('le paiement', () {
    test('rend l’ADRESSE de la page Stripe — rien n’est activé ici', () async {
      when(() => payer('dev-1')).thenAnswer(
        (_) async => const Right('https://checkout.stripe.com/c/pay/cs_devis'),
      );
      final cubit = construire();

      final adresse = await cubit.adressePaiementDevis('dev-1');

      expect(adresse, 'https://checkout.stripe.com/c/pay/cs_devis');
      expect(cubit.state.devisEnCours, isFalse);
      // Aucun droit n'a changé : c'est le webhook, côté serveur, qui tranche.
      expect(cubit.state.droits.source, 'aucun');
    });

    test('un refus rend `null` et affiche le message du serveur', () async {
      when(() => payer(any())).thenAnswer(
        (_) async => const Left(ServerFailure(errorMessage: 'Ce devis a déjà été réglé.')),
      );
      final cubit = construire();

      final adresse = await cubit.adressePaiementDevis('dev-1');

      expect(adresse, isNull);
      expect(cubit.state.erreurDevis, 'Ce devis a déjà été réglé.');
    });

    test('une nouvelle action efface le refus précédent', () async {
      when(() => payer(any())).thenAnswer(
        (_) async => const Left(ServerFailure(errorMessage: 'Ce devis a expiré.')),
      );
      when(() => accepter(any())).thenAnswer((_) async => Right(devis()));
      final cubit = construire();
      await cubit.adressePaiementDevis('dev-1');
      expect(cubit.state.erreurDevis, isNotNull);

      await cubit.accepter('dev-1');

      expect(cubit.state.erreurDevis, isNull);
    });
  });

  group('lecture de la réponse du serveur', () {
    test('un montant en chaîne (décimal SQL) est lu comme un nombre', () {
      final d = Devis.fromJson({
        'id': 'dev-1', 'numero': 'WDJ-2026-0001', 'statut': 'envoye',
        'montantHt': '6500.00', 'montantTtc': '7800.00', 'tauxTva': '20.00',
        'dureeMois': 12, 'chiffre': true, 'peutEtreAccepte': true,
      });

      expect(d.montantHt, 6500);
      expect(d.montantTtc, 7800);
      expect(d.tauxTva, 20);
    });

    test('un statut inconnu du mobile ne casse rien', () {
      final d = Devis.fromJson({'id': 'x', 'numero': 'N', 'statut': 'nouveau_statut'});

      expect(d.statut, StatutDevis.inconnu);
      // Et sans drapeau du serveur, aucun bouton ne s'affiche.
      expect(d.peutEtreAccepte, isFalse);
      expect(d.peutEtrePaye, isFalse);
    });

    test('un devis non chiffré n’a ni montant ni droit d’acceptation', () {
      final d = Devis.fromJson({
        'id': 'dev-1', 'numero': 'WDJ-2026-0001', 'statut': 'brouillon',
        'montantTtc': null, 'chiffre': false, 'peutEtreAccepte': false,
      });

      expect(d.montantTtc, isNull);
      expect(d.chiffre, isFalse);
      expect(d.peutEtreAccepte, isFalse);
    });
  });

  group('la boutique', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('iOS : pas de devis — il mène à un paiement hors achat intégré', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(ReglesStore.commerceAutorise, isFalse);
    });

    test('Android : le parcours est ouvert', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(ReglesStore.commerceAutorise, isTrue);
    });
  });
}

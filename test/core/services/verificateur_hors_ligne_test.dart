import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/services/verificateur_hors_ligne.dart';

class _MockStockage extends Mock implements FlutterSecureStorage {}

/// Le vérificateur est la SEULE barrière d'une connexion sans réseau : chaque
/// test ici verrouille une façon de la franchir indûment.
void main() {
  late _MockStockage stockage;
  late Map<String, String> disque;
  late DateTime maintenant;
  late VerificateurHorsLigne v;

  setUp(() {
    stockage = _MockStockage();
    disque = {};
    maintenant = DateTime(2026, 10, 6, 12);
    when(() => stockage.read(key: any(named: 'key'))).thenAnswer((i) async => disque[i.namedArguments[#key]]);
    when(() => stockage.write(key: any(named: 'key'), value: any(named: 'value'))).thenAnswer((i) async {
      disque[i.namedArguments[#key] as String] = i.namedArguments[#value] as String;
    });
    when(() => stockage.delete(key: any(named: 'key'))).thenAnswer((i) async {
      disque.remove(i.namedArguments[#key]);
    });
    v = VerificateurHorsLigne(secureStorage: stockage, maintenant: () => maintenant, iterations: 50);
  });

  Future<void> inscrire() => v.enregistrer(
        utilisateurId: 'u1',
        identifiants: ['Balla@Widjila.com', '  +221770000000 '],
        motDePasse: 'Secret#123',
      );

  test('refuse tout tant que le serveur n\'a jamais authentifié personne', () async {
    final r = await v.verifier(identifiant: 'x', motDePasse: 'y');
    expect(r.accepte, isFalse);
    expect(r.refus, RefusHorsLigne.aucunCompte);
  });

  test('accepte le bon couple, identifiant insensible à la casse et aux espaces', () async {
    await inscrire();
    final r = await v.verifier(identifiant: ' balla@widjila.COM ', motDePasse: 'Secret#123');
    expect(r.accepte, isTrue);
    expect(r.utilisateurId, 'u1');
    expect((await v.verifier(identifiant: '+221770000000', motDePasse: 'Secret#123')).accepte, isTrue);
  });

  test('ne stocke jamais le mot de passe en clair', () async {
    await inscrire();
    expect(disque.values.join(), isNot(contains('Secret#123')));
  });

  test('refuse un mauvais mot de passe ET un mauvais identifiant, sans les distinguer', () async {
    await inscrire();
    final mdp = await v.verifier(identifiant: 'balla@widjila.com', motDePasse: 'autre');
    final ident = await v.verifier(identifiant: 'inconnu@x.com', motDePasse: 'Secret#123');
    expect(mdp.refus, RefusHorsLigne.identifiantsInvalides);
    expect(ident.refus, RefusHorsLigne.identifiantsInvalides);
  });

  test('verrouille dès le 3e échec, même après redémarrage, puis se rouvre', () async {
    await inscrire();
    for (var i = 0; i < 2; i++) {
      await v.verifier(identifiant: 'balla@widjila.com', motDePasse: 'non');
    }
    final troisieme = await v.verifier(identifiant: 'balla@widjila.com', motDePasse: 'non');
    expect(troisieme.refus, RefusHorsLigne.verrouille);

    // Nouvelle instance = redémarrage de l'application : l'état est persistant.
    final relance = VerificateurHorsLigne(secureStorage: stockage, maintenant: () => maintenant, iterations: 50);
    final bon = await relance.verifier(identifiant: 'balla@widjila.com', motDePasse: 'Secret#123');
    expect(bon.refus, RefusHorsLigne.verrouille, reason: 'le bon mot de passe ne contourne pas le verrou');

    maintenant = maintenant.add(const Duration(seconds: 6));
    expect((await relance.verifier(identifiant: 'balla@widjila.com', motDePasse: 'Secret#123')).accepte, isTrue);
  });

  test('efface tout au 10e échec : seule une connexion en ligne rouvre l\'accès', () async {
    await inscrire();
    for (var i = 0; i < 10; i++) {
      await v.verifier(identifiant: 'balla@widjila.com', motDePasse: 'non');
      maintenant = maintenant.add(const Duration(minutes: 20));
    }
    expect(await v.aUnCompte, isFalse);
    final r = await v.verifier(identifiant: 'balla@widjila.com', motDePasse: 'Secret#123');
    expect(r.refus, RefusHorsLigne.aucunCompte);
  });

  test('expire après la fenêtre de validité, et marquerValide la renouvelle', () async {
    await inscrire();
    maintenant = maintenant.add(const Duration(days: 10));
    await v.marquerValide('u1');
    maintenant = maintenant.add(const Duration(days: 10));
    expect((await v.verifier(identifiant: 'balla@widjila.com', motDePasse: 'Secret#123')).accepte, isTrue);

    maintenant = maintenant.add(const Duration(days: 15));
    final r = await v.verifier(identifiant: 'balla@widjila.com', motDePasse: 'Secret#123');
    expect(r.refus, RefusHorsLigne.expire);
  });

  test('marquerValide ignore un autre compte', () async {
    await inscrire();
    maintenant = maintenant.add(const Duration(days: 13));
    await v.marquerValide('autre');
    maintenant = maintenant.add(const Duration(days: 2));
    expect((await v.verifier(identifiant: 'balla@widjila.com', motDePasse: 'Secret#123')).refus,
        RefusHorsLigne.expire);
  });

  test('refuse quand l\'horloge a été reculée pour prolonger la fenêtre', () async {
    await inscrire();
    maintenant = maintenant.add(const Duration(days: 13));
    await v.verifier(identifiant: 'balla@widjila.com', motDePasse: 'Secret#123'); // mémorise l'heure vue
    maintenant = maintenant.subtract(const Duration(days: 12));
    final r = await v.verifier(identifiant: 'balla@widjila.com', motDePasse: 'Secret#123');
    expect(r.refus, RefusHorsLigne.horlogeIncoherente);
  });

  test('un nouvel enregistrement remplace le précédent (un seul compte par appareil)', () async {
    await inscrire();
    await v.enregistrer(utilisateurId: 'u2', identifiants: ['autre@x.com'], motDePasse: 'Autre#456');
    expect((await v.verifier(identifiant: 'balla@widjila.com', motDePasse: 'Secret#123')).accepte, isFalse);
    final r = await v.verifier(identifiant: 'autre@x.com', motDePasse: 'Autre#456');
    expect(r.utilisateurId, 'u2');
  });

  test('effacer retire l\'accès', () async {
    await inscrire();
    await v.effacer();
    expect((await v.verifier(identifiant: 'balla@widjila.com', motDePasse: 'Secret#123')).refus,
        RefusHorsLigne.aucunCompte);
  });

  test('un enregistrement corrompu est traité comme absent, jamais comme accepté', () async {
    disque['sc_verifieur_hors_ligne'] = '{pas du json';
    final r = await v.verifier(identifiant: 'a', motDePasse: 'b');
    expect(r.refus, RefusHorsLigne.aucunCompte);
    expect(disque, isEmpty);
  });
}

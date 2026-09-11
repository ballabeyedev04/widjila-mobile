import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/configuration_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/envoi_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/etat_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/modele_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/rapport.dart';

/// Le vocabulaire du cahier des charges côté mobile — § 4, § 5, § 10, § 19.
///
/// Ces valeurs partent au serveur telles quelles : une faute de frappe dans
/// un code (« A_CONTROLE » au lieu de « A_CONTROLER ») ne se verrait nulle
/// part, sinon dans un filtre qui n'agit pas.
void main() {
  group('§ 5 — modèles', () {
    test('les huit modèles, avec les codes du serveur', () {
      expect(ModeleRapport.values.map((m) => m.raw), [
        'GLOBAL', 'BATIMENT', 'ETAGE_ZONE', 'ENTREPRISE', 'CORPS_ETAT', 'A_TRAITER', 'LEVEES', 'OPR',
      ]);
      for (final m in ModeleRapport.values) {
        expect(ModeleRapportX.fromString(m.raw), m);
      }
    });

    test('un modèle inconnu reste inconnu, plutôt que d’être travesti', () {
      expect(ModeleRapportX.fromString('SAV'), isNull);
    });

    test('les modèles ciblés EXIGENT leur filtre', () {
      expect(ModeleRapport.batiment.filtresRequis, {FiltreRequis.batiment});
      expect(ModeleRapport.etageZone.filtresRequis, {FiltreRequis.etageOuZone});
      expect(ModeleRapport.entreprise.filtresRequis, {FiltreRequis.entreprise});
      expect(ModeleRapport.corpsEtat.filtresRequis, {FiltreRequis.corpsEtat});
      expect(ModeleRapport.global.filtresRequis, isEmpty);
    });

    test('« à traiter » et « levées » posent leur périmètre ; les levées allument l’historique (§ 17)', () {
      expect(ModeleRapport.aTraiter.statutsParDefaut,
          [StatutReserveRapport.aTraiter, StatutReserveRapport.enCours, StatutReserveRapport.aControler]);
      expect(ModeleRapport.levees.statutsParDefaut, [StatutReserveRapport.levee, StatutReserveRapport.cloturee]);
      expect(ModeleRapport.levees.sectionsParDefaut.history, isTrue);
      expect(ModeleRapport.global.sectionsParDefaut.history, isFalse);
    });
  });

  group('§ 4 — filtres', () {
    test('statuts et gravités, avec les codes du serveur', () {
      expect(StatutReserveRapport.values.map((s) => s.raw),
          ['A_TRAITER', 'EN_COURS', 'A_CONTROLER', 'LEVEE', 'CLOTUREE']);
      expect(GraviteRapport.values.map((g) => g.raw), ['CRITIQUE', 'MAJEURE', 'MINEURE']);
    });

    test('« Excel » et « XLSX » désignent le même format', () {
      expect(FormatRapportX.fromString('Excel'), FormatRapport.xlsx);
      expect(FormatRapportX.fromString('xlsx'), FormatRapport.xlsx);
      expect(FormatRapportX.fromString('pdf'), FormatRapport.pdf);
    });

    test('aller-retour JSON sans perte, dates au jour près', () {
      final filtres = FiltresRapport(
        batiments: const ['b1'],
        etages: const ['e1', 'e2'],
        zones: const ['z1'],
        entreprises: const ['p1'],
        corpsEtat: const ['ce1'],
        statuts: const [StatutReserveRapport.levee],
        gravites: const [GraviteRapport.critique],
        dateDebut: DateTime(2026, 9, 1),
        dateFin: DateTime(2026, 9, 30, 18, 45),
      );

      final json = filtres.toJson();
      expect(json['dateDebut'], '2026-09-01');
      expect(json['dateFin'], '2026-09-30');
      expect(FiltresRapport.fromJson(json), filtres.copyWith(dateFin: DateTime(2026, 9, 30)));
    });

    test('des filtres vides ne produisent AUCUNE clé — « Tous »', () {
      expect(const FiltresRapport().toJson(), isEmpty);
      expect(const FiltresRapport().estVide, isTrue);
    });

    test('dit ce qui MANQUE pour le modèle choisi', () {
      const vides = FiltresRapport();
      expect(vides.manquantsPour(ModeleRapport.batiment), [FiltreRequis.batiment]);
      expect(vides.manquantsPour(ModeleRapport.global), isEmpty);
      // Un étage OU une zone suffit.
      expect(const FiltresRapport(zones: ['z1']).manquantsPour(ModeleRapport.etageZone), isEmpty);
    });

    test('une valeur inconnue du serveur est ignorée, pas inventée', () {
      final f = FiltresRapport.fromJson({
        'statuts': ['A_TRAITER', 'PERDU'],
        'gravites': ['ENORME'],
      });
      expect(f.statuts, [StatutReserveRapport.aTraiter]);
      expect(f.gravites, isEmpty);
    });
  });

  group('§ 19 — états', () {
    test('les sept états du cahier des charges', () {
      expect(EtatRapport.values.map((e) => e.raw),
          ['brouillon', 'en_attente', 'generation', 'genere', 'envoye', 'echec', 'archive']);
    });

    test('un rapport ANTÉRIEUR au module, sans état, est un rapport généré', () {
      expect(EtatRapportX.fromString(null), EtatRapport.genere);
    });
  });

  group('Rapport', () {
    test('le titre : le nom, sinon le modèle, sinon l’ancien type', () {
      const avecNom = Rapport(id: 'r', chantierId: 'c', fichierUrl: '', nom: 'Relance ABC', modele: ModeleRapport.entreprise);
      const sansNom = Rapport(id: 'r', chantierId: 'c', fichierUrl: '', modele: ModeleRapport.opr);
      expect(avecNom.nom, 'Relance ABC');
      expect(sansNom.modele, ModeleRapport.opr);
      expect(const Rapport(id: 'r', chantierId: 'c', fichierUrl: '').estGenere, isFalse);
      expect(const Rapport(id: 'r', chantierId: 'c', fichierUrl: '/u.pdf').estGenere, isTrue);
    });

    test('sa configuration est reprise à l’identique pour la modifier (§ 20)', () {
      final rapport = Rapport.fromJson({
        'id': 'r1',
        'chantierId': 'c1',
        'nom': 'Levées',
        'modele': 'LEVEES',
        'statut': 'genere',
        'fichier_url': '/uploads/rapports/r1.pdf',
        'formats': ['XLSX'],
        'sections': {'history': true, 'plans': false},
        'filtres': {
          'statuts': ['LEVEE'],
        },
      });

      final config = rapport.configuration();
      expect(config.modele, ModeleRapport.levees);
      expect(config.formats, {FormatRapport.xlsx});
      expect(config.sections.plans, isFalse);
      expect(config.filtres.statuts, [StatutReserveRapport.levee]);
    });

    test('survit à une charge utile minimale', () {
      final rapport = Rapport.fromJson({'id': 'r1'});
      expect(rapport.fichierUrl, '');
      expect(rapport.formats, {FormatRapport.pdf});
      expect(rapport.version, 1);
    });
  });

  group('§ 13 — demande d’envoi', () {
    test('aller-retour JSON — c’est ce qui part dans la file hors ligne (§ 22)', () {
      const demande = DemandeEnvoiRapport(
        exclure: ['a@ex.fr'],
        destinataires: ['b@ex.fr'],
        copies: [],
        objet: 'Objet',
        message: 'Message',
        mode: ModeEnvoiRapport.lien,
      );
      expect(DemandeEnvoiRapport.fromJson(demande.toJson()), demande);
    });

    test('par défaut, seule la liste des retraits part', () {
      expect(const DemandeEnvoiRapport().toJson(), {'exclure': <String>[]});
    });
  });
}

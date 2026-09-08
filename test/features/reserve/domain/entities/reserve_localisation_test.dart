import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve_collaboration.dart';
import 'package:suivie_chantier_mobile/l10n/generated/app_localizations.dart';

/// La localisation d'une réserve, et le destinataire d'une affectation.
///
/// ## Les deux bugs verrouillés ici
///
/// 1. « Non localisée » sur une réserve qui porte pourtant un plan.
///
///    Le libellé ne regardait que bâtiment, étage et zone. Or, depuis que le
///    relevé se fait en appuyant sur un plan, c'est le PLAN la localisation
///    principale — le serveur en DÉDUIT les trois niveaux. Un chantier dont
///    personne n'a saisi la structure n'en a donc aucun, et toutes ses réserves
///    s'affichaient « Non localisée » : des cartes sans information.
///
/// 2. « — » à la place du nom de l'intervenant.
///
///    Une affectation peut viser un COMPTE, une ENTREPRISE UTILISATRICE ou une
///    entreprise de l'ANNUAIRE. Cette troisième nature n'existait pas côté
///    client : le nom n'était lu ni dans le JSON, ni affiché.
void main() {
  // Les traductions FRANÇAISES, chargées directement : `localisationLabel` ne
  // demande qu'un `AppLocalizations`, pas un arbre de widgets.
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('fr'));
  });

  Reserve reserveAvec({
    ReservePlanRef? plan,
    ReserveLocalisationRef? batiment,
    ReserveLocalisationRef? etage,
    ReserveLocalisationRef? zone,
  }) =>
      Reserve(
        id: 'r1',
        numero: 'R-0001',
        chantierId: 'c1',
        titre: 'Fissure au plafond',
        plan: plan,
        batiment: batiment,
        etage: etage,
        zone: zone,
      );

  group('la localisation affichée sur une carte', () {
    test('nomme le PLAN quand le chantier n’a aucune structure saisie', () {
      // Le cas exact qui affichait « Non localisée » : la réserve est posée sur
      // un plan, à un point précis, mais personne n'a découpé le chantier en
      // bâtiments et étages.
      final r = reserveAvec(plan: const ReservePlanRef(id: 'p1', nom: 'Niveau R+2'));

      expect(r.localisationLabel(l10n), 'Niveau R+2');
    });

    test('met le plan EN TÊTE, puis précise avec la structure', () {
      final r = reserveAvec(
        plan: const ReservePlanRef(id: 'p1', nom: 'Appartement A203'),
        batiment: const ReserveLocalisationRef(id: 'b1', nom: 'Bâtiment A'),
        etage: const ReserveLocalisationRef(id: 'e1', nom: 'R+2'),
      );

      expect(r.localisationLabel(l10n), 'Appartement A203 · Bâtiment A · R+2');
    });

    test('garde le comportement d’avant pour une réserve SANS plan', () {
      // Les réserves anciennes, et celles consignées depuis la liste.
      final r = reserveAvec(
        batiment: const ReserveLocalisationRef(id: 'b1', nom: 'Bâtiment A'),
        zone: const ReserveLocalisationRef(id: 'z1', nom: 'A203'),
      );

      expect(r.localisationLabel(l10n), 'Bâtiment A · A203');
    });

    test('ne dit « non localisée » que si elle ne l’est VRAIMENT pas', () {
      expect(reserveAvec().localisationLabel(l10n), isNot(contains('·')));
      expect(reserveAvec().localisationLabel(l10n).trim(), isNotEmpty);
    });

    test('ignore un nom vide plutôt que d’afficher un séparateur orphelin', () {
      final r = reserveAvec(
        plan: const ReservePlanRef(id: 'p1', nom: '   '),
        batiment: const ReserveLocalisationRef(id: 'b1', nom: 'Bâtiment A'),
      );

      expect(r.localisationLabel(l10n), 'Bâtiment A');
    });
  });

  group('le plan porteur, lu depuis le détail', () {
    test('se lit avec sa version et son fichier — de quoi le ROUVRIR', () {
      final r = Reserve.fromJson(const {
        'id': 'r1',
        'numero': 'R-0001',
        'chantierId': 'c1',
        'titre': 'Fissure',
        'plan': {
          'id': 'p1',
          'nom': 'Appartement A203',
          'version': 3,
          'fichier_url': '/uploads/plans/a203.pdf',
        },
      });

      expect(r.plan!.id, 'p1');
      expect(r.plan!.nom, 'Appartement A203');
      expect(r.plan!.version, 3);
      expect(r.plan!.fichierUrl, '/uploads/plans/a203.pdf');
    });

    test('reste nul quand le serveur ne le joint pas', () {
      // Les listes ne servent pas le plan : la carte retombe alors sur la
      // structure, sans lever.
      final r = Reserve.fromJson(const {
        'id': 'r1', 'numero': 'R-0001', 'chantierId': 'c1', 'titre': 'Fissure',
      });

      expect(r.plan, isNull);
    });

    test('survit à un aller-retour par le cache hors ligne', () {
      // `toJson`/`fromJson` sont le format du cache local : un champ oublié
      // dans l'un des deux fait disparaître l'information hors ligne.
      final origine = Reserve.fromJson(const {
        'id': 'r1',
        'numero': 'R-0001',
        'chantierId': 'c1',
        'titre': 'Fissure',
        'plan': {'id': 'p1', 'nom': 'A203', 'version': 2, 'fichier_url': '/uploads/plans/x.pdf'},
      });

      final relu = Reserve.fromJson(origine.toJson());

      expect(relu.plan, origine.plan);
    });
  });

  group('le destinataire d’une affectation', () {
    test('nomme l’intervenant de l’annuaire', () {
      // La nature la plus fréquente, et la seule que le client ne savait pas
      // lire : la ligne s'affichait « — ».
      final a = AffectationReserve.fromJson(const {
        'id': 'aff-1',
        'partenaire': {'id': 'p-1', 'nom': 'SARL Diallo Étanchéité', 'type': 'sous_traitant'},
      });

      expect(a.libelle, 'SARL Diallo Étanchéité');
      expect(a.partenaireId, 'p-1');
      expect(a.estEntreprise, isTrue);
    });

    test('nomme toujours un membre de l’équipe, et le fait primer', () {
      final a = AffectationReserve.fromJson(const {
        'id': 'aff-1',
        'utilisateur': {'id': 'u-1', 'nom': 'BEYE', 'prenom': 'Balla'},
      });

      expect(a.libelle, 'Balla BEYE');
      expect(a.estEntreprise, isFalse);
    });

    test('nomme toujours une entreprise utilisatrice de la plateforme', () {
      final a = AffectationReserve.fromJson(const {
        'id': 'aff-1',
        'entreprise': {'id': 'o-1', 'nom': 'Groupe Sénégal BTP'},
      });

      expect(a.libelle, 'Groupe Sénégal BTP');
      expect(a.estEntreprise, isTrue);
    });

    test('retombe sur la clé étrangère brute plutôt que de perdre le lien', () {
      // Ceinture : si un jour une réponse revenait sans ses jointures, on garde
      // au moins de quoi savoir QUI est visé.
      final a = AffectationReserve.fromJson(const {'id': 'aff-1', 'partenaireId': 'p-1'});

      expect(a.partenaireId, 'p-1');
    });

    test('affiche un tiret, et non « null », quand il n’y a vraiment personne', () {
      final a = AffectationReserve.fromJson(const {'id': 'aff-1'});

      expect(a.libelle, '—');
    });
  });
}

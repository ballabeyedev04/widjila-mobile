import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/l10n/generated/app_localizations.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('fr'));
  });

  group('UserRole — nouveaux rôles Pilote et SousTraitant', () {
    test('fromString/raw font l\'aller-retour pour Pilote', () {
      expect(UserRoleX.fromString('Pilote'), UserRole.pilote);
      expect(UserRole.pilote.raw, 'Pilote');
    });

    test('fromString/raw font l\'aller-retour pour SousTraitant', () {
      expect(UserRoleX.fromString('SousTraitant'), UserRole.sousTraitant);
      expect(UserRole.sousTraitant.raw, 'SousTraitant');
    });

    test('Pilote peut intervenir sur les réserves (RESERVE_INTERVENANTS) mais ne pilote jamais', () {
      expect(UserRole.pilote.peutIntervenirSurReserves, isTrue);
      expect(UserRole.pilote.peutPiloter, isFalse);
      expect(UserRole.pilote.estSousTraitant, isFalse);
    });

    test('Pilote ne gère ni l\'organisation ni les documents (hors des groupes existants)', () {
      expect(UserRole.pilote.peutGererOrganisation, isFalse);
      expect(UserRole.pilote.estOperationnelOuControle, isFalse);
    });

    test('SousTraitant n\'a PAS le même accès large que les autres intervenants', () {
      // Contrairement à Entreprise, SousTraitant n'est volontairement pas
      // dans le groupe RESERVE_INTERVENANTS côté back (accès restreint aux
      // deux routes qui lui sont ouvertes) — miroir exact ici.
      expect(UserRole.sousTraitant.peutIntervenirSurReserves, isFalse);
      expect(UserRole.sousTraitant.estSousTraitant, isTrue);
      expect(UserRole.sousTraitant.peutPiloter, isFalse);
      expect(UserRole.sousTraitant.peutGererOrganisation, isFalse);
    });

    test('un rôle brut inconnu ne casse rien (comportement déjà existant, non régressé)', () {
      expect(UserRoleX.fromString('RoleInexistant'), UserRole.inconnu);
      expect(UserRoleX.fromString(null), UserRole.inconnu);
    });

    test('label et icon sont définis pour les deux nouveaux rôles (pas de crash d\'exhaustivité)', () {
      expect(UserRole.pilote.label(l10n), isNotEmpty);
      expect(UserRole.sousTraitant.label(l10n), isNotEmpty);
      expect(UserRole.pilote.icon, isNotNull);
      expect(UserRole.sousTraitant.icon, isNotNull);
    });
  });
}

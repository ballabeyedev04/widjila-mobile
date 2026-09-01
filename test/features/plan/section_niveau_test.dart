import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/pages/plan_navigation_page.dart';
import 'package:suivie_chantier_mobile/features/referentiel/domain/entities/code_niveau.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/chantier_structure.dart';

EtageStructure _niveau(
  String nom, {
  int cote = 0,
  TypeNiveau type = TypeNiveau.etage,
}) =>
    EtageStructure(id: 'e-$nom', nom: nom, niveau: cote, typeNiveau: type);

/// Rangement d'un niveau sous l'une des trois sections de l'écran de plans.
///
/// Deux régimes coexistent, et c'est voulu :
///
///   - les niveaux déposés par « Envoi de plans » portent une NATURE déclarée,
///     choisie dans le référentiel. Elle fait foi ;
///   - ceux créés avant ce référentiel valent tous `etage` par défaut de la
///     migration, qui n'a rien deviné de leur nom. Pour eux seulement, la cote
///     et le nom servent de repli.
///
/// Le premier régime a été ajouté APRÈS coup : jusque-là, la section se
/// déduisait du nom (« toiture ») et de la cote. Un « SS1 » déposé par le
/// nouveau parcours arrive sans cote — il atterrissait donc dans ÉTAGES.
void main() {
  group('nature déclarée — elle fait foi', () {
    test('range un sous-sol déclaré, même sans cote', () {
      // LA régression : le parcours de dépôt ne demande pas la cote, seulement
      // le code. Sans la nature déclarée, ce niveau tombait dans ÉTAGES.
      expect(
        sectionDuNiveau(_niveau('SS1', type: TypeNiveau.sousSol)),
        TypeNiveau.sousSol,
      );
    });

    test('range une toiture déclarée, quel que soit son nom', () {
      // « Édicule » et « Local technique » sont des niveaux de toiture qu'aucun
      // mot-clé sur « toiture » n'aurait attrapés.
      for (final nom in ['EDIC', 'LTEC', 'Niveau haut']) {
        expect(
          sectionDuNiveau(_niveau(nom, type: TypeNiveau.toiture)),
          TypeNiveau.toiture,
          reason: nom,
        );
      }
    });

    test('la nature déclarée l’emporte sur une cote contradictoire', () {
      // Une toiture déclarée avec une cote négative reste une toiture : c'est
      // la saisie explicite qui compte, pas l'inférence.
      expect(
        sectionDuNiveau(_niveau('TOIT', cote: -2, type: TypeNiveau.toiture)),
        TypeNiveau.toiture,
      );
    });
  });

  group('repli pour les niveaux antérieurs au référentiel', () {
    test('une cote négative est un sous-sol', () {
      expect(sectionDuNiveau(_niveau('Sous-sol 1', cote: -1)), TypeNiveau.sousSol);
    });

    test('le vocabulaire de la toiture est reconnu', () {
      // Les quatre niveaux réellement dessinés en toiture. La version
      // précédente ne connaissait que « toiture » et manquait les trois
      // autres.
      for (final nom in ['Toiture-terrasse', 'Combles perdus', 'Édicule', 'Local technique']) {
        expect(sectionDuNiveau(_niveau(nom)), TypeNiveau.toiture, reason: nom);
      }
    });

    test('la casse et les accents ne changent rien', () {
      expect(sectionDuNiveau(_niveau('TERRASSE')), TypeNiveau.toiture);
      expect(sectionDuNiveau(_niveau('edicule')), TypeNiveau.toiture);
    });

    test('un étage ordinaire reste dans ÉTAGES', () {
      for (final nom in ['RDC', 'R+1', 'Niveau 3', 'Mezzanine']) {
        expect(sectionDuNiveau(_niveau(nom, cote: 1)), TypeNiveau.etage, reason: nom);
      }
    });

    test('l’acrotère n’est PAS un niveau de toiture', () {
      // C'est un détail de rive, pas un niveau — vérifié auprès de sources du
      // bâtiment. L'inclure aurait rangé un niveau courant au mauvais endroit.
      expect(sectionDuNiveau(_niveau('Acrotère nord')), TypeNiveau.etage);
    });

    test('un niveau ancien sans indice reste dans ÉTAGES', () {
      // Limite assumée : « Niveau -1 » avec une cote à 0 ne peut pas être
      // deviné sans inventer. Le client corrige la nature depuis la fiche.
      expect(sectionDuNiveau(_niveau('Niveau -1')), TypeNiveau.etage);
    });
  });
}

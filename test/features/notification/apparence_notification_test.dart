import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/theme/app_colors.dart';
import 'package:suivie_chantier_mobile/features/notification/presentation/widgets/notification_card.dart';

/// Les types de notification sont produits par le BACK et consommés ici. Ces
/// tests figent la liste réellement émise aujourd'hui — si le serveur en
/// renomme un, c'est ici que ça doit casser, pas silencieusement à l'écran.
///
/// Régression : une première version comparait des mots simples (`'reserve'`)
/// alors que les types sont pointés (`reserve.affectee`). Aucun cas ne
/// correspondait, toutes les notifications tombaient sur l'icône neutre.
void main() {
  /// Types réellement émis, relevés dans le backend :
  ///   - reserve.service.js       → reserve.affectee, reserve.statut
  ///   - chantier.service.js      → chantier.affectation
  ///   - inspectionExtra.service  → inspection.convocation
  ///   - jobs/markReservesEnRetard → reserve.en_retard
  ///   - jobs/reminders           → reserve.echeance_proche, reserve.escalade
  const typesEmisParLeBack = [
    'reserve.affectee',
    'reserve.statut',
    'reserve.en_retard',
    'reserve.echeance_proche',
    'reserve.escalade',
    'chantier.affectation',
    'inspection.convocation',
  ];

  test('aucun type réel ne retombe sur l’icône neutre', () {
    for (final type in typesEmisParLeBack) {
      final (icone, _) = apparenceNotification(type);
      expect(
        icone,
        isNot(Icons.notifications_none_rounded),
        reason: '« $type » n’est pas reconnu et affiche l’icône par défaut',
      );
    }
  });

  test('les réserves urgentes se distinguent des réserves ordinaires', () {
    final (_, retard) = apparenceNotification('reserve.en_retard');
    final (_, escalade) = apparenceNotification('reserve.escalade');
    final (_, echeance) = apparenceNotification('reserve.echeance_proche');
    final (_, ordinaire) = apparenceNotification('reserve.affectee');

    expect(retard, AppColors.danger);
    expect(escalade, AppColors.danger);
    expect(echeance, AppColors.warning);
    expect(ordinaire, AppColors.primary);
  });

  test('chaque famille a sa propre icône', () {
    final (reserve, _) = apparenceNotification('reserve.affectee');
    final (chantier, _) = apparenceNotification('chantier.affectation');
    final (inspection, _) = apparenceNotification('inspection.convocation');

    expect({reserve, chantier, inspection}, hasLength(3));
  });

  test('un type inconnu de la même famille hérite de son icône', () {
    // Le back peut ajouter un type sans que le mobile soit redéployé.
    final (connu, _) = apparenceNotification('reserve.affectee');
    final (futur, _) = apparenceNotification('reserve.commentee');
    expect(futur, connu);
  });

  test('un type d’une famille inconnue retombe proprement sur le neutre', () {
    final (icone, couleur) = apparenceNotification('facturation.echue');
    expect(icone, Icons.notifications_none_rounded);
    expect(couleur, AppColors.neutral);
  });

  test('un type vide ou malformé ne fait pas planter', () {
    expect(() => apparenceNotification(''), returnsNormally);
    expect(() => apparenceNotification('.'), returnsNormally);
    expect(() => apparenceNotification('reserve.'), returnsNormally);
  });
}

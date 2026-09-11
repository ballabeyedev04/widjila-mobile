import '../../features/reserve/domain/entities/reserve.dart';
import 'file_attente.dart';

/// Réconciliation d'une réserve : ce que l'écran doit montrer quand le
/// serveur et l'appareil ne sont pas encore d'accord.
///
/// ## La règle (deuxième audit)
///
/// ```text
/// VUE = VERSION SERVEUR  +  changements locaux ENCORE EN FILE, rejoués dessus
/// ```
///
/// C'est un rebase. Le serveur fait foi pour tout ce que l'utilisateur n'a
/// pas touché — un titre corrigé depuis le web, un nom de lot, le numéro
/// définitif. Les actions faites sur l'appareil et pas encore confirmées
/// s'appliquent PAR-DESSUS, dans leur ordre.
///
/// La version précédente figeait toute la ligne locale dès qu'un seul
/// changement était en attente : un statut changé hors ligne cachait
/// indéfiniment le titre corrigé par quelqu'un d'autre (donnée périmée
/// affichée comme vraie).

/// Types d'action dont l'effet se voit sur la ligne locale d'une réserve.
/// Une photo en file ne la modifie pas.
const Set<TypeAction> typesQuiReecriventLaReserve = {
  TypeAction.creerReserve,
  TypeAction.changerStatutReserve,
  TypeAction.modifierReserve,
  TypeAction.supprimerReserve,
};

/// Applique des champs modifiés (clés du serveur : `titre`, `description`,
/// `severite`, `categorie`, `date_limite`) à une réserve.
Reserve appliquerChamps(Reserve r, Map<String, dynamic> champs) => r.copierAvec(
      titre: champs['titre'] as String?,
      description: champs['description'] as String?,
      severite: champs.containsKey('severite') ? ReserveSeveriteX.fromString(champs['severite'] as String?) : null,
      categorie: champs.containsKey('categorie') ? ReserveCategorieX.fromString(champs['categorie'] as String?) : null,
      dateLimite: champs['date_limite'] is String ? DateTime.tryParse(champs['date_limite'] as String) : null,
    );

/// Valeurs ACTUELLES de [r] pour les champs [champs] — les « valeurs de
/// départ » d'une modification, que le serveur compare aux siennes pour
/// détecter un conflit.
Map<String, dynamic> valeursDe(Reserve r, Iterable<String> champs) => {
      for (final c in champs)
        c: switch (c) {
          'titre' => r.titre,
          'description' => r.description,
          'severite' => r.severite.raw,
          'categorie' => r.categorie.raw,
          'date_limite' => r.dateLimite?.toIso8601String().split('T').first,
          _ => null,
        },
    };

/// Rejoue [actions] (dans leur ordre) sur [base]. Retourne `null` si une
/// suppression locale est en attente : la réserve ne doit plus s'afficher.
Reserve? rejouerActionsLocales(Reserve base, Iterable<ActionEnAttente> actions) {
  Reserve? vue = base;
  for (final a in actions) {
    final courante = vue;
    if (courante == null) break;
    switch (a.type) {
      case TypeAction.changerStatutReserve:
        vue = courante.copierAvec(statut: ReserveStatutX.fromString(a.charge['statut'] as String?));
      case TypeAction.modifierReserve:
        vue = appliquerChamps(courante, (a.charge['champs'] as Map?)?.cast<String, dynamic>() ?? const {});
      case TypeAction.supprimerReserve:
        vue = null;
      case TypeAction.creerReserve:
      case TypeAction.ajouterPhotoReserve:
      case TypeAction.envoyerRapport:
        // La version serveur contient déjà la création ; photo et rapport ne
        // changent pas la ligne.
        break;
    }
  }
  return vue;
}

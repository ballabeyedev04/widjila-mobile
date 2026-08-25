/// Cache local du profil utilisateur (JSON) — évite un écran blanc le temps
/// que la session soit revalidée auprès du backend au démarrage : l'app
/// peut afficher immédiatement le rôle/nom en cache, puis se corriger
/// silencieusement une fois la réponse serveur reçue.
///
/// Volontairement générique (`Map<String, dynamic>`, pas de dépendance vers
/// `features/auth`) : `core/` ne doit jamais dépendre d'une feature — c'est
/// l'inverse qui est vrai dans cette architecture.
abstract class UserCache {
  Future<void> saveJson(Map<String, dynamic> json);
  Future<Map<String, dynamic>?> readJson();
  Future<void> clear();
}

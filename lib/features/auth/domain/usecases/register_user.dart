import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/user.dart';
import '../repositories/auth_repository.dart';

class RegisterUser {
  final AuthRepository repository;
  RegisterUser(this.repository);

  Future<Either<Failure, User>> call({
    required String nom,
    required String prenom,
    required String email,
    required String motDePasse,
    String? telephone,
    String? fonction,
    String? organisationNom,
    String? raisonSociale,
    /// Identifiants d'entreprise, indexés par la clé attendue par le serveur
    /// (`siret`, `ninea`, `nif`, `ncc`, `idu`, `rccm`, `num_tva`).
    ///
    /// Une carte plutôt que des paramètres nommés : les champs varient selon
    /// le pays, et les figer ici obligerait à modifier chaque couche à chaque
    /// pays ajouté.
    Map<String, String> identifiants = const {},
    String? organisationTelephone,
    String? organisationEmail,
    String? organisationAdresse,
    String? organisationVille,
    String? organisationPays,
  }) {
    return repository.register(
      nom: nom,
      prenom: prenom,
      email: email,
      motDePasse: motDePasse,
      telephone: telephone,
      fonction: fonction,
      organisationNom: organisationNom,
      raisonSociale: raisonSociale,
      identifiants: identifiants,
      organisationTelephone: organisationTelephone,
      organisationEmail: organisationEmail,
      organisationAdresse: organisationAdresse,
      organisationVille: organisationVille,
      organisationPays: organisationPays,
    );
  }
}

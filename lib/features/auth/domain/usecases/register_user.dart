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
    String? siret,
    String? rccm,
    String? ninea,
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
      siret: siret,
      rccm: rccm,
      ninea: ninea,
      organisationTelephone: organisationTelephone,
      organisationEmail: organisationEmail,
      organisationAdresse: organisationAdresse,
      organisationVille: organisationVille,
      organisationPays: organisationPays,
    );
  }
}

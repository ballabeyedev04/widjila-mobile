import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/code_niveau.dart';
import '../repositories/referentiel_repository.dart';

/// Crée un code de niveau absent de la liste — le « + » de l'écran de dépôt.
///
/// Le code appartient à l'organisation de l'appelant : le serveur refuse
/// d'écrire dans le catalogue standard de la plateforme, de sorte qu'une
/// entreprise n'impose pas ses codes aux autres clients.
class CreerCodeNiveau {
  final ReferentielRepository repository;
  CreerCodeNiveau(this.repository);

  Future<Either<Failure, CodeNiveau>> call({
    required TypeNiveau typeNiveau,
    required String code,
    String? nom,
  }) =>
      repository.creerCodeNiveau(typeNiveau: typeNiveau, code: code, nom: nom);
}

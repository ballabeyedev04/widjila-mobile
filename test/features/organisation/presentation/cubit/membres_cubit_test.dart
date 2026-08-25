import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/organisation/domain/entities/membre.dart';
import 'package:suivie_chantier_mobile/features/organisation/domain/usecases/ajouter_membre.dart';
import 'package:suivie_chantier_mobile/features/organisation/domain/usecases/changer_statut_membre.dart';
import 'package:suivie_chantier_mobile/features/organisation/domain/usecases/get_membres.dart';
import 'package:suivie_chantier_mobile/features/organisation/presentation/cubit/membres_cubit.dart';
import 'package:suivie_chantier_mobile/features/organisation/presentation/cubit/membres_state.dart';

class MockGetMembres extends Mock implements GetMembres {}

class MockAjouterMembre extends Mock implements AjouterMembre {}

class MockChangerStatutMembre extends Mock implements ChangerStatutMembre {}

Membre _membre(String id, {String nom = 'Diop', String prenom = 'Awa'}) => Membre(
      id: id,
      nom: nom,
      prenom: prenom,
      email: '$id@chantier.sn',
      role: UserRole.conducteurTravaux,
    );

void main() {
  late MockGetMembres getMembres;
  late MockAjouterMembre ajouterMembreUsecase;

  setUpAll(() {
    registerFallbackValue(UserRole.conducteurTravaux);
  });

  setUp(() {
    getMembres = MockGetMembres();
    ajouterMembreUsecase = MockAjouterMembre();
  });

  MembresCubit build() => MembresCubit(
        getMembres: getMembres,
        ajouterMembreUsecase: ajouterMembreUsecase,
        changerStatutMembreUsecase: MockChangerStatutMembre(),
      );

  blocTest<MembresCubit, MembresState>(
    'charger() émet chargement puis succès avec la liste des membres',
    build: () {
      when(() => getMembres()).thenAnswer((_) async => Right([_membre('m1'), _membre('m2')]));
      return build();
    },
    act: (cubit) => cubit.charger(),
    expect: () => [
      const MembresState(status: MembresStatus.chargement),
      isA<MembresState>()
          .having((s) => s.status, 'status', MembresStatus.succes)
          .having((s) => s.membres.length, 'membres.length', 2),
    ],
  );

  blocTest<MembresCubit, MembresState>(
    'charger() émet une erreur quand le back échoue',
    build: () {
      when(() => getMembres()).thenAnswer((_) async => const Left(NetworkFailure()));
      return build();
    },
    act: (cubit) => cubit.charger(),
    expect: () => [
      const MembresState(status: MembresStatus.chargement),
      isA<MembresState>()
          .having((s) => s.status, 'status', MembresStatus.erreur)
          .having((s) => s.erreur, 'erreur', const NetworkFailure().errorMessage),
    ],
  );

  blocTest<MembresCubit, MembresState>(
    'ajouter() succès : le nouveau membre est ajouté en tête de liste et le mot de passe temporaire conservé',
    build: () {
      when(() => ajouterMembreUsecase(
            nom: any(named: 'nom'),
            prenom: any(named: 'prenom'),
            email: any(named: 'email'),
            role: any(named: 'role'),
            telephone: any(named: 'telephone'),
            fonction: any(named: 'fonction'),
            motDePasse: any(named: 'motDePasse'),
          )).thenAnswer((_) async => Right(AjouterMembreResult(
            membre: _membre('nouveau', nom: 'Fall', prenom: 'Moussa'),
            motDePasseTemporaire: 'Tmp!2026',
          )));
      return build();
    },
    seed: () => MembresState(status: MembresStatus.succes, membres: [_membre('m1')]),
    act: (cubit) => cubit.ajouter(
      nom: 'Fall',
      prenom: 'Moussa',
      email: 'moussa.fall@chantier.sn',
      role: UserRole.conducteurTravaux,
    ),
    expect: () => [
      isA<MembresState>().having((s) => s.soumissionStatus, 'soumissionStatus', SoumissionStatus.enCours),
      isA<MembresState>()
          .having((s) => s.soumissionStatus, 'soumissionStatus', SoumissionStatus.succes)
          .having((s) => s.membres.map((m) => m.id).toList(), 'ids', ['nouveau', 'm1'])
          .having((s) => s.dernierAjout?.motDePasseTemporaire, 'motDePasseTemporaire', 'Tmp!2026'),
    ],
  );

  blocTest<MembresCubit, MembresState>(
    'ajouter() échec : l\'erreur de soumission est posée et la liste reste inchangée',
    build: () {
      when(() => ajouterMembreUsecase(
            nom: any(named: 'nom'),
            prenom: any(named: 'prenom'),
            email: any(named: 'email'),
            role: any(named: 'role'),
            telephone: any(named: 'telephone'),
            fonction: any(named: 'fonction'),
            motDePasse: any(named: 'motDePasse'),
          )).thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Email déjà utilisé')));
      return build();
    },
    seed: () => MembresState(status: MembresStatus.succes, membres: [_membre('m1')]),
    act: (cubit) => cubit.ajouter(
      nom: 'Fall',
      prenom: 'Moussa',
      email: 'moussa.fall@chantier.sn',
      role: UserRole.conducteurTravaux,
    ),
    expect: () => [
      isA<MembresState>().having((s) => s.soumissionStatus, 'soumissionStatus', SoumissionStatus.enCours),
      isA<MembresState>()
          .having((s) => s.soumissionStatus, 'soumissionStatus', SoumissionStatus.erreur)
          .having((s) => s.soumissionErreur, 'soumissionErreur', 'Email déjà utilisé')
          .having((s) => s.membres.map((m) => m.id).toList(), 'ids inchangés', ['m1']),
    ],
  );

  blocTest<MembresCubit, MembresState>(
    'accuserReceptionAjout() réinitialise le statut de soumission et efface le dernier ajout',
    build: build,
    seed: () => MembresState(
      soumissionStatus: SoumissionStatus.succes,
      dernierAjout: AjouterMembreResult(membre: _membre('nouveau'), motDePasseTemporaire: 'Tmp!2026'),
    ),
    act: (cubit) => cubit.accuserReceptionAjout(),
    expect: () => [
      isA<MembresState>()
          .having((s) => s.soumissionStatus, 'soumissionStatus', SoumissionStatus.inactif)
          .having((s) => s.dernierAjout, 'dernierAjout', isNull)
          .having((s) => s.soumissionErreur, 'soumissionErreur', isNull),
    ],
  );
}

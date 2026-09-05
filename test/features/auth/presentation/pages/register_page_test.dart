import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_event.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/bloc/auth_state.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/pages/register_page.dart';
import 'package:suivie_chantier_mobile/features/referentiel/domain/entities/pays.dart';
import 'package:suivie_chantier_mobile/features/referentiel/domain/usecases/get_pays.dart';
import 'package:suivie_chantier_mobile/features/referentiel/presentation/cubit/pays_cubit.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/pompe_page.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _MockPays extends Mock implements GetPays {}

/// L'écran d'inscription.
///
/// ## Le catalogue des pays décide de la forme du formulaire
///
/// Les champs d'identification d'entreprise ne sont pas les mêmes selon le
/// pays : SIRET et TVA en France, NINEA au Sénégal, RCCM en Côte d'Ivoire et
/// au Mali. Le catalogue vient donc de l'API, avec la liste des champs
/// attendus pour chaque pays.
///
/// Cela crée une dépendance inhabituelle : si l'appel échoue, l'écran ne sait
/// plus quels champs demander. Il doit néanmoins s'ouvrir — sans quoi une
/// panne de référentiel fermerait la porte d'entrée de l'application aux
/// nouveaux clients, c'est-à-dire à ceux qui n'ont aucun autre moyen d'entrer.
void main() {
  late _MockPays getPays;

  AuthBloc bloc(AuthState etat) {
    final b = _MockAuthBloc();
    whenListen(b, const Stream<AuthState>.empty(), initialState: etat);
    return b;
  }

  void desinscrire() {
    if (sl.isRegistered<PaysCubit>()) sl.unregister<PaysCubit>();
  }

  setUp(() {
    getPays = _MockPays();
    desinscrire();
    sl.registerFactory<PaysCubit>(() => PaysCubit(getPays: getPays));
  });

  tearDown(desinscrire);

  const repos = AuthState(status: AuthStatus.nonAuthentifie);

  const catalogue = [
    Pays(code: 'FR', nom: 'France', indicatif: '+33'),
    Pays(code: 'SN', nom: 'Senegal', indicatif: '+221'),
  ];

  testWidgets('s ouvre pendant que le catalogue des pays charge', (tester) async {
    // L'écran ne doit pas rester blanc en attendant un référentiel.
    final attente = Completer<Either<Failure, List<Pays>>>();
    when(getPays.call).thenAnswer((_) => attente.future);

    await pomperPage(tester, const RegisterPage(), auth: bloc(repos));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);

    attente.complete(const Right(catalogue));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('le catalogue en PANNE ne ferme pas la porte d entree',
      (tester) async {
    // C'est le seul écran par lequel un nouveau client peut entrer. Une
    // panne de référentiel ne doit pas le rendre inaccessible.
    when(getPays.call).thenAnswer(
      (_) async => const Left<Failure, List<Pays>>(NetworkFailure()),
    );

    await pomperPage(tester, const RegisterPage(), auth: bloc(repos));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });

  testWidgets('avec le catalogue, l ecran se monte sans incident', (tester) async {
    when(getPays.call)
        .thenAnswer((_) async => const Right<Failure, List<Pays>>(catalogue));

    await pomperPage(tester, const RegisterPage(), auth: bloc(repos));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });

  testWidgets('un refus du serveur s affiche sans casser le formulaire',
      (tester) async {
    when(getPays.call)
        .thenAnswer((_) async => const Right<Failure, List<Pays>>(catalogue));

    await pomperPage(
      tester,
      const RegisterPage(),
      auth: bloc(const AuthState(
        status: AuthStatus.nonAuthentifie,
        erreur: 'Cette adresse est deja utilisee.',
      )),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });
}

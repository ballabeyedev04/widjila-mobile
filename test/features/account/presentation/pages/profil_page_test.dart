import 'dart:async';

import 'package:flutter/material.dart';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/account/presentation/pages/profil_page.dart';
import 'package:suivie_chantier_mobile/features/organisation/domain/entities/organisation.dart';
import 'package:suivie_chantier_mobile/features/organisation/domain/usecases/get_mon_organisation.dart';
import 'package:suivie_chantier_mobile/features/organisation/domain/usecases/modifier_organisation.dart';
import 'package:suivie_chantier_mobile/features/organisation/presentation/cubit/mon_organisation_cubit.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/balayage_responsive.dart';
import '../../../../helpers/pompe_page.dart';

class _MockGetOrga extends Mock implements GetMonOrganisation {}

class _MockModifier extends Mock implements ModifierOrganisation {}

/// L'écran Profil.
///
/// ## Ce qu'il ne doit pas faire
///
/// L'identité de l'utilisateur vient de l'`AuthBloc`, donc de la mémoire :
/// elle est là avant même le premier octet réseau. Son ORGANISATION, elle,
/// demande un appel. Si cet appel échoue, l'écran doit continuer d'afficher
/// le nom, le rôle et l'adresse de la personne connectée : perdre le profil
/// entier parce que la fiche d'entreprise n'a pas répondu serait une panne
/// bien plus large que la vraie.
void main() {
  late _MockGetOrga getOrga;

  void desinscrire() {
    if (sl.isRegistered<MonOrganisationCubit>()) sl.unregister<MonOrganisationCubit>();
  }

  setUp(() {
    getOrga = _MockGetOrga();
    desinscrire();
    sl.registerFactory<MonOrganisationCubit>(() => MonOrganisationCubit(
          getMonOrganisation: getOrga,
          modifierOrganisationUsecase: _MockModifier(),
        ));
  });

  tearDown(desinscrire);

  testWidgets('affiche l identite connectee des le premier rendu', (tester) async {
    // L'appel d'organisation n'a pas encore répondu : le profil ne l'attend
    // pas pour montrer qui est connecté.
    final attente = Completer<Either<Failure, Organisation>>();
    when(getOrga.call).thenAnswer((_) => attente.future);

    await pomperPage(tester, const ProfilPage(), role: UserRole.conducteurTravaux);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('balla@widjila.com'), findsWidgets);
    expect(tester.takeException(), isNull);

    attente.complete(const Right(Organisation(id: 'o1', nom: 'Widjila BTP')));
    await tester.pumpAndSettle();
  });

  /// Fait defiler jusqu'a la section « Entreprise ».
  ///
  /// Le profil est une `ListView` : ce qui est hors ecran n'est pas
  /// construit, donc introuvable. Chercher la fiche d'entreprise sans
  /// defiler donnerait un test qui echoue pour une raison sans rapport avec
  /// ce qu'il verifie.
  Future<void> defilerVersEntreprise(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
  }

  testWidgets('organisation en panne : le profil reste lisible', (tester) async {
    when(getOrga.call).thenAnswer(
      (_) async =>
          const Left<Failure, Organisation>(ServerFailure(errorMessage: 'Indisponible')),
    );

    await pomperPage(tester, const ProfilPage());
    await tester.pumpAndSettle();

    // L'identite reste la, en haut, intacte.
    expect(find.textContaining('balla@widjila.com'), findsWidgets);

    // Et la section entreprise se contente de dire qu'elle est
    // indisponible : la panne est CONTENUE a la carte concernee.
    await defilerVersEntreprise(tester);
    expect(find.textContaining('Indisponible'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('organisation chargee : elle vient completer la fiche', (tester) async {
    when(getOrga.call).thenAnswer(
      (_) async => const Right<Failure, Organisation>(
        Organisation(id: 'o1', nom: 'Widjila BTP', ville: 'Dakar'),
      ),
    );

    await pomperPage(tester, const ProfilPage());
    await tester.pumpAndSettle();
    await defilerVersEntreprise(tester);

    expect(find.textContaining('Widjila BTP'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  group('mise en page — balayage des formats', () {
    // Un ecran dessine sur un telephone de 390 dp passe presque toujours a
    // 390 dp. Les debordements se produisent aux EXTREMES : sur un petit
    // Android de 320 dp encore courant sur les chantiers, et sur une tablette
    // ou une rangee concue serree se distend.
    //
    // `flutter_test` remonte un `RenderFlex overflowed` comme une exception :
    // pomper l'ecran a chaque format et verifier qu'aucune n'a ete levee
    // transforme l'audit visuel en mesure repetable.
    for (final format in tousLesFormats) {
      testWidgets('sans debordement sur $format', (tester) async {
        when(getOrga.call).thenAnswer(
          (_) async => const Right<Failure, Organisation>(
            Organisation(id: 'o1', nom: 'Widjila BTP', ville: 'Dakar'),
          ),
        );

        await pomperPage(
          tester,
          const ProfilPage(),
          // Le libelle de role le plus long : c'est lui qui debordait de la
          // pastille sur un telephone etroit.
          role: UserRole.conducteurTravaux,
          taille: format.taille,
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'debordement de mise en page sur $format');
      });
    }
  });
}

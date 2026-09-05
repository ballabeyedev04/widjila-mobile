import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/widgets/error_view.dart';
import 'package:suivie_chantier_mobile/core/widgets/loading_list.dart';
import 'package:suivie_chantier_mobile/features/notification/data/datasources/notification_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/notification/domain/entities/notification.dart';
import 'package:suivie_chantier_mobile/features/notification/domain/usecases/get_notifications.dart';
import 'package:suivie_chantier_mobile/features/notification/domain/usecases/marquer_notifications_lues.dart';
import 'package:suivie_chantier_mobile/features/notification/presentation/cubit/notifications_cubit.dart';
import 'package:suivie_chantier_mobile/features/notification/presentation/pages/notifications_page.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/balayage_responsive.dart';
import '../../../../helpers/pompe_page.dart';

class _MockGet extends Mock implements GetNotifications {}

class _MockMarquer extends Mock implements MarquerNotificationsLues {}

/// L'écran Notifications.
///
/// ## Une subtilité propre à cet écran
///
/// La page crée SON PROPRE [NotificationsCubit] (`sl<NotificationsCubit>()`),
/// distinct de celui que la coquille fournit pour la cloche. Les deux
/// coexistent donc à l'écran, et le `BlocProvider` local doit masquer celui du
/// dessus — sinon la liste afficherait l'état du compteur de la cloche, qui
/// ne contient jamais d'éléments. Monter la page est la seule façon de
/// vérifier que cette superposition tient.
void main() {
  late _MockGet getNotifications;

  NotificationItem item(String id, {DateTime? lu}) => NotificationItem(
        id: id,
        type: 'reserve_creee',
        titre: 'Nouvelle réserve $id',
        message: 'Une réserve vous a été affectée.',
        luLe: lu,
        creeLe: DateTime(2026, 6, 1),
      );

  PageNotifications page(List<NotificationItem> items) =>
      (items: items, total: items.length, nonLues: items.where((i) => i.nonLue).length);

  setUp(() {
    getNotifications = _MockGet();
    if (sl.isRegistered<NotificationsCubit>()) sl.unregister<NotificationsCubit>();
    sl.registerFactory<NotificationsCubit>(() => NotificationsCubit(
          getNotifications: getNotifications,
          marquerLues: _MockMarquer(),
        ));
  });

  tearDown(() {
    if (sl.isRegistered<NotificationsCubit>()) sl.unregister<NotificationsCubit>();
  });

  testWidgets('un squelette pendant le chargement', (tester) async {
    final attente = Completer<Either<Failure, PageNotifications>>();
    when(() => getNotifications(page: any(named: 'page'), limit: any(named: 'limit')))
        .thenAnswer((_) => attente.future);

    await pomperPage(tester, const NotificationsPage());

    expect(find.byType(LoadingList), findsOneWidget);
    expect(tester.takeException(), isNull);

    attente.complete(Right(page(const [])));
    await tester.pumpAndSettle();
  });

  testWidgets('aucune notification : un message, pas un écran blanc', (tester) async {
    when(() => getNotifications(page: any(named: 'page'), limit: any(named: 'limit')))
        .thenAnswer((_) async => Right<Failure, PageNotifications>(page(const [])));

    await pomperPage(tester, const NotificationsPage());
    await tester.pumpAndSettle();

    expect(find.text('Aucune notification'), findsOneWidget);
    // La phrase dit d'où viendront les alertes : sans elle, l'utilisateur ne
    // sait pas si l'écran est vide ou cassé.
    expect(find.textContaining('appara'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panne serveur : une erreur explicite', (tester) async {
    when(() => getNotifications(page: any(named: 'page'), limit: any(named: 'limit')))
        .thenAnswer((_) async =>
            const Left<Failure, PageNotifications>(ServerFailure(errorMessage: 'Indisponible')));

    await pomperPage(tester, const NotificationsPage());
    await tester.pumpAndSettle();

    expect(find.text('Aucune notification'), findsNothing);
    expect(find.byType(ErrorView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('affiche les notifications reçues', (tester) async {
    when(() => getNotifications(page: any(named: 'page'), limit: any(named: 'limit')))
        .thenAnswer((_) async => Right<Failure, PageNotifications>(page([item('n1'), item('n2')])));

    await pomperPage(tester, const NotificationsPage());
    await tester.pumpAndSettle();

    expect(find.text('Aucune notification'), findsNothing);
    expect(find.textContaining('Nouvelle réserve n1'), findsOneWidget);
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
        when(() => getNotifications(
              page: any(named: 'page'),
              limit: any(named: 'limit'),
            )).thenAnswer(
          (_) async => Right<Failure, PageNotifications>(page([item('n1'), item('n2')])),
        );

        await pomperPage(
          tester,
          const NotificationsPage(),
          taille: format.taille,
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'debordement de mise en page sur $format');
      });
    }
  });
}

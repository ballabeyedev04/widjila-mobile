import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/widgets/liste_chrome.dart';
import 'package:suivie_chantier_mobile/features/notification/data/datasources/notification_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/notification/domain/entities/notification.dart';
import 'package:suivie_chantier_mobile/features/notification/domain/usecases/get_notifications.dart';
import 'package:suivie_chantier_mobile/features/notification/domain/usecases/marquer_notifications_lues.dart';
import 'package:suivie_chantier_mobile/features/notification/presentation/cubit/notifications_cubit.dart';

import '../../helpers/l10n_test_helpers.dart';

class MockGetNotifications extends Mock implements GetNotifications {}

class MockMarquerLues extends Mock implements MarquerNotificationsLues {}

/// La pastille de la cloche guide l'utilisateur : elle doit refléter le
/// compteur RÉEL du serveur, et disparaître quand il n'y a rien à lire — un
/// point rouge permanent perdrait tout pouvoir d'alerte.
void main() {
  late MockGetNotifications getNotifications;
  late MockMarquerLues marquerLues;

  NotificationItem item(String id) => NotificationItem(id: id, type: 'reserve.affectee', titre: 'Réserve $id');

  Future<void> poser(WidgetTester tester, {required int nonLues, int total = 3}) async {
    getNotifications = MockGetNotifications();
    marquerLues = MockMarquerLues();

    when(() => getNotifications.call(page: any(named: 'page'), limit: any(named: 'limit')))
        .thenAnswer((_) async => Right<Failure, PageNotifications>((
              items: List.generate(total, (i) => item('$i')),
              total: total,
              nonLues: nonLues,
            )));

    final cubit = NotificationsCubit(getNotifications: getNotifications, marquerLues: marquerLues);
    await cubit.charger();

    await tester.pumpWidget(
      MaterialApp(
        locale: testLocale,
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: BlocProvider.value(
          value: cubit,
          child: const Scaffold(body: EnTeteListe(titre: 'Réserves')),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('aucune pastille quand tout est lu', (tester) async {
    await poser(tester, nonLues: 0);
    expect(find.byType(PastilleCompteur), findsNothing);
  });

  testWidgets('affiche le nombre de messages non lus', (tester) async {
    await poser(tester, nonLues: 4);
    expect(find.byType(PastilleCompteur), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('plafonne l’affichage à 99+', (tester) async {
    // Au-delà, le nombre exact n'apporte rien et ferait éclater la pastille.
    await poser(tester, nonLues: 250, total: 250);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('la cloche reste accessible au lecteur d’écran', (tester) async {
    await poser(tester, nonLues: 2);
    expect(find.byTooltip('Notifications'), findsOneWidget);
  });

  group('PastilleCompteur', () {
    testWidgets('reste lisible pour un nombre à deux chiffres', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: PastilleCompteur(nombre: 42))),
      ));

      expect(find.text('42'), findsOneWidget);
      // Le padding horizontal s'ouvre au-delà de 9 : sans lui, le texte
      // déborderait du cercle de 18 px.
      final taille = tester.getSize(find.byType(PastilleCompteur));
      expect(taille.width, greaterThan(18));
      expect(taille.height, 18);
    });

    testWidgets('reste circulaire pour un seul chiffre', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: PastilleCompteur(nombre: 7))),
      ));

      final taille = tester.getSize(find.byType(PastilleCompteur));
      expect(taille.width, 18);
      expect(taille.height, 18);
    });
  });
}

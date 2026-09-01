import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/network/dio_client_factory.dart';
import 'core/network/network_info.dart';
import 'core/offline/base_locale.dart';
import 'core/offline/cache_chantiers.dart';
import 'core/offline/cache_reserves.dart';
import 'core/offline/detecteur_connexion.dart';
import 'core/offline/executeur_actions.dart';
import 'core/offline/file_attente.dart';
import 'core/offline/session_locale.dart';
import 'core/offline/stockage_medias.dart';
import 'core/offline/synchronisation_service.dart';
import 'core/services/locale_controller.dart';
import 'core/services/ouverture_fichier.dart';
import 'core/services/preferences_notification.dart';
import 'core/services/verrou_biometrique.dart';
import 'core/services/token_service.dart';
import 'core/services/user_cache.dart';
import 'core/services/user_cache_impl.dart';

// Auth
import 'features/auth/data/datasources/auth_remote_datasource.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/domain/repositories/auth_repository.dart';
import 'features/auth/domain/usecases/forgot_password.dart';
import 'features/auth/domain/usecases/login_user.dart';
import 'features/auth/domain/usecases/logout_user.dart';
import 'features/auth/domain/usecases/register_user.dart';
import 'features/auth/domain/usecases/reset_password.dart';
import 'features/auth/domain/usecases/restaurer_session.dart';
import 'features/auth/domain/usecases/verifier_mfa.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';

// Dashboard
import 'features/dashboard/data/datasources/dashboard_remote_datasource.dart';
import 'features/dashboard/data/repositories/dashboard_repository_impl.dart';
import 'features/dashboard/domain/repositories/dashboard_repository.dart';
import 'features/dashboard/domain/usecases/get_dashboard_stats.dart';
import 'features/dashboard/presentation/cubit/dashboard_cubit.dart';

// Chantier
import 'features/chantier/data/datasources/chantier_remote_datasource.dart';
import 'features/chantier/data/repositories/chantier_repository_impl.dart';
import 'features/chantier/domain/repositories/chantier_repository.dart';
import 'features/chantier/domain/usecases/get_chantier_detail.dart';
import 'features/chantier/domain/usecases/get_chantiers.dart';
import 'features/chantier/presentation/cubit/chantier_detail_cubit.dart';
import 'features/chantier/presentation/cubit/chantiers_list_cubit.dart';
import 'features/chantier/domain/usecases/creer_chantier.dart';
import 'features/referentiel/domain/usecases/creer_code_niveau.dart';
import 'features/referentiel/domain/usecases/get_codes_niveau.dart';
import 'features/chantier/domain/usecases/creer_structure.dart';
import 'features/chantier/presentation/cubit/demandes_chantier_cubit.dart';
import 'features/chantier/presentation/cubit/creer_chantier_cubit.dart';

// Réserve
import 'features/reserve/data/datasources/reserve_remote_datasource.dart';
import 'features/reserve/data/repositories/reserve_repository_impl.dart';
import 'features/reserve/domain/repositories/reserve_repository.dart';
import 'features/reserve/domain/usecases/ajouter_media_reserve.dart';
import 'features/reserve/domain/usecases/changer_statut_reserve.dart';
import 'features/reserve/domain/usecases/creer_reserve.dart';
import 'features/reserve/domain/usecases/get_chantier_structure.dart';
import 'features/reserve/domain/usecases/get_reserve_detail.dart';
import 'features/reserve/domain/usecases/get_reserve_evolution.dart';
import 'features/reserve/domain/usecases/get_reserve_statuts_count.dart';
import 'features/reserve/domain/usecases/get_reserves.dart';
import 'features/reserve/domain/usecases/get_toutes_reserves.dart';
import 'features/reserve/presentation/cubit/chantier_dashboard_cubit.dart';
import 'features/reserve/presentation/cubit/reserve_detail_cubit.dart';
import 'features/reserve/presentation/cubit/reserve_wizard_cubit.dart';
import 'features/reserve/presentation/cubit/reserves_list_cubit.dart';
import 'features/reserve/presentation/cubit/toutes_reserves_cubit.dart';

// Notification
import 'features/notification/data/datasources/notification_remote_datasource.dart';
import 'features/notification/data/repositories/notification_repository_impl.dart';
import 'features/notification/domain/repositories/notification_repository.dart';
import 'features/notification/domain/usecases/get_notifications.dart';
import 'features/notification/domain/usecases/gerer_appareil_push.dart';
import 'features/notification/domain/usecases/marquer_notifications_lues.dart';
import 'features/notification/presentation/cubit/notifications_cubit.dart';

// Plan
import 'features/corps_etat/data/datasources/corps_etat_remote_datasource.dart';
import 'features/corps_etat/data/repositories/corps_etat_repository_impl.dart';
import 'features/corps_etat/domain/repositories/corps_etat_repository.dart';
import 'features/corps_etat/domain/usecases/get_corps_etat_actifs.dart';
import 'features/corps_etat/presentation/cubit/corps_etat_cubit.dart';
import 'features/phase/data/datasources/phase_remote_datasource.dart';
import 'features/phase/data/repositories/phase_repository_impl.dart';
import 'features/phase/domain/repositories/phase_repository.dart';
import 'features/phase/domain/usecases/get_phases_actives.dart';
import 'features/abonnement/data/datasources/abonnement_remote_datasource.dart';
import 'features/abonnement/data/repositories/abonnement_repository_impl.dart';
import 'features/abonnement/domain/repositories/abonnement_repository.dart';
import 'features/abonnement/domain/usecases/get_droits.dart';
import 'features/abonnement/domain/usecases/get_formules.dart';
import 'features/abonnement/presentation/cubit/abonnement_cubit.dart';
import 'features/referentiel/data/datasources/referentiel_remote_datasource.dart';
import 'features/referentiel/data/repositories/referentiel_repository_impl.dart';
import 'features/referentiel/domain/entities/type_referentiel.dart';
import 'features/referentiel/domain/repositories/referentiel_repository.dart';
import 'features/referentiel/domain/usecases/get_types_actifs.dart';
import 'features/referentiel/presentation/cubit/types_referentiel_cubit.dart';
import 'features/referentiel/domain/usecases/get_pays.dart';
import 'features/referentiel/presentation/cubit/pays_cubit.dart';
import 'features/plan/data/datasources/plan_remote_datasource.dart';
import 'features/plan/data/repositories/plan_repository_impl.dart';
import 'features/plan/domain/repositories/plan_repository.dart';
import 'features/plan/domain/usecases/get_plan_detail.dart';
import 'features/plan/domain/usecases/get_plans_chantier.dart';
import 'features/plan/domain/usecases/get_tous_plans.dart';
import 'features/plan/domain/usecases/uploader_plan.dart';
import 'features/plan/presentation/cubit/plan_detail_cubit.dart';
import 'features/plan/presentation/cubit/plans_list_cubit.dart';

// Organisation
import 'features/organisation/data/datasources/organisation_remote_datasource.dart';
import 'features/organisation/data/repositories/organisation_repository_impl.dart';
import 'features/organisation/domain/repositories/organisation_repository.dart';
import 'features/organisation/domain/usecases/ajouter_membre.dart';
import 'features/organisation/domain/usecases/changer_statut_partenaire.dart';
import 'features/organisation/domain/usecases/changer_statut_membre.dart';
import 'features/organisation/domain/usecases/creer_partenaire.dart';
import 'features/organisation/domain/usecases/get_mon_organisation.dart';
import 'features/organisation/domain/usecases/modifier_organisation.dart';
import 'features/organisation/presentation/cubit/mon_organisation_cubit.dart';
import 'features/organisation/domain/usecases/get_membres.dart';
import 'features/organisation/domain/usecases/get_partenaires.dart';
import 'features/organisation/presentation/cubit/membres_cubit.dart';
import 'features/organisation/presentation/cubit/partenaires_cubit.dart';

// Document
import 'features/inspection/data/datasources/inspection_remote_datasource.dart';
import 'features/inspection/data/repositories/inspection_repository_impl.dart';
import 'features/inspection/domain/repositories/inspection_repository.dart';
import 'features/inspection/domain/usecases/inspection_usecases.dart';
import 'features/rapport/data/datasources/rapport_remote_datasource.dart';
import 'features/rapport/data/repositories/rapport_repository_impl.dart';
import 'features/rapport/domain/repositories/rapport_repository.dart';
import 'features/rapport/domain/usecases/rapport_usecases.dart';
import 'features/document/data/datasources/document_remote_datasource.dart';
import 'features/document/data/repositories/document_repository_impl.dart';
import 'features/document/domain/repositories/document_repository.dart';
import 'features/document/domain/usecases/ajouter_document.dart';
import 'features/document/domain/usecases/get_documents.dart';
import 'features/document/presentation/cubit/documents_list_cubit.dart';

// Account (Paramètres)
import 'features/account/data/datasources/account_remote_datasource.dart';
import 'features/account/data/repositories/account_repository_impl.dart';
import 'features/account/domain/repositories/account_repository.dart';
import 'features/account/presentation/cubit/settings_cubit.dart';

final sl = GetIt.instance;

/// Initialise tous les services partagés (core) puis chaque feature, dans
/// l'ordre de leurs dépendances. Appelé une seule fois au démarrage
/// (`main.dart`), avant `runApp`.
Future<void> init() async {
  //================================================
  // SERVICES EXTERNES / CORE
  //================================================
  sl.registerLazySingleton(() => const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
      ));
  sl.registerLazySingleton(() => Connectivity());
  sl.registerLazySingleton<NetworkInfo>(() => NetworkInfoImpl(sl()));
  sl.registerLazySingletonAsync<SharedPreferences>(() => SharedPreferences.getInstance());
  await sl.isReady<SharedPreferences>();

  sl.registerLazySingleton(() => LocaleController(prefs: sl()));
  // Filtre local des alertes — aucune route de préférences côté back,
  // ce réglage décide de ce que CET appareil affiche.
  sl.registerLazySingleton(() => PreferencesNotification(prefs: sl()));
  sl.registerLazySingleton(() => VerrouBiometrique(prefs: sl()));
  sl.registerLazySingleton(() => TokenService(secureStorage: sl()));
  // Téléchargement + ouverture d'un fichier de l'API : passe par le Dio
  // applicatif, seul porteur du jeton exigé par /uploads/*.
  sl.registerLazySingleton(() => OuvertureFichier(dio: sl()));
  sl.registerLazySingleton<UserCache>(() => UserCacheImpl(secureStorage: sl()));

  sl.registerLazySingletonAsync<Dio>(() => DioClientFactory.create(tokenService: sl()));
  await sl.isReady<Dio>();

  //================================================
  // MODE HORS LIGNE (socle transversal — voir core/offline/)
  //================================================
  // Un seul singleton pour toute l'app : chaque feature qui a besoin de
  // fonctionner sans réseau (aujourd'hui Chantier et Réserve) partage la
  // MÊME base, le même détecteur et la même file — sinon deux instances de
  // `BaseLocale` ouvriraient chacune leur propre connexion SQLite vers le
  // même fichier, ce que `sqflite` ne garantit pas de bien gérer en écriture
  // concurrente.
  sl.registerLazySingleton(() => BaseLocale.instance);
  sl.registerLazySingleton(() => FileAttente(sl()));
  sl.registerLazySingleton(() => CacheChantiers(sl()));
  sl.registerLazySingleton(() => CacheReserves(sl()));
  sl.registerLazySingleton(() => StockageMedias());
  // Propriété des données locales — voir `SessionLocale` : garantit qu'un
  // compte ne lit ni ne synchronise jamais les données d'un autre sur le
  // même appareil, y compris après une déconnexion interrompue.
  sl.registerLazySingleton(() => SessionLocale(base: sl(), medias: sl()));
  sl.registerLazySingleton(() => DetecteurConnexion(dio: sl(), connectivity: sl()));

  // Traduit une action de la file vers le VRAI appel réseau qui la
  // concrétise. N'a besoin que du datasource réserve aujourd'hui — l'étendre
  // à d'autres domaines (plans, documents) ajoutera leurs datasources ici.
  sl.registerLazySingleton(() => ExecuteurActionsHorsLigne(
        reserves: sl(),
        cache: sl(),
        medias: sl(),
      ));

  sl.registerLazySingleton(() => SynchronisationService(
        file: sl(),
        detecteur: sl(),
        base: sl(),
        executer: (action) => sl<ExecuteurActionsHorsLigne>().executer(action),
      ));

  //================================================
  // FEATURE — AUTH
  //================================================
  sl.registerLazySingleton<AuthRemoteDataSource>(() => AuthRemoteDataSourceImpl(dio: sl()));
  sl.registerLazySingleton<AuthRepository>(() => AuthRepositoryImpl(
        remoteDataSource: sl(),
        tokenService: sl(),
        userCache: sl(),
        sessionLocale: sl(),
      ));
  sl.registerLazySingleton(() => LoginUser(sl()));
  sl.registerLazySingleton(() => VerifierMfa(sl()));
  sl.registerLazySingleton(() => RegisterUser(sl()));
  sl.registerLazySingleton(() => ForgotPassword(sl()));
  sl.registerLazySingleton(() => ResetPassword(sl()));
  sl.registerLazySingleton(() => LogoutUser(sl()));
  sl.registerLazySingleton(() => RestaurerSession(sl()));

  // Singleton (pas factory) : le AuthBloc porte l'état de session pour
  // TOUTE l'app (consommé par le routeur) — une seule instance doit exister.
  sl.registerLazySingleton(() => AuthBloc(
        loginUser: sl(),
        verifierMfa: sl(),
        logoutUser: sl(),
        restaurerSession: sl(),
        registerUser: sl(),
        forgotPassword: sl(),
        resetPassword: sl(),
        localeController: sl(),
      ));

  //================================================
  // FEATURE — DASHBOARD
  //================================================
  sl.registerLazySingleton<DashboardRemoteDataSource>(() => DashboardRemoteDataSourceImpl(dio: sl()));
  sl.registerLazySingleton<DashboardRepository>(() => DashboardRepositoryImpl(sl()));
  sl.registerLazySingleton(() => GetDashboardStats(sl()));
  sl.registerFactory(() => DashboardCubit(getDashboardStats: sl()));

  //================================================
  // FEATURE — CHANTIER
  //================================================
  sl.registerLazySingleton<ChantierRemoteDataSource>(() => ChantierRemoteDataSourceImpl(dio: sl()));
  sl.registerLazySingleton<ChantierRepository>(() => ChantierRepositoryImpl(sl(), cache: sl()));
  sl.registerLazySingleton(() => GetChantiers(sl()));
  sl.registerLazySingleton(() => GetChantierDetail(sl()));
  sl.registerFactory(() => ChantiersListCubit(getChantiers: sl(), getDashboardStats: sl()));
  sl.registerLazySingleton(() => CreerChantier(sl()));
  sl.registerLazySingleton(() => CreerBatiment(sl()));
  sl.registerLazySingleton(() => CreerEtage(sl()));
  sl.registerFactory(() => DemandesChantierCubit(getChantiers: sl()));
  // `GetMembres` appartient au module Organisation, enregistre plus bas :
  // `sl()` le resout a la CONSTRUCTION du cubit, donc apres l'initialisation.
  sl.registerFactory(() => CreerChantierCubit(creerChantier: sl(), getMembres: sl()));
  sl.registerFactoryParam<ChantierDetailCubit, String, void>(
    (chantierId, _) => ChantierDetailCubit(getChantierDetail: sl(), chantierId: chantierId),
  );

  //================================================
  // FEATURE — RÉSERVE
  //================================================
  sl.registerLazySingleton<ReserveRemoteDataSource>(() => ReserveRemoteDataSourceImpl(dio: sl()));
  sl.registerLazySingleton<ReserveRepository>(() => ReserveRepositoryImpl(
        sl(),
        detecteur: sl(),
        fileAttente: sl(),
        cache: sl(),
        medias: sl(),
      ));
  sl.registerLazySingleton(() => GetReserves(sl()));
  sl.registerLazySingleton(() => GetToutesReserves(sl()));
  sl.registerLazySingleton(() => GetReserveStatutsCount(sl()));
  sl.registerLazySingleton(() => GetReserveStatutsCountGlobal(sl()));
  sl.registerLazySingleton(() => GetReserveDetail(sl()));
  sl.registerLazySingleton(() => CreerReserve(sl()));
  sl.registerLazySingleton(() => ChangerStatutReserve(sl()));
  sl.registerLazySingleton(() => AjouterMediaReserve(sl()));
  sl.registerLazySingleton(() => GetChantierStructure(sl()));
  sl.registerLazySingleton(() => GetReserveEvolution(sl()));

  sl.registerFactory(() => ToutesReservesCubit(getToutesReserves: sl(), getStatutsCountGlobal: sl()));
  sl.registerFactoryParam<ReservesListCubit, String, void>(
    (chantierId, _) => ReservesListCubit(
      getReserves: sl(),
      getReserveStatutsCount: sl(),
      chantierId: chantierId,
    ),
  );
  sl.registerFactoryParam<ReserveDetailCubit, String, void>(
    (reserveId, _) => ReserveDetailCubit(
      getReserveDetail: sl(),
      changerStatutReserve: sl(),
      ajouterMediaReserve: sl(),
      repository: sl(),
      reserveId: reserveId,
    ),
  );
  sl.registerFactoryParam<ReserveWizardCubit, String, void>(
    (chantierId, _) => ReserveWizardCubit(
      getChantierStructure: sl(),
      creerReserve: sl(),
      getCorpsEtatActifs: sl(),
      getPhasesActives: sl(),
      chantierId: chantierId,
    ),
  );
  sl.registerFactoryParam<ChantierDashboardCubit, String, void>(
    (chantierId, _) => ChantierDashboardCubit(
      getReserveStatutsCount: sl(),
      getReserveEvolution: sl(),
      chantierId: chantierId,
    ),
  );

  //================================================
  // FEATURE — PLAN
  //================================================
  // ── Notifications ──────────────────────────────────────────────────────────
  sl.registerLazySingleton<NotificationRemoteDataSource>(() => NotificationRemoteDataSourceImpl(dio: sl()));
  sl.registerLazySingleton<NotificationRepository>(() => NotificationRepositoryImpl(sl()));
  sl.registerLazySingleton(() => GetNotifications(sl()));
  sl.registerLazySingleton(() => MarquerNotificationsLues(sl()));
  sl.registerLazySingleton(() => GererAppareilPush(sl()));
  sl.registerFactory(() => NotificationsCubit(getNotifications: sl(), marquerLues: sl()));

  sl.registerLazySingleton<PlanRemoteDataSource>(() => PlanRemoteDataSourceImpl(dio: sl()));
  sl.registerLazySingleton<PlanRepository>(() => PlanRepositoryImpl(sl()));
  sl.registerLazySingleton(() => GetTousPlans(sl()));
  sl.registerLazySingleton(() => GetPlansChantier(sl()));
  sl.registerLazySingleton(() => GetPlanDetail(sl()));
  sl.registerLazySingleton(() => UploaderPlan(sl()));
  sl.registerFactory(() => PlansListCubit(getTousPlans: sl(), getPlansChantier: sl(), uploaderPlan: sl()));
  sl.registerFactory(() => PlanDetailCubit(getPlanDetail: sl()));

  //================================================
  // FEATURE — CORPS D'ÉTAT (catalogue des métiers BTP)
  //================================================
  // Le REPOSITORY est un singleton, et c'est délibéré : c'est lui qui porte
  // le cache du catalogue (donnée de référence, relue à chaque ouverture du
  // formulaire de réserve). En faire une factory le recréerait — donc le
  // viderait — à chaque injection, et le cache ne servirait jamais.
  sl.registerLazySingleton<CorpsEtatRemoteDataSource>(() => CorpsEtatRemoteDataSourceImpl(dio: sl()));
  sl.registerLazySingleton<CorpsEtatRepository>(() => CorpsEtatRepositoryImpl(sl()));
  sl.registerLazySingleton(() => GetCorpsEtatActifs(sl()));
  sl.registerFactory(() => CorpsEtatCubit(getCorpsEtatActifs: sl()));

  //================================================
  // FEATURE — PHASES (référentiel de chantier)
  //================================================
  // Repository en SINGLETON, comme le catalogue des métiers : c'est lui qui
  // porte le cache, et la phase étant obligatoire, ce cache est ce qui permet
  // encore de créer une réserve quand le réseau tombe.
  sl.registerLazySingleton<PhaseRemoteDataSource>(() => PhaseRemoteDataSourceImpl(dio: sl()));
  sl.registerLazySingleton<PhaseRepository>(() => PhaseRepositoryImpl(sl()));
  sl.registerLazySingleton(() => GetPhasesActives(sl()));

  //================================================
  // FEATURE — ABONNEMENT (offres, droits, consommation)
  //================================================
  // Repository en SINGLETON : il garde les derniers droits reçus, ce qui
  // permet à l'interface de rester cohérente hors ligne. Ce cache n'AUTORISE
  // rien — le serveur reste seul juge, il évite seulement d'afficher un écran
  // vide sur un chantier sans réseau.
  sl.registerLazySingleton<AbonnementRemoteDataSource>(() => AbonnementRemoteDataSourceImpl(dio: sl()));
  sl.registerLazySingleton<AbonnementRepository>(() => AbonnementRepositoryImpl(sl()));
  sl.registerLazySingleton(() => GetFormules(sl()));
  sl.registerLazySingleton(() => GetDroits(sl()));
  sl.registerFactory(() => AbonnementCubit(getFormules: sl(), getDroits: sl()));

  //================================================
  // FEATURE — RÉFÉRENTIELS DE TYPE (documents, intervenants, inspections)
  //================================================
  // Repository en SINGLETON : c'est lui qui porte le cache des trois
  // catalogues. En faire une factory le recréerait — donc le viderait — à
  // chaque injection, et le cache ne servirait jamais.
  sl.registerLazySingleton<ReferentielRemoteDataSource>(
    () => ReferentielRemoteDataSourceImpl(dio: sl()),
  );
  sl.registerLazySingleton<ReferentielRepository>(() => ReferentielRepositoryImpl(sl()));
  sl.registerLazySingleton(() => GetTypesActifs(sl()));
  sl.registerLazySingleton(() => GetPays(sl()));
  sl.registerLazySingleton(() => GetCodesNiveau(sl()));
  sl.registerLazySingleton(() => CreerCodeNiveau(sl()));
  // Catalogue des pays du formulaire d'inscription — voir PaysCubit.
  sl.registerFactory(() => PaysCubit(getPays: sl()));

  // Un cubit PAR référentiel, choisi au moment de l'injection : les trois
  // listes sont indépendantes, et les réunir obligerait à charger les trois
  // pour en afficher une.
  sl.registerFactoryParam<TypesReferentielCubit, ReferentielType, void>(
    (referentiel, _) => TypesReferentielCubit(getTypesActifs: sl(), referentiel: referentiel),
  );

  //================================================
  // FEATURE — ORGANISATION (membres)
  //================================================
  sl.registerLazySingleton<OrganisationRemoteDataSource>(() => OrganisationRemoteDataSourceImpl(dio: sl()));
  sl.registerLazySingleton<OrganisationRepository>(() => OrganisationRepositoryImpl(sl()));
  sl.registerLazySingleton(() => GetMonOrganisation(sl()));
  sl.registerLazySingleton(() => ModifierOrganisation(sl()));
  sl.registerLazySingleton(() => GetMembres(sl()));
  sl.registerLazySingleton(() => ChangerStatutMembre(sl()));
  sl.registerLazySingleton(() => AjouterMembre(sl()));
  sl.registerLazySingleton(() => GetPartenaires(sl()));
  sl.registerLazySingleton(() => CreerPartenaire(sl()));
  sl.registerLazySingleton(() => ChangerStatutPartenaire(sl()));
  sl.registerFactory(() => MonOrganisationCubit(getMonOrganisation: sl(), modifierOrganisationUsecase: sl()));
  sl.registerFactory(() => MembresCubit(getMembres: sl(), ajouterMembreUsecase: sl(), changerStatutMembreUsecase: sl()));
  sl.registerFactory(() => PartenairesCubit(
        getPartenaires: sl(),
        creerPartenaireUsecase: sl(),
        changerStatutPartenaireUsecase: sl(),
      ));

  //================================================
  // FEATURE — DOCUMENT
  //================================================
  // ── Inspections ────────────────────────────────────────────────────────────
  // Les cubits ne sont PAS enregistrés ici : ils sont créés par les pages
  // via `BlocProvider`, qui les ferme au démontage. Un singleton survivrait
  // au changement de chantier et resservirait les visites du précédent.
  sl.registerLazySingleton<InspectionRemoteDataSource>(() => InspectionRemoteDataSourceImpl(dio: sl()));
  sl.registerLazySingleton<InspectionRepository>(() => InspectionRepositoryImpl(sl()));
  sl.registerLazySingleton(() => GetInspections(sl()));
  sl.registerLazySingleton(() => GetInspection(sl()));
  sl.registerLazySingleton(() => CreerInspection(sl()));
  sl.registerLazySingleton(() => ChangerStatutInspection(sl()));
  sl.registerLazySingleton(() => CocherLigneChecklist(sl()));
  sl.registerLazySingleton(() => GetConvocations(sl()));
  sl.registerLazySingleton(() => RepondreConvocation(sl()));

  // ── Rapports ───────────────────────────────────────────────────────────────
  sl.registerLazySingleton<RapportRemoteDataSource>(() => RapportRemoteDataSourceImpl(dio: sl()));
  sl.registerLazySingleton<RapportRepository>(() => RapportRepositoryImpl(sl()));
  sl.registerLazySingleton(() => GetRapports(sl()));
  sl.registerLazySingleton(() => GenererRapport(sl()));
  sl.registerLazySingleton(() => SupprimerRapport(sl()));

  sl.registerLazySingleton<DocumentRemoteDataSource>(() => DocumentRemoteDataSourceImpl(dio: sl()));
  sl.registerLazySingleton<DocumentRepository>(() => DocumentRepositoryImpl(sl()));
  sl.registerLazySingleton(() => GetDocuments(sl()));
  sl.registerLazySingleton(() => AjouterDocument(sl()));
  sl.registerFactoryParam<DocumentsListCubit, String, void>(
    (chantierId, _) => DocumentsListCubit(getDocuments: sl(), ajouterDocument: sl(), chantierId: chantierId),
  );

  //================================================
  // FEATURE — ACCOUNT (Paramètres)
  //================================================
  sl.registerLazySingleton<AccountRemoteDataSource>(() => AccountRemoteDataSourceImpl(dio: sl(), tokenService: sl()));
  sl.registerLazySingleton<AccountRepository>(() => AccountRepositoryImpl(sl()));
  sl.registerFactory(() => SettingsCubit(repository: sl()));
}

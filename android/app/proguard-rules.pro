# Règles R8/ProGuard — release (voir isMinifyEnabled/isShrinkResources dans
# app/build.gradle.kts). Couvre le moteur Flutter et les plugins natifs
# utilisés par cette app ; à compléter si un futur plugin natif provoque un
# crash "ClassNotFoundException"/"NoSuchMethodError" en release uniquement.

# Flutter — le moteur et le générateur de plugins ne doivent jamais être
# renommés/supprimés, R8 ne peut pas suivre les appels JNI/plateforme.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**

# Firebase (Messaging, Crashlytics) — sérialisation par réflexion des
# modèles internes.
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keepattributes SourceFile,LineNumberTable,*Annotation*,Signature,Exceptions,InnerClasses,EnclosingMethod

# Crashlytics a besoin des numéros de ligne pour des rapports lisibles — voir
# la remarque sur SourceFile/LineNumberTable ci-dessus.

# Play Core (déféré au build system Flutter, mais certains templates
# l'exigent explicitement pour éviter un R8 "missing_rules" sur les
# fonctionnalités de livraison différée que Flutter référence même sans
# les utiliser).
-dontwarn com.google.android.play.core.**

# Dio / okhttp (dépendance transitive) — classes internes accédées par
# réflexion pour la négociation de protocole.
-dontwarn okhttp3.**
-dontwarn okio.**

# sqflite — accès JNI aux méthodes natives SQLite.
-keep class io.flutter.plugins.sqflite.** { *; }

# flutter_local_notifications — les receivers/services déclarés dans le
# manifest ne doivent pas être renommés.
-keep class com.dexterous.** { *; }

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Aligne le compileSdk de TOUS les plugins Android sur celui de l'app.
//
// Pourquoi : chaque plugin Flutter fige son propre compileSdk au moment de sa
// publication. `flutter_plugin_android_lifecycle` exige desormais 36, tandis
// que `file_picker` 8.1.7 compile encore contre 34 : `checkReleaseAarMetadata`
// compare les deux et casse le build release. Attendre que chaque auteur
// publie une mise a jour n'est pas tenable, et remonter `file_picker` d'une
// version majeure changerait son API pour l'import de plan.
//
// Relever le compileSdk d'une bibliotheque ne change NI son minSdk (les
// appareils supportes) NI son targetSdk (le comportement d'execution) : cela
// ne fait qu'autoriser la compilation contre des API plus recentes.
val compileSdkMinimal = 36

subprojects {
    val projet = this

    val alignerCompileSdk = {
        val android = projet.extensions.findByType(com.android.build.api.dsl.CommonExtension::class.java)
        val actuel = android?.compileSdk
        if (android != null && actuel != null && actuel < compileSdkMinimal) {
            android.compileSdk = compileSdkMinimal
        }
    }

    // Le bloc `evaluationDependsOn(":app")` ci-dessus force l'evaluation de
    // certains projets AVANT que cette boucle ne les atteigne : leur poser un
    // `afterEvaluate` leverait alors « Cannot run Project.afterEvaluate(Action)
    // when the project is already evaluated ». D'ou les deux chemins.
    if (projet.state.executed) alignerCompileSdk() else projet.afterEvaluate { alignerCompileSdk() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

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
subprojects {
    // v1.4.0: some plugin libraries (onnxruntime) are compiled against
    // android-33 while their own AndroidX dependencies require
    // compileSdk 34 or later, so their checkDebugAarMetadata task fails
    // the whole build. Raise every library subproject that sits below
    // the app's compileSdk (37) up to 37. Compile-time only: targetSdk,
    // minSdk and runtime behavior are untouched.
    project.afterEvaluate {
        val libraryExtension =
            project.extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
        if (libraryExtension != null && (libraryExtension.compileSdk ?: 0) < 37) {
            libraryExtension.compileSdk = 37
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

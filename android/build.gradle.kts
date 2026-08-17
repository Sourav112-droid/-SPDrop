allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("$rootDir/local_repo") }
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
    afterEvaluate {
        project.extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.let { ext ->
            ext.compileSdk = 36
            if (ext.namespace == null) {
                ext.namespace = project.group.toString()
            }
            if (project.name == "nsd_android") {
                ext.namespace = "com.haberey.flutter.nsd_android"
            }
            if (project.name == "irondash_engine_context") {
                ext.namespace = "dev.irondash.engine_context"
            }
            if (project.name == "irondash_message_channel") {
                ext.namespace = "dev.irondash.message_channel"
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    if (project.name == "receive_sharing_intent") {
        project.tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
        }
    }
}

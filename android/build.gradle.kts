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
    if (project.path != ":app") {
        project.evaluationDependsOn(":app")
    }
}

subprojects {
    val projectNamespaceFix = Action<Project> {
        if (plugins.hasPlugin("com.android.application") || plugins.hasPlugin("com.android.library")) {
            val android = extensions.findByName("android")
            if (android != null) {
                try {
                    val getNamespace = android.javaClass.getMethod("getNamespace")
                    if (getNamespace.invoke(android) == null) {
                        val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                        val ns = when (project.name) {
                            "geolocator_android" -> "com.baseflow.geolocator"
                            "permission_handler_android" -> "com.baseflow.permissionhandler"
                            else -> "com.legacy.${project.name.replace("-", "_")}"
                        }
                        setNamespace.invoke(android, ns)
                    }
                } catch (e: Exception) {
                    // Ignore errors during reflection
                }
            }
        }
    }

    if (state.executed) {
        projectNamespaceFix.execute(this)
    } else {
        afterEvaluate { projectNamespaceFix.execute(this) }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

import java.io.File
import java.util.Properties

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
    if (name != "app") {
        afterEvaluate {
            val androidExt = extensions.findByName("android")
            if (androidExt != null) {
                val propsFile = rootProject.file("local.properties")
                val props = Properties()
                if (propsFile.exists()) {
                    propsFile.inputStream().use { props.load(it) }
                }
                val sdkPath = System.getenv("ANDROID_HOME")
                    ?: System.getenv("ANDROID_SDK_ROOT")
                    ?: props.getProperty("sdk.dir")
                val installedNdks = sdkPath
                    ?.let {
                        File(it, "ndk")
                            .listFiles()
                            ?.filter { d -> d.isDirectory && File(d, "source.properties").exists() }
                            ?.map { d -> d.name }
                            ?.sorted()
                    }
                    .orEmpty()
                if (installedNdks.isNotEmpty()) {
                    val getNdk = androidExt.javaClass.methods.firstOrNull {
                        it.name == "getNdkVersion" && it.parameterCount == 0
                    }
                    val setNdk = androidExt.javaClass.methods.firstOrNull {
                        it.name == "setNdkVersion" && it.parameterCount == 1
                    }
                    val currentNdk = getNdk?.invoke(androidExt) as? String
                    if (currentNdk == null || !installedNdks.contains(currentNdk)) {
                        setNdk?.invoke(androidExt, installedNdks.last())
                    }
                }
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

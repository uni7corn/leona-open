pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
        // Mirrors last: use them as fallback only when primary upstreams are unavailable.
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/public")
        maven("https://maven.aliyun.com/repository/gradle-plugin")
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/public")
    }
}

rootProject.name = "leona-sdk-android"

include(":sdk")
include(":sample-app")

val privateSdkCoreDir = file("private/sdk-private-core")
val includePrivateSdkCore =
    providers.gradleProperty("LEONA_INCLUDE_PRIVATE_CORE")
        .orElse(providers.environmentVariable("LEONA_INCLUDE_PRIVATE_CORE"))
        .orElse("false")
        .get()
        .lowercase()
        .let { value -> value == "true" || value == "1" || value == "yes" }

if (includePrivateSdkCore && privateSdkCoreDir.isDirectory) {
    include(":sdk-private-core")
    project(":sdk-private-core").projectDir = privateSdkCoreDir
}

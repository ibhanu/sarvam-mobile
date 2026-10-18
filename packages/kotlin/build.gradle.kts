plugins {
    id("com.android.library") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("org.jetbrains.kotlin.jvm") version "2.0.21" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.0.21" apply false
    id("org.jetbrains.dokka") version "1.9.20" apply false
    id("org.jetbrains.kotlinx.binary-compatibility-validator") version "0.16.3" apply false
    `maven-publish`
    signing
}

allprojects {
    group = (findProperty("GROUP") as? String) ?: "io.github.ibhanu"
    version = (findProperty("VERSION_NAME") as? String) ?: "0.1.0"
}

subprojects {
    plugins.withType<MavenPublishPlugin> {
        apply(plugin = "signing")

        val signingKey = System.getenv("SIGNING_KEY") ?: project.findProperty("signing.key") as? String
        val signingPassword = System.getenv("SIGNING_PASSWORD") ?: project.findProperty("signing.password") as? String

        if (!signingKey.isNullOrBlank()) {
            configure<SigningExtension> {
                useInMemoryPgpKeys(signingKey, signingPassword ?: "")
                sign(extensions.getByType<PublishingExtension>().publications)
            }
        }

        configure<PublishingExtension> {
            repositories {
                maven {
                    name = "staging"
                    url = uri(rootProject.layout.buildDirectory.dir("staging-repo"))
                }
                maven {
                    name = "GitHubPackages"
                    url = uri("https://maven.pkg.github.com/ibhanu/sarvam-mobile")
                    credentials {
                        username = System.getenv("GITHUB_ACTOR") ?: project.findProperty("gpr.user") as? String
                        password = System.getenv("GITHUB_TOKEN") ?: project.findProperty("gpr.key") as? String
                    }
                }
            }
        }
    }

    tasks.withType<Test> {
        testLogging {
            events("passed", "skipped", "failed", "standardError")
            showExceptions = true
            showCauses = true
            showStackTraces = true
            exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
        }
    }
}

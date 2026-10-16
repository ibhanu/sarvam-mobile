plugins {
    id("org.jetbrains.kotlin.jvm")
    id("org.jetbrains.kotlin.plugin.serialization")
    `maven-publish`
    id("jacoco")
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(21))
    }
    withSourcesJar()
    withJavadocJar()
}

publishing {
    publications {
        create<MavenPublication>("mavenJava") {
            from(components["java"])
            groupId = project.group.toString()
            artifactId = "sarvam-core"
            version = project.version.toString()

            pom {
                name.set("sarvam-core")
                description.set("Official Kotlin/Android Core SDK for Sarvam AI Indic language models and speech services")
                url.set("https://github.com/ibhanu/sarvam-mobile")
                inceptionYear.set("2026")
                licenses {
                    license {
                        name.set("MIT License")
                        url.set("https://opensource.org/licenses/MIT")
                        distribution.set("repo")
                    }
                }
                developers {
                    developer {
                        id.set("sarvam")
                        name.set("Sarvam AI")
                        email.set("dev@sarvam.ai")
                    }
                }
                scm {
                    connection.set("scm:git:git://github.com/ibhanu/sarvam-mobile.git")
                    developerConnection.set("scm:git:ssh://github.com:ibhanu/sarvam-mobile.git")
                    url.set("https://github.com/ibhanu/sarvam-mobile")
                }
            }
        }
    }
}

kotlin {
    jvmToolchain(21)
    compilerOptions {
        freeCompilerArgs.addAll(
            "-opt-in=kotlin.RequiresOptIn",
            "-opt-in=kotlinx.coroutines.ExperimentalCoroutinesApi"
        )
    }
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:okhttp-sse:4.12.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
}

tasks.test {
    useJUnit()
    finalizedBy(tasks.jacocoTestReport)
}

tasks.jacocoTestReport {
    dependsOn(tasks.test)
    reports {
        xml.required.set(true)
        csv.required.set(true)
        html.required.set(true)
    }
    classDirectories.setFrom(
        files(classDirectories.files.map {
            fileTree(it) {
                exclude(
                    "ai/sarvam/generated/**",
                    "**/*\$serializer*",
                    "**/*\$Companion*",
                    "**/AndroidAudioCaptureDriver*",
                    "**/AndroidAudioPlaybackDriver*",
                    "**/AndroidAudioRecordCaptureDriver*",
                    "**/AndroidAudioTrackPlaybackDriver*"
                )
            }
        })
    )
}

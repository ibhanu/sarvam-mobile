plugins {
    id("com.android.library") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("org.jetbrains.kotlin.jvm") version "2.0.21" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.0.21" apply false
    id("org.jetbrains.dokka") version "1.9.20" apply false
    id("org.jetbrains.kotlinx.binary-compatibility-validator") version "0.16.3" apply false
    `maven-publish`
}

allprojects {
    group = (findProperty("GROUP") as? String) ?: "ai.sarvam"
    version = (findProperty("VERSION_NAME") as? String) ?: "0.1.0"
}

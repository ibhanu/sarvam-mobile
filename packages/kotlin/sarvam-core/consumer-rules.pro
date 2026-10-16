# ==============================================================================
# Sarvam AI Mobile SDK - R8 / ProGuard Consumer Rules
# ==============================================================================

# Keep all public API classes, methods, and fields in ai.sarvam.**
-keep public class ai.sarvam.** {
    public protected *;
}

# Preserve generic type signatures and metadata for reflection & serialization
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keepattributes *Annotation*

# Kotlinx Serialization rules
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.SerializationKt

-keepclassmembers class * {
    *** Companion;
}

-keepclasseswithmembers class * {
    kotlinx.serialization.KSerializer serializer(...);
}

-keepclassmembers class **$$serializer {
    *;
}

# Don't warn on missing optional annotations
-dontwarn ai.sarvam.**

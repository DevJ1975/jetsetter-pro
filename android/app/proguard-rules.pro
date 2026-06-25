# JetSetter Pro — ProGuard / R8 rules.
# Minification is disabled in this scaffold; these rules are here for when it is enabled.

# Keep data models (serialized via Moshi reflection).
-keep class com.jetsetter.pro.core.model.** { *; }
-keep class com.jetsetter.pro.core.data.remote.dto.** { *; }

# Retrofit / OkHttp / Moshi
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn retrofit2.**
-keepattributes Signature, *Annotation*, EnclosingMethod

# Kotlin metadata for Moshi reflective adapter
-keep class kotlin.Metadata { *; }

# flutter_local_notifications serialises scheduled notifications with Gson.
-keep class com.dexterous.** { *; }
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }

# Gson generic signatures
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn com.google.errorprone.annotations.**

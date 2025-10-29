# ==============================================================================
# FLUTTER & DART CORE
# ==============================================================================

# Flutter Wrapper - Essential for Flutter runtime
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Dart VM - Keep native methods for Flutter engine
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.embedding.engine.** { *; }

# Google Play Core (required for Flutter deferred components, even if not used)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }
-keep class com.google.android.play.core.splitcompat.** { *; }
-keep class com.google.android.play.core.splitinstall.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }

# Keep native methods (required for JNI calls from Dart)
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep methods with @Keep annotation
-keep @androidx.annotation.Keep class * { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

# ==============================================================================
# GSON / JSON SERIALIZATION
# ==============================================================================

# Gson - Keep serialization signatures
-keepattributes Signature
-keepattributes *Annotation*
-keep class sun.misc.Unsafe { *; }
-keep class com.google.gson.** { *; }

# Prevent obfuscation of models with @SerializedName
-keepclassmembers class ** {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Keep model classes used for JSON deserialization
# Add your specific model package here if needed:
# -keep class com.example.my_app_gps.data.models.** { *; }

# ==============================================================================
# OBJECTBOX DATABASE
# ==============================================================================

# ObjectBox - Keep entity classes and annotations
-keep class io.objectbox.** { *; }
-keep @io.objectbox.annotation.Entity class * { *; }
-keep @io.objectbox.annotation.Id class * { *; }
-keep class * extends io.objectbox.Box { *; }

# ObjectBox native library
-keep class io.objectbox.BoxStore { *; }
-keep class io.objectbox.Cursor { *; }
-keep class io.objectbox.Transaction { *; }

# ==============================================================================
# FLUTTER PLUGINS
# ==============================================================================

# Geolocator - Location services
-keep class com.baseflow.geolocator.** { *; }
-keepclassmembers class com.baseflow.geolocator.** { *; }

# Firebase - Cloud messaging and analytics
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Flutter Local Notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class androidx.core.app.NotificationCompat** { *; }

# Permission Handler
-keep class com.baseflow.permissionhandler.** { *; }

# Shared Preferences
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Path Provider
-keep class io.flutter.plugins.pathprovider.** { *; }

# URL Launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# Package Info
-keep class io.flutter.plugins.packageinfo.** { *; }

# Share Plus
-keep class dev.fluttercommunity.plus.share.** { *; }

# Connectivity Plus
-keep class dev.fluttercommunity.plus.connectivity.** { *; }

# Battery Plus
-keep class dev.fluttercommunity.plus.battery.** { *; }

# Sensors Plus
-keep class dev.fluttercommunity.plus.sensors.** { *; }

# Workmanager
-keep class be.tramckrijte.workmanager.** { *; }

# Flutter Map (if using custom markers/renderers)
-keep class com.mapbox.mapboxsdk.** { *; }
-dontwarn com.mapbox.mapboxsdk.**

# ==============================================================================
# KOTLIN & COROUTINES
# ==============================================================================

# Kotlin metadata for reflection
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-keepclassmembers class kotlin.Metadata {
    public <methods>;
}

# Kotlin coroutines
-keepclassmembernames class kotlinx.** { *; }
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}

# ==============================================================================
# ANDROID COMPONENTS
# ==============================================================================

# Keep custom views and attributes
-keepclasseswithmembers class * {
    public <init>(android.content.Context, android.util.AttributeSet);
}
-keepclasseswithmembers class * {
    public <init>(android.content.Context, android.util.AttributeSet, int);
}

# Keep activity lifecycle methods
-keepclassmembers class * extends android.app.Activity {
    public void *(android.view.View);
}

# Keep enums
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep parcelables
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Keep serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# ==============================================================================
# R8 OPTIMIZATION FLAGS
# ==============================================================================

# Enable aggressive optimization (R8 handles these better than ProGuard)
-optimizationpasses 5
-dontusemixedcaseclassnames
-dontskipnonpubliclibraryclasses
-dontskipnonpubliclibraryclassmembers
-verbose

# Allow R8 to optimize method calls
-allowaccessmodification

# Enable class merging for smaller APK
-mergeinterfacesaggressively

# Remove logging in release builds (important for performance!)
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
    public static *** w(...);
    public static *** e(...);
}

# Remove debug prints from Dart/Flutter
-assumenosideeffects class io.flutter.Log {
    public static *** v(...);
    public static *** d(...);
    public static *** i(...);
    public static *** w(...);
    public static *** e(...);
}

# Remove System.out.println calls
-assumenosideeffects class java.io.PrintStream {
    public void println(%);
    public void println(**);
}

# ==============================================================================
# WARNINGS SUPPRESSION (Only for known safe warnings)
# ==============================================================================

# Suppress warnings for optional dependencies
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
-dontwarn javax.annotation.**
-dontwarn org.codehaus.mojo.animal_sniffer.IgnoreJRERequirement

# ==============================================================================
# ATTRIBUTES TO KEEP (for debugging and reflection)
# ==============================================================================

# Keep line numbers for better crash reports
-keepattributes SourceFile,LineNumberTable

# Keep annotations for runtime reflection
-keepattributes *Annotation*

# Keep generic signatures for reflection
-keepattributes Signature

# Keep exceptions for crash reporting
-keepattributes Exceptions

# Keep inner classes
-keepattributes InnerClasses

# Keep encryption attributes
-keepattributes EnclosingMethod

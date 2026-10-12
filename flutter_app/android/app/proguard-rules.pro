# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# MapLibre Native & annotations
-keep class org.maplibre.** { *; }
-keep class com.mapbox.** { *; }
-dontwarn org.maplibre.**
-dontwarn com.mapbox.**

# flutter_background_service & geolocator
-keep class id.flutter.flutter_background_service.** { *; }
-keep class com.baseflow.geolocator.** { *; }

# OkHttp / Networking
-dontwarn okhttp3.**
-dontwarn okio.**

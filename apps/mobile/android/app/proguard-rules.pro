# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# ML Kit Text Recognition
# google_mlkit_text_recognition references language-specific recognizers
# (Chinese, Devanagari, Japanese, Korean) that are not bundled when we only
# use the Latin script. R8 emits warnings/errors for those references; the
# rules below tell R8 to ignore them.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Google Play Core (deferred components / split install)
# Flutter's embedding references Play Core classes for deferred component
# installation, but the app does not use them. R8 needs explicit dontwarn
# rules so the missing classes do not fail the release build.
-dontwarn com.google.android.play.core.**

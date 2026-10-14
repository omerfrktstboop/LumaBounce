# LumaReviewPlugin Android bridge

This small Android library exposes Google Play In-App Review to Godot 4.7.2.
Its source is kept here because the packaged AARs under
`addons/LumaReviewPlugin/bin/` cannot be reviewed or rebuilt on their own.

Build both variants from the repository root:

```powershell
$env:JAVA_HOME = 'D:\DevTools\jdk17\jdk-17.0.20.1+1'
$env:ANDROID_HOME = 'D:\DevTools\android-sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:GRADLE_USER_HOME = 'D:\DevTools\gradle-home'
.\android\build\gradlew.bat -p .\tools\android_review_plugin --no-daemon installPluginAars
```

The Gradle task copies debug and release AARs into the enabled Godot editor
plugin. The Godot export script supplies `com.google.android.play:review:2.0.2`
to the application build.

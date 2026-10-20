-dontwarn com.gemalto.jp2.**
-dontwarn com.tom_roush.pdfbox.filter.JPXFilter

# Flutter embedding and plugins are reached through reflection/JNI.
-keep class io.flutter.** { *; }
-keep class com.psyche.kelivo.** { *; }
-keep class com.yalantis.ucrop.** { *; }
-keepattributes Signature,*Annotation*,EnclosingMethod
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**

# Flutter references Play Core for deferred components, which this app does not
# ship. The classes are absent, so R8 must not fail on the optional references.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# =====================================================================
# Flutter Overlay Window rules
# =====================================================================
-keep class flutter.overlay.window.flutter_overlay_window.** { *; }

# =====================================================================
# Keep App's Native Code (Hi Car Application Package)
# Nơi lưu giữ toàn bộ các lớp cấu trúc Native để tránh lỗi Release
# =====================================================================
-keep class com.hicar.ora.limited.** { *; }
-keep class com.hicar.ora.limited.MainActivity { *; }
-keep class com.hicar.ora.limited.MainActivity$Companion { *; }

# 🟢 ĐÃ BỔ SUNG: Giữ lại lớp BootReceiver để Android không bị mất tính năng tự khởi động khi bật xe/thiết bị
-keep class com.hicar.ora.limited.BootReceiver { *; }

# =====================================================================
# Keep Flutter Entry Points (@pragma('vm:entry-point'))
# Cách viết chuẩn để bảo vệ overlayMain và onStartService ở bản Release
# =====================================================================
-keepattributes *Annotation*

-keepclassmembers class * {
    @vm.entry-point *;
}

-keep class * {
    @androidx.annotation.Keep <fields>;
    @androidx.annotation.Keep <methods>;
}

# =====================================================================
# General Flutter keep rules
# =====================================================================
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# =====================================================================
# Flutter Background Service rules (Nếu bạn có dùng cho Foreground)
# =====================================================================
-keep class id.flutter.flutter_background_service.** { *; }

# =====================================================================
# AndroidX Media (MediaBrowserServiceCompat / Android Auto)
# Giữ để chế độ Android Auto bind được service ở bản Release (R8).
# =====================================================================
-keep class androidx.media.** { *; }
-keep class android.support.v4.media.** { *; }
-dontwarn androidx.media.**

# =====================================================================
# Giữ các Service/Receiver native khai báo trong Manifest (R8 an toàn)
# =====================================================================
-keep public class * extends android.app.Service { *; }
-keep public class * extends android.content.BroadcastReceiver { *; }

# Giữ enum (một số plugin dùng valueOf/values qua phản chiếu)
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# =====================================================================
# Flutter deferred components / Play Core (optional — app không dùng split APK)
# R8 báo "Missing class" nếu không có -dontwarn khi bật minifyEnabled.
# =====================================================================
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
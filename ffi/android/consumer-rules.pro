# Consumer ProGuard rules applied to apps that depend on this AAR.
# JNA needs to keep all its native callback classes.
-dontwarn java.awt.**
-keep class com.sun.jna.** { *; }
-keep class * implements com.sun.jna.** { *; }

# uniffi-generated wrapper classes are reflected against from native code.
-keep class uniffi.ant_ffi.** { *; }

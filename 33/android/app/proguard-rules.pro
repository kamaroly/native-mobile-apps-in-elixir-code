# R8 rules for the release build (minifyEnabled). Libraries (Compose, ML
# Kit, Firebase, CameraX, Coil…) ship their own consumer rules; these cover
# what R8 can't see from the Kotlin code.

# The BEAM calls into the bridge through JNI (FindClass
# "com/example/risiti_app/MobBridge" and method lookups by name), and the
# plugins' bridges are registered and called the same way. Keep them whole,
# with their names.
-keep class com.example.risiti_app.** { *; }
-keep class io.mob.** { *; }

# Native methods are bound by their mangled names (Java_com_example_...).
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# Stack traces in crash reports keep file and line numbers.
-keepattributes SourceFile,LineNumberTable,*Annotation*,Signature,InnerClasses,EnclosingMethod

# kotlinx.serialization ships its own R8 rules; nothing app-specific needed.
# Keep line numbers for readable crash stack traces.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Tesseract / Leptonica are called from native code (JNI).
-keep class com.googlecode.tesseract.android.** { *; }
-keep class com.googlecode.leptonica.android.** { *; }

# The Anthropic SDK reads and writes its models with Jackson (reflection).
-keep class com.anthropic.** { *; }
-keep class com.fasterxml.jackson.** { *; }
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-dontwarn com.fasterxml.jackson.**
-dontwarn org.slf4j.**
-dontwarn java.beans.**

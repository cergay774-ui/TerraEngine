# Project files are kotlinx.serialization models; keep their generated serializers.
-keepattributes *Annotation*, InnerClasses
-keepclassmembers class com.flurocup.** {
    *** Companion;
}
-keepclasseswithmembers class com.flurocup.** {
    kotlinx.serialization.KSerializer serializer(...);
}

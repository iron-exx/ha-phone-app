# PJSUA2 (SWIG): native code calls SwigDirector_* callbacks and Java classes by name.
-keep class org.pjsip.** { *; }
-keepclassmembers class * { native <methods>; }
# gomobile / libtailscale (also shipped as consumer rules in the AAR, kept explicit).
-keep class go.** { *; }
-keep class libtailscale.** { *; }
# Our implementations of libtailscale / PJSUA2 interfaces are called from native code.
-keep class de.haphone.app.test.tailscale.** { *; }
-keep class de.haphone.app.test.sip.** { *; }

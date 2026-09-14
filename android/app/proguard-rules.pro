# Razorpay's checkout runs in a WebView and calls back into Java through
# @JavascriptInterface, so R8 must not rename or strip any of it. Without these
# rules a minified release build opens the checkout and then silently never
# reports success or failure.
-keepattributes JavascriptInterface
-keepattributes *Annotation*
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keep class com.razorpay.** { *; }
-dontwarn com.razorpay.**
-optimizations !method/inlining/*
-keepclasseswithmembers class * {
    public void onPayment*(...);
}

# flutter_webrtc / libwebrtc
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

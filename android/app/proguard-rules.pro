# Razorpay Checkout (https://razorpay.com/docs/payments/payment-gateway/android-integration/standard/)
# Checkout runs in a WebView with a JavaScript bridge; R8 must not strip or rename it.
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keepattributes JavascriptInterface
-keepattributes *Annotation*
-dontwarn com.razorpay.**
-keep class com.razorpay.** { *; }
-optimizations !method/inlining/*
-keepclasseswithmembers class * {
    public void onPayment*(...);
}

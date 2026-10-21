/*
 * bypass_ssl_pinning.js —— Android SSL Pinning 旁路 (frida -U -f <pkg> -l bypass_ssl_pinning.js --no-pause)
 * 覆盖: TrustManagerImpl / OkHttp3 / Retrofit / Conscrypt / WebView / HostnameVerifier / NetworkSecurityConfig
 * 与 eMudhra MITM 配合: mitm 出示的链已被系统根信任，若 app 另有 pinning 再用本脚本卸掉。
 */
Java.perform(function () {
    var log = function (m) { console.log("[ssl-bypass] " + m); };

    // ---- 1. 通用 TrustManager/SSLSocket ----
    try {
        var X509TrustManager = Java.use('javax.net.ssl.X509TrustManager');
        var SSLContext = Java.use('javax.net.ssl.SSLContext');
        var TrustManager = Java.registerClass({
            name: 'com.redteam.TrustAll',
            implements: [X509TrustManager],
            methods: {
                checkClientTrusted: function () {},
                checkServerTrusted: function () {},
                getAcceptedIssuers: function () { return []; }
            }
        });
        var tm = [TrustManager.$new()];
        var ctx = SSLContext.getInstance("TLS");
        ctx.init(null, tm, null);
        SSLContext.getInstance.overload('java.lang.String').implementation = function (a) {
            var c = this.getInstance(a);
            try { c.init(null, tm, null); } catch (e) {}
            return c;
        };
        log("SSLContext/X509TrustManager hook 完成");
    } catch (e) { log("通用 TrustManager: " + e); }

    // ---- 2. TrustManagerImpl.checkTrustedRecursive (Conscrypt) ----
    try {
        var TMI = Java.use('com.android.org.conscrypt.TrustManagerImpl');
        TMI.checkTrustedRecursive.implementation = function () { return Java.use('java.util.ArrayList').$new(); };
        log("Conscrypt TrustManagerImpl hook 完成");
    } catch (e) { log("Conscrypt: " + e); }

    // ---- 3. OkHttp3 CertificatePinner ----
    try {
        var Pinner = Java.use('okhttp3.CertificatePinner');
        Pinner.check.overload('java.lang.String', 'java.util.List').implementation = function () { log("OkHttp3 check(String,List) 放行"); };
        Pinner.check.overload('java.lang.String', '[Ljava.security.cert.Certificate;').implementation = function () { log("OkHttp3 check(String,Cert[]) 放行"); };
    } catch (e) { log("OkHttp3: " + e); }

    // ---- 4. HostnameVerifier ----
    try {
        var HV = Java.use('javax.net.ssl.HostnameVerifier');
        var HVC = Java.registerClass({
            name: 'com.redteam.AllHosts',
            implements: [HV],
            methods: { verify: function () { return true; } }
        });
        var HVCtor = Java.use('javax.net.ssl.HttpsURLConnection');
        HVCtor.setDefaultHostnameVerifier(HVC.$new());
        log("HostnameVerifier hook 完成");
    } catch (e) { log("HostnameVerifier: " + e); }

    // ---- 5. WebView SSL error ----
    try {
        var WVC = Java.use('android.webkit.WebViewClient');
        WVC.onReceivedSslError.implementation = function (v, h, e) { h.proceed(); return; };
        log("WebViewClient SSL hook 完成");
    } catch (e) { log("WebView: " + e); }

    // ---- 6. 常见第三方库 pinning 兜底 ----
    try {
        var AppA = Java.use('com.datatheorem.android.trustkit.pinning.OkHostnameVerifier');
        AppA.verify.overload('java.lang.String', 'javax.net.ssl.SSLSession').implementation = function () { return true; };
    } catch (e) {}
    try {
        var NHV = Java.use('com.squareup.okhttp.internal.tls.OkHostnameVerifier');
        NHV.verify.overload('java.lang.String', 'javax.net.ssl.SSLSession').implementation = function () { return true; };
    } catch (e) {}
    try {  // Appmattus / 其他
        var CW = Java.use('com.android.org.conscrypt.Platform');
        CW.checkServerTrusted.overload('java.security.cert.X509Certificate', 'java.lang.String', 'com.android.org.conscrypt.ConscryptEngineSocket', 'byte[][]').implementation = function () {};
    } catch (e) {}

    log("=== 全部 hook 安装完成, 现在可用 eMudhra MITM 观测流量 ===");
});
package ru.yasny.english;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.speech.tts.TextToSpeech;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.Locale;
import org.json.JSONArray;
import org.json.JSONObject;

public class MainActivity extends Activity {
    private static final String HOST = "app.yasny.local";
    private static final int REQ_MIC = 1, REQ_NOTIFY = 2;
    private WebView web;
    private TextToSpeech tts;
    private volatile boolean ttsReady = false;
    private SpeechRecognizer recognizer;
    private String pendingLang = "en-US";

    /** Мост для JavaScript: озвучка, распознавание речи, напоминания. */
    public class Bridge {
        @JavascriptInterface public boolean ready() { return ttsReady; }
        @JavascriptInterface public void speak(String text, float rate, String lang) {
            if (!ttsReady || text == null) return;
            tts.setLanguage("en-GB".equals(lang) ? Locale.UK : Locale.US);
            tts.setSpeechRate(Math.max(0.3f, Math.min(2f, rate)));
            tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "yasny");
        }
        @JavascriptInterface public void stop() { if (tts != null) tts.stop(); }
        @JavascriptInterface public boolean hasSpeech() { return SpeechRecognizer.isRecognitionAvailable(MainActivity.this); }
        @JavascriptInterface public void startListening(final String lang) {
            runOnUiThread(new Runnable() { public void run() { startListen(lang == null ? "en-US" : lang); } });
        }
        @JavascriptInterface public void stopListening() {
            runOnUiThread(new Runnable() { public void run() { if (recognizer != null) recognizer.stopListening(); } });
        }
        @JavascriptInterface public void shareToGemini(final String text) {
            runOnUiThread(new Runnable() { public void run() { openGemini(text); } });
        }
        @JavascriptInterface public void setReminder(final int h, final int m, final boolean on) {
            runOnUiThread(new Runnable() { public void run() { applyReminder(h, m, on); } });
        }
    }

    private void send(JSONObject o) {
        final String js = "window.__nativeSpeech&&window.__nativeSpeech(" + o.toString() + ")";
        web.post(new Runnable() { public void run() { web.evaluateJavascript(js, null); } });
    }

    private void sendType(String type, String key, String val) {
        try { JSONObject o = new JSONObject(); o.put("type", type); if (key != null) o.put(key, val); send(o); } catch (Exception ignored) {}
    }

    private void startListen(String lang) {
        if (Build.VERSION.SDK_INT >= 23 && checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            pendingLang = lang;
            requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, REQ_MIC);
            return;
        }
        if (!SpeechRecognizer.isRecognitionAvailable(this)) { sendType("error", "error", "unavailable"); return; }
        if (tts != null) tts.stop();
        if (recognizer == null) {
            recognizer = SpeechRecognizer.createSpeechRecognizer(this);
            recognizer.setRecognitionListener(new RecognitionListener() {
                public void onReadyForSpeech(Bundle b) { sendType("start", null, null); }
                public void onBeginningOfSpeech() {}
                public void onRmsChanged(float v) {}
                public void onBufferReceived(byte[] b) {}
                public void onEndOfSpeech() {}
                public void onEvent(int t, Bundle b) {}
                public void onError(int code) {
                    String e = code == SpeechRecognizer.ERROR_NO_MATCH || code == SpeechRecognizer.ERROR_SPEECH_TIMEOUT ? "nomatch"
                             : code == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ? "permission"
                             : code == SpeechRecognizer.ERROR_NETWORK || code == SpeechRecognizer.ERROR_NETWORK_TIMEOUT ? "network" : "other";
                    sendType("error", "error", e);
                }
                public void onPartialResults(Bundle b) {
                    ArrayList<String> r = b.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
                    if (r != null && !r.isEmpty()) sendType("partial", "text", r.get(0));
                }
                public void onResults(Bundle b) {
                    ArrayList<String> r = b.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
                    try {
                        JSONObject o = new JSONObject();
                        o.put("type", "final");
                        o.put("text", r != null && !r.isEmpty() ? r.get(0) : "");
                        JSONArray alts = new JSONArray();
                        if (r != null) for (String s : r) alts.put(s);
                        o.put("alts", alts);
                        send(o);
                    } catch (Exception ignored) {}
                }
            });
        }
        Intent i = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
        i.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
        i.putExtra(RecognizerIntent.EXTRA_LANGUAGE, lang);
        i.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true);
        i.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5);
        recognizer.startListening(i);
    }

    /** Отправляет готовый запрос в приложение Gemini (через подписку пользователя). */
    private void openGemini(String text) {
        try {
            android.content.ClipboardManager cm = (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
            if (cm != null) cm.setPrimaryClip(android.content.ClipData.newPlainText("Запрос для Gemini", text));
        } catch (Exception ignored) {}
        Intent send = new Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text);
        try {
            startActivity(new Intent(send).setPackage("com.google.android.apps.bard"));
        } catch (Exception e) {
            try { startActivity(Intent.createChooser(send, "Отправить запрос в…")); }
            catch (Exception e2) {
                try { startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse("https://gemini.google.com/app"))); } catch (Exception ignored) {}
            }
        }
    }

    private void applyReminder(int h, int m, boolean on) {
        getSharedPreferences("yasny", 0).edit().putInt("h", h).putInt("m", m).putBoolean("on", on).apply();
        Reminder.schedule(this);
        if (on && Build.VERSION.SDK_INT >= 33 && checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{"android.permission.POST_NOTIFICATIONS"}, REQ_NOTIFY);
        }
    }

    @Override public void onRequestPermissionsResult(int code, String[] perms, int[] res) {
        boolean ok = res.length > 0 && res[0] == PackageManager.PERMISSION_GRANTED;
        if (code == REQ_MIC) { if (ok) startListen(pendingLang); else sendType("error", "error", "permission"); }
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        tts = new TextToSpeech(this, new TextToSpeech.OnInitListener() {
            @Override public void onInit(int status) {
                if (status == TextToSpeech.SUCCESS) { tts.setLanguage(Locale.US); ttsReady = true; }
            }
        });
        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setTextZoom(100);
        web.addJavascriptInterface(new Bridge(), "AndroidTTS");
        web.setWebViewClient(new WebViewClient() {
            @Override public WebResourceResponse shouldInterceptRequest(WebView v, WebResourceRequest req) {
                Uri u = req.getUrl();
                if (!HOST.equals(u.getHost())) return null;
                String path = u.getPath();
                if (path == null || path.equals("/") || path.isEmpty()) path = "/index.html";
                try {
                    InputStream in = getAssets().open(path.substring(1));
                    String mime = path.endsWith(".html") ? "text/html" : path.endsWith(".png") ? "image/png" : "application/octet-stream";
                    return new WebResourceResponse(mime, "utf-8", in);
                } catch (Exception e) { return null; }
            }
            @Override public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest req) {
                Uri u = req.getUrl();
                if (HOST.equals(u.getHost())) return false;
                try { startActivity(new Intent(Intent.ACTION_VIEW, u)); } catch (Exception ignored) {}
                return true;
            }
        });
        setContentView(web);
        Reminder.schedule(this);
        if (state != null) web.restoreState(state);
        else web.loadUrl("https://" + HOST + "/index.html#today");
    }

    @Override protected void onSaveInstanceState(Bundle out) { super.onSaveInstanceState(out); web.saveState(out); }

    @Override public void onBackPressed() {
        if (web != null && web.canGoBack()) web.goBack(); else super.onBackPressed();
    }

    @Override protected void onPause() {
        super.onPause();
        if (tts != null) tts.stop();
        if (recognizer != null) recognizer.cancel();
    }

    @Override protected void onDestroy() {
        if (tts != null) tts.shutdown();
        if (recognizer != null) recognizer.destroy();
        if (web != null) web.destroy();
        super.onDestroy();
    }
}

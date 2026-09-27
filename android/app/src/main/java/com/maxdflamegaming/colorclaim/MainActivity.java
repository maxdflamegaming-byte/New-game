package com.maxdflamegaming.colorclaim;

import android.app.Activity;
import android.content.ContentValues;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Base64;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Collections;

/**
 * Color Claim as an Android app: the web game (bundled in assets/) in a full-screen WebView.
 *
 * The game is served from https://appassets.androidplatform.net/ (a host reserved for exactly
 * this) instead of file://, so it runs as a normal secure web page: saves (localStorage) work
 * and stay put between updates, and nothing is fetched from the internet except the fonts.
 */
public class MainActivity extends Activity {
    private static final String HOST = "appassets.androidplatform.net";
    private static final String START = "https://" + HOST + "/color-claim/index.html";

    private WebView web;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        web = new WebView(this);
        web.setBackgroundColor(0xffcfd6e4);
        setContentView(web);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setTextZoom(100); // the game sizes its own text (and has a Large text setting)

        web.setWebViewClient(new GameClient());
        web.addJavascriptInterface(new Bridge(), "AndroidApp");
        // "Download GIF", "Save photo" and "Save card" are links to blob: URLs, which only the
        // page can read: ask it to hand the file over through the bridge
        web.setDownloadListener((url, userAgent, disposition, mime, length) -> {
            if (!url.startsWith("blob:")) return;
            String js = "(function(u){var a=document.querySelector('a[href=\"'+u+'\"]');"
                    + "var name=(a&&a.download)||'color-claim';"
                    + "fetch(u).then(function(r){return r.blob();}).then(function(b){"
                    + "var f=new FileReader();f.onload=function(){AndroidApp.saveFile(name,f.result);};f.readAsDataURL(b);});"
                    + "})(" + quote(url) + ")";
            web.evaluateJavascript(js, null);
        });

        if (state != null) web.restoreState(state);
        else web.loadUrl(START);
        hideSystemBars();
    }

    private static String quote(String s) {
        return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'";
    }

    /** Serves the game's files out of the app's assets; anything else (fonts) goes to the web. */
    private class GameClient extends WebViewClient {
        @Override
        public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest req) {
            Uri url = req.getUrl();
            if (!HOST.equals(url.getHost())) return null;
            String path = url.getPath() == null ? "" : url.getPath().replaceFirst("^/+", "");
            if (path.isEmpty() || path.endsWith("/")) path += "index.html";
            try {
                InputStream in = getAssets().open(path);
                String mime = mimeOf(path);
                return new WebResourceResponse(mime, mime.startsWith("image/") ? null : "utf-8", in);
            } catch (IOException e) {
                return new WebResourceResponse("text/plain", "utf-8", 404, "Not Found",
                        Collections.emptyMap(), new ByteArrayInputStream(new byte[0]));
            }
        }

        @Override
        public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
            Uri url = req.getUrl();
            if (HOST.equals(url.getHost())) return false;
            // Links out of the game open in the browser
            try {
                startActivity(new Intent(Intent.ACTION_VIEW, url));
            } catch (Exception ignored) {
                // no browser
            }
            return true;
        }
    }

    private static String mimeOf(String path) {
        String p = path.toLowerCase();
        if (p.endsWith(".html")) return "text/html";
        if (p.endsWith(".js")) return "text/javascript";
        if (p.endsWith(".css")) return "text/css";
        if (p.endsWith(".json") || p.endsWith(".webmanifest")) return "application/json";
        if (p.endsWith(".png")) return "image/png";
        if (p.endsWith(".gif")) return "image/gif";
        if (p.endsWith(".svg")) return "image/svg+xml";
        return "application/octet-stream";
    }

    /** Called from the page (on a background thread). */
    private class Bridge {
        @JavascriptInterface
        public void saveFile(String name, String dataUrl) {
            int comma = dataUrl.indexOf(',');
            if (comma < 0) return;
            String mime = dataUrl.substring(5, dataUrl.indexOf(';') > 0 ? dataUrl.indexOf(';') : comma);
            byte[] bytes = Base64.decode(dataUrl.substring(comma + 1), Base64.DEFAULT);
            String where;
            try {
                where = save(name, mime, bytes);
            } catch (Exception e) {
                where = null;
            }
            final String msg = where != null ? "Saved to " + where : "Couldn't save the file";
            runOnUiThread(() -> Toast.makeText(MainActivity.this, msg, Toast.LENGTH_LONG).show());
        }
    }

    /** Saves into Downloads/Color Claim (Android 10+), or the app's own folder on older phones. */
    private String save(String name, String mime, byte[] bytes) throws IOException {
        if (Build.VERSION.SDK_INT >= 29) {
            ContentValues v = new ContentValues();
            v.put(MediaStore.Downloads.DISPLAY_NAME, name);
            v.put(MediaStore.Downloads.MIME_TYPE, mime);
            v.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/Color Claim");
            Uri uri = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v);
            if (uri == null) throw new IOException("no uri");
            try (OutputStream out = getContentResolver().openOutputStream(uri)) {
                if (out == null) throw new IOException("no stream");
                out.write(bytes);
            }
            return "Downloads/Color Claim";
        }
        File dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
        if (dir == null) dir = getFilesDir();
        File file = new File(dir, name);
        try (FileOutputStream out = new FileOutputStream(file)) {
            out.write(bytes);
        }
        return file.getAbsolutePath();
    }

    /**
     * Back button: pause or resume a game, close photo mode or the replay, or go back to the
     * home screen. On the home screen it leaves the app.
     */
    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
        String js = "(function(){try{"
                + "var shown=document.querySelector('.screen.show');"
                + "if(state==='play'){togglePause();return 'ok';}"
                + "if(state==='paused'){togglePause();return 'ok';}"
                + "if(state==='photo'){closePhoto();return 'ok';}"
                + "if(state==='replay'){stopReplay();return 'ok';}"
                + "if(state==='over'){var q=document.getElementById(shown&&shown.id==='cup'?'cup-quit':'menu-btn');if(q){q.click();return 'ok';}}"
                + "if(state==='menu'&&shown&&shown.id!=='menu'){showScreen('menu');return 'ok';}"
                + "}catch(e){}return 'exit';})()";
        web.evaluateJavascript(js, result -> {
            if ("\"exit\"".equals(result)) finish();
        });
    }

    @Override
    protected void onPause() {
        // Leaving the app pauses the game
        web.evaluateJavascript("try{if(state==='play')togglePause();}catch(e){}", null);
        web.onPause();
        web.pauseTimers();
        super.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        web.onResume();
        web.resumeTimers();
        hideSystemBars();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) hideSystemBars();
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        web.saveState(out);
    }

    @Override
    protected void onDestroy() {
        web.destroy();
        super.onDestroy();
    }

    /** Full screen: the status and navigation bars come back with a swipe from the edge. */
    @SuppressWarnings("deprecation")
    private void hideSystemBars() {
        if (Build.VERSION.SDK_INT >= 30) {
            WindowInsetsController c = getWindow().getInsetsController();
            if (c != null) {
                c.hide(WindowInsets.Type.systemBars());
                c.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            }
        } else {
            getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    | View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    | View.SYSTEM_UI_FLAG_LAYOUT_STABLE | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
        }
    }
}

package com.towersiege.ads;

import android.app.Activity;

import com.google.android.gms.ads.AdError;
import com.google.android.gms.ads.AdRequest;
import com.google.android.gms.ads.FullScreenContentCallback;
import com.google.android.gms.ads.LoadAdError;
import com.google.android.gms.ads.MobileAds;
import com.google.android.gms.ads.rewarded.RewardedAd;
import com.google.android.gms.ads.rewarded.RewardedAdLoadCallback;

/**
 * Rewarded ads (Google AdMob) for the game, which reaches this class through Godot's
 * JavaClassWrapper. Godot can't receive Java callbacks that way, so the ad's progress is kept in
 * a state the game reads every frame: "idle", "loading", "ready", "showing", "closed" (the ad
 * went away; earned() says whether it was watched to the end) or "failed" (none to show).
 * Everything that touches the ad runs on Android's UI thread, as the ads library requires.
 */
public final class Ads {
    private static volatile String state = "idle";
    private static volatile boolean earned = false;
    private static volatile String lastError = "";
    private static volatile boolean started = false;
    private static RewardedAd ad;

    private Ads() {}

    /** Start the ads library once, when the game starts. */
    public static void init(final Activity activity) {
        if (activity == null || started) {
            return;
        }
        started = true;
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    MobileAds.initialize(activity);
                } catch (Throwable t) {
                    lastError = String.valueOf(t);
                }
            }
        });
    }

    /** Fetch a rewarded ad for the ad unit, so it's ready when the player asks for one. */
    public static void load(final Activity activity, final String unit) {
        if (activity == null || unit == null || unit.isEmpty()) {
            return;
        }
        if ("loading".equals(state) || "ready".equals(state) || "showing".equals(state)) {
            return;
        }
        state = "loading";
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    RewardedAd.load(activity, unit, new AdRequest.Builder().build(), new RewardedAdLoadCallback() {
                        @Override
                        public void onAdLoaded(RewardedAd loaded) {
                            ad = loaded;
                            state = "ready";
                        }

                        @Override
                        public void onAdFailedToLoad(LoadAdError error) {
                            ad = null;
                            lastError = error.getMessage();
                            state = "failed";
                        }
                    });
                } catch (Throwable t) {
                    lastError = String.valueOf(t);
                    state = "failed";
                }
            }
        });
    }

    /** Show the loaded ad. The game then waits for "closed" and asks earned(). */
    public static void show(final Activity activity) {
        if (activity == null || ad == null || !"ready".equals(state)) {
            return;
        }
        state = "showing";
        earned = false;
        final RewardedAd showing = ad;
        ad = null;
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    showing.setFullScreenContentCallback(new FullScreenContentCallback() {
                        @Override
                        public void onAdDismissedFullScreenContent() {
                            state = "closed";
                        }

                        @Override
                        public void onAdFailedToShowFullScreenContent(AdError error) {
                            lastError = error.getMessage();
                            state = "closed";
                        }
                    });
                    showing.show(activity, item -> earned = true);
                } catch (Throwable t) {
                    lastError = String.valueOf(t);
                    state = "closed";
                }
            }
        });
    }

    public static String state() {
        return state;
    }

    public static boolean earned() {
        return earned;
    }

    public static String lastError() {
        return lastError;
    }

    /** After the game has read a closed or failed ad: back to idle, ready to load the next. */
    public static void reset() {
        if ("closed".equals(state) || "failed".equals(state)) {
            state = "idle";
            earned = false;
        }
    }
}

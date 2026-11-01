package com.towersiege.reminders;

import android.app.Activity;
import android.os.Build;
import android.view.Display;
import android.view.Window;
import android.view.WindowManager;

/**
 * The screen's refresh rate. Many phones run their screen at 90 or 120 Hz; a battle drawn at 60
 * frames a second on such a screen can't be spaced evenly, so it judders. Asking for the
 * screen's 60 Hz mode while the game runs makes every frame line up with the screen (and saves
 * battery). Phones without such a mode just keep theirs.
 */
public final class Screen {
    private Screen() {}

    /** Ask for the screen mode closest to hz (same resolution). Safe to call from any thread. */
    public static void preferRefreshRate(final Activity activity, final float hz) {
        if (activity == null) {
            return;
        }
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    Window w = activity.getWindow();
                    WindowManager.LayoutParams lp = w.getAttributes();
                    if (Build.VERSION.SDK_INT >= 23) {
                        Display d = w.getWindowManager().getDefaultDisplay();
                        Display.Mode cur = d.getMode();
                        int best = 0;
                        float bestDiff = Float.MAX_VALUE;
                        for (Display.Mode m : d.getSupportedModes()) {
                            if (m.getPhysicalWidth() != cur.getPhysicalWidth()
                                    || m.getPhysicalHeight() != cur.getPhysicalHeight()) {
                                continue;
                            }
                            float diff = Math.abs(m.getRefreshRate() - hz);
                            if (diff < bestDiff) {
                                bestDiff = diff;
                                best = m.getModeId();
                            }
                        }
                        if (best != 0) {
                            lp.preferredDisplayModeId = best;
                        }
                    }
                    lp.preferredRefreshRate = hz;
                    w.setAttributes(lp);
                } catch (Throwable t) {
                    // Not worth stopping the game for: the screen keeps its own rate
                }
            }
        });
    }
}

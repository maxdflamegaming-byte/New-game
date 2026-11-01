package com.towersiege.reminders;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

/**
 * Tower Siege's reminders: a notification at a set time ("your daily reward is ready", "the
 * weekend event is on"), even when the game is closed. The game calls these through Godot's
 * JavaClassWrapper; the alarm wakes ReminderReceiver, which shows the notification.
 */
public class Reminders {
    /** Show a notification at atMillis (Unix time in ms); the same id replaces an earlier one. */
    public static boolean schedule(Context ctx, int id, long atMillis, String title, String text) {
        try {
            AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
            if (am == null) return false;
            am.set(AlarmManager.RTC_WAKEUP, atMillis, pending(ctx, id, title, text));
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /** Forget a reminder that hasn't been shown yet. */
    public static void cancel(Context ctx, int id) {
        try {
            AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
            if (am != null) am.cancel(pending(ctx, id, "", ""));
        } catch (Exception e) {
            // nothing to cancel
        }
    }

    private static PendingIntent pending(Context ctx, int id, String title, String text) {
        Intent i = new Intent(ctx, ReminderReceiver.class);
        i.putExtra("id", id);
        i.putExtra("title", title);
        i.putExtra("text", text);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= 23) flags |= PendingIntent.FLAG_IMMUTABLE;
        return PendingIntent.getBroadcast(ctx, id, i, flags);
    }
}

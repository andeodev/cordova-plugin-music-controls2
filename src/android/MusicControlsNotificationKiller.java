package com.homerours.musiccontrols;

import android.app.Notification;
import android.app.Service;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.app.NotificationManager;
import android.content.Intent;

import org.apache.cordova.LOG;

public class MusicControlsNotificationKiller extends Service {

	private int NOTIFICATION_ID;
	private NotificationManager mNM;
	private final IBinder mBinder = new KillBinder(this);

	private final String LOG_TAG = "MusicControls::Service";

	private PowerManager.WakeLock wakeLock;

	@Override
	public IBinder onBind(Intent intent) {
		this.NOTIFICATION_ID=intent.getIntExtra("notificationID",1);
		return mBinder;
	}
	@Override
	public int onStartCommand(Intent intent, int flags, int startId) {
		LOG.d(LOG_TAG, "Service started");
		return Service.START_STICKY;
	}

	@Override
	public void onCreate() {
		mNM = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
		mNM.cancel(NOTIFICATION_ID);

		LOG.d(LOG_TAG, "Service created");
	}

	@Override
	public void onDestroy() {
		mNM = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
		mNM.cancel(NOTIFICATION_ID);

		LOG.d(LOG_TAG, "Service destroyed");
	}

	public void setForeground(Notification notification, boolean isPlaying) {
		try {
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
				this.startForeground(this.NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
			} else {
				this.startForeground(this.NOTIFICATION_ID, notification);
			}
        } catch (Exception ex) {
            ex.printStackTrace();
            return;
        }

		if (this.wakeLock == null) {
			PowerManager powerManager = (PowerManager) getSystemService(POWER_SERVICE);
			this.wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Adonia::MediaPlayer");
		}

		if (isPlaying && !this.wakeLock.isHeld()) {
			this.wakeLock.acquire();
		} else if (!isPlaying && this.wakeLock.isHeld()) {
			try {
				this.wakeLock.release();
			} catch (Exception ex) {
				ex.printStackTrace();
			}
		}

		LOG.d(LOG_TAG, "Service set to foreground, isPlaying=" + isPlaying);
	}

	public void clearForeground() {
		if (android.os.Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
			return;
		}

		this.stopForeground(STOP_FOREGROUND_DETACH);

		if (this.wakeLock != null && this.wakeLock.isHeld()) {
            try {
		        this.wakeLock.release();
		    } catch (Exception ex) {
                ex.printStackTrace();
                return;
            }
		}

		LOG.d(LOG_TAG, "Service removed from foreground");
	}
}

package app.readlater.readlater

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import java.lang.ref.WeakReference

class BackgroundWorkService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    private val runtime: ReadlaterRuntime
        get() = (application as ReadlaterApplication).runtime

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        activeService = WeakReference(this)
        runtime.createNotificationChannels()
        startForegroundCompat()
        renewWakeLock()
        if (intent?.action == ReadlaterRuntime.ACTION_CANCEL) {
            runtime.emitCancelAll()
            stopSelf()
            return START_NOT_STICKY
        }
        runtime.ensureEngine(RuntimeMode.INTERACTIVE)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        if (activeService?.get() === this) {
            activeService = null
        }
        runtime.markBackgroundServiceStopped()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        runtime.emitTimeout()
        stopSelf(startId)
    }

    private fun startForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                RUNNING_NOTIFICATION_ID,
                runtime.runningNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(RUNNING_NOTIFICATION_ID, runtime.runningNotification())
        }
    }

    fun renewWakeLock() {
        releaseWakeLock()
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "$packageName:backgroundWork",
        ).apply {
            setReferenceCounted(false)
            acquire(WAKE_LOCK_TIMEOUT_MS)
        }
    }

    private fun releaseWakeLock() {
        val lock = wakeLock
        if (lock?.isHeld == true) {
            lock.release()
        }
        wakeLock = null
    }

    companion object {
        private var activeService: WeakReference<BackgroundWorkService>? = null
        private const val RUNNING_NOTIFICATION_ID = 42022
        private const val WAKE_LOCK_TIMEOUT_MS = 10 * 60 * 1000L

        fun renewActiveWakeLock() {
            activeService?.get()?.renewWakeLock()
        }
    }
}

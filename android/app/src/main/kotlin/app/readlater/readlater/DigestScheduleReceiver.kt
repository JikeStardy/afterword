package app.readlater.readlater

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class DigestScheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val application = context.applicationContext as? ReadlaterApplication ?: return
        application.runtime.rescheduleDigest()
    }
}

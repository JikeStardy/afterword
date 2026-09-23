package app.readlater.readlater

import io.flutter.app.FlutterApplication

class ReadlaterApplication : FlutterApplication() {
    lateinit var runtime: ReadlaterRuntime
        private set

    override fun onCreate() {
        super.onCreate()
        runtime = ReadlaterRuntime(this)
        runtime.createNotificationChannels()
        runtime.ensureDigestScheduled()
    }
}

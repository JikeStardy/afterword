package app.readlater.readlater

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private val runtime: ReadlaterRuntime
        get() = (application as ReadlaterApplication).runtime

    override fun provideFlutterEngine(context: android.content.Context): FlutterEngine {
        return runtime.ensureEngine(RuntimeMode.INTERACTIVE)
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // The application runtime owns plugin registration and the native channel.
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        runtime.attachActivity(this)
        runtime.handleLaunchIntent(intent)
        runtime.handleIncomingShare(intent)
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        runtime.handleLaunchIntent(intent)
        runtime.handleIncomingShare(intent)
    }

    override fun onDestroy() {
        runtime.detachActivity(this)
        super.onDestroy()
    }
}

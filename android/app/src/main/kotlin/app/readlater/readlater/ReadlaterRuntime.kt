package app.readlater.readlater

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.drawable.Icon
import android.graphics.pdf.PdfRenderer
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.Calendar
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

enum class RuntimeMode(val wireName: String) {
    INTERACTIVE("interactive"),
    DIGEST_ONLY("digestOnly"),
}

class ReadlaterRuntime(private val app: ReadlaterApplication) {
    private val inboxLock = Any()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private var activity: MainActivity? = null
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var currentMode = RuntimeMode.INTERACTIVE
    private var openedEntityType: String? = null
    private var openedEntityId: String? = null
    private var launchedFromNotification = false
    private var activeDigestJob: Pair<android.app.job.JobService, JobParameters>? = null
    private var runningProgress = ProgressSnapshot()
    private var backgroundServiceStarted = false
    private val recentRuntimeEvents = ArrayDeque<Map<String, Any?>>()
    private val nativeCopyLock = Any()
    private var nativeCopyCount = 0
    private val leasedShareIds = mutableSetOf<String>()
    private var stopWhenShareLeasesFinish = false
    private var dartBackgroundOwner = false
    private val activeCancelledShareIds = mutableSetOf<String>()
    private val activeShareIds = mutableSetOf<String>()
    private var activeWebCapture: WebArticleCaptureDialog? = null

    fun ensureEngine(mode: RuntimeMode): FlutterEngine {
        synchronized(this) {
            currentMode = mode
            val existing = engine
            if (existing != null) {
                return existing
            }
            val next = FlutterEngine(app)
            GeneratedPluginRegistrant.registerWith(next)
            MethodChannel(next.dartExecutor.binaryMessenger, CHANNEL).also {
                channel = it
                installChannel(it)
            }
            FlutterEngineCache.getInstance().put(ENGINE_ID, next)
            next.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
            engine = next
            return next
        }
    }

    fun attachActivity(next: MainActivity) {
        activity = next
        currentMode = RuntimeMode.INTERACTIVE
        emitRuntimeEvent(mapOf("kind" to "interactive"))
    }

    fun detachActivity(leaving: MainActivity) {
        if (activity === leaving) activity = null
        activeWebCapture?.cancelFromHost()
    }

    fun handleLaunchIntent(intent: Intent?) {
        if (intent == null) return
        val entityType = intent.getStringExtra(EXTRA_ENTITY_TYPE)
        val entityId = intent.getStringExtra(EXTRA_ENTITY_ID).orEmpty()
        if (entityType.isNullOrBlank() || (entityType != "today" && entityId.isBlank())) {
            return
        }
        openedEntityType = entityType
        openedEntityId = entityId
        launchedFromNotification = true
        emitRuntimeEvent(
            mapOf(
                "kind" to "openEntity",
                "entityType" to entityType,
                "entityId" to entityId,
            ),
        )
    }

    fun handleIncomingShare(intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: return
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT).orEmpty()
        val uris = sharedUris(intent)
        if (text.isBlank() && uris.isEmpty()) return

        val id = "${System.currentTimeMillis()}-${UUID.randomUUID()}"
        beginNativeShareCopy(id)
        startBackgroundWork(claimDartOwner = false)
        executor.execute {
            val shareDir = File(inboxDir(), id).also { it.mkdirs() }
            val errors = mutableListOf<String>()
            try {
                if (uris.size > MAX_SHARED_FILES) {
                    errors.add("Only the first $MAX_SHARED_FILES shared files were imported.")
                }
                val copyResults = uris.take(MAX_SHARED_FILES)
                    .mapIndexed { index, uri -> copySharedUri(uri, shareDir, index) }
                val paths = copyResults.mapNotNull { copy -> copy.path }
                errors.addAll(copyResults.mapNotNull { copy -> copy.error })
                val cancelledAtCopyEnd = nativeShareCopyCancelled(id)
                if (cancelledAtCopyEnd) {
                    errors.add(0, "用户已取消自动分析；附件已保留，可在应用内手动重试。")
                }
                val cancelled = appendShare(
                    JSONObject()
                        .put("id", id)
                        .put("text", text)
                        .put("paths", JSONArray(paths))
                        .put("error", errors.joinToString("; "))
                        .put("cancelled", cancelledAtCopyEnd),
                )
                mainHandler.post {
                    channel?.invokeMethod("sharesReady", null)
                    if (!cancelled) {
                        emitRuntimeEvent(mapOf("kind" to "interactive"))
                    }
                }
            } finally {
                finishNativeShareCopy(id)
            }
        }
    }

    fun startBackgroundWork(claimDartOwner: Boolean = true): Boolean {
        synchronized(nativeCopyLock) {
            if (claimDartOwner) {
                dartBackgroundOwner = true
                stopWhenShareLeasesFinish = false
            }
        }
        backgroundServiceStarted = true
        val intent = Intent(app, BackgroundWorkService::class.java)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                app.startForegroundService(intent)
            } else {
                app.startService(intent)
            }
            return true
        } catch (error: Exception) {
            backgroundServiceStarted = false
            emitRuntimeEvent(
                mapOf(
                    "kind" to "timeout",
                    "message" to "后台服务无法启动：${error.message.orEmpty()}",
                ),
            )
            return false
        }
    }

    fun stopBackgroundWork() {
        synchronized(nativeCopyLock) {
            dartBackgroundOwner = false
            if (leasedShareIds.isNotEmpty()) {
                stopWhenShareLeasesFinish = true
                return
            }
        }
        if (backgroundServiceStarted) {
            app.stopService(Intent(app, BackgroundWorkService::class.java))
        }
        backgroundServiceStarted = false
    }

    fun markBackgroundServiceStopped() {
        backgroundServiceStarted = false
    }

    fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = notificationManager()
        manager.createNotificationChannels(
            listOf(
                NotificationChannel(
                    CHANNEL_RUNNING,
                    "Readlater 运行进度",
                    NotificationManager.IMPORTANCE_LOW,
                ),
                NotificationChannel(
                    CHANNEL_RESULTS,
                    "Readlater 任务结果",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
                NotificationChannel(
                    CHANNEL_DIGEST,
                    "Readlater 每日汇总",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
                NotificationChannel(
                    CHANNEL_RESEARCH,
                    "Readlater 研究提醒",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            ),
        )
    }

    fun runningNotification(): Notification {
        return buildNotification(
            channelId = CHANNEL_RUNNING,
            title = runningProgress.title.ifBlank { "Readlater 正在处理" },
            body = runningProgress.body(),
            entityType = null,
            entityId = null,
            ongoing = true,
            cancelAction = true,
        )
    }

    fun emitTimeout() {
        emitRuntimeEvent(
            mapOf(
                "kind" to "timeout",
                "message" to "系统前台服务时限已触发，任务已暂停等待下次恢复。",
            ),
        )
    }

    fun emitCancelAll() {
        cancelNativeShareCopy()
        emitRuntimeEvent(mapOf("kind" to "cancelAll"))
    }

    fun startDigestJob(service: android.app.job.JobService, params: JobParameters) {
        activeDigestJob = service to params
        ensureEngine(RuntimeMode.DIGEST_ONLY)
        emitRuntimeEvent(mapOf("kind" to "digest"))
    }

    fun stopDigestJob(service: android.app.job.JobService, params: JobParameters): Boolean {
        if (activeDigestJob?.first === service && activeDigestJob?.second === params) {
            activeDigestJob = null
        }
        rescheduleDigest()
        return false
    }

    fun finishDigest() {
        activeDigestJob?.let { (service, params) ->
            service.jobFinished(params, false)
            activeDigestJob = null
        }
        rescheduleDigest()
    }

    fun configureDigest(enabled: Boolean, hour: Int, minute: Int) {
        val prefs = prefs()
        val boundedHour = hour.coerceIn(0, 23)
        val boundedMinute = minute.coerceIn(0, 59)
        val changed = prefs.getBoolean(PREF_DIGEST_ENABLED, true) != enabled ||
            prefs.getInt(PREF_DIGEST_HOUR, 20) != boundedHour ||
            prefs.getInt(PREF_DIGEST_MINUTE, 0) != boundedMinute
        prefs().edit()
            .putBoolean(PREF_DIGEST_ENABLED, enabled)
            .putInt(PREF_DIGEST_HOUR, boundedHour)
            .putInt(PREF_DIGEST_MINUTE, boundedMinute)
            .apply()
        if (changed) {
            rescheduleDigest()
        } else {
            ensureDigestScheduled()
        }
    }

    fun ensureDigestScheduled() {
        scheduleDigest(replaceExisting = false)
    }

    fun rescheduleDigest() {
        scheduleDigest(replaceExisting = true)
    }

    private fun scheduleDigest(replaceExisting: Boolean) {
        val scheduler = app.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
        if (!prefs().getBoolean(PREF_DIGEST_ENABLED, true)) {
            scheduler.cancel(DIGEST_JOB_ID)
            emitRuntimeEvent(
                mapOf(
                    "kind" to "digestSchedule",
                    "message" to "每日汇总调度已取消：功能未启用。",
                    "result" to "cancelled",
                ),
            )
            return
        }
        val hasPending = scheduler.allPendingJobs.any { job -> job.id == DIGEST_JOB_ID }
        if (!replaceExisting && hasPending) {
            emitRuntimeEvent(
                mapOf(
                    "kind" to "digestSchedule",
                    "message" to "每日汇总已有待执行调度。",
                    "result" to "skipped",
                ),
            )
            return
        }
        if (replaceExisting) {
            scheduler.cancel(DIGEST_JOB_ID)
            emitRuntimeEvent(
                mapOf(
                    "kind" to "digestSchedule",
                    "message" to "每日汇总旧调度已取消，准备重新调度。",
                    "result" to "replacing",
                ),
            )
        }
        val hour = prefs().getInt(PREF_DIGEST_HOUR, 20)
        val minute = prefs().getInt(PREF_DIGEST_MINUTE, 0)
        val delay = delayUntilNextDigest(hour, minute)
        val info = JobInfo.Builder(
            DIGEST_JOB_ID,
            ComponentName(app, DigestJobService::class.java),
        )
            .setMinimumLatency(delay)
            .setPersisted(true)
            .build()
        val result = scheduler.schedule(info)
        emitRuntimeEvent(
            mapOf(
                "kind" to "digestSchedule",
                "message" to if (result == JobScheduler.RESULT_SUCCESS) {
                    "每日汇总调度成功。"
                } else {
                    "每日汇总调度失败。"
                },
                "result" to if (result == JobScheduler.RESULT_SUCCESS) "success" else "failure",
                "delayMs" to delay,
            ),
        )
    }

    private fun installChannel(nativeChannel: MethodChannel) {
        nativeChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "runtimeContext" -> result.success(runtimeContext())
                "diagnosticEnvironment" -> result.success(diagnosticEnvironment())
                "pendingShares" -> result.success(pendingShares())
                "acknowledgeShare" -> acknowledgeShare(call, result)
                "renderPdf" -> renderPdf(call, result)
                "requestNotificationPermission" -> requestNotificationPermission(result)
                "notify" -> notifyCompat(call, result)
                "publishNotification" -> publishNotification(call, result)
                "notificationStatus" -> result.success(notificationAllowed())
                "openFile" -> openFile(call, result)
                "openUrl" -> openUrl(call, result)
                "captureWebArticle" -> captureWebArticle(call, result)
                "startBackgroundWork" -> {
                    if (startBackgroundWork()) {
                        result.success(null)
                    } else {
                        result.error(
                            "background_service_unavailable",
                            "Android did not allow the foreground service to start.",
                            null,
                        )
                    }
                }
                "updateBackgroundProgress" -> updateBackgroundProgress(call, result)
                "stopBackgroundWork" -> {
                    stopBackgroundWork()
                    result.success(null)
                }
                "configureDigest" -> {
                    configureDigest(
                        call.argument<Boolean>("enabled") ?: true,
                        call.argument<Int>("hour") ?: 20,
                        call.argument<Int>("minute") ?: 0,
                    )
                    result.success(null)
                }
                "finishDigest" -> {
                    finishDigest()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun captureWebArticle(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url").orEmpty()
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("activity_required", "微信公众号回退需要当前可见页面。", null)
            return
        }
        if (activeWebCapture != null) {
            result.error("capture_in_progress", "已有微信公众号回退窗口正在打开。", null)
            return
        }
        val validated = WebArticleCaptureDialog.validateWeChatArticleUrl(url)
        if (validated == null) {
            result.error(
                "invalid_wechat_url",
                "仅支持 https://mp.weixin.qq.com 的公众号文章链接。",
                null,
            )
            return
        }
        var completed = false
        fun finish(block: () -> Unit) {
            if (completed) return
            completed = true
            activeWebCapture = null
            block()
        }
        val dialog = WebArticleCaptureDialog(
            activity = currentActivity,
            initialUrl = validated,
            onComplete = { captured ->
                finish { result.success(captured) }
            },
            onClosed = {
                if (!completed) {
                    finish { result.success(null) }
                }
            },
        )
        activeWebCapture = dialog
        try {
            dialog.show()
        } catch (error: Exception) {
            activeWebCapture = null
            dialog.disposeSilently()
            result.error("capture_unavailable", "微信公众号回退窗口无法打开。", null)
        }
    }

    private fun diagnosticEnvironment(): Map<String, Any?> {
        val packageInfo = try {
            app.packageManager.getPackageInfo(app.packageName, 0)
        } catch (_: Exception) {
            null
        }
        val connectivity = app.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        val activeNetwork = connectivity?.activeNetwork
        val capabilities = activeNetwork?.let { connectivity.getNetworkCapabilities(it) }
        val networkType = when {
            capabilities == null -> "unknown"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
            else -> "other"
        }
        val vpnActive = capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo?.longVersionCode?.toString()
        } else {
            @Suppress("DEPRECATION")
            packageInfo?.versionCode?.toString()
        }
        return mapOf(
            "platform" to "android",
            "appVersion" to (packageInfo?.versionName ?: "unknown"),
            "buildNumber" to (versionCode ?: "unknown"),
            "osVersion" to Build.VERSION.RELEASE.orEmpty().ifBlank { "unknown" },
            "sdkInt" to Build.VERSION.SDK_INT,
            "networkType" to networkType,
            "vpnActive" to (vpnActive ?: "unknown"),
        )
    }

    private fun runtimeContext(): Map<String, Any?> = synchronized(this) {
        mapOf(
            "mode" to currentMode.wireName,
            "openedEntityType" to openedEntityType,
            "openedEntityId" to openedEntityId,
            "launchedFromNotification" to launchedFromNotification,
            "recentEvents" to recentRuntimeEvents.toList(),
        )
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || notificationAllowed()) {
            result.success(null)
            return
        }
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("activity_required", "Notification permission requires a visible Activity.", null)
            return
        }
        currentActivity.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_REQUEST_CODE,
        )
        result.success(null)
    }

    private fun notificationAllowed(channelId: String? = null): Boolean {
        if (!NotificationManagerCompat.from(app).areNotificationsEnabled()) return false
        val permissionAllowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            app.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (!permissionAllowed) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && channelId != null) {
            val channel = notificationManager().getNotificationChannel(channelId)
            if (channel?.importance == NotificationManager.IMPORTANCE_NONE) {
                return false
            }
        }
        return true
    }

    private fun notifyCompat(call: MethodCall, result: MethodChannel.Result) {
        val title = call.argument<String>("title").orEmpty()
        val body = call.argument<String>("body").orEmpty()
        if (title.isBlank() && body.isBlank()) {
            result.error("invalid_notification", "Notification title or body is required.", null)
            return
        }
        publishNotification(
            "legacy",
            CHANNEL_RESULTS,
            title.ifBlank { "Readlater" },
            body,
            null,
            null,
        )
        result.success(null)
    }

    private fun publishNotification(call: MethodCall, result: MethodChannel.Result) {
        val title = call.argument<String>("title").orEmpty()
        val body = call.argument<String>("body").orEmpty()
        if (title.isBlank() && body.isBlank()) {
            result.error("invalid_notification", "Notification title or body is required.", null)
            return
        }
        val channelId = channelId(call.argument<String>("channel").orEmpty())
        val posted = publishNotification(
            notificationKey(call),
            channelId,
            title,
            body,
            call.argument<String>("entityType"),
            call.argument<String>("entityId"),
        )
        result.success(posted)
    }

    private fun publishNotification(
        id: String,
        channelId: String,
        title: String,
        body: String,
        entityType: String?,
        entityId: String?,
    ): Boolean {
        if (!notificationAllowed(channelId)) return false
        notificationManager().notify(
            notificationId(id),
            buildNotification(
                channelId,
                title,
                body,
                entityType,
                entityId,
                groupKey = if (channelId == CHANNEL_RESULTS) GROUP_RESULTS else null,
            ),
        )
        if (channelId == CHANNEL_RESULTS) {
            updateResultSummary(notificationId(id))
        }
        return true
    }

    private fun updateBackgroundProgress(call: MethodCall, result: MethodChannel.Result) {
        runningProgress = ProgressSnapshot(
            jobId = call.argument<String>("jobId").orEmpty(),
            title = call.argument<String>("title").orEmpty(),
            stage = call.argument<String>("stage").orEmpty(),
            completed = call.argument<Int>("completed"),
            total = call.argument<Int>("total"),
        )
        if (notificationAllowed()) {
            notificationManager().notify(RUNNING_NOTIFICATION_ID, runningNotification())
        }
        BackgroundWorkService.renewActiveWakeLock()
        result.success(null)
    }

    private fun buildNotification(
        channelId: String,
        title: String,
        body: String,
        entityType: String?,
        entityId: String?,
        ongoing: Boolean = false,
        cancelAction: Boolean = false,
        groupKey: String? = null,
        groupSummary: Boolean = false,
    ): Notification {
        val notificationIdentity = listOf(
            channelId,
            entityType.orEmpty(),
            entityId.orEmpty(),
            if (ongoing) "ongoing" else "result",
        ).joinToString(":")
        val intent = Intent(app, MainActivity::class.java).apply {
            action = "$ACTION_OPEN_NOTIFICATION:$notificationIdentity"
            data = Uri.parse("readlater://notification/${Uri.encode(notificationIdentity)}")
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (!entityType.isNullOrBlank() && !entityId.isNullOrBlank()) {
                putExtra(EXTRA_ENTITY_TYPE, entityType)
                putExtra(EXTRA_ENTITY_ID, entityId)
            } else if (entityType == "today") {
                putExtra(EXTRA_ENTITY_TYPE, entityType)
                putExtra(EXTRA_ENTITY_ID, "")
            }
        }
        val contentIntent = PendingIntent.getActivity(
            app,
            notificationIdentity.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(app, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(app)
        }
        builder
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle(title.ifBlank { "Readlater" })
            .setContentText(body)
            .setContentIntent(contentIntent)
            .setOngoing(ongoing)
            .setAutoCancel(!ongoing)
        if (groupKey != null) {
            builder.setGroup(groupKey)
            if (groupSummary) {
                builder.setGroupSummary(true)
                builder.setOnlyAlertOnce(true)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                builder.setGroupAlertBehavior(Notification.GROUP_ALERT_CHILDREN)
            }
        }
        if (cancelAction) {
            val cancelIntent = PendingIntent.getService(
                app,
                1,
                Intent(app, BackgroundWorkService::class.java).setAction(ACTION_CANCEL),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            builder.addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(app, android.R.drawable.ic_menu_close_clear_cancel),
                    "取消",
                    cancelIntent,
                ).build(),
            )
        }
        return builder.build()
    }

    private fun updateResultSummary(currentNotificationId: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val childIds = notificationManager().activeNotifications
            .filter { status ->
                status.id != RESULTS_SUMMARY_NOTIFICATION_ID &&
                    status.notification.group == GROUP_RESULTS &&
                    (status.notification.flags and Notification.FLAG_GROUP_SUMMARY) == 0
            }
            .map { status -> status.id }
            .toMutableSet()
        childIds.add(currentNotificationId)
        if (childIds.size > 1) {
            publishResultSummary(childIds.size)
        } else {
            notificationManager().cancel(RESULTS_SUMMARY_NOTIFICATION_ID)
        }
    }

    private fun publishResultSummary(resultCount: Int) {
        notificationManager().notify(
            RESULTS_SUMMARY_NOTIFICATION_ID,
            buildNotification(
                CHANNEL_RESULTS,
                "任务结果",
                "有 $resultCount 项任务结果",
                "today",
                "",
                groupKey = GROUP_RESULTS,
                groupSummary = true,
            ),
        )
    }

    private fun channelId(raw: String): String = when (raw) {
        "running" -> CHANNEL_RUNNING
        "digest" -> CHANNEL_DIGEST
        "research" -> CHANNEL_RESEARCH
        else -> CHANNEL_RESULTS
    }

    private fun notificationKey(call: MethodCall): String {
        return call.argument<String>("id")
            ?: call.argument<Int>("id")?.toString()
            ?: "notification"
    }

    private fun notificationId(id: String): Int = id.hashCode().and(0x7fffffff)

    private fun emitRuntimeEvent(arguments: Map<String, Any?>) {
        synchronized(this) {
            recentRuntimeEvents.addLast(arguments)
            while (recentRuntimeEvents.size > MAX_RECENT_RUNTIME_EVENTS) {
                recentRuntimeEvents.removeFirst()
            }
        }
        mainHandler.post {
            channel?.invokeMethod("runtimeEvent", arguments)
        }
    }

    private fun sharedUris(intent: Intent): List<Uri> {
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                    ?: emptyList()
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM) ?: emptyList()
            }
        }
        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
        return listOfNotNull(uri)
    }

    private fun copySharedUri(uri: Uri, shareDir: File, index: Int): CopyResult {
        var target: File? = null
        var name = "附件 ${index + 1}"
        return try {
            name = safeFileName(displayName(uri) ?: "shared-file")
            val extension = if (name.substringAfterLast('.', "").lowercase() in
                listOf("pdf", "png", "jpg", "jpeg", "webp", "gif")
            ) {
                ""
            } else {
                extensionFor(uri)
            }
            val destination = safeChild(shareDir, "${index + 1}-$name$extension")
                ?: return CopyResult(error = "附件名称无效，无法导入。")
            target = destination
            app.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(destination).use { output -> copyWithLimit(input, output) }
            } ?: throw IllegalArgumentException("Could not open shared file.")
            CopyResult(path = destination.absolutePath)
        } catch (error: Exception) {
            target?.delete()
            CopyResult(error = "无法导入 $name：附件不可读取或超出限制，请重新分享。")
        }
    }

    private fun displayName(uri: Uri): String? {
        if (uri.scheme == "file") return uri.lastPathSegment
        return app.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (!cursor.moveToFirst()) return@use null
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) cursor.getString(index) else null
            }
    }

    private fun extensionFor(uri: Uri): String {
        val mime = app.contentResolver.getType(uri).orEmpty()
        val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime)
        return if (extension.isNullOrBlank()) ".bin" else ".$extension"
    }

    private fun pendingShares(): List<Map<String, Any>> {
        return synchronized(inboxLock) {
            val shares = prefs().getString(PREF_SHARES, "[]") ?: "[]"
            val array = JSONArray(shares)
            (0 until array.length()).map { index ->
                val item = array.getJSONObject(index)
                val paths = item.optJSONArray("paths") ?: JSONArray()
                mapOf(
                    "id" to item.optString("id"),
                    "text" to item.optString("text"),
                    "paths" to (0 until paths.length())
                        .map { pathIndex -> paths.optString(pathIndex) }
                        .filter { path -> path.isNotBlank() },
                    "error" to item.optString("error"),
                    "cancelled" to item.optBoolean("cancelled", false),
                )
            }
        }
    }

    private fun beginNativeShareCopy(id: String) {
        synchronized(nativeCopyLock) {
            nativeCopyCount++
            leasedShareIds.add(id)
            activeShareIds.add(id)
            stopWhenShareLeasesFinish = false
        }
    }

    private fun finishNativeShareCopy(id: String) {
        synchronized(nativeCopyLock) {
            nativeCopyCount = max(0, nativeCopyCount - 1)
            activeShareIds.remove(id)
        }
    }

    private fun cancelNativeShareCopy() {
        synchronized(nativeCopyLock) {
            activeCancelledShareIds.addAll(activeShareIds)
        }
        markPendingSharesCancelled()
    }

    private fun nativeShareCopyCancelled(id: String): Boolean = synchronized(nativeCopyLock) {
        activeCancelledShareIds.contains(id)
    }

    private fun releaseNativeShareLease(id: String) {
        val shouldStop = synchronized(nativeCopyLock) {
            leasedShareIds.remove(id)
            val stop = leasedShareIds.isEmpty() &&
                (stopWhenShareLeasesFinish || !dartBackgroundOwner)
            if (stop) stopWhenShareLeasesFinish = false
            stop
        }
        if (shouldStop) stopBackgroundWork()
    }

    private fun markPendingSharesCancelled() {
        synchronized(inboxLock) {
            val current = JSONArray(prefs().getString(PREF_SHARES, "[]") ?: "[]")
            if (current.length() == 0) return
            val next = JSONArray()
            for (index in 0 until current.length()) {
                val item = current.getJSONObject(index)
                markShareJsonCancelled(item)
                next.put(item)
            }
            prefs().edit().putString(PREF_SHARES, next.toString()).apply()
        }
    }

    private fun acknowledgeShare(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id").orEmpty()
        if (id.isBlank()) {
            result.error("invalid_share_id", "Share id is required.", null)
            return
        }
        synchronized(inboxLock) {
            val current = JSONArray(prefs().getString(PREF_SHARES, "[]") ?: "[]")
            val next = JSONArray()
            for (index in 0 until current.length()) {
                val item = current.getJSONObject(index)
                if (item.optString("id") == id) {
                    File(inboxDir(), id).deleteRecursively()
                    synchronized(nativeCopyLock) {
                        activeCancelledShareIds.remove(id)
                    }
                    releaseNativeShareLease(id)
                } else {
                    next.put(item)
                }
            }
            prefs().edit().putString(PREF_SHARES, next.toString()).apply()
        }
        result.success(null)
    }

    private fun renderPdf(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path").orEmpty()
        val startPage = call.argument<Int>("startPage") ?: 0
        val maxPages = call.argument<Int>("maxPages") ?: 4
        val file = safePrivateFile(path)
        if (file == null || file.extension.lowercase() != "pdf") {
            result.error("invalid_pdf", "PDF path must point to a local app PDF.", null)
            return
        }
        executor.execute {
            try {
                val pages = renderPdfPages(file, startPage, maxPages)
                mainHandler.post { result.success(pages) }
            } catch (error: IllegalArgumentException) {
                mainHandler.post { result.error("invalid_pdf_range", error.message, null) }
            } catch (error: Exception) {
                mainHandler.post { result.error("pdf_render_failed", error.message, null) }
            }
        }
    }

    private fun renderPdfPages(file: File, startPage: Int, maxPages: Int): Map<String, Any> {
        require(startPage >= 0) { "startPage must be zero or greater." }
        val boundedMax = maxPages.coerceIn(1, 4)
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
            PdfRenderer(descriptor).use { renderer ->
                require(startPage < renderer.pageCount) { "startPage is outside the PDF." }
                val endExclusive = min(renderer.pageCount, startPage + boundedMax)
                val images = (startPage until endExclusive).map { pageIndex ->
                    renderer.openPage(pageIndex).use { page ->
                        val pageWidth = max(1, page.width)
                        val pageHeight = max(1, page.height)
                        val scale = min(
                            1.0,
                            min(
                                min(
                                    MAX_PDF_DIMENSION.toDouble() / pageWidth,
                                    MAX_PDF_DIMENSION.toDouble() / pageHeight,
                                ),
                                sqrt(MAX_PDF_PIXELS.toDouble() / (pageWidth.toDouble() * pageHeight)),
                            ),
                        )
                        val width = max(1, (pageWidth * scale).toInt())
                        val height = max(1, (pageHeight * scale).toInt())
                        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                        try {
                            Canvas(bitmap).drawColor(Color.WHITE)
                            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            bitmap.toJpegBase64()
                        } finally {
                            bitmap.recycle()
                        }
                    }
                }
                return mapOf("pageCount" to renderer.pageCount, "images" to images)
            }
        }
    }

    private fun Bitmap.toJpegBase64(): String {
        val output = ByteArrayOutputStream()
        compress(Bitmap.CompressFormat.JPEG, 82, output)
        return android.util.Base64.encodeToString(output.toByteArray(), android.util.Base64.NO_WRAP)
    }

    private fun openUrl(call: MethodCall, result: MethodChannel.Result) {
        val uri = Uri.parse(call.argument<String>("url").orEmpty())
        if (uri.scheme !in listOf("http", "https") || uri.host.isNullOrBlank()) {
            result.error("invalid_url", "仅支持 HTTP 或 HTTPS 来源链接", null)
            return
        }
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("activity_required", "Opening URLs requires a visible Activity.", null)
            return
        }
        try {
            currentActivity.startActivity(
                Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE),
            )
            result.success(null)
        } catch (_: ActivityNotFoundException) {
            result.error("no_viewer", "未找到可以打开来源链接的浏览器", null)
        } catch (_: SecurityException) {
            result.error("open_url_failed", "系统不允许打开此来源链接", null)
        }
    }

    private fun openFile(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path").orEmpty()
        val sourceFile = safePrivateFile(path)
        if (sourceFile == null) {
            result.error("invalid_file", "File path must point to a local app file.", null)
            return
        }
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("activity_required", "Opening files requires a visible Activity.", null)
            return
        }
        executor.execute {
            try {
                val file = copyToOpenCache(sourceFile)
                mainHandler.post { launchFile(currentActivity, file, result) }
            } catch (error: Exception) {
                mainHandler.post { result.error("open_file_failed", error.message, null) }
            }
        }
    }

    private fun launchFile(currentActivity: Activity, file: File, result: MethodChannel.Result) {
        val uri = FileProvider.getUriForFile(app, "${app.packageName}.files", file)
        val mime = MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(file.extension.lowercase())
            ?: "application/octet-stream"
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, mime)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        intent.clipData = ClipData.newUri(app.contentResolver, file.name, uri)
        try {
            currentActivity.startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            result.error("no_viewer", "No app can open this file type.", null)
            return
        }
        result.success(null)
    }

    private fun safePrivateFile(path: String): File? {
        if (path.isBlank()) return null
        val file = File(path)
        if (!file.exists() || !file.isFile) return null
        val rootPath = app.filesDir.canonicalPath + File.separator
        return if (file.canonicalPath.startsWith(rootPath)) file else null
    }

    private fun copyToOpenCache(source: File): File {
        val cacheDir = File(inboxDir(), "open_cache").also {
            it.deleteRecursively()
            it.mkdirs()
        }
        val target = safeChild(cacheDir, safeFileName(source.name)) ?: File(cacheDir, "open-file")
        try {
            source.inputStream().use { input ->
                FileOutputStream(target).use { output -> copyWithLimit(input, output) }
            }
        } catch (error: Exception) {
            target.delete()
            throw error
        }
        return target
    }

    private fun appendShare(share: JSONObject): Boolean {
        synchronized(inboxLock) {
            val cancelled = synchronized(nativeCopyLock) {
                share.optBoolean("cancelled", false) ||
                    activeCancelledShareIds.contains(share.optString("id"))
            }
            if (cancelled) {
                markShareJsonCancelled(share)
            }
            val array = JSONArray(prefs().getString(PREF_SHARES, "[]") ?: "[]")
            array.put(share)
            prefs().edit().putString(PREF_SHARES, array.toString()).apply()
            return share.optBoolean("cancelled", false)
        }
    }

    private fun markShareJsonCancelled(item: JSONObject) {
        val message = "用户已取消自动分析；附件已保留，可在应用内手动重试。"
        val existing = item.optString("error")
        item.put("cancelled", true)
        if (existing.contains(message)) return
        item.put(
            "error",
            listOf(message, existing).filter { it.isNotBlank() }.joinToString("; "),
        )
    }

    private fun delayUntilNextDigest(hour: Int, minute: Int): Long {
        val now = Calendar.getInstance()
        val next = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (!after(now)) add(Calendar.DAY_OF_YEAR, 1)
        }
        return max(1_000L, next.timeInMillis - now.timeInMillis)
    }

    private fun safeFileName(name: String): String {
        val sanitized = name
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .trim('_', '.', '-')
        val extension = sanitized.substringAfterLast('.', "")
            .takeIf { it.length in 1..8 && it.all(Char::isLetterOrDigit) }
        val suffix = extension?.let { ".$it" }.orEmpty()
        val stem = if (suffix.isEmpty()) sanitized else sanitized.removeSuffix(suffix)
        return stem.take(80 - suffix.length).ifBlank { "shared-file" } + suffix
    }

    private fun safeChild(parent: File, childName: String): File? {
        val child = File(parent, childName)
        val parentPath = parent.canonicalPath + File.separator
        return if (child.canonicalPath.startsWith(parentPath)) child else null
    }

    private fun copyWithLimit(input: java.io.InputStream, output: java.io.OutputStream) {
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0L
        while (true) {
            val read = input.read(buffer)
            if (read == -1) return
            total += read
            if (total > MAX_FILE_BYTES) {
                throw IllegalArgumentException("File exceeds 50 MB limit.")
            }
            output.write(buffer, 0, read)
        }
    }

    private fun inboxDir(): File = File(app.filesDir, "shared_inbox").also { it.mkdirs() }

    private fun prefs() = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun notificationManager() =
        app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private data class CopyResult(
        val path: String? = null,
        val error: String? = null,
    )

    private data class ProgressSnapshot(
        val jobId: String = "",
        val title: String = "",
        val stage: String = "",
        val completed: Int? = null,
        val total: Int? = null,
    ) {
        fun body(): String {
            val progress = if (completed != null && total != null && total > 0) {
                " $completed/$total"
            } else {
                ""
            }
            return listOf(stage, progress.trim()).filter { it.isNotBlank() }.joinToString(" ")
        }
    }

    companion object {
        const val ENGINE_ID = "readlater_engine"
        private const val CHANNEL = "readlater/native"
        private const val PREFS = "readlater_native"
        private const val PREF_SHARES = "shares"
        private const val PREF_DIGEST_ENABLED = "digest_enabled"
        private const val PREF_DIGEST_HOUR = "digest_hour"
        private const val PREF_DIGEST_MINUTE = "digest_minute"
        private const val CHANNEL_RUNNING = "readlater_running"
        private const val CHANNEL_RESULTS = "readlater_results"
        private const val CHANNEL_DIGEST = "readlater_digest"
        private const val CHANNEL_RESEARCH = "readlater_research"
        private const val GROUP_RESULTS = "readlater_group_results"
        const val ACTION_CANCEL = "app.readlater.readlater.action.CANCEL_BACKGROUND"
        private const val ACTION_OPEN_NOTIFICATION = "app.readlater.readlater.action.OPEN_NOTIFICATION"
        private const val EXTRA_ENTITY_TYPE = "entityType"
        private const val EXTRA_ENTITY_ID = "entityId"
        private const val NOTIFICATION_ID = 42021
        private const val RUNNING_NOTIFICATION_ID = 42022
        private const val NOTIFICATION_REQUEST_CODE = 421
        private const val DIGEST_JOB_ID = 42023
        private const val RESULTS_SUMMARY_NOTIFICATION_ID = 42024
        private const val MAX_SHARED_FILES = 20
        private const val MAX_FILE_BYTES = 50L * 1024L * 1024L
        private const val MAX_PDF_DIMENSION = 2000
        private const val MAX_PDF_PIXELS = 2_000_000
        private const val MAX_RECENT_RUNTIME_EVENTS = 8
    }
}

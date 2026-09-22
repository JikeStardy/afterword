package app.readlater.readlater

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {
    private val inboxLock = Any()
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private var nativeChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIncomingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nativeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        nativeChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "pendingShares" -> result.success(pendingShares())
                "acknowledgeShare" -> acknowledgeShare(call, result)
                "renderPdf" -> renderPdf(call, result)
                "requestNotificationPermission" -> {
                    requestNotificationPermission()
                    result.success(null)
                }
                "notify" -> notify(call, result)
                "openFile" -> openFile(call, result)
                "openUrl" -> openUrl(call, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        nativeChannel = null
        executor.shutdown()
        super.onDestroy()
    }

    private fun handleIncomingIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: return
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return

        val text = intent.getStringExtra(Intent.EXTRA_TEXT).orEmpty()
        val allUris = sharedUris(intent)
        if (text.isBlank() && allUris.isEmpty()) return

        executor.execute {
            val id = "${System.currentTimeMillis()}-${UUID.randomUUID()}"
            val shareDir = File(inboxDir(), id).also { it.mkdirs() }
            val errors = mutableListOf<String>()
            if (allUris.size > MAX_SHARED_FILES) {
                errors.add("Only the first $MAX_SHARED_FILES shared files were imported.")
            }
            val copyResults = allUris.take(MAX_SHARED_FILES)
                .mapIndexed { index, uri -> copySharedUri(uri, shareDir, index) }
            val paths = copyResults.mapNotNull { copy -> copy.path }
            errors.addAll(copyResults.mapNotNull { copy -> copy.error })
            val share = JSONObject()
                .put("id", id)
                .put("text", text)
                .put("paths", JSONArray(paths))
                .put("error", errors.joinToString("; "))
            appendShare(share)
            runOnUiThread { nativeChannel?.invokeMethod("sharesReady", null) }
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
                listOf("pdf", "png", "jpg", "jpeg", "webp", "gif")) "" else extensionFor(uri)
            val destination = safeChild(shareDir, "${index + 1}-$name$extension")
                ?: return CopyResult(error = "附件名称无效，无法导入。")
            target = destination
            contentResolver.openInputStream(uri)?.use { input ->
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
        return contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (!cursor.moveToFirst()) return@use null
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) cursor.getString(index) else null
            }
    }

    private fun extensionFor(uri: Uri): String {
        val mime = contentResolver.getType(uri).orEmpty()
        val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime)
        return if (extension.isNullOrBlank()) ".bin" else ".$extension"
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
                )
            }
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
                runOnUiThread { result.success(pages) }
            } catch (error: IllegalArgumentException) {
                runOnUiThread { result.error("invalid_pdf_range", error.message, null) }
            } catch (error: Exception) {
                runOnUiThread { result.error("pdf_render_failed", error.message, null) }
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

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST_CODE)
        }
    }

    private fun notify(call: MethodCall, result: MethodChannel.Result) {
        val title = call.argument<String>("title").orEmpty()
        val body = call.argument<String>("body").orEmpty()
        if (title.isBlank() && body.isBlank()) {
            result.error("invalid_notification", "Notification title or body is required.", null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            result.success(null)
            return
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL,
                    "Readlater",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        manager.notify(
            NOTIFICATION_ID,
            builder
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title.ifBlank { "Readlater" })
                .setContentText(body)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .build(),
        )
        result.success(null)
    }

    private fun openUrl(call: MethodCall, result: MethodChannel.Result) {
        val uri = Uri.parse(call.argument<String>("url").orEmpty())
        if (uri.scheme !in listOf("http", "https") || uri.host.isNullOrBlank()) {
            result.error("invalid_url", "仅支持 HTTP 或 HTTPS 来源链接", null)
            return
        }
        try {
            startActivity(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE))
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
        executor.execute {
            try {
                val file = copyToOpenCache(sourceFile)
                runOnUiThread { launchFile(file, result) }
            } catch (error: Exception) {
                runOnUiThread { result.error("open_file_failed", error.message, null) }
            }
        }
    }

    private fun launchFile(file: File, result: MethodChannel.Result) {
        val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
        val mime = MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(file.extension.lowercase())
            ?: "application/octet-stream"
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, mime)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        intent.clipData = ClipData.newUri(contentResolver, file.name, uri)
        try {
            startActivity(intent)
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
        val rootPath = filesDir.canonicalPath + File.separator
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

    private data class CopyResult(
        val path: String? = null,
        val error: String? = null,
    )

    private fun appendShare(share: JSONObject) {
        synchronized(inboxLock) {
            val array = JSONArray(prefs().getString(PREF_SHARES, "[]") ?: "[]")
            array.put(share)
            prefs().edit().putString(PREF_SHARES, array.toString()).apply()
        }
    }

    private fun inboxDir(): File = File(filesDir, "shared_inbox").also { it.mkdirs() }

    private fun prefs() = getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    companion object {
        private const val CHANNEL = "readlater/native"
        private const val PREFS = "readlater_native"
        private const val PREF_SHARES = "shares"
        private const val NOTIFICATION_CHANNEL = "readlater_updates"
        private const val NOTIFICATION_ID = 42021
        private const val NOTIFICATION_REQUEST_CODE = 421
        private const val MAX_SHARED_FILES = 20
        private const val MAX_FILE_BYTES = 50L * 1024L * 1024L
        private const val MAX_PDF_DIMENSION = 2000
        private const val MAX_PDF_PIXELS = 2_000_000
    }
}

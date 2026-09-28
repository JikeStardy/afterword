package app.readlater.readlater

import android.app.Activity
import android.app.Dialog
import android.graphics.Color
import android.net.Uri
import android.net.http.SslError
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.net.URI
import java.util.concurrent.atomic.AtomicBoolean

class WebArticleCaptureDialog(
    private val activity: Activity,
    private val initialUrl: String,
    private val onComplete: (Map<String, String>?) -> Unit,
    private val onClosed: () -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())
    private val closed = AtomicBoolean(false)
    private var navigationGeneration = 0
    private var loadFailed = false
    private var extracting = false
    private var extractToken = 0
    private var activeExtractToken: Int? = null
    private var lastFinishedUrl: String? = null
    private var timeoutRunnable: Runnable? = null
    private var extractTimeoutRunnable: Runnable? = null
    private var probeToken = 0
    private var activeProbeToken: Int? = null
    private var autoCaptureGeneration: Int? = null
    private var probeRunnable: Runnable? = null
    private var probeTimeoutRunnable: Runnable? = null
    private var autoCaptureDeadline = 0L
    private var stableSignature: String? = null
    private var stableSince = 0L

    private lateinit var dialog: Dialog
    private lateinit var webView: WebView
    private lateinit var addressView: TextView
    private lateinit var statusView: TextView
    private lateinit var progressBar: ProgressBar
    private lateinit var saveButton: Button
    private lateinit var retryButton: Button

    fun show() {
        dialog = Dialog(activity)
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)
        dialog.setContentView(buildContent())
        dialog.setOnCancelListener { closeWithCancel() }
        dialog.setOnDismissListener { releaseWebView() }
        configureWebView()
        dialog.show()
        dialog.window?.setLayout(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        updateStatus("页面加载中，正文加载完成后会自动保存。", busy = true)
        load(initialUrl)
    }

    fun cancelFromHost() {
        closeWithCancel()
    }

    fun disposeSilently() {
        closed.set(true)
        cancelLoadTimeout()
        cancelExtractTimeout()
        cancelAutoCapture()
        releaseWebView()
        if (::dialog.isInitialized && dialog.isShowing) {
            dialog.dismiss()
        }
    }

    private fun buildContent(): View {
        val root = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(WARM_WHITE)
            setPadding(dp(16), dp(14), dp(16), dp(12))
        }
        root.addView(
            TextView(activity).apply {
                text = "保存微信公众号正文"
                setTextColor(DEEP_GREEN)
                textSize = 18f
            },
        )
        root.addView(
            TextView(activity).apply {
                text = "正文加载完成后会自动保存。如需微信验证，请在下方页面完成；也可手动保存。"
                setTextColor(TEXT_MUTED)
                textSize = 14f
                setPadding(0, dp(6), 0, dp(8))
            },
        )
        addressView = TextView(activity).apply {
            setTextColor(TEXT_DARK)
            textSize = 12f
            maxLines = 2
        }
        root.addView(addressView)
        progressBar = ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal).apply {
            isIndeterminate = true
        }
        root.addView(
            progressBar,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(4),
            ).apply { setMargins(0, dp(8), 0, dp(8)) },
        )
        statusView = TextView(activity).apply {
            setTextColor(TEXT_MUTED)
            textSize = 13f
        }
        root.addView(statusView)
        webView = WebView(activity)
        root.addView(
            webView,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ).apply { setMargins(0, dp(12), 0, dp(12)) },
        )
        val actions = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
        }
        val cancelButton = Button(activity).apply {
            text = "取消"
            setOnClickListener { closeWithCancel() }
        }
        retryButton = Button(activity).apply {
            text = "重试"
            visibility = View.GONE
            setOnClickListener { load(initialUrl) }
        }
        saveButton = Button(activity).apply {
            text = "保存正文"
            isEnabled = false
            setTextColor(Color.WHITE)
            setBackgroundColor(DEEP_GREEN)
            setOnClickListener { extractHtml() }
        }
        actions.addView(
            cancelButton,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
        )
        actions.addView(
            retryButton,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
        )
        actions.addView(
            saveButton,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
        )
        root.addView(actions)
        return root
    }

    private fun configureWebView() {
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
            databaseEnabled = false
            cacheMode = WebSettings.LOAD_NO_CACHE
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                safeBrowsingEnabled = true
            }
        }
        webView.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                progressBar.isIndeterminate = newProgress < 100
                if (newProgress >= 100) progressBar.progress = 100
            }

            override fun onCreateWindow(
                view: WebView?,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: android.os.Message?,
            ): Boolean {
                updateStatus("已阻止弹出窗口。", busy = false, failed = true)
                return false
            }
        }
        webView.setDownloadListener { _, _, _, _, _ ->
            updateStatus("已阻止下载。请仅保存页面正文。", busy = false, failed = true)
        }
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?,
            ): Boolean {
                val url = request?.url?.toString().orEmpty()
                if (!request.isMainFrameOrTrue()) return blocksUnsafeSubresource(url)
                if (!isAllowedWeChatArticleUrl(url)) {
                    updateStatus("已阻止跳转到非微信公众号文章地址。", busy = false, failed = true)
                    return true
                }
                return false
            }

            override fun shouldInterceptRequest(
                view: WebView?,
                request: WebResourceRequest?,
            ): WebResourceResponse? {
                val url = request?.url?.toString().orEmpty()
                val mainFrame = request.isMainFrameOrTrue()
                if ((mainFrame && !isAllowedWeChatArticleUrl(url)) ||
                    (!mainFrame && blocksUnsafeSubresource(url))
                ) {
                    return emptyBlockedResponse()
                }
                return null
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                navigationGeneration++
                cancelAutoCapture()
                cancelActiveExtraction()
                loadFailed = false
                lastFinishedUrl = null
                saveButton.isEnabled = false
                retryButton.visibility = View.GONE
                updateAddress(url.orEmpty())
                updateStatus("页面加载中，正文加载完成后会自动保存。", busy = true)
                scheduleLoadTimeout(navigationGeneration)
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                val pageUrl = url.orEmpty()
                if (closed.get() || loadFailed || !isAllowedWeChatArticleUrl(pageUrl) ||
                    pageUrl != webView.url.orEmpty() || lastFinishedUrl == pageUrl
                ) return
                cancelLoadTimeout()
                lastFinishedUrl = pageUrl
                updateAddress(pageUrl)
                saveButton.isEnabled = true
                updateStatus("正在等待正文加载完成；如需验证，请在页面中完成。", busy = false)
                startAutoCapture()
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?,
            ) {
                if (!request.isMainFrameOrTrue()) return
                cancelLoadTimeout()
                loadFailed = true
                saveButton.isEnabled = false
                updateStatus("页面加载失败，请检查网络后重试。", busy = false, failed = true)
            }

            override fun onReceivedHttpError(
                view: WebView?,
                request: WebResourceRequest?,
                errorResponse: WebResourceResponse?,
            ) {
                if (!request.isMainFrameOrTrue()) return
                cancelLoadTimeout()
                loadFailed = true
                saveButton.isEnabled = false
                val code = errorResponse?.statusCode ?: 0
                val suffix = if (code > 0) "（HTTP $code）" else ""
                updateStatus("页面加载失败$suffix，请重试。", busy = false, failed = true)
            }

            override fun onReceivedSslError(
                view: WebView?,
                handler: SslErrorHandler?,
                error: SslError?,
            ) {
                handler?.cancel()
                cancelLoadTimeout()
                loadFailed = true
                saveButton.isEnabled = false
                updateStatus("证书校验失败，已停止加载。", busy = false, failed = true)
            }
        }
    }

    private fun load(url: String) {
        if (closed.get()) return
        navigationGeneration++
        lastFinishedUrl = null
        cancelLoadTimeout()
        cancelAutoCapture()
        cancelActiveExtraction()
        loadFailed = false
        extracting = false
        activeExtractToken = null
        retryButton.visibility = View.GONE
        saveButton.isEnabled = false
        webView.stopLoading()
        webView.loadUrl(url)
    }

    private fun extractHtml(expectedSignature: String? = null) {
        if (closed.get() || extracting) return
        if (expectedSignature == null) cancelAutoCapture()
        val expectedGeneration = navigationGeneration
        val expectedUrl = webView.url.orEmpty()
        if (!isAllowedWeChatArticleUrl(expectedUrl) || expectedUrl != lastFinishedUrl) {
            updateStatus("当前页面地址已变化，请等待加载完成后再保存。", busy = false, failed = true)
            return
        }
        extracting = true
        val token = ++extractToken
        activeExtractToken = token
        saveButton.isEnabled = false
        updateStatus("正在提取正文。", busy = true)
        scheduleExtractTimeout(expectedGeneration, token)
        val script = expectedSignature?.let(::automaticExtractionScript) ?: EXTRACT_SCRIPT
        webView.evaluateJavascript(script) { raw ->
            handler.post {
                handleExtractResult(expectedGeneration, expectedUrl, token, raw, expectedSignature != null)
            }
        }
    }

    private fun handleExtractResult(
        expectedGeneration: Int,
        expectedUrl: String,
        token: Int,
        raw: String?,
        automatic: Boolean,
    ) {
        if (closed.get()) return
        if (activeExtractToken != token) return
        if (automatic && (activeProbeToken == null || SystemClock.uptimeMillis() >= autoCaptureDeadline)) {
            clearActiveExtraction(token)
            if (activeProbeToken != null) {
                finishAutoCaptureWait()
            } else {
                saveButton.isEnabled = !loadFailed && expectedUrl == lastFinishedUrl &&
                    expectedUrl == webView.url.orEmpty()
            }
            return
        }
        if (loadFailed) {
            clearActiveExtraction(token)
            return
        }
        if (expectedGeneration != navigationGeneration || expectedUrl != webView.url.orEmpty()) {
            clearActiveExtraction(token)
            updateStatus("页面已变化，请重新确认后保存。", busy = false, failed = true)
            return
        }
        clearActiveExtraction(token)
        val payload = decodeJavascriptString(raw)
        val json = runCatching { JSONObject(payload) }.getOrNull()
        if (json == null) {
            saveButton.isEnabled = true
            updateStatus("正文提取失败，请重试。", busy = false, failed = true)
            return
        }
        val pageUrl = json.optString("url")
        if (!isAllowedWeChatArticleUrl(pageUrl) || pageUrl != webView.url.orEmpty()) {
            saveButton.isEnabled = true
            updateStatus("页面地址校验失败，请重试。", busy = false, failed = true)
            return
        }
        if (!sameArticle(initialUrl, pageUrl)) {
            saveButton.isEnabled = true
            updateStatus("已跳转到其他文章，请返回原文章或另行收藏。", busy = false, failed = true)
            return
        }
        val error = json.optString("error")
        if (error.isNotBlank()) {
            saveButton.isEnabled = true
            if (automatic && error == "content_changed") {
                // Keep the original deadline while the new document stabilizes.
                stableSignature = null
                stableSince = 0L
                val probe = activeProbeToken ?: return
                if (isCurrentProbe(probe, expectedGeneration, expectedUrl)) {
                    updateStatus("正文仍在更新，加载完成后会自动保存。", busy = false)
                    scheduleProbe(probe, expectedGeneration, expectedUrl)
                }
                return
            }
            val message = when (error) {
                "missing_content" -> "未找到可保存的公众号正文，请完成验证后重试。"
                "too_large" -> "页面正文超过 5 MiB，无法通过回退窗口保存。"
                else -> "正文提取失败，请重试。"
            }
            updateStatus(message, busy = false, failed = true)
            return
        }
        val html = json.optString("html")
        if (html.isBlank()) {
            saveButton.isEnabled = true
            updateStatus("未找到可保存的公众号正文，请完成验证后重试。", busy = false, failed = true)
            return
        }
        if (html.toByteArray(Charsets.UTF_8).size > MAX_HTML_BYTES) {
            saveButton.isEnabled = true
            updateStatus("页面正文超过 5 MiB，无法通过回退窗口保存。", busy = false, failed = true)
            return
        }
        closeWithResult(
            mapOf(
                "url" to pageUrl,
                "html" to html,
            ),
        )
    }

    private fun updateStatus(message: String, busy: Boolean, failed: Boolean = false) {
        if (failed) cancelAutoCapture()
        statusView.text = message
        statusView.setTextColor(if (failed) ERROR_RED else TEXT_MUTED)
        progressBar.visibility = if (busy) View.VISIBLE else View.GONE
        if (failed) retryButton.visibility = View.VISIBLE
    }

    private fun updateAddress(url: String) {
        addressView.text = url.ifBlank { initialUrl }
    }

    private fun startAutoCapture() {
        // Duplicate page-finished events must not extend the automatic window.
        if (autoCaptureGeneration == navigationGeneration || closed.get() || extracting) return
        val expectedUrl = lastFinishedUrl ?: return
        if (!sameArticle(initialUrl, expectedUrl)) return
        val generation = navigationGeneration
        autoCaptureGeneration = generation
        val token = ++probeToken
        activeProbeToken = token
        autoCaptureDeadline = SystemClock.uptimeMillis() + AUTO_CAPTURE_TIMEOUT_MS
        probeTimeoutRunnable = Runnable {
            if (closed.get() || activeProbeToken != token) return@Runnable
            finishAutoCaptureWait()
        }.also { handler.postDelayed(it, AUTO_CAPTURE_TIMEOUT_MS) }
        probeForArticle(token, generation, expectedUrl)
    }

    private fun isCurrentProbe(token: Int, generation: Int, expectedUrl: String): Boolean =
        !closed.get() && !loadFailed && !extracting && activeProbeToken == token &&
            SystemClock.uptimeMillis() < autoCaptureDeadline &&
            navigationGeneration == generation && lastFinishedUrl == expectedUrl &&
            webView.url.orEmpty() == expectedUrl

    private fun probeForArticle(token: Int, generation: Int, expectedUrl: String) {
        if (!isCurrentProbe(token, generation, expectedUrl)) return
        webView.evaluateJavascript(PROBE_SCRIPT) { raw ->
            handler.post {
                if (!isCurrentProbe(token, generation, expectedUrl)) return@post
                val json = runCatching { JSONObject(decodeJavascriptString(raw)) }.getOrNull()
                val signature = json?.optString("signature").orEmpty()
                if (json?.optString("url") == expectedUrl &&
                    json.optBoolean("ready") && signature.isNotEmpty()
                ) {
                    val now = SystemClock.uptimeMillis()
                    if (signature != stableSignature) {
                        stableSignature = signature
                        stableSince = now
                    } else if (now - stableSince >= AUTO_CAPTURE_STABLE_MS) {
                        extractHtml(expectedSignature = signature)
                        return@post
                    }
                } else {
                    stableSignature = null
                    stableSince = 0L
                }
                scheduleProbe(token, generation, expectedUrl)
            }
        }
    }

    private fun scheduleProbe(token: Int, generation: Int, expectedUrl: String) {
        probeRunnable = Runnable {
            probeForArticle(token, generation, expectedUrl)
        }.also { handler.postDelayed(it, AUTO_CAPTURE_PROBE_MS) }
    }

    private fun finishAutoCaptureWait() {
        cancelAutoCapture()
        cancelActiveExtraction()
        saveButton.isEnabled = !loadFailed && lastFinishedUrl == webView.url.orEmpty()
        updateStatus("暂未自动保存。请完成验证并确认正文可见后，点击保存正文。", busy = false)
    }

    private fun cancelAutoCapture() {
        activeProbeToken = null
        probeRunnable?.let(handler::removeCallbacks)
        probeTimeoutRunnable?.let(handler::removeCallbacks)
        probeRunnable = null
        probeTimeoutRunnable = null
        autoCaptureDeadline = 0L
        stableSignature = null
        stableSince = 0L
    }

    private fun scheduleLoadTimeout(generation: Int) {
        cancelLoadTimeout()
        timeoutRunnable = Runnable {
            if (closed.get() || generation != navigationGeneration || lastFinishedUrl != null) return@Runnable
            loadFailed = true
            webView.stopLoading()
            saveButton.isEnabled = false
            updateStatus("页面加载超时，请重试。", busy = false, failed = true)
        }.also { handler.postDelayed(it, LOAD_TIMEOUT_MS) }
    }

    private fun cancelLoadTimeout() {
        timeoutRunnable?.let(handler::removeCallbacks)
        timeoutRunnable = null
    }

    private fun scheduleExtractTimeout(generation: Int, token: Int) {
        cancelExtractTimeout()
        extractTimeoutRunnable = Runnable {
            if (closed.get() || generation != navigationGeneration || activeExtractToken != token) {
                return@Runnable
            }
            extracting = false
            activeExtractToken = null
            saveButton.isEnabled = true
            updateStatus("正文提取超时，请重试。", busy = false, failed = true)
        }.also { handler.postDelayed(it, EXTRACT_TIMEOUT_MS) }
    }

    private fun cancelExtractTimeout() {
        extractTimeoutRunnable?.let(handler::removeCallbacks)
        extractTimeoutRunnable = null
    }

    private fun cancelActiveExtraction() {
        if (!extracting && activeExtractToken == null) return
        activeExtractToken = null
        extracting = false
        cancelExtractTimeout()
    }

    private fun clearActiveExtraction(token: Int) {
        if (activeExtractToken == token) {
            activeExtractToken = null
        }
        extracting = false
        cancelExtractTimeout()
    }

    private fun closeWithResult(value: Map<String, String>) {
        if (!closed.compareAndSet(false, true)) return
        cancelLoadTimeout()
        cancelExtractTimeout()
        cancelAutoCapture()
        onComplete(value)
        if (::dialog.isInitialized) dialog.dismiss()
    }

    private fun closeWithCancel() {
        if (!closed.compareAndSet(false, true)) return
        cancelLoadTimeout()
        cancelExtractTimeout()
        cancelAutoCapture()
        onClosed()
        if (::dialog.isInitialized) {
            dialog.dismiss()
        } else {
            releaseWebView()
        }
    }

    private fun releaseWebView() {
        cancelLoadTimeout()
        cancelExtractTimeout()
        cancelAutoCapture()
        if (::webView.isInitialized) {
            webView.stopLoading()
            webView.webChromeClient = null
            webView.webViewClient = WebViewClient()
            webView.removeAllViews()
            webView.destroy()
        }
    }

    private fun WebResourceRequest?.isMainFrameOrTrue(): Boolean =
        this?.isForMainFrame ?: true

    private fun blocksUnsafeSubresource(url: String): Boolean {
        val uri = safeUri(url) ?: return true
        return uri.scheme != "https" ||
            uri.userInfo != null ||
            (uri.port != -1 && uri.port != 443) ||
            uri.host.isNullOrBlank()
    }

    private fun emptyBlockedResponse(): WebResourceResponse =
        WebResourceResponse(
            "text/plain",
            "UTF-8",
            ByteArrayInputStream(ByteArray(0)),
        )

    private fun decodeJavascriptString(raw: String?): String {
        if (raw.isNullOrBlank() || raw == "null") return ""
        return runCatching { JSONArray("[$raw]").getString(0) }.getOrElse { "" }
    }

    private fun dp(value: Int): Int =
        (value * activity.resources.displayMetrics.density).toInt()

    companion object {
        private const val WECHAT_HOST = "mp.weixin.qq.com"
        private const val MAX_HTML_BYTES = 5 * 1024 * 1024
        private const val LOAD_TIMEOUT_MS = 45_000L
        private const val EXTRACT_TIMEOUT_MS = 10_000L
        private const val AUTO_CAPTURE_TIMEOUT_MS = 60_000L
        private const val AUTO_CAPTURE_STABLE_MS = 2_000L
        private const val AUTO_CAPTURE_PROBE_MS = 500L
        private const val WARM_WHITE = 0xFFFAF8F3.toInt()
        private const val DEEP_GREEN = 0xFF476B4F.toInt()
        private const val TEXT_DARK = 0xFF27352B.toInt()
        private const val TEXT_MUTED = 0xFF5F6F64.toInt()
        private const val ERROR_RED = 0xFF9C2F2F.toInt()
        private sealed interface ArticleIdentity {
            data class SlugPath(val path: String) : ArticleIdentity
            data class QueryKey(val biz: String, val mid: String, val idx: String) : ArticleIdentity
            data class ExactUrl(val url: String) : ArticleIdentity
        }

        private val PROBE_SCRIPT = """
            (function() {
              var result = { ready: false, url: location.href };
              if (document.readyState !== 'complete' || document.visibilityState !== 'visible') return JSON.stringify(result);
              var content = document.querySelector('#js_content');
              if (!content || !content.getClientRects().length) return JSON.stringify(result);
              for (var element = content; element; element = element.parentElement) {
                var style = getComputedStyle(element);
                if (style.display === 'none' || style.visibility === 'hidden' || style.visibility === 'collapse' || Number(style.opacity) === 0) return JSON.stringify(result);
              }
              var text = (content.textContent || '').trim();
              if (!text || !(content.innerText || '').trim()) return JSON.stringify(result);
              var images = Array.prototype.map.call(content.querySelectorAll('img'), function(image) {
                return ['src', 'data-src', 'srcset', 'data-srcset'].map(function(name) {
                  return image.getAttribute(name) || '';
                }).concat(image.currentSrc || '');
              });
              // Exact text and image values detect even equal-length hydration changes.
              var signature = JSON.stringify([document.title || '', text, images]);
              if (signature.length > $MAX_HTML_BYTES) return JSON.stringify(result);
              result.ready = true;
              result.signature = signature;
              return JSON.stringify(result);
            })();
        """.trimIndent()

        private val EXTRACT_SCRIPT = """
            (function() {
              var limit = $MAX_HTML_BYTES;
              var content = document.querySelector('#js_content');
              if (!content || !content.textContent || !content.textContent.trim()) {
                return JSON.stringify({ error: 'missing_content', url: location.href });
              }
              var html = document.documentElement ? document.documentElement.outerHTML : '';
              var size = 0;
              try {
                size = new Blob([html]).size;
              } catch (e) {
                size = html.length * 2;
              }
              if (size > limit) {
                return JSON.stringify({ error: 'too_large', url: location.href });
              }
              return JSON.stringify({
                url: location.href,
                title: document.title || '',
                html: '<!doctype html>\n' + html
              });
            })();
        """.trimIndent()

        private fun automaticExtractionScript(expectedSignature: String): String {
            val probeExpression = PROBE_SCRIPT.removeSuffix(";")
            val captureExpression = EXTRACT_SCRIPT.removeSuffix(";")
            // Readiness, exact signature and HTML are read in one synchronous JS task.
            return """
                (function() {
                  var readiness = JSON.parse($probeExpression);
                  if (!readiness.ready || readiness.signature !== ${JSONObject.quote(expectedSignature)}) {
                    return JSON.stringify({ error: 'content_changed', url: location.href });
                  }
                  return $captureExpression;
                })();
            """.trimIndent()
        }

        fun validateWeChatArticleUrl(url: String): String? {
            val uri = safeUri(url) ?: return null
            return if (isAllowedUri(uri)) uri.toASCIIString() else null
        }

        fun isAllowedWeChatArticleUrl(url: String): Boolean {
            val uri = safeUri(url) ?: return false
            return isAllowedUri(uri)
        }

        fun sameArticle(initialUrl: String, finalUrl: String): Boolean {
            val initial = articleIdentity(initialUrl) ?: return false
            val final = articleIdentity(finalUrl) ?: return false
            return when {
                initial is ArticleIdentity.SlugPath && final is ArticleIdentity.SlugPath ->
                    initial.path == final.path
                initial is ArticleIdentity.QueryKey && final is ArticleIdentity.QueryKey ->
                    initial == final
                initial is ArticleIdentity.ExactUrl && final is ArticleIdentity.ExactUrl ->
                    initial.url == final.url
                else -> false
            }
        }

        private fun isAllowedUri(uri: URI): Boolean =
            uri.scheme == "https" &&
                uri.host?.equals(WECHAT_HOST, ignoreCase = true) == true &&
                uri.userInfo == null &&
                (uri.port == -1 || uri.port == 443)

        private fun articleIdentity(url: String): ArticleIdentity? {
            val uri = safeUri(url) ?: return null
            if (!isAllowedUri(uri)) return null
            val path = uri.rawPath.orEmpty()
            if (path.startsWith("/s/") && path.length > "/s/".length) {
                return ArticleIdentity.SlugPath(path)
            }
            if (path == "/s") {
                val androidUri = Uri.parse(uri.toASCIIString())
                val biz = androidUri.getQueryParameter("__biz")?.takeIf { it.isNotBlank() }
                val mid = androidUri.getQueryParameter("mid")?.takeIf { it.isNotBlank() }
                val idx = androidUri.getQueryParameter("idx")?.takeIf { it.isNotBlank() } ?: "1"
                if (biz != null && mid != null) {
                    return ArticleIdentity.QueryKey(biz, mid, idx)
                }
            }
            return ArticleIdentity.ExactUrl(stripFragment(uri))
        }

        private fun stripFragment(uri: URI): String =
            URI(
                uri.scheme,
                uri.userInfo,
                uri.host,
                uri.port,
                uri.path,
                uri.query,
                null,
            ).toASCIIString()

        private fun safeUri(url: String): URI? =
            runCatching { Uri.parse(url).normalizeScheme().toString() }
                .mapCatching { URI(it) }
                .getOrNull()
    }
}

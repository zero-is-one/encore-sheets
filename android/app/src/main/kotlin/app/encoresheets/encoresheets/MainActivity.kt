package app.encoresheets.encoresheets

import android.app.Activity
import android.content.Intent
import android.hardware.display.DisplayManager
import android.net.Uri
import android.provider.OpenableColumns
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingBackup: Pair<File, MethodChannel.Result>? = null
    private var pendingScan: MethodChannel.Result? = null
    private var importChannel: MethodChannel? = null
    private var linksChannel: MethodChannel? = null
    private val pendingLinks = mutableListOf<String>()
    private var scorePresentation: ScorePresentation? = null
    private val sharedPdfs = mutableListOf<Uri>()

    @Suppress("DEPRECATION")
    private fun collectPdfs(intent: Intent) {
        if (intent.action !in listOf(Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE)) return
        val uris = if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM).orEmpty()
        } else {
            listOfNotNull(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
        }
        val clips = intent.clipData
        val received = (uris + (0 until (clips?.itemCount ?: 0)).mapNotNull {
            clips?.getItemAt(it)?.uri
        }).filter { it.scheme == "content" }.distinct()
        sharedPdfs.addAll(received)
        intent.action = null
        if (received.isNotEmpty()) importChannel?.invokeMethod("available", null)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        collectPdfs(intent)
        collectScoreLink(intent)
    }

    private fun collectScoreLink(intent: Intent) {
        if (intent.action != Intent.ACTION_VIEW || intent.data?.scheme != "encoresheets") return
        val link = intent.dataString?.takeIf { it.length <= 2048 } ?: return
        if (pendingLinks.size >= 8) pendingLinks.removeAt(0)
        pendingLinks.add(link)
        intent.action = null
        linksChannel?.invokeMethod("available", null)
    }

    override fun onDestroy() {
        scorePresentation?.dismiss()
        scorePresentation = null
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun beginScan(result: MethodChannel.Result) {
        if (pendingScan != null) {
            result.error("scan_pending", "A scan is already open.", null)
            return
        }
        pendingScan = result
        val options = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(true)
            .setPageLimit(50)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_PDF)
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .build()
        GmsDocumentScanning.getClient(options).getStartScanIntent(this)
            .addOnSuccessListener { sender ->
                try {
                    startIntentSenderForResult(sender, SCAN_REQUEST, null, 0, 0, 0)
                } catch (error: Exception) {
                    pendingScan = null
                    result.error("scan_start", error.message, null)
                }
            }
            .addOnFailureListener { error ->
                pendingScan = null
                result.error("scan_unavailable", error.message, null)
            }
    }

    private fun finishScan(resultCode: Int, data: Intent?) {
        val result = pendingScan ?: return
        if (resultCode == Activity.RESULT_CANCELED) {
            pendingScan = null
            result.success(null)
            return
        }
        val pdf = GmsDocumentScanningResult.fromActivityResultIntent(data)?.pdf
        if (resultCode != Activity.RESULT_OK || pdf == null) {
            pendingScan = null
            result.error("scan_result", "The scanner did not return a PDF.", null)
            return
        }
        Thread {
            try {
                val file = File.createTempFile("score-scan-", ".pdf", cacheDir)
                val input = contentResolver.openInputStream(pdf.uri)
                    ?: error("Could not open the scanned PDF.")
                input.use { source -> file.outputStream().use { source.copyTo(it) } }
                runOnUiThread {
                    pendingScan = null
                    result.success(file.path)
                }
            } catch (error: Exception) {
                runOnUiThread {
                    pendingScan = null
                    result.error("scan_copy", error.message, null)
                }
            }
        }.start()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        linksChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "encoresheets/links")
        linksChannel?.setMethodCallHandler { call, result ->
            if (call.method == "take") {
                result.success(pendingLinks.toList())
                pendingLinks.clear()
            } else {
                result.notImplemented()
            }
        }
        collectScoreLink(intent)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "encoresheets/presentation")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "hide" -> {
                            scorePresentation?.dismiss()
                            scorePresentation = null
                            result.success(null)
                        }
                        "show" -> {
                            val path = requireNotNull(call.argument<String>("path"))
                            val page = call.argument<Int>("page") ?: 1
                            val manager = getSystemService(DisplayManager::class.java)
                            val display = manager.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
                                .firstOrNull()
                            if (display == null) {
                                result.error("missing_display", "Connect a supported second display.", null)
                                return@setMethodCallHandler
                            }
                            val presentation = scorePresentation?.takeIf { it.isShowing }
                                ?: ScorePresentation(this, display).also { it.show() }
                            scorePresentation = presentation
                            presentation.showPage(path, page - 1)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    scorePresentation?.dismiss()
                    scorePresentation = null
                    result.error("presentation_unavailable", error.message, null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "encoresheets/score-windows")
            .setMethodCallHandler { call, result ->
                val path = call.argument<String>("path")
                if (call.method != "open" || path == null) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    startActivity(Intent(this, ScoreWindowActivity::class.java).apply {
                        putExtra("path", path)
                        putExtra("title", call.argument<String>("title"))
                        putExtra("page", call.argument<Int>("page") ?: 1)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT or
                            Intent.FLAG_ACTIVITY_MULTIPLE_TASK or
                            Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT)
                    })
                    result.success(null)
                } catch (error: Exception) {
                    result.error("window_unavailable", error.message, null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "encoresheets/scanner")
            .setMethodCallHandler { call, result ->
                if (call.method == "scan") beginScan(result) else result.notImplemented()
            }
        importChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "encoresheets/import")
        importChannel?.setMethodCallHandler { call, result ->
            if (call.method != "take") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val pending = sharedPdfs.toList()
            sharedPdfs.clear()
            Thread {
                val paths = pending.mapNotNull { uri ->
                    runCatching {
                        val display = contentResolver.query(
                            uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
                        )?.use { if (it.moveToFirst()) it.getString(0) else null }
                        val name = display?.substringAfterLast('/')?.substringAfterLast('\\')
                            ?.takeIf { it.endsWith(".pdf", ignoreCase = true) } ?: "Shared score.pdf"
                        val folder = File(cacheDir, "pdf-import-${java.util.UUID.randomUUID()}")
                        check(folder.mkdir())
                        val target = File(folder, name)
                        val input = contentResolver.openInputStream(uri) ?: error("Missing PDF")
                        input.use { source -> target.outputStream().use { source.copyTo(it) } }
                        target.path
                    }.getOrNull()
                }
                runOnUiThread { result.success(paths) }
            }.start()
        }
        collectPdfs(intent)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "encoresheets/backup")
            .setMethodCallHandler { call, result ->
                if (call.method != "save") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path == null || pendingBackup != null) {
                    result.error("backup_unavailable", "Cannot start the backup picker.", null)
                    return@setMethodCallHandler
                }
                val file = File(path)
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/zip"
                    putExtra(Intent.EXTRA_TITLE, file.name)
                }
                try {
                    pendingBackup = Pair(file, result)
                    @Suppress("DEPRECATION")
                    startActivityForResult(intent, BACKUP_REQUEST)
                } catch (error: Exception) {
                    pendingBackup = null
                    result.error("backup_picker", error.message, null)
                }
            }
    }

    @Deprecated("Uses FlutterActivity's existing activity result callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SCAN_REQUEST) {
            finishScan(resultCode, data)
            return
        }
        if (requestCode != BACKUP_REQUEST) return
        val (file, result) = pendingBackup ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pendingBackup = null
            result.success(false)
            return
        }
        Thread {
            try {
                file.inputStream().use { source ->
                    val stream = contentResolver.openOutputStream(uri, "wt")
                        ?: error("Could not open the selected file.")
                    stream.use { output -> source.copyTo(output) }
                }
                runOnUiThread {
                    pendingBackup = null
                    result.success(true)
                }
            } catch (error: Exception) {
                runOnUiThread {
                    pendingBackup = null
                    result.error("backup_write", error.message, null)
                }
            }
        }.start()
    }

    private companion object {
        const val BACKUP_REQUEST = 8041
        const val SCAN_REQUEST = 8042
    }
}

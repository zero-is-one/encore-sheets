package app.encoresheets.encoresheets

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingBackup: Pair<File, MethodChannel.Result>? = null
    private var importChannel: MethodChannel? = null
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
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
    }
}

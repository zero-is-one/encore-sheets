package app.encoresheets.encoresheets

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingBackup: Pair<File, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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

package uz.sardor.file_transfer

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.StatFs
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.system.Os
import android.system.OsConstants
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.nio.file.Files
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private var pendingNetworkPermission: MethodChannel.Result? = null
    private val permissionCode = 8752
    private val lanPermission = "android.permission.ACCESS_LOCAL_NETWORK"
    private val exportCode = 8753
    private val exportExecutor = Executors.newSingleThreadExecutor()
    private var pendingExport: ExportRequest? = null
    private var storageChannel: MethodChannel? = null

    private data class ExportRequest(
        val source: File,
        val result: MethodChannel.Result,
        val cancelled: AtomicBoolean = AtomicBoolean(false),
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "uz.sardor.file_transfer/permissions").setMethodCallHandler { call, result ->
            if (call.method != "ensureLocalNetwork") {
                result.notImplemented()
            } else if (Build.VERSION.SDK_INT < 37 ||
                checkSelfPermission(lanPermission) == PackageManager.PERMISSION_GRANTED) {
                result.success(true)
            } else if (pendingNetworkPermission != null) {
                result.error("REQUEST_IN_PROGRESS", "A permission request is active.", null)
            } else {
                pendingNetworkPermission = result
                requestPermissions(arrayOf(lanPermission), permissionCode)
            }
        }
        storageChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "file_transfer/storage").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "freeBytes" -> readFreeBytes(call, result)
                    "exportFile" -> beginExport(call, result)
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun readFreeBytes(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "A storage directory is required.", null)
            return
        }
        try {
            val directory = File(path).canonicalFile
            val root = filesDir.canonicalFile
            if (!directory.isDirectory || !isWithin(directory, root)) {
                result.error("STORAGE_UNAVAILABLE", "Storage capacity is unavailable.", null)
                return
            }
            result.success(StatFs(directory.path).availableBytes)
        } catch (_: Exception) {
            result.error("STORAGE_UNAVAILABLE", "Storage capacity is unavailable.", null)
        }
    }

    private fun isWithin(file: File, root: File): Boolean =
        file.path == root.path || file.path.startsWith(root.path + File.separator)

    private fun validateSource(path: String): File {
        val source = File(path).absoluteFile
        val root = File(filesDir, "file-transfer-v1/inbox/received").canonicalFile
        val canonical = source.canonicalFile
        if (!isWithin(canonical, root) || canonical == root ||
            !canonical.isFile || !canonical.canRead()) {
            throw IOException("The received file is unavailable.")
        }
        // Reject links in the managed path. The directory is app-private and
        // the controller keeps committed sources immutable during an export.
        var current: File? = source
        while (current != null && isWithin(current, filesDir.absoluteFile)) {
            if (Files.isSymbolicLink(current.toPath())) {
                throw IOException("Linked export sources are not supported.")
            }
            current = current.parentFile
        }
        return canonical
    }

    private fun beginExport(call: MethodCall, result: MethodChannel.Result) {
        if (pendingExport != null) {
            result.error("EXPORT_BUSY", "Another save dialog or export is active.", null)
            return
        }
        val path = call.argument<String>("sourcePath")
        val displayName = call.argument<String>("displayName")
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        if (path.isNullOrBlank() || displayName.isNullOrBlank() ||
            displayName.length > 255 || displayName == "." || displayName == ".." ||
            displayName.any { it == '/' || it == '\\' || it.code < 32 }) {
            result.error("INVALID_ARGUMENT", "A received file and safe name are required.", null)
            return
        }
        val source = try { validateSource(path) } catch (_: Exception) {
            result.error("EXPORT_SOURCE_UNAVAILABLE", "The received file is unavailable.", null)
            return
        }
        val request = ExportRequest(source, result)
        pendingExport = request
        try {
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mimeType
                putExtra(Intent.EXTRA_TITLE, displayName)
            }
            // ACTION_CREATE_DOCUMENT creates a new document; Android resolves
            // existing names without replacing the user's existing document.
            startActivityForResult(intent, exportCode)
        } catch (_: Exception) {
            pendingExport = null
            result.error("EXPORT_UNSUPPORTED", "No document save provider is available.", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != exportCode) return
        val request = pendingExport ?: return
        if (resultCode != Activity.RESULT_OK) {
            pendingExport = null
            request.result.success(null)
            return
        }
        val destination = data?.data
        if (destination == null || destination.scheme != "content") {
            pendingExport = null
            request.result.error("EXPORT_FAILED", "The provider returned no document.", null)
            return
        }
        exportExecutor.execute { copyDocument(request, destination) }
    }

    private fun copyDocument(request: ExportRequest, destination: Uri) {
        try {
            val source = validateSource(request.source.path)
            val length = source.length()
            var copied = 0L
            val descriptor = contentResolver.openFileDescriptor(destination, "w")
                ?: throw IOException("The selected document is not writable.")
            ParcelFileDescriptor.AutoCloseOutputStream(descriptor).use { output ->
                FileInputStream(source).use { input ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        if (request.cancelled.get() || Thread.currentThread().isInterrupted) {
                            throw IOException("Export was interrupted.")
                        }
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (count == 0) continue
                        output.write(buffer, 0, count)
                        copied += count
                    }
                }
                if (copied != length || source.length() != length) {
                    throw IOException("The received file changed during export.")
                }
                output.flush()
                // Cloud providers may return a pipe. fsync is meaningful only
                // for a regular file; close/checkError propagates provider I/O.
                if (OsConstants.S_ISREG(Os.fstat(descriptor.fileDescriptor).st_mode)) {
                    output.fd.sync()
                }
                descriptor.checkError()
            }
            if (request.cancelled.get()) throw IOException("Export was interrupted.")
            val label = queryDisplayName(destination) ?: "Выбранный документ"
            runOnUiThread {
                if (pendingExport === request) {
                    pendingExport = null
                    request.result.success(mapOf(
                        "status" to "exported",
                        "destinationLabel" to label,
                        "platformReference" to destination.toString(),
                    ))
                }
            }
        } catch (_: Exception) {
            // Only the newly created destination is eligible for cleanup. Never
            // touch the committed internal copy or another existing document.
            try { DocumentsContract.deleteDocument(contentResolver, destination) }
            catch (_: Exception) { /* A provider may retain its partial file. */ }
            runOnUiThread {
                if (pendingExport === request) {
                    pendingExport = null
                    request.result.error(
                        if (request.cancelled.get()) "EXPORT_INTERRUPTED" else "EXPORT_FAILED",
                        "The copy was not saved. The received file remains in the app.",
                        null,
                    )
                }
            }
        }
    }

    private fun queryDisplayName(uri: Uri): String? = try {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0)?.takeIf { it.isNotBlank() }
                else null
            }
    } catch (_: Exception) { null }

    override fun onDestroy() {
        pendingExport?.let {
            it.cancelled.set(true)
            it.result.error("EXPORT_INTERRUPTED", "The save operation was interrupted.", null)
        }
        pendingExport = null
        storageChannel?.setMethodCallHandler(null)
        storageChannel = null
        exportExecutor.shutdownNow()
        pendingNetworkPermission?.error("REQUEST_INTERRUPTED", "Permission request interrupted.", null)
        pendingNetworkPermission = null
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(requestCode: Int,
        permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionCode) {
            pendingNetworkPermission?.success(grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED)
            pendingNetworkPermission = null
        }
    }
}

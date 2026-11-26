package uz.sardor.file_transfer

import android.app.Activity
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.content.ContentResolver
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.PersistableBundle
import android.provider.MediaStore
import android.view.WindowManager
import android.webkit.MimeTypeMap
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
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private var pendingNetworkPermission: MethodChannel.Result? = null
    private val permissionCode = 8752
    private val lanPermission = "android.permission.ACCESS_LOCAL_NETWORK"
    private val lanAskedKey = "local_network_permission_requested"
    private val exportCode = 8753
    private val exportExecutor = Executors.newSingleThreadExecutor()
    private var pendingExport: ExportRequest? = null
    private var storageChannel: MethodChannel? = null
    private var intakeChannel: MethodChannel? = null
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val handledExtra = "uz.ulash.intent_handled"

    private data class ExportRequest(
        val source: File,
        val result: MethodChannel.Result,
        val cancelled: AtomicBoolean = AtomicBoolean(false),
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "uz.sardor.file_transfer/permissions").setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureLocalNetwork" -> ensureLocalNetwork(result)
                "localNetworkStatus" -> result.success(localNetworkStatus())
                "openSettings" -> openAppSettings(result)
                else -> result.notImplemented()
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "file_transfer/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToPhotos" -> saveToPhotos(call, result)
                "setSecureScreen" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (enabled) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                }
                "copySensitive" -> copySensitive(call, result)
                else -> result.notImplemented()
            }
        }
        intakeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "file_transfer/intake").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "takePending" -> ioExecutor.execute {
                        val items = takePending()
                        mainHandler.post { result.success(items) }
                    }
                    "pendingCount" -> ioExecutor.execute {
                        val count = intakeRoot().walkTopDown().count { it.isFile }
                        mainHandler.post { result.success(count) }
                    }
                    else -> result.notImplemented()
                }
            }
        }
        handleIncoming(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncoming(intent)
    }

    // ----- Intake: "Share → Ulash" and "Open with Ulash" -----

    private fun intakeRoot(): File = File(cacheDir, "intake")
    private fun takenRoot(): File = File(cacheDir, "intake-taken")

    /** Copies shared content URIs into the app cache and tells Dart. */
    private fun handleIncoming(intent: Intent?) {
        if (intent == null || intent.getBooleanExtra(handledExtra, false)) return
        val uris = mutableListOf<Uri>()
        var text: String? = null
        when (intent.action) {
            Intent.ACTION_SEND -> {
                val stream = streamExtra(intent)
                stream?.takeIf { isForeignContentUri(it) }?.let { uris.add(it) }
                if (stream == null) text = intent.getStringExtra(Intent.EXTRA_TEXT)
            }
            Intent.ACTION_SEND_MULTIPLE -> uris.addAll(streamListExtra(intent).filter { isForeignContentUri(it) })
            Intent.ACTION_VIEW -> intent.data?.takeIf { isForeignContentUri(it) }?.let { uris.add(it) }
            else -> return
        }
        intent.putExtra(handledExtra, true)
        if (uris.isEmpty() && text.isNullOrBlank()) return
        ioExecutor.execute {
            val batch = File(intakeRoot(), UUID.randomUUID().toString())
            batch.mkdirs()
            var copied = 0
            for (uri in uris) {
                try {
                    val name = safeName(queryDisplayName(uri) ?: uri.lastPathSegment ?: "file")
                    val target = uniqueFile(File(batch, name))
                    contentResolver.openInputStream(uri)?.use { input ->
                        target.outputStream().use { output -> input.copyTo(output, 64 * 1024) }
                        copied++
                    }
                } catch (_: Exception) {
                    // A provider that fails or revokes access is skipped.
                }
            }
            if (!text.isNullOrBlank()) {
                try {
                    uniqueFile(File(batch, "Text.txt")).writeText(text!!)
                    copied++
                } catch (_: Exception) { }
            }
            if (copied == 0) batch.deleteRecursively()
            else mainHandler.post { intakeChannel?.invokeMethod("intakeAvailable", null) }
        }
    }

    /**
     * Only content:// URIs served by ANOTHER app are read. file:// URIs and
     * URIs of Ulash's own providers are refused: otherwise any app could make
     * Ulash copy its private files (keys, databases) into the send list.
     */
    private fun isForeignContentUri(uri: Uri): Boolean {
        if (uri.scheme?.lowercase() != ContentResolver.SCHEME_CONTENT) return false
        val authority = uri.authority?.takeIf { it.isNotBlank() } ?: return false
        // A provider may declare several authorities separated by ';'; drop
        // any user-info part ("user@authority").
        return authority.substringAfterLast('@').split(';').none { isOwnAuthority(it.trim()) }
    }

    private fun isOwnAuthority(authority: String): Boolean {
        if (authority.isEmpty()) return true
        if (authority == packageName || authority.startsWith("$packageName.")) return true
        val provider = try {
            @Suppress("DEPRECATION")
            packageManager.resolveContentProvider(authority, 0)
        } catch (_: Exception) {
            null
        }
        return provider?.packageName == packageName
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri

    @Suppress("DEPRECATION")
    private fun streamListExtra(intent: Intent): List<Uri> =
        (if (Build.VERSION.SDK_INT >= 33)
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)) ?: emptyList()

    /** Returns each pending file once as {path, name}; Dart stages and deletes them. */
    private fun takePending(): List<Map<String, String>> {
        val result = mutableListOf<Map<String, String>>()
        val batches = intakeRoot().listFiles()?.filter { it.isDirectory } ?: return result
        for (batch in batches) {
            val destination = File(takenRoot(), UUID.randomUUID().toString())
            destination.mkdirs()
            for (file in batch.listFiles()?.filter { it.isFile } ?: emptyList()) {
                val target = uniqueFile(File(destination, file.name))
                if (file.renameTo(target)) {
                    result.add(mapOf("path" to target.absolutePath, "name" to target.name))
                }
            }
            batch.deleteRecursively()
        }
        return result
    }

    private fun safeName(raw: String): String {
        val cleaned = raw.replace('/', '_').replace('\\', '_').replace(':', '_').trim()
        return if (cleaned.isEmpty() || cleaned.startsWith(".")) "file$cleaned" else cleaned
    }

    private fun uniqueFile(file: File): File {
        if (!file.exists()) return file
        val base = file.nameWithoutExtension
        val ext = file.extension
        var index = 2
        while (true) {
            val candidate = File(file.parentFile, if (ext.isEmpty()) "$base $index" else "$base $index.$ext")
            if (!candidate.exists()) return candidate
            index++
        }
    }

    // ----- Photos, secure clipboard -----

    /** Adds a received photo/video to the gallery (Pictures|Movies/Ulash). No permission on API 29+. */
    private fun saveToPhotos(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val isVideo = call.argument<String>("kind") == "video"
        if (path.isNullOrBlank()) {
            result.success("failed")
            return
        }
        ioExecutor.execute {
            val outcome = try {
                val source = File(path).canonicalFile
                val appRoots = listOfNotNull(filesDir, getExternalFilesDir(null), cacheDir)
                    .map { it.canonicalFile }
                require(appRoots.any { isWithin(source, it) } && source.isFile)
                val mime = MimeTypeMap.getSingleton()
                    .getMimeTypeFromExtension(source.extension.lowercase())
                    ?: if (isVideo) "video/mp4" else "image/jpeg"
                val collection = if (isVideo)
                    MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                else MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, source.name)
                    put(MediaStore.MediaColumns.MIME_TYPE, mime)
                    put(MediaStore.MediaColumns.RELATIVE_PATH,
                        if (isVideo) "Movies/Ulash" else "Pictures/Ulash")
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val item = contentResolver.insert(collection, values)
                    ?: throw IOException("MediaStore insert failed")
                try {
                    contentResolver.openOutputStream(item)?.use { output ->
                        FileInputStream(source).use { input -> input.copyTo(output, 64 * 1024) }
                    } ?: throw IOException("No output stream")
                    contentResolver.update(item, ContentValues().apply {
                        put(MediaStore.MediaColumns.IS_PENDING, 0)
                    }, null, null)
                    "saved"
                } catch (error: Exception) {
                    contentResolver.delete(item, null, null)
                    throw error
                }
            } catch (_: Exception) {
                "failed"
            }
            mainHandler.post { result.success(outcome) }
        }
    }

    /** Copies a pairing invitation without exposing it to clipboard previews; clears it later. */
    private fun copySensitive(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text")
        if (text == null) {
            result.success(false)
            return
        }
        val seconds = (call.argument<Int>("seconds") ?: 120).coerceIn(10, 600)
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = ClipData.newPlainText("Ulash", text)
        clip.description.extras = PersistableBundle().apply {
            if (Build.VERSION.SDK_INT >= 33) putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
            else putBoolean("android.content.extra.IS_SENSITIVE", true)
        }
        clipboard.setPrimaryClip(clip)
        mainHandler.postDelayed({
            try {
                val current = clipboard.primaryClip
                if (current != null && current.itemCount > 0 &&
                    current.getItemAt(0).text?.toString() == text) {
                    clipboard.clearPrimaryClip()
                }
            } catch (_: Exception) {
                // Without focus Android may refuse to read the clipboard; skip.
            }
        }, seconds * 1000L)
        result.success(true)
    }

    private fun lanPermissionGranted(): Boolean = Build.VERSION.SDK_INT < 37 ||
        checkSelfPermission(lanPermission) == PackageManager.PERMISSION_GRANTED

    private fun ensureLocalNetwork(result: MethodChannel.Result) {
        if (lanPermissionGranted()) {
            result.success(true)
        } else if (pendingNetworkPermission != null) {
            result.error("REQUEST_IN_PROGRESS", "A permission request is active.", null)
        } else {
            pendingNetworkPermission = result
            getPreferences(Context.MODE_PRIVATE).edit().putBoolean(lanAskedKey, true).apply()
            requestPermissions(arrayOf(lanPermission), permissionCode)
        }
    }

    /** "denied" only after the user answered and Android will not ask again;
     * an un-asked or re-askable permission is "unknown" so the app may request it. */
    private fun localNetworkStatus(): String {
        if (lanPermissionGranted()) return "granted"
        val asked = getPreferences(Context.MODE_PRIVATE).getBoolean(lanAskedKey, false)
        return if (asked && !shouldShowRequestPermissionRationale(lanPermission)) {
            "denied"
        } else {
            "unknown"
        }
    }

    private fun openAppSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            result.success(true)
        } catch (error: Exception) {
            result.success(false)
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
        // Received files live under the app's private data root (and, from
        // 1.2, may also live under its external files dir "Ulash").
        val roots = listOfNotNull(
            File(filesDir, "file-transfer-v1").canonicalFile,
            getExternalFilesDir(null)?.let { File(it, "Ulash").canonicalFile },
        )
        val canonical = source.canonicalFile
        val root = roots.firstOrNull { isWithin(canonical, it) }
        if (root == null || canonical == root ||
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
        intakeChannel?.setMethodCallHandler(null)
        intakeChannel = null
        exportExecutor.shutdownNow()
        ioExecutor.shutdown()
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

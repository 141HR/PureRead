package com.pureread.pureread

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.view.KeyEvent
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val PLATFORM_CHANNEL = "com.pureread.app/platform"
        private const val VOLUME_EVENT_CHANNEL = "com.pureread.app/platform/volume_keys"
        private const val REQUEST_PICK_FILES = 4101
    }

    private val ioExecutor = Executors.newSingleThreadExecutor()
    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingAllowedExtensions: Set<String> = emptySet()
    private var volumeKeyPagingEnabled: Boolean = false
    private var volumeKeySink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PLATFORM_CHANNEL,
        ).setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VOLUME_EVENT_CHANNEL,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    volumeKeySink = events
                }

                override fun onCancel(arguments: Any?) {
                    volumeKeySink = null
                }
            },
        )
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFiles" -> {
                val rawExtensions = call.argument<List<*>>("extensions").orEmpty()
                val extensions = rawExtensions
                    .filterIsInstance<String>()
                    .map { it.trim().trimStart('.').lowercase(Locale.ROOT) }
                    .filter { it.isNotEmpty() }
                    .toSet()
                val allowMultiple = call.argument<Boolean>("allowMultiple") ?: false
                launchDocumentPicker(extensions, allowMultiple, result)
            }

            "setKeepScreenOn" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                runOnUiThread {
                    if (enabled) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
            }

            "setVolumeKeyPaging" -> {
                volumeKeyPagingEnabled = call.argument<Boolean>("enabled") ?: false
                result.success(null)
            }

            "setImmersiveMode" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                runOnUiThread {
                    applyImmersiveMode(enabled)
                    result.success(null)
                }
            }

            "bossKeyHide" -> {
                runOnUiThread {
                    moveTaskToBack(true)
                    result.success(null)
                }
            }

            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun launchDocumentPicker(
        extensions: Set<String>,
        allowMultiple: Boolean,
        result: MethodChannel.Result,
    ) {
        if (pendingPickResult != null) {
            result.error("PICK_IN_PROGRESS", "A file picker request is already active.", null)
            return
        }
        pendingPickResult = result
        pendingAllowedExtensions = extensions

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple)
            if (extensions == setOf("txt")) {
                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("text/plain", "text/*"))
            }
        }
        try {
            startActivityForResult(intent, REQUEST_PICK_FILES)
        } catch (e: Exception) {
            pendingPickResult = null
            pendingAllowedExtensions = emptySet()
            result.error("PICK_LAUNCH_FAILED", e.message, null)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_PICK_FILES) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        val result = pendingPickResult
        val allowedExtensions = pendingAllowedExtensions
        pendingPickResult = null
        pendingAllowedExtensions = emptySet()
        if (result == null) return

        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<String>())
            return
        }

        val uris = mutableListOf<Uri>()
        val clipData = data.clipData
        if (clipData != null) {
            for (i in 0 until clipData.itemCount) {
                clipData.getItemAt(i)?.uri?.let { uris.add(it) }
            }
        } else {
            data.data?.let { uris.add(it) }
        }

        if (uris.isEmpty()) {
            result.success(emptyList<String>())
            return
        }

        ioExecutor.execute {
            try {
                val copiedPaths = copyUrisToImports(uris, allowedExtensions)
                runOnUiThread { result.success(copiedPaths) }
            } catch (e: Exception) {
                runOnUiThread { result.error("PICK_COPY_FAILED", e.message, null) }
            }
        }
    }

    private fun copyUrisToImports(
        uris: List<Uri>,
        allowedExtensions: Set<String>,
    ): List<String> {
        val importsRoot = File(filesDir, "imports")
        if (!importsRoot.exists()) {
            importsRoot.mkdirs()
        }

        val timestamp = System.currentTimeMillis()
        val copied = mutableListOf<String>()

        uris.forEachIndexed { index, uri ->
            val rawName = queryDisplayName(uri) ?: "import_${timestamp}_$index"
            val safeName = sanitizeFileName(rawName, fallback = "import_${timestamp}_$index")
            val dotIdx = safeName.lastIndexOf('.')
            val ext = if (dotIdx >= 0 && dotIdx < safeName.length - 1) {
                safeName.substring(dotIdx + 1).lowercase(Locale.ROOT)
            } else {
                ""
            }
            if (allowedExtensions.isNotEmpty() && ext.isNotEmpty() && !allowedExtensions.contains(ext)) {
                return@forEachIndexed
            }

            val finalName = if (ext.isEmpty() && allowedExtensions.size == 1) {
                "$safeName.${allowedExtensions.first()}"
            } else {
                safeName
            }

            val batchDir = File(importsRoot, "${timestamp}_$index")
            if (!batchDir.exists()) {
                batchDir.mkdirs()
            }
            val outFile = File(batchDir, finalName)

            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(outFile).use { output ->
                    input.copyTo(output)
                }
                copied.add(outFile.absolutePath)
            }
        }
        return copied
    }

    private fun queryDisplayName(uri: Uri): String? {
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) {
                    return cursor.getString(idx)
                }
            }
        }
        return uri.lastPathSegment
    }

    private fun sanitizeFileName(name: String, fallback: String): String {
        val leaf = name.substringAfterLast('/').substringAfterLast('\\')
            .replace("\u0000", "")
            .trim()
        if (leaf.isEmpty() || leaf == "." || leaf == "..") {
            return fallback
        }
        return leaf
    }

    @Suppress("DEPRECATION")
    private fun applyImmersiveMode(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val controller = window.insetsController ?: return
            if (enabled) {
                controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            } else {
                controller.show(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
            }
        } else {
            val decorView = window.decorView
            if (enabled) {
                decorView.systemUiVisibility = (
                    View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                        or View.SYSTEM_UI_FLAG_FULLSCREEN
                        or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                        or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                        or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    )
            } else {
                decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (volumeKeyPagingEnabled &&
            (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
                event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                val direction = if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) "up" else "down"
                volumeKeySink?.success(direction)
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onDestroy() {
        pendingPickResult = null
        volumeKeySink = null
        ioExecutor.shutdownNow()
        super.onDestroy()
    }
}

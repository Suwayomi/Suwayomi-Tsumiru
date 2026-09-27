package io.github.aaronbamblett.tsumiru

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.os.Build
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

import dev.darttools.flutter_android_volume_keydown.FlutterAndroidVolumeKeydownActivity

class MainActivity: FlutterAndroidVolumeKeydownActivity() {
    private val backgroundExecutor = Executors.newFixedThreadPool(3)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tsumiru/image_transcoder")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "transcodeFileToJpeg" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("INVALID_ARGS", "Path cannot be null", null)
                            return@setMethodCallHandler
                        }

                        val sourceFile = File(path)
                        if (!sourceFile.exists()) {
                            result.error("FILE_NOT_FOUND", "File does not exist: $path", null)
                            return@setMethodCallHandler
                        }

                        backgroundExecutor.execute {
                            try {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                    val source = ImageDecoder.createSource(sourceFile)
                                    val bitmap = ImageDecoder.decodeBitmap(source) { decoder, _, _ ->
                                        // Force software memory allocation to bypass Codec2 hardware limits
                                        decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                                    }

                                    val tempFile = File(sourceFile.parentFile, "${sourceFile.name}.tmp")
                                    FileOutputStream(tempFile).use { out ->
                                        bitmap.compress(Bitmap.CompressFormat.JPEG, 92, out)
                                    }
                                    bitmap.recycle()

                                    val success = tempFile.exists() && tempFile.length() > 0L && tempFile.renameTo(sourceFile)
                                    if (!success) {
                                        tempFile.delete()
                                    }
                                    runOnUiThread { result.success(success) }
                                } else {
                                    runOnUiThread { result.success(false) }
                                }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("TRANSCODE_FAILED", e.message, null)
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tsumiru/display_cutout")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setDrawUnderCutout" -> {
                        val enable = call.argument<Boolean>("enable") ?: false
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            runOnUiThread {
                                val attrs = window.attributes
                                attrs.layoutInDisplayCutoutMode = if (enable) {
                                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                                } else {
                                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_DEFAULT
                                }
                                window.attributes = attrs
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tsumiru/clipboard")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "copyImage" -> {
                        try {
                            val path = call.argument<String>("path")!!
                            val uri = FileProvider.getUriForFile(
                                this, "$packageName.fileprovider", File(path)
                            )
                            val clip = ClipData.newUri(contentResolver, "image", uri)
                            val cm = getSystemService(Context.CLIPBOARD_SERVICE)
                                    as ClipboardManager
                            cm.setPrimaryClip(clip)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("COPY_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
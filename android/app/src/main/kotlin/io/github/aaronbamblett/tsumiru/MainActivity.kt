package io.github.aaronbamblett.tsumiru

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.os.Build
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

import dev.darttools.flutter_android_volume_keydown.FlutterAndroidVolumeKeydownActivity;

private const val MAX_TRANSCODE_PIXELS = 16_000_000L

class MainActivity: FlutterAndroidVolumeKeydownActivity() {
    private val backgroundExecutor = Executors.newFixedThreadPool(3)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tsumiru/image_transcoder")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                    "transcodeFileToJpeg" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                            result.success(false)
                            return@setMethodCallHandler
                        }

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
                            val tempFile = File(sourceFile.parentFile, "${sourceFile.name}.tmp")
                            var decoded: Bitmap? = null
                            var flattened: Bitmap? = null
                            var success = false
                            try {
                                val source = ImageDecoder.createSource(sourceFile)
                                val bitmap = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                                    // Software allocation bypasses Codec2 hardware limits
                                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                                    val pixels = info.size.width.toLong() * info.size.height
                                    if (pixels > MAX_TRANSCODE_PIXELS) {
                                        var sampleSize = 2
                                        while (pixels > MAX_TRANSCODE_PIXELS * sampleSize * sampleSize) {
                                            sampleSize *= 2
                                        }
                                        decoder.setTargetSampleSize(sampleSize)
                                    }
                                }
                                decoded = bitmap

                                // JPEG has no alpha, so transparent pixels would turn black
                                val opaque = if (bitmap.hasAlpha()) {
                                    flattenOnWhite(bitmap).also { flattened = it }
                                } else {
                                    bitmap
                                }

                                FileOutputStream(tempFile).use { out ->
                                    opaque.compress(Bitmap.CompressFormat.JPEG, 92, out)
                                }
                                success = tempFile.length() > 0L && tempFile.renameTo(sourceFile)
                            } catch (e: Throwable) {
                                success = false
                            } finally {
                                decoded?.recycle()
                                flattened?.recycle()
                                if (tempFile.exists()) {
                                    tempFile.delete()
                                }
                                runOnUiThread { result.success(success) }
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
        // Copy a reader page image to the system clipboard (Komikku parity —
        // ClipData.newUri on a FileProvider content:// URI, no re-encode).
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

    private fun flattenOnWhite(bitmap: Bitmap): Bitmap {
        val flat = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(flat)
        canvas.drawColor(Color.WHITE)
        canvas.drawBitmap(bitmap, 0f, 0f, null)
        return flat
    }
}

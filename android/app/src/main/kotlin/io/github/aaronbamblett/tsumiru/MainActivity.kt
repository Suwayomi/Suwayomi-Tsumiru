package io.github.aaronbamblett.tsumiru

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

import dev.darttools.flutter_android_volume_keydown.FlutterAndroidVolumeKeydownActivity;

class MainActivity: FlutterAndroidVolumeKeydownActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
}

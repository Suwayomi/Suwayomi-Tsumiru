package io.github.aaronbamblett.tsumiru

import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
    }
}

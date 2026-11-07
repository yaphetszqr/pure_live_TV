package com.mystyle.purelive.tv

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * A real SurfaceView for mpv to draw into (lib/player/native/native_mpv_surface_view.dart).
 *
 * media_kit draws into a Flutter texture, which is composited into the 1080p UI
 * layer on TVs that render their UI at 1080p. A SurfaceView embedded with
 * Hybrid Composition gets its own hardware layer instead, so the TV scales the
 * decoded frames straight to the panel. Each view talks over its own channel,
 * `purelive/native_video_surface/<viewId>`, and hands Dart the JNI global
 * reference mpv expects as `wid`.
 */
class NativeVideoSurfaceFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        NativeVideoSurfaceView(context, MethodChannel(messenger, "$VIEW_TYPE/$viewId"))

    companion object {
        const val VIEW_TYPE = "purelive/native_video_surface"
    }
}

private class NativeVideoSurfaceView(context: Context, private val channel: MethodChannel) :
    PlatformView, SurfaceHolder.Callback {
    private val surfaceView = SurfaceView(context)
    private val handler = Handler(Looper.getMainLooper())
    private var wid = 0L
    private var width = 0
    private var height = 0

    init {
        surfaceView.holder.addCallback(this)
        // Dart may install its handler after the surface already exists; it
        // asks for the current state once it is listening.
        channel.setMethodCallHandler { call, result ->
            if (call.method == "sync") {
                if (wid != 0L) sendAttach()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun getView(): View = surfaceView

    override fun surfaceCreated(holder: SurfaceHolder) {}

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        this.width = width
        this.height = height
        if (wid == 0L) {
            wid = MediaKitAndroidHelper.newGlobalObjectRef(holder.surface)
            sendAttach()
        } else {
            channel.invokeMethod("resize", mapOf("width" to width, "height" to height))
        }
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        channel.invokeMethod("detach", null)
        releaseWid()
    }

    override fun dispose() {
        surfaceView.holder.removeCallback(this)
        channel.setMethodCallHandler(null)
        releaseWid()
    }

    private fun sendAttach() {
        channel.invokeMethod("attach", mapOf("wid" to wid, "width" to width, "height" to height))
    }

    private fun releaseWid() {
        val ref = wid
        wid = 0L
        // mpv may still touch the surface until Dart's detach lands; media_kit
        // delays the release the same way.
        if (ref != 0L) handler.postDelayed({ MediaKitAndroidHelper.deleteGlobalObjectRef(ref) }, 5000)
    }
}

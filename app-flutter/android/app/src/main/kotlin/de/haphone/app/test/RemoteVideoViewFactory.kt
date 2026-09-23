package de.haphone.app.test

import android.content.Context
import android.graphics.SurfaceTexture
import android.view.Surface
import android.view.TextureView
import android.view.View
import de.haphone.app.test.sip.VideoSurfaceBinder
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Flutter platform view "de.haphone.app.test/remote_video": shows the current call's
 * incoming (door station) video in the Flutter call screen. TextureView, not
 * SurfaceView, because a SurfaceView punches through Flutter's composition.
 */
class RemoteVideoViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView = RemoteVideoView(context)

    companion object {
        const val VIEW_TYPE = "de.haphone.app.test/remote_video"
    }
}

private class RemoteVideoView(context: Context) : PlatformView, TextureView.SurfaceTextureListener {
    private val textureView = TextureView(context).also { it.surfaceTextureListener = this }
    private var surface: Surface? = null

    override fun getView(): View = textureView

    override fun dispose() {
        release()
    }

    override fun onSurfaceTextureAvailable(st: SurfaceTexture, width: Int, height: Int) {
        val s = Surface(st)
        surface = s
        VideoSurfaceBinder.setSurface(s)
    }

    override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, width: Int, height: Int) {}

    override fun onSurfaceTextureDestroyed(st: SurfaceTexture): Boolean {
        release()
        return true
    }

    override fun onSurfaceTextureUpdated(st: SurfaceTexture) {}

    private fun release() {
        val s = surface ?: return
        surface = null
        VideoSurfaceBinder.clearSurface(s)
        s.release()
    }
}

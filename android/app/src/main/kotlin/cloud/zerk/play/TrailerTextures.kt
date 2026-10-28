package cloud.zerk.play

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

@OptIn(UnstableApi::class)
class TrailerTextures(
    private val context: Context,
    messenger: BinaryMessenger,
    private val textures: TextureRegistry,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "zerk/trailer")
    private val main = Handler(Looper.getMainLooper())
    private val trailers = mutableMapOf<Long, Trailer>()

    init {
        channel.setMethodCallHandler(this)
    }

    fun release() {
        trailers.values.forEach { it.release() }
        trailers.clear()
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (call.method == "create") {
                val trailer = Trailer(
                    textures.createSurfaceProducer(),
                    (call.argument<Number>("width") ?: 1280).toInt(),
                    (call.argument<Number>("height") ?: 720).toInt(),
                )
                trailers[trailer.id] = trailer
                result.success(trailer.id)
                return
            }
            val id = (call.argument<Number>("id") ?: -1).toLong()
            val trailer = trailers[id] ?: return result.error("unknown", "No trailer $id", null)
            when (call.method) {
                "open" -> trailer.open(
                    Uri.parse(call.argument<String>("video")!!),
                    call.argument<String>("audio")?.let(Uri::parse),
                    call.argument<Boolean>("muted") != false,
                )
                "muted" -> trailer.player.volume = if (call.argument<Boolean>("muted") == true) 0f else 1f
                "paused" -> trailer.player.playWhenReady = call.argument<Boolean>("paused") != true
                "seekBy" -> trailer.player.let {
                    it.seekTo((it.currentPosition + (call.argument<Number>("ms") ?: 0).toLong()).coerceAtLeast(0))
                }
                "restart" -> trailer.player.let { it.seekTo(0); it.play() }
                "stop" -> trailer.stop()
                "resize" -> Unit
                "dispose" -> {
                    trailers.remove(id)
                    trailer.release()
                }
                else -> return result.notImplemented()
            }
            result.success(null)
        } catch (e: Exception) {
            Log.w("ZerkTrailer", "${call.method}: $e")
            result.error("trailer", e.message, null)
        }
    }

    private inner class Trailer(
        private val producer: TextureRegistry.SurfaceProducer,
        width: Int,
        height: Int,
    ) : Player.Listener {

        val id = producer.id()
        private val http = DefaultHttpDataSource.Factory().setUserAgent("ZerkPlay/2.0 (Android TV)")
        private val sources = ProgressiveMediaSource.Factory(DefaultDataSource.Factory(context, http))
        val player: ExoPlayer = ExoPlayer.Builder(context).build()
        private var ready = false
        private var released = false

        private val ticker = object : Runnable {
            override fun run() {
                emit()
                if (player.isPlaying) main.postDelayed(this, 500)
            }
        }

        init {
            producer.setSize(width, height)
            producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
                override fun onSurfaceAvailable() {
                    if (!released) player.setVideoSurface(producer.surface)
                }

                override fun onSurfaceCleanup() {
                    if (!released) player.clearVideoSurface()
                }
            })
            player.setVideoSurface(producer.surface)
            player.volume = 0f
            player.addListener(this)
        }

        fun open(video: Uri, audio: Uri?, muted: Boolean) {
            ready = false
            val source = sources.createMediaSource(MediaItem.fromUri(video))
            player.setMediaSource(
                if (audio == null) source else MergingMediaSource(source, sources.createMediaSource(MediaItem.fromUri(audio)))
            )
            player.volume = if (muted) 0f else 1f
            player.playWhenReady = true
            player.prepare()
        }

        fun stop() {
            ready = false
            player.stop()
            player.clearMediaItems()
            emit()
        }

        fun release() {
            if (released) return
            released = true
            main.removeCallbacks(ticker)
            player.removeListener(this)
            player.release()
            producer.release()
        }

        override fun onVideoSizeChanged(videoSize: VideoSize) {
            if (videoSize.width > 0 && videoSize.height > 0) producer.setSize(videoSize.width, videoSize.height)
        }

        override fun onRenderedFirstFrame() {
            ready = true
            emit()
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            main.removeCallbacks(ticker)
            if (isPlaying) main.post(ticker) else emit()
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            emit()
        }

        override fun onPlayerError(error: PlaybackException) {
            Log.w("ZerkTrailer", "playback failed: ${error.errorCodeName} ${error.message}")
            ready = false
            emit(failed = true)
        }

        private fun emit(failed: Boolean = false) {
            if (released) return
            channel.invokeMethod(
                "state",
                mapOf(
                    "id" to id,
                    "ready" to ready,
                    "failed" to failed,
                    "ended" to (player.playbackState == Player.STATE_ENDED),
                    "paused" to !player.playWhenReady,
                    "position" to player.currentPosition,
                    "duration" to player.duration.coerceAtLeast(0),
                ),
            )
        }
    }
}

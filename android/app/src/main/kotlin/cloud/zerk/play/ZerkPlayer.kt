package cloud.zerk.play

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.text.SpannableString
import android.text.Spanned
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import android.util.Log
import android.view.Gravity
import android.view.SurfaceView
import android.view.View
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.text.Cue
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DecoderReuseEvaluation
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.FormatHolder
import androidx.media3.exoplayer.hls.HlsManifest
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.util.EventLogger
import androidx.media3.exoplayer.video.MediaCodecVideoRenderer
import androidx.media3.exoplayer.video.VideoRendererEventListener
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.SubtitleView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

@OptIn(UnstableApi::class)
class ZerkPlayer(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler, Player.Listener {

    private val methods = MethodChannel(messenger, "zerk/player")
    private val eventChannel = EventChannel(messenger, "zerk/player/events")
    private var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())

    private var layer: FrameLayout? = null
    private var frame: AspectRatioFrameLayout? = null
    private var surface: SurfaceView? = null
    private var subtitles: SubtitleView? = null

    private var subtitleShadow: SubtitleView? = null

    private var subtitlePadding = 40f / 720

    private var subtitleLift = 0f

    private var resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT

    private var cropBox: CropBox? = null
    private var detector: BarDetector? = null
    private var scope = 0f
    private var anamorphic = 1f
    private var autoCrop = false
    private var videoAspect = 0f
    private var cropRuns = 0

    private val cropTicker = object : Runnable {
        override fun run() {
            val exo = player ?: return
            if (!autoCrop) return
            if (exo.isPlaying) {
                detector?.sample()
                cropRuns++
            }
            main.postDelayed(this, if (cropRuns < 8) 2_000 else 15_000)
        }
    }

    private var videoDecoder: String? = null

    private var audioDecoder: String? = null

    private var shadowOffset = 2f / 720
    private var player: ExoPlayer? = null

    private var mediaUrl: Uri? = null
    private val externalSubs = mutableListOf<MediaItem.SubtitleConfiguration>()

    private var pendingAudio: Int? = null
    private var pendingSub: Int? = null
    private var pendingExternalId: String? = null

    @Volatile private var copiedDolbyVision: String? = null

    private var announceLoaded = false

    private val ticker = object : Runnable {
        override fun run() {
            emitState()
            main.postDelayed(this, 500)
        }
    }

    init {
        methods.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    fun attach(layer: FrameLayout) {
        this.layer = layer
    }

    fun pause() {
        player?.pause()
    }

    fun release() {
        close()
        methods.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "open" -> {
                    open(
                        call.argument<Map<String, Any?>>("subtitleStyle") ?: emptyMap(),
                        call.argument<List<String>>("passthrough"),
                        call.argument<Boolean>("encodeAc3") == true,
                    )
                    result.success(null)
                }
                "load" -> {
                    load(
                        Uri.parse(call.argument<String>("url")!!),
                        (call.argument<Number>("startMs") ?: 0).toLong(),
                        call.argument<Int>("audio"),
                        call.argument<Int>("sub"),
                        call.argument<String>("dolbyVision"),
                    )
                    result.success(null)
                }
                "play" -> { player?.play(); result.success(null) }
                "pause" -> { player?.pause(); result.success(null) }
                "togglePause" -> {
                    player?.let { if (it.isPlaying || it.playWhenReady) it.pause() else it.play() }
                    emitState()
                    result.success(null)
                }
                "seekTo" -> {
                    player?.seekTo((call.argument<Number>("ms") ?: 0).toLong())
                    emitState()
                    result.success(null)
                }
                "selectTrack" -> {
                    selectTrack(call.argument<String>("type")!!, call.argument<String>("id"))
                    result.success(null)
                }
                "addSubtitle" -> {
                    addSubtitle(
                        Uri.parse(call.argument<String>("url")!!),
                        call.argument<String>("format") ?: "srt",
                        call.argument<String>("title"),
                        call.argument<String>("language"),
                    )
                    result.success(null)
                }
                "subtitleLift" -> {
                    subtitleLift = (call.argument<Number>("fraction") ?: 0).toFloat()
                    liftSubtitles()
                    result.success(null)
                }
                "speed" -> {
                    player?.setPlaybackSpeed((call.argument<Number>("speed") ?: 1).toFloat())
                    result.success(null)
                }
                "resizeMode" -> {
                    resizeMode = when (call.argument<String>("mode")) {
                        "zoom" -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                        "fill" -> AspectRatioFrameLayout.RESIZE_MODE_FILL
                        else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
                    }
                    frame?.resizeMode = resizeMode
                    result.success(null)
                }
                "screen" -> {
                    scope = (call.argument<Number>("scope") ?: 0).toFloat()
                    anamorphic = (call.argument<Number>("anamorphic") ?: 1).toFloat().coerceAtLeast(1f)
                    autoCrop = call.argument<Boolean>("autoCrop") == true
                    if (!autoCrop) applyCrop(0f)
                    applyScreen()
                    updateAspect()
                    restartCropDetection()
                    result.success(null)
                }
                "matchRefresh" -> result.success(DisplayModes.match(activity, (call.argument<Number>("fps") ?: 0).toDouble()))
                "stats" -> result.success(stats())
                "subtitleStyle" -> {
                    restyleSubtitles(call.argument<Map<String, Any?>>("style") ?: emptyMap())
                    result.success(null)
                }
                "displayHdr" -> result.success(DeviceCaps.displayHdr(activity))
                "capabilities" -> result.success(DeviceCaps.query(activity))
                "close" -> {
                    if (call.argument<Boolean>("keepRefresh") != true) DisplayModes.restore(activity)
                    close()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "${call.method} failed", e)
            result.error("player", e.message, null)
        }
    }

    private fun open(subtitleStyle: Map<String, Any?>, passthrough: List<String>?, encodeAc3: Boolean) {
        val layer = layer ?: throw IllegalStateException("No video layer")
        if (player != null) return

        val surface = SurfaceView(activity).apply { keepScreenOn = true }
        val box = CropBox(activity).apply {
            addView(surface, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        }
        val frame = AspectRatioFrameLayout(activity).apply {
            resizeMode = this@ZerkPlayer.resizeMode
            addView(box, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        }
        val shadow = SubtitleView(activity).apply { applyStyle(this, subtitleStyle, shadow = true) }
        val subtitles = SubtitleView(activity).apply { applyStyle(this, subtitleStyle, shadow = false) }
        layer.addView(frame, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT, Gravity.CENTER))
        layer.addView(shadow, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        layer.addView(subtitles, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        shadowOffset = (subtitleStyle["shadowOffsetFraction"] as? Number)?.toFloat() ?: (2f / 720)
        shadow.addOnLayoutChangeListener { v, _, top, _, bottom, _, _, _, _ ->
            val px = (bottom - top) * shadowOffset
            v.translationX = px
            v.translationY = px
        }
        layer.visibility = View.VISIBLE
        layer.addOnLayoutChangeListener(screenListener)

        val renderers = object : DefaultRenderersFactory(activity) {
            override fun buildVideoRenderers(
                context: Context, extensionRendererMode: Int, mediaCodecSelector: MediaCodecSelector,
                enableDecoderFallback: Boolean, eventHandler: Handler, eventListener: VideoRendererEventListener,
                allowedVideoJoiningTimeMs: Long, out: ArrayList<Renderer>,
            ) {
                super.buildVideoRenderers(context, extensionRendererMode, mediaCodecSelector, enableDecoderFallback,
                    eventHandler, eventListener, allowedVideoJoiningTimeMs, out)
                val i = out.indexOfFirst { it is MediaCodecVideoRenderer }
                if (i >= 0) out[i] = CopiedDolbyVisionRenderer(context, mediaCodecSelector, allowedVideoJoiningTimeMs,
                    enableDecoderFallback, eventHandler, eventListener) { copiedDolbyVision }
            }

            override fun buildAudioSink(context: Context, enableFloatOutput: Boolean, enableAudioTrackPlaybackParams: Boolean): AudioSink? {
                val sink = super.buildAudioSink(context, enableFloatOutput, enableAudioTrackPlaybackParams) ?: return null
                return Ac3EncodingAudioSink(sink, passthroughEncodings(passthrough), encodeAc3)
            }
        }
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
            .setEnableDecoderFallback(true)
        val http = DefaultHttpDataSource.Factory()
            .setUserAgent("ZerkPlay/2.0 (Android TV)")
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(20_000)
        val exo = ExoPlayer.Builder(activity, renderers)
            .setMediaSourceFactory(DefaultMediaSourceFactory(DefaultDataSource.Factory(activity, http)))
            .setAudioAttributes(
                AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),
                true,
            )
            .setHandleAudioBecomingNoisy(true)
            .setSeekBackIncrementMs(10_000)
            .setSeekForwardIncrementMs(10_000)
            .build()
        exo.setVideoSurfaceView(surface)
        exo.addListener(this)
        exo.addAnalyticsListener(EventLogger())
        exo.addAnalyticsListener(object : AnalyticsListener {
            override fun onVideoDecoderInitialized(
                eventTime: AnalyticsListener.EventTime, decoderName: String, initializedTimestampMs: Long, initializationDurationMs: Long,
            ) {
                videoDecoder = decoderName
            }

            override fun onAudioDecoderInitialized(
                eventTime: AnalyticsListener.EventTime, decoderName: String, initializedTimestampMs: Long, initializationDurationMs: Long,
            ) {
                audioDecoder = decoderName
            }
        })

        this.surface = surface
        this.frame = frame
        this.cropBox = box
        this.detector = BarDetector(surface, main) { applyCrop(it) }
        this.subtitles = subtitles
        this.subtitleShadow = shadow
        subtitlePadding = (subtitleStyle["bottomPaddingFraction"] as? Number)?.toFloat() ?: (40f / 720)
        this.player = exo
        main.post(ticker)
    }

    private val screenListener = View.OnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> applyScreen() }

    private fun applyScreen() {
        val layer = layer ?: return
        val height = if (anamorphic > 1f) layer.height else scopeHeight(scope, layer.width, layer.height)
        val target = if (height >= layer.height) FrameLayout.LayoutParams.MATCH_PARENT else height
        for (view in listOfNotNull(frame, subtitleShadow, subtitles)) {
            val lp = view.layoutParams as? FrameLayout.LayoutParams ?: continue
            if (lp.height == target && lp.gravity == Gravity.CENTER) continue
            lp.height = target
            lp.gravity = Gravity.CENTER
            view.post { view.layoutParams = lp }
        }
    }

    private fun updateAspect() {
        if (videoAspect <= 0f) return
        val crop = cropBox?.crop ?: 0f
        frame?.setAspectRatio(videoAspect / anamorphic / (1 - 2 * crop))
    }

    private fun applyCrop(fraction: Float) {
        val box = cropBox ?: return
        if (box.crop == fraction) return
        Log.i(TAG, "black bars: cropping ${"%.3f".format(fraction)} top and bottom")
        box.crop = fraction
        updateAspect()
    }

    private fun restartCropDetection() {
        main.removeCallbacks(cropTicker)
        cropRuns = 0
        if (autoCrop && player != null) main.postDelayed(cropTicker, 2_000)
    }

    private fun liftSubtitles() {
        val padding = maxOf(subtitlePadding, subtitleLift)
        subtitles?.setBottomPaddingFraction(padding)
        subtitleShadow?.setBottomPaddingFraction(padding)
    }

    private fun restyleSubtitles(style: Map<String, Any?>) {
        subtitles?.let { applyStyle(it, style, shadow = false) }
        subtitleShadow?.let {
            applyStyle(it, style, shadow = true)
            shadowOffset = (style["shadowOffsetFraction"] as? Number)?.toFloat() ?: shadowOffset
            val px = it.height * shadowOffset
            it.translationX = px
            it.translationY = px
        }
        subtitlePadding = (style["bottomPaddingFraction"] as? Number)?.toFloat() ?: subtitlePadding
        liftSubtitles()
    }

    private fun applyStyle(view: SubtitleView, style: Map<String, Any?>, shadow: Boolean) {
        fun num(key: String, default: Double) = (style[key] as? Number)?.toDouble() ?: default
        fun color(key: String, default: Long) = ((style[key] as? Number)?.toLong() ?: default).toInt()
        val embedded = style["applyEmbeddedStyles"] as? Boolean ?: true
        val box = style["background"] as? Boolean ?: false
        view.visibility = if (shadow && box) View.GONE else View.VISIBLE
        val text = if (shadow) color("shadowColor", 0xFF000000) else color("textColor", 0xFFFFFFFF)
        val edge = if (shadow) color("shadowColor", 0xFF000000) else color("outlineColor", 0xFF000000)
        view.setStyle(
            CaptionStyleCompat(
                text,
                if (box) color("backgroundColor", 0x99000000) else Color.TRANSPARENT,
                Color.TRANSPARENT,
                if (box) CaptionStyleCompat.EDGE_TYPE_NONE else CaptionStyleCompat.EDGE_TYPE_OUTLINE,
                edge,
                Typeface.create("sans-serif", Typeface.NORMAL),
            ),
        )
        view.setFractionalTextSize(num("textSizeFraction", 52.0 / 720).toFloat())
        view.setBottomPaddingFraction(num("bottomPaddingFraction", 40.0 / 720).toFloat())
        view.setApplyEmbeddedStyles(embedded)
        view.setApplyEmbeddedFontSizes(embedded)
    }

    private fun close() {
        main.removeCallbacks(ticker)
        main.removeCallbacks(cropTicker)
        layer?.removeOnLayoutChangeListener(screenListener)
        cropBox = null
        detector = null
        videoAspect = 0f
        player?.let {
            it.removeListener(this)
            it.release()
        }
        player = null
        videoDecoder = null
        audioDecoder = null
        layer?.apply {
            removeAllViews()
            visibility = View.GONE
        }
        surface = null
        frame = null
        subtitles = null
        subtitleShadow = null
        mediaUrl = null
        externalSubs.clear()
    }

    private fun load(url: Uri, startMs: Long, audio: Int?, sub: Int?, dolbyVision: String?) {
        val exo = player ?: throw IllegalStateException("Player not open")
        mediaUrl = url
        val profile = dolbyVision?.substringAfter('.')?.substringBefore('.')?.toIntOrNull()
        copiedDolbyVision = dolbyVision?.takeIf { profile in DeviceCaps.dolbyVisionProfiles }
        externalSubs.clear()
        pendingAudio = audio
        pendingSub = sub ?: 0
        pendingExternalId = null
        announceLoaded = true
        detector?.reset()
        applyCrop(0f)
        restartCropDetection()
        exo.trackSelectionParameters = exo.trackSelectionParameters.buildUpon()
            .clearOverrides()
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
            .build()
        exo.setMediaItem(buildItem(), startMs)
        exo.prepare()
        exo.playWhenReady = true
    }

    private fun buildItem(): MediaItem {
        val url = mediaUrl!!
        val builder = MediaItem.Builder().setUri(url).setSubtitleConfigurations(externalSubs.toList())
        if (url.path?.endsWith(".m3u8") == true) builder.setMimeType(MimeTypes.APPLICATION_M3U8)
        return builder.build()
    }

    private fun addSubtitle(url: Uri, format: String, title: String?, language: String?) {
        val exo = player ?: return
        val id = "zerkext:${externalSubs.size}"
        externalSubs += MediaItem.SubtitleConfiguration.Builder(url)
            .setId(id)
            .setMimeType(if (format == "ass") MimeTypes.TEXT_SSA else MimeTypes.APPLICATION_SUBRIP)
            .setLabel(title)
            .setLanguage(language)
            .build()
        pendingAudio = currentOrdinal(C.TRACK_TYPE_AUDIO)
        pendingSub = null
        pendingExternalId = id
        announceLoaded = false
        val position = exo.currentPosition
        val playing = exo.playWhenReady
        exo.setMediaItem(buildItem(), position)
        exo.prepare()
        exo.playWhenReady = playing
    }

    private fun selectTrack(type: String, id: String?) {
        val exo = player ?: return
        val trackType = if (type == "audio") C.TRACK_TYPE_AUDIO else C.TRACK_TYPE_TEXT
        val params = exo.trackSelectionParameters.buildUpon()
        if (id == null) {
            params.clearOverridesOfType(trackType).setTrackTypeDisabled(trackType, true)
        } else {
            val (g, t) = id.split(":").map { it.toInt() }
            val group = exo.currentTracks.groups.getOrNull(g) ?: return
            params.setTrackTypeDisabled(trackType, false)
                .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, t))
        }
        exo.trackSelectionParameters = params.build()
    }

    private fun passthroughEncodings(codecs: List<String>?): Set<Int>? = codecs?.takeIf { it.isNotEmpty() }?.flatMap {
        when (it) {
            "ac3" -> listOf(C.ENCODING_AC3)
            "eac3" -> listOf(C.ENCODING_E_AC3, C.ENCODING_E_AC3_JOC)
            "dts" -> listOf(C.ENCODING_DTS, C.ENCODING_DTS_HD)
            "dtshd" -> listOf(C.ENCODING_DTS, C.ENCODING_DTS_HD)
            "truehd" -> listOf(C.ENCODING_DOLBY_TRUEHD)
            else -> emptyList()
        }
    }?.toSet()

    private fun isExternal(format: Format) = format.id?.contains("zerkext:") == true

    private fun ownTracks(tracks: Tracks, type: Int): List<Pair<Int, Int>> {
        val own = mutableListOf<Pair<Int, Int>>()
        tracks.groups.forEachIndexed { g, group ->
            if (group.type != type) return@forEachIndexed
            for (t in 0 until group.length) if (!isExternal(group.getTrackFormat(t))) own += g to t
        }
        val numbers = own.map { (g, t) -> containerTrackNumber(tracks.groups[g].getTrackFormat(t)) }
        if (numbers.any { it == null }) return own
        return own.indices.sortedBy { numbers[it] }.map { own[it] }
    }

    private fun containerTrackNumber(format: Format): Long? =
        format.id?.let { TRAILING_NUMBER.find(it)?.groupValues?.get(1)?.toLongOrNull() }

    private fun findOrdinal(tracks: Tracks, type: Int, ordinal: Int): Pair<Int, Int>? =
        ownTracks(tracks, type).getOrNull(ordinal - 1)

    private fun currentOrdinal(type: Int): Int? {
        val tracks = player?.currentTracks ?: return null
        val i = ownTracks(tracks, type).indexOfFirst { (g, t) -> tracks.groups[g].isTrackSelected(t) }
        return if (i < 0) null else i + 1
    }

    private fun applyPending(tracks: Tracks) {
        val exo = player ?: return
        val params = exo.trackSelectionParameters.buildUpon()
        pendingAudio?.let { ordinal ->
            findOrdinal(tracks, C.TRACK_TYPE_AUDIO, ordinal)?.let { (g, t) ->
                params.setOverrideForType(TrackSelectionOverride(tracks.groups[g].mediaTrackGroup, t))
            }
        }
        val external = pendingExternalId
        val subTarget: Pair<Int, Int>? = when {
            external != null -> tracks.groups.withIndex().firstNotNullOfOrNull { (g, group) ->
                (0 until group.length).firstOrNull { group.getTrackFormat(it).id?.endsWith(external) == true }?.let { g to it }
            }
            (pendingSub ?: 0) > 0 -> findOrdinal(tracks, C.TRACK_TYPE_TEXT, pendingSub!!)
            else -> null
        }
        if (subTarget != null) {
            params.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                .setOverrideForType(TrackSelectionOverride(tracks.groups[subTarget.first].mediaTrackGroup, subTarget.second))
        }
        exo.trackSelectionParameters = params.build()
        pendingAudio = null
        pendingSub = null
        pendingExternalId = null
    }

    private fun hlsSubtitleIndexes(): Map<String, Int> {
        val manifest = player?.currentManifest as? HlsManifest ?: return emptyMap()
        return manifest.multivariantPlaylist.subtitles.mapNotNull { r ->
            val id = r.format.id ?: return@mapNotNull null
            val index = SUBTITLE_STREAM_INDEX.find(r.url.toString())?.groupValues?.get(1)?.toIntOrNull()
            index?.let { id to it }
        }.toMap()
    }

    private fun hlsSubtitleIndex(format: Format, hlsIndexes: Map<String, Int>): Int? {
        val id = format.id ?: return null
        return hlsIndexes[id] ?: hlsIndexes.entries.firstOrNull { id.endsWith(":${it.key}") }?.value
    }

    private fun trackList(tracks: Tracks): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        val ordinals = mutableMapOf<Pair<Int, Int>, Int>()
        for (type in listOf(C.TRACK_TYPE_AUDIO, C.TRACK_TYPE_TEXT)) {
            ownTracks(tracks, type).forEachIndexed { i, track -> ordinals[track] = i + 1 }
        }
        val hlsIndexes = hlsSubtitleIndexes()
        tracks.groups.forEachIndexed { g, group ->
            val type = when (group.type) {
                C.TRACK_TYPE_AUDIO -> "audio"
                C.TRACK_TYPE_TEXT -> "sub"
                else -> return@forEachIndexed
            }
            for (t in 0 until group.length) {
                val format = group.getTrackFormat(t)
                val external = isExternal(format)
                val ordinal = if (external) null else ordinals[g to t]
                val extIndex = if (external) format.id!!.substringAfter("zerkext:").toIntOrNull() else null
                out += mapOf(
                    "id" to "$g:$t",
                    "type" to type,
                    "ordinal" to ordinal,
                    "ffIndex" to if (external || group.type != C.TRACK_TYPE_TEXT) null else hlsSubtitleIndex(format, hlsIndexes),
                    "external" to external,
                    "url" to extIndex?.let { externalSubs.getOrNull(it)?.uri?.toString() },
                    "selected" to group.isTrackSelected(t),
                )
            }
        }
        return out
    }

    override fun onTracksChanged(tracks: Tracks) {
        if (tracks.groups.isEmpty()) return
        if (pendingAudio != null || pendingSub != null || pendingExternalId != null) applyPending(tracks)
        if (announceLoaded) {
            announceLoaded = false
            emitState()
            emit(mapOf("event" to "loaded"))
            return
        }
        emitState()
    }

    override fun onCues(cueGroup: CueGroup) {
        subtitles?.setCues(cueGroup.cues)
        subtitleShadow?.setCues(shadowCues(cueGroup.cues))
    }

    private fun shadowCues(cues: List<Cue>): List<Cue> = cues.mapNotNull { cue ->
        if (cue.bitmap != null) return@mapNotNull null
        val text = cue.text ?: return@mapNotNull cue
        val plain = if (text is Spanned) {
            SpannableString(text).apply {
                for (span in getSpans(0, length, ForegroundColorSpan::class.java)) removeSpan(span)
                for (span in getSpans(0, length, BackgroundColorSpan::class.java)) removeSpan(span)
            }
        } else {
            text
        }
        cue.buildUpon().setText(plain).clearWindowColor().build()
    }

    override fun onVideoSizeChanged(videoSize: VideoSize) {
        if (videoSize.width == 0 || videoSize.height == 0) return
        videoAspect = videoSize.width * videoSize.pixelWidthHeightRatio / videoSize.height
        updateAspect()
    }

    override fun onPlaybackStateChanged(playbackState: Int) = emitState()

    override fun onIsPlayingChanged(isPlaying: Boolean) = emitState()

    override fun onPlayerError(error: PlaybackException) {
        Log.w(TAG, "playback error", error)
        emit(mapOf("event" to "error", "message" to "${error.errorCodeName}: ${error.cause?.message ?: error.message}"))
    }

    private fun emitState() {
        val exo = player ?: return
        val video = exo.videoFormat
        val transfer = when (video?.colorInfo?.colorTransfer) {
            null -> if (video == null) null else "bt.1886"
            C.COLOR_TRANSFER_ST2084 -> "pq"
            C.COLOR_TRANSFER_HLG -> "hlg"
            else -> "bt.1886"
        }
        emit(
            mapOf(
                "event" to "state",
                "position" to exo.currentPosition,
                "duration" to exo.duration.takeIf { it != C.TIME_UNSET },
                "paused" to !exo.playWhenReady,
                "buffering" to (exo.playbackState == Player.STATE_BUFFERING),
                "ended" to (exo.playbackState == Player.STATE_ENDED),
                "volume" to (exo.volume * 100).toDouble(),
                "transfer" to transfer,
                "dolbyVision" to (video?.sampleMimeType == MimeTypes.VIDEO_DOLBY_VISION),
                "fps" to video?.frameRate?.takeIf { it > 0 }?.toDouble(),
                "tracks" to trackList(exo.currentTracks),
            ),
        )
    }

    private fun stats(): Map<String, Any?> {
        val exo = player ?: return emptyMap()
        val video = exo.videoFormat
        val audio = exo.audioFormat
        return mapOf(
            "videoMime" to video?.sampleMimeType,
            "videoCodecs" to video?.codecs,
            "width" to video?.width?.takeIf { it > 0 },
            "height" to video?.height?.takeIf { it > 0 },
            "fps" to video?.frameRate?.takeIf { it > 0 }?.toDouble(),
            "videoBitrate" to video?.bitrate?.takeIf { it > 0 },
            "videoDecoder" to videoDecoder,
            "audioMime" to audio?.sampleMimeType,
            "channels" to audio?.channelCount?.takeIf { it > 0 },
            "sampleRate" to audio?.sampleRate?.takeIf { it > 0 },
            "audioBitrate" to audio?.bitrate?.takeIf { it > 0 },
            "audioDecoder" to audioDecoder,
            "dropped" to exo.videoDecoderCounters?.droppedBufferCount,
            "speed" to exo.playbackParameters.speed.toDouble(),
        )
    }

    private fun emit(event: Map<String, Any?>) {
        sink?.success(event)
    }

    private class CopiedDolbyVisionRenderer(
        context: Context, selector: MediaCodecSelector, joiningTimeMs: Long, decoderFallback: Boolean,
        handler: Handler, listener: VideoRendererEventListener, private val codecs: () -> String?,
    ) : MediaCodecVideoRenderer(context, selector, joiningTimeMs, decoderFallback, handler, listener,
        DefaultRenderersFactory.MAX_DROPPED_VIDEO_FRAME_COUNT_TO_NOTIFY) {

        override fun onInputFormatChanged(formatHolder: FormatHolder): DecoderReuseEvaluation? {
            val dv = codecs()
            val format = formatHolder.format
            if (dv != null && format?.sampleMimeType == MimeTypes.VIDEO_H265) {
                formatHolder.format = format.buildUpon().setSampleMimeType(MimeTypes.VIDEO_DOLBY_VISION).setCodecs(dv).build()
            }
            return super.onInputFormatChanged(formatHolder)
        }
    }

    companion object {
        private const val TAG = "ZerkPlayer"
        private val TRAILING_NUMBER = Regex("""(\d+)$""")
        private val SUBTITLE_STREAM_INDEX = Regex("""CurrentSubtitleStreamIndex=(\d+)""")
    }
}

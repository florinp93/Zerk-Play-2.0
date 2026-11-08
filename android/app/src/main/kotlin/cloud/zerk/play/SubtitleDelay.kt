package cloud.zerk.play

import androidx.annotation.OptIn
import androidx.media3.common.Format
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ForwardingRenderer
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.RendererConfiguration
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.SampleStream

@OptIn(UnstableApi::class)
class SubtitleDelayRenderer(renderer: Renderer, private val delayUs: () -> Long) : ForwardingRenderer(renderer) {

    override fun enable(
        configuration: RendererConfiguration, formats: Array<out Format>, stream: SampleStream, positionUs: Long,
        joining: Boolean, mayRenderStartOfStream: Boolean, startPositionUs: Long, offsetUs: Long,
        mediaPeriodId: MediaSource.MediaPeriodId,
    ) = super.enable(configuration, formats, stream, positionUs - delayUs(), joining, mayRenderStartOfStream,
        startPositionUs, offsetUs, mediaPeriodId)

    override fun resetPosition(positionUs: Long, sampleStreamIsResetToKeyFrame: Boolean) =
        super.resetPosition(positionUs - delayUs(), sampleStreamIsResetToKeyFrame)

    override fun render(positionUs: Long, elapsedRealtimeUs: Long) = super.render(positionUs - delayUs(), elapsedRealtimeUs)

    override fun isEnded() = super.isEnded() || (isCurrentStreamFinal && hasReadStreamToEnd())
}

package cloud.zerk.play

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.roundToInt

class DownmixTuning(
    val matrices: Map<Int, FloatArray>,
    val threshold: Float,
    val ratio: Float,
    val makeup: Float,
    val attackMs: Float,
    val releaseMs: Float,
    val limit: Float,
) {
    fun gain(envelope: Float): Float {
        val compressed = if (envelope > threshold) (threshold + (envelope - threshold) / ratio) / envelope else 1f
        return compressed * makeup
    }

    companion object {
        fun from(config: Map<String, Any?>?): DownmixTuning? {
            val raw = config?.get("matrices") as? Map<*, *> ?: return null
            val matrices = raw.entries.mapNotNull { (k, v) ->
                val channels = k.toString().toIntOrNull() ?: return@mapNotNull null
                val values = (v as? List<*>)?.map { (it as Number).toFloat() } ?: return@mapNotNull null
                if (values.size != channels * 2) return@mapNotNull null
                channels to values.toFloatArray()
            }.toMap()
            fun num(key: String) = (config[key] as Number).toFloat()
            return DownmixTuning(
                matrices,
                num("threshold"),
                num("ratio"),
                num("makeup"),
                num("attackMs"),
                num("releaseMs"),
                num("limit"),
            )
        }
    }
}

@OptIn(UnstableApi::class)
class DialogueDownmixProcessor(
    private val tuning: DownmixTuning?,
    private val enabled: () -> Boolean,
) : BaseAudioProcessor() {

    private var matrix: FloatArray? = null
    private var attack = 0f
    private var release = 0f
    private var envelope = 0f

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        val t = tuning ?: return AudioProcessor.AudioFormat.NOT_SET
        if (!enabled()) return AudioProcessor.AudioFormat.NOT_SET
        val encoding = inputAudioFormat.encoding
        if (encoding != C.ENCODING_PCM_16BIT && encoding != C.ENCODING_PCM_FLOAT) return AudioProcessor.AudioFormat.NOT_SET
        if (t.matrices[inputAudioFormat.channelCount] == null) return AudioProcessor.AudioFormat.NOT_SET
        return AudioProcessor.AudioFormat(inputAudioFormat.sampleRate, 2, encoding)
    }

    override fun onFlush() {
        val t = tuning
        matrix = t?.matrices?.get(inputAudioFormat.channelCount)
        val rate = inputAudioFormat.sampleRate.coerceAtLeast(1)
        attack = t?.let { exp(-1000f / (rate * it.attackMs)) } ?: 0f
        release = t?.let { exp(-1000f / (rate * it.releaseMs)) } ?: 0f
        envelope = 0f
    }

    override fun onReset() {
        matrix = null
        envelope = 0f
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val t = tuning
        val m = matrix
        if (t == null || m == null) {
            val out = replaceOutputBuffer(inputBuffer.remaining())
            out.put(inputBuffer)
            out.flip()
            return
        }
        val channels = inputAudioFormat.channelCount
        val float = inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT
        val bytes = if (float) 4 else 2
        val frames = inputBuffer.remaining() / (channels * bytes)
        val src = inputBuffer.duplicate().order(ByteOrder.nativeOrder())
        val out = replaceOutputBuffer(frames * 2 * bytes)
        val limit = t.limit
        for (f in 0 until frames) {
            var l = 0f
            var r = 0f
            for (c in 0 until channels) {
                val s = if (float) src.getFloat() else src.getShort() / 32768f
                l += s * m[c * 2]
                r += s * m[c * 2 + 1]
            }
            val peak = max(abs(l), abs(r))
            envelope = if (peak > envelope) attack * envelope + (1 - attack) * peak else release * envelope + (1 - release) * peak
            val g = t.gain(envelope)
            l = (l * g).coerceIn(-limit, limit)
            r = (r * g).coerceIn(-limit, limit)
            if (float) {
                out.putFloat(l)
                out.putFloat(r)
            } else {
                out.putShort((l * 32767f).roundToInt().toShort())
                out.putShort((r * 32767f).roundToInt().toShort())
            }
        }
        inputBuffer.position(inputBuffer.limit())
        out.flip()
    }
}

package cloud.zerk.play

import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.ForwardingAudioSink
import java.nio.ByteBuffer
import java.nio.ByteOrder

object Ac3Encoder {
    const val FRAME_SAMPLES = 1536
    const val MAX_FRAME_BYTES = 3840

    val available: Boolean = runCatching { System.loadLibrary("zerkac3") }
        .onFailure { Log.w("Ac3Encoder", "libzerkac3 not loaded", it) }
        .isSuccess

    @JvmStatic external fun nativeOpen(sampleRate: Int, bitrateKbps: Int): Long
    @JvmStatic external fun nativeEncode(handle: Long, pcm: ByteBuffer, channels: Int, isFloat: Boolean, out: ByteBuffer): Int
    @JvmStatic external fun nativeClose(handle: Long)
}

@OptIn(UnstableApi::class)
class Ac3EncodingAudioSink(
    sink: AudioSink,
    private val passthrough: Set<Int>?,
    private val encode: Boolean,
) : ForwardingAudioSink(sink) {

    private var handle = 0L
    private var channels = 0
    private var isFloat = false
    private var sampleRate = 0
    private var bytesPerFrame = 0

    private var pcm: ByteBuffer? = null
    private var pcmStartUs = 0L

    private val out = ByteBuffer.allocateDirect(Ac3Encoder.MAX_FRAME_BYTES).order(ByteOrder.nativeOrder())
    private var outPending = false
    private var outUs = 0L

    private var input: ByteBuffer? = null
    private var inputStart = 0

    private val encoding get() = handle != 0L

    override fun supportsFormat(format: Format) = getFormatSupport(format) != AudioSink.SINK_FORMAT_UNSUPPORTED

    override fun getFormatSupport(format: Format): Int {
        val mime = format.sampleMimeType
        if (passthrough != null && mime != null && mime != MimeTypes.AUDIO_RAW) {
            val e = MimeTypes.getEncoding(mime, format.codecs)
            if (e != C.ENCODING_INVALID && e !in passthrough) return AudioSink.SINK_FORMAT_UNSUPPORTED
        }
        return super.getFormatSupport(format)
    }

    override fun configure(inputFormat: Format, specifiedBufferSize: Int, outputChannels: IntArray?) {
        close()
        val pcmEncoding = inputFormat.pcmEncoding
        val wanted = encode && Ac3Encoder.available &&
            inputFormat.sampleMimeType == MimeTypes.AUDIO_RAW &&
            (pcmEncoding == C.ENCODING_PCM_16BIT || pcmEncoding == C.ENCODING_PCM_FLOAT) &&
            (inputFormat.channelCount == 6 || inputFormat.channelCount == 8) &&
            inputFormat.sampleRate in SAMPLE_RATES
        if (wanted) {
            val ac3 = Format.Builder()
                .setSampleMimeType(MimeTypes.AUDIO_AC3)
                .setChannelCount(6)
                .setSampleRate(inputFormat.sampleRate)
                .setAverageBitrate(BITRATE_KBPS * 1000)
                .build()
            if (super.getFormatSupport(ac3) == AudioSink.SINK_FORMAT_SUPPORTED_DIRECTLY) {
                handle = Ac3Encoder.nativeOpen(inputFormat.sampleRate, BITRATE_KBPS)
            }
            if (encoding) {
                channels = inputFormat.channelCount
                isFloat = pcmEncoding == C.ENCODING_PCM_FLOAT
                sampleRate = inputFormat.sampleRate
                bytesPerFrame = channels * (if (isFloat) 4 else 2)
                pcm = ByteBuffer.allocateDirect(Ac3Encoder.FRAME_SAMPLES * bytesPerFrame).order(ByteOrder.nativeOrder())
                Log.i(TAG, "encoding ${inputFormat.channelCount}ch ${if (isFloat) "float" else "pcm-16"} " +
                    "${inputFormat.sampleRate} Hz to AC-3 5.1 $BITRATE_KBPS kbps")
                super.configure(ac3, 0, null)
                return
            }
        }
        super.configure(inputFormat, specifiedBufferSize, outputChannels)
    }

    override fun handleBuffer(buffer: ByteBuffer, presentationTimeUs: Long, encodedAccessUnitCount: Int): Boolean {
        if (!encoding) return super.handleBuffer(buffer, presentationTimeUs, encodedAccessUnitCount)
        if (buffer !== input) {
            input = buffer
            inputStart = buffer.position()
        }
        val pcm = pcm!!
        while (true) {
            if (outPending) {
                if (!super.handleBuffer(out, outUs, 1)) return false
                outPending = false
            }
            if (!buffer.hasRemaining()) {
                input = null
                return true
            }
            if (pcm.position() == 0) {
                val framesIn = (buffer.position() - inputStart) / bytesPerFrame
                pcmStartUs = presentationTimeUs + framesIn * C.MICROS_PER_SECOND / sampleRate
            }
            val n = minOf(buffer.remaining(), pcm.remaining())
            val slice = buffer.duplicate()
            slice.limit(slice.position() + n)
            pcm.put(slice)
            buffer.position(buffer.position() + n)
            if (!pcm.hasRemaining()) encodeFrame(pcmStartUs)
        }
    }

    private fun encodeFrame(timeUs: Long) {
        val pcm = pcm!!
        pcm.flip()
        out.clear()
        val size = Ac3Encoder.nativeEncode(handle, pcm, channels, isFloat, out)
        pcm.clear()
        if (size <= 0) {
            Log.w(TAG, "AC-3 encode failed ($size)")
            return
        }
        out.limit(size)
        outUs = timeUs
        outPending = true
    }

    override fun playToEndOfStream() {
        if (encoding) {
            val pcm = pcm!!
            if (pcm.position() > 0 && !outPending) {
                while (pcm.hasRemaining()) pcm.put(0)
                encodeFrame(pcmStartUs)
            }
            val deadline = System.nanoTime() + 2_000_000_000L
            while (outPending && System.nanoTime() < deadline) {
                if (super.handleBuffer(out, outUs, 1)) outPending = false else Thread.sleep(5)
            }
            outPending = false
        }
        super.playToEndOfStream()
    }

    override fun isEnded() = !outPending && super.isEnded()

    override fun hasPendingData() = outPending || super.hasPendingData()

    override fun flush() {
        clearBuffers()
        super.flush()
    }

    override fun reset() {
        close()
        super.reset()
    }

    override fun release() {
        close()
        super.release()
    }

    private fun clearBuffers() {
        pcm?.clear()
        outPending = false
        input = null
    }

    private fun close() {
        clearBuffers()
        pcm = null
        if (handle != 0L) Ac3Encoder.nativeClose(handle)
        handle = 0L
    }

    companion object {
        private const val TAG = "Ac3EncodingAudioSink"
        private const val BITRATE_KBPS = 640
        private val SAMPLE_RATES = setOf(48_000, 44_100, 32_000)
    }
}

package cloud.zerk.play

import android.app.Activity
import android.media.MediaCodecInfo.CodecProfileLevel
import android.media.MediaCodecList
import android.os.Build
import android.view.Display
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.decoder.ffmpeg.FfmpegLibrary
import androidx.media3.exoplayer.audio.AudioCapabilities

@OptIn(UnstableApi::class)
object DeviceCaps {
    fun query(activity: Activity): Map<String, Any?> {
        val codecs = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filter { !it.isEncoder }

        fun decoders(mime: String) = codecs.filter { info -> info.supportedTypes.any { it.equals(mime, ignoreCase = true) } }
        fun hasDecoder(mime: String) = decoders(mime).isNotEmpty()
        fun hasProfile(mime: String, profile: Int) = decoders(mime).any { info ->
            info.getCapabilitiesForType(mime).profileLevels.any { it.profile == profile }
        }

        fun maxSize(mime: String): List<Int>? = decoders(mime).mapNotNull { info ->
            info.getCapabilitiesForType(mime).videoCapabilities?.let { listOf(it.supportedWidths.upper, it.supportedHeights.upper) }
        }.maxByOrNull { it[0] * it[1] }

        val video = mapOf(
            "h264" to hasDecoder(MimeTypes.VIDEO_H264),
            "hevc" to hasDecoder(MimeTypes.VIDEO_H265),
            "hevcMain10" to hasProfile(MimeTypes.VIDEO_H265, CodecProfileLevel.HEVCProfileMain10),
            "vp9" to hasDecoder(MimeTypes.VIDEO_VP9),
            "vp9Profile2" to hasProfile(MimeTypes.VIDEO_VP9, CodecProfileLevel.VP9Profile2),
            "av1" to hasDecoder(MimeTypes.VIDEO_AV1),
            "vp8" to hasDecoder(MimeTypes.VIDEO_VP8),
            "mpeg2" to hasDecoder(MimeTypes.VIDEO_MPEG2),
            "mpeg4" to hasDecoder(MimeTypes.VIDEO_MP4V),
            "vc1" to hasDecoder("video/wvc1"),
            "dolbyVision" to hasDecoder(MimeTypes.VIDEO_DOLBY_VISION),
        )

        val sink = AudioCapabilities.getCapabilities(activity, AudioAttributes.DEFAULT, null)
        val passthrough = mapOf(
            "ac3" to sink.supportsEncoding(C.ENCODING_AC3),
            "eac3" to sink.supportsEncoding(C.ENCODING_E_AC3),
            "eac3joc" to sink.supportsEncoding(C.ENCODING_E_AC3_JOC),
            "dts" to sink.supportsEncoding(C.ENCODING_DTS),
            "dtshd" to sink.supportsEncoding(C.ENCODING_DTS_HD),
            "truehd" to sink.supportsEncoding(C.ENCODING_DOLBY_TRUEHD),
        )
        val ffmpeg = FfmpegLibrary.isAvailable()
        val ffmpegAudio = if (!ffmpeg) emptyList() else listOf(
            "ac3" to MimeTypes.AUDIO_AC3,
            "eac3" to MimeTypes.AUDIO_E_AC3,
            "dts" to MimeTypes.AUDIO_DTS,
            "dtshd" to MimeTypes.AUDIO_DTS_HD,
            "truehd" to MimeTypes.AUDIO_TRUEHD,
            "flac" to MimeTypes.AUDIO_FLAC,
            "alac" to MimeTypes.AUDIO_ALAC,
            "opus" to MimeTypes.AUDIO_OPUS,
            "vorbis" to MimeTypes.AUDIO_VORBIS,
            "mp2" to MimeTypes.AUDIO_MPEG_L2,
            "mp3" to MimeTypes.AUDIO_MPEG,
            "aac" to MimeTypes.AUDIO_AAC,
            "pcm_mulaw" to MimeTypes.AUDIO_MLAW,
            "pcm_alaw" to MimeTypes.AUDIO_ALAW,
        ).filter { (_, mime) -> FfmpegLibrary.supportsFormat(mime) }.map { it.first }

        return mapOf(
            "model" to Build.MODEL,
            "sdk" to Build.VERSION.SDK_INT,
            "video" to video,
            "maxHevc" to maxSize(MimeTypes.VIDEO_H265),
            "maxH264" to maxSize(MimeTypes.VIDEO_H264),
            "dolbyVisionProfiles" to dolbyVisionProfiles,
            "passthrough" to passthrough,
            "maxChannels" to sink.maxChannelCount,
            "ffmpeg" to ffmpeg,
            "ffmpegAudio" to ffmpegAudio,
            "display" to displayHdr(activity),
        )
    }

    val dolbyVisionProfiles: List<Int> by lazy {
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
            .filter { info -> !info.isEncoder && info.supportedTypes.any { it.equals(MimeTypes.VIDEO_DOLBY_VISION, ignoreCase = true) } }
            .flatMap { it.getCapabilitiesForType(MimeTypes.VIDEO_DOLBY_VISION).profileLevels.map { p -> dvProfileNumber(p.profile) } }
            .filterNotNull().distinct().sorted()
    }

    @Suppress("DEPRECATION")
    fun displayHdr(activity: Activity): Map<String, Any?> {
        val display: Display? = if (Build.VERSION.SDK_INT >= 30) activity.display else activity.windowManager.defaultDisplay
        val types = display?.hdrCapabilities?.supportedHdrTypes ?: IntArray(0)
        val names = types.map {
            when (it) {
                Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION -> "dolbyVision"
                Display.HdrCapabilities.HDR_TYPE_HDR10 -> "hdr10"
                Display.HdrCapabilities.HDR_TYPE_HLG -> "hlg"
                Display.HdrCapabilities.HDR_TYPE_HDR10_PLUS -> "hdr10plus"
                else -> "other"
            }
        }
        return mapOf("supported" to names.isNotEmpty(), "enabled" to names.isNotEmpty(), "types" to names)
    }

    private fun dvProfileNumber(profile: Int): Int? = when (profile) {
        CodecProfileLevel.DolbyVisionProfileDvavPer -> 0
        CodecProfileLevel.DolbyVisionProfileDvavPen -> 1
        CodecProfileLevel.DolbyVisionProfileDvheDer -> 2
        CodecProfileLevel.DolbyVisionProfileDvheDen -> 3
        CodecProfileLevel.DolbyVisionProfileDvheDtr -> 4
        CodecProfileLevel.DolbyVisionProfileDvheStn -> 5
        CodecProfileLevel.DolbyVisionProfileDvheDth -> 6
        CodecProfileLevel.DolbyVisionProfileDvheDtb -> 7
        CodecProfileLevel.DolbyVisionProfileDvheSt -> 8
        CodecProfileLevel.DolbyVisionProfileDvavSe -> 9
        CodecProfileLevel.DolbyVisionProfileDvav110 -> 10
        else -> null
    }
}

package cloud.zerk.play

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.BaseColumns
import android.util.Log
import androidx.tvprovider.media.tv.TvContractCompat
import androidx.tvprovider.media.tv.TvContractCompat.PreviewProgramColumns
import androidx.tvprovider.media.tv.TvContractCompat.WatchNextPrograms
import androidx.tvprovider.media.tv.WatchNextProgram
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

object TvHome {
    private const val SCHEME = "zerkplay"
    private const val HOST = "play"
    private const val TAG = "TvHome"
    private val worker = Executors.newSingleThreadExecutor()
    private var channel: MethodChannel? = null
    private var pending: String? = null

    fun install(activity: Activity, messenger: BinaryMessenger) {
        val supported = Build.VERSION.SDK_INT >= 26 &&
            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        channel = MethodChannel(messenger, "zerk/tvhome").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeLaunch" -> result.success(pending.also { pending = null })
                    "publish", "clear" -> {
                        if (!supported) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        @Suppress("UNCHECKED_CAST")
                        val items = if (call.method == "clear") emptyList() else call.arguments as List<Map<String, Any?>>
                        val app = activity.applicationContext
                        worker.execute {
                            try {
                                sync(app, items)
                            } catch (e: Exception) {
                                Log.w(TAG, "watch next sync failed", e)
                            }
                            activity.runOnUiThread { result.success(null) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun onIntent(intent: Intent?, running: Boolean) {
        val data = intent?.data ?: return
        if (data.scheme != SCHEME || data.host != HOST) return
        pending = data.lastPathSegment ?: return
        if (running) channel?.invokeMethod("launch", null)
    }

    private fun sync(context: Context, items: List<Map<String, Any?>>) {
        val resolver = context.contentResolver
        val existing = HashMap<String, Row>()
        resolver.query(
            WatchNextPrograms.CONTENT_URI,
            arrayOf(BaseColumns._ID, PreviewProgramColumns.COLUMN_INTERNAL_PROVIDER_ID, PreviewProgramColumns.COLUMN_BROWSABLE),
            null, null, null,
        )?.use { c ->
            while (c.moveToNext()) {
                val key = c.getString(1) ?: continue
                existing[key] = Row(c.getLong(0), browsable = c.getInt(2) != 0)
            }
        }
        val keep = HashSet<String>()
        for (item in items) {
            val id = item["id"] as? String ?: continue
            keep += id
            val known = existing[id]
            if (known != null && !known.browsable) continue
            val values = program(id, item).toContentValues()
            if (known == null) {
                resolver.insert(WatchNextPrograms.CONTENT_URI, values)
            } else {
                resolver.update(TvContractCompat.buildWatchNextProgramUri(known.id), values, null, null)
            }
        }
        for ((id, row) in existing) {
            if (id !in keep) resolver.delete(TvContractCompat.buildWatchNextProgramUri(row.id), null, null)
        }
        Log.i(TAG, "watch next: ${keep.size} published, ${existing.keys.count { it !in keep }} removed")
    }

    private class Row(val id: Long, val browsable: Boolean)

    private fun program(id: String, item: Map<String, Any?>): WatchNextProgram {
        val position = (item["positionMs"] as? Number)?.toInt() ?: 0
        val episode = item["episodeTitle"] as? String
        val builder = WatchNextProgram.Builder()
            .setType(if (episode != null) PreviewProgramColumns.TYPE_TV_EPISODE else PreviewProgramColumns.TYPE_MOVIE)
            .setWatchNextType(
                if (position > 0) WatchNextPrograms.WATCH_NEXT_TYPE_CONTINUE else WatchNextPrograms.WATCH_NEXT_TYPE_NEXT,
            )
            .setLastEngagementTimeUtcMillis((item["engagedMs"] as? Number)?.toLong() ?: System.currentTimeMillis())
            .setTitle(item["title"] as? String ?: "")
            .setInternalProviderId(id)
            .setContentId(id)
            .setIntentUri(Uri.parse("$SCHEME://$HOST/$id"))
        if (episode != null) builder.setEpisodeTitle(episode)
        (item["season"] as? Number)?.let { builder.setSeasonNumber(it.toInt()) }
        (item["episode"] as? Number)?.let { builder.setEpisodeNumber(it.toInt()) }
        (item["overview"] as? String)?.let { builder.setDescription(it) }
        (item["image"] as? String)?.let {
            builder.setPosterArtUri(Uri.parse(it)).setPosterArtAspectRatio(PreviewProgramColumns.ASPECT_RATIO_16_9)
        }
        (item["durationMs"] as? Number)?.let { builder.setDurationMillis(it.toInt()) }
        if (position > 0) builder.setLastPlaybackPositionMillis(position)
        return builder.build()
    }
}

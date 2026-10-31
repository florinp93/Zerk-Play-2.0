package cloud.zerk.play

import android.app.Activity
import android.os.Build
import android.util.Log
import android.view.Display
import kotlin.math.abs

object DisplayModes {
    private const val TAG = "ZerkDisplay"
    private var switched = false

    private fun display(activity: Activity): Display? =
        if (Build.VERSION.SDK_INT >= 30) activity.display else @Suppress("DEPRECATION") activity.windowManager.defaultDisplay

    private fun fits(hz: Float, fps: Double): Boolean {
        for (k in 1..6) if (abs(hz - fps * k) < 0.02 * k) return true
        return false
    }

    fun match(activity: Activity, fps: Double): Double? {
        if (Build.VERSION.SDK_INT < 23 || fps < 10 || fps > 121) return null
        val display = display(activity) ?: return null
        val current = display.mode
        Log.i(TAG, "${"%.3f".format(fps)} fps video, display ${current.physicalWidth}x${current.physicalHeight} @ ${current.refreshRate} Hz")
        if (fits(current.refreshRate, fps)) return null
        val best = display.supportedModes
            .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight && fits(it.refreshRate, fps) }
            .minByOrNull { it.refreshRate }
        if (best == null) {
            Log.i(TAG, "no display mode fits ${"%.3f".format(fps)} fps")
            return null
        }
        val attrs = activity.window.attributes
        attrs.preferredDisplayModeId = best.modeId
        activity.window.attributes = attrs
        switched = true
        Log.i(TAG, "switching to mode ${best.modeId} (${best.refreshRate} Hz)")
        return best.refreshRate.toDouble()
    }

    fun restore(activity: Activity) {
        if (!switched || Build.VERSION.SDK_INT < 23) return
        switched = false
        val attrs = activity.window.attributes
        attrs.preferredDisplayModeId = 0
        activity.window.attributes = attrs
        Log.i(TAG, "display mode back to the system default")
    }
}

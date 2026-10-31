package cloud.zerk.play

import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.view.PixelCopy
import android.view.SurfaceView
import android.widget.FrameLayout
import kotlin.math.abs
import kotlin.math.min

class CropBox(context: Context) : FrameLayout(context) {
    var crop = 0f
        set(value) {
            if (field == value) return
            field = value
            requestLayout()
        }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        val child = getChildAt(0) ?: return
        val h = (measuredHeight / (1 - 2 * crop)).toInt()
        child.measure(MeasureSpec.makeMeasureSpec(measuredWidth, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY))
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val child = getChildAt(0) ?: return
        val top0 = (measuredHeight - child.measuredHeight) / 2
        child.layout(0, top0, child.measuredWidth, top0 + child.measuredHeight)
    }
}

class BarDetector(private val surface: SurfaceView, private val handler: Handler, private val onCrop: (Float) -> Unit) {
    private var seen: Float? = null
    private var hits = 0
    var applied = 0f
        private set

    fun reset() {
        seen = null
        hits = 0
        applied = 0f
    }

    fun sample() {
        if (Build.VERSION.SDK_INT < 24 || surface.width == 0 || !surface.holder.surface.isValid) return
        val bitmap = Bitmap.createBitmap(320, 180, Bitmap.Config.ARGB_8888)
        try {
            PixelCopy.request(surface, bitmap, { result ->
                if (result == PixelCopy.SUCCESS) analyse(bitmap)
                bitmap.recycle()
            }, handler)
        } catch (e: IllegalArgumentException) {
            bitmap.recycle()
        }
    }

    private fun black(bitmap: Bitmap, y: Int): Boolean {
        val w = bitmap.width
        val x0 = w / 20
        val step = (w * 9 / 10) / 40
        for (i in 0 until 40) {
            val c = bitmap.getPixel(x0 + i * step, y)
            if ((c shr 16 and 0xFF) > 24 || (c shr 8 and 0xFF) > 24 || (c and 0xFF) > 24) return false
        }
        return true
    }

    private fun analyse(bitmap: Bitmap) {
        val h = bitmap.height
        val limit = h * 3 / 10
        var top = 0
        while (top < limit && black(bitmap, top)) top++
        var bottom = 0
        while (bottom < limit && black(bitmap, h - 1 - bottom)) bottom++
        if (top >= limit || bottom >= limit) return
        var t = top.toFloat() / h
        var b = bottom.toFloat() / h
        if (t < 0.01f && b < 0.01f) { t = 0f; b = 0f }
        if (abs(t - b) > 0.02f) return
        val m = min(t, b)
        val last = seen
        if (last != null && abs(last - m) < 0.008f) hits++ else { seen = m; hits = 1 }
        if (hits >= 2 && ((applied == 0f && m > 0f) || m < applied - 0.006f || (hits >= 4 && abs(m - applied) > 0.006f))) {
            applied = m
            onCrop(m)
        }
    }
}

fun scopeHeight(scope: Float, width: Int, height: Int): Int =
    if (scope <= 0f || height == 0 || scope <= width.toFloat() / height + 0.01f) height else (width / scope).toInt()

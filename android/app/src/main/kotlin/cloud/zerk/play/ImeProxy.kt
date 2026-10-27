package cloud.zerk.play

import android.content.Context
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputMethodManager
import io.flutter.embedding.android.FlutterView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class ImeProxy private constructor(context: Context, private val flutterView: FlutterView) : View(context) {
    private var editing = false

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        if (Build.VERSION.SDK_INT >= 26) defaultFocusHighlightEnabled = false
    }

    override fun onCheckIsTextEditor() = editing

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection? =
        flutterView.onCreateInputConnection(outAttrs)

    override fun checkInputConnectionProxy(view: View) = view === flutterView

    private fun setEditing(value: Boolean) {
        if (editing == value) return
        editing = value
        if (!value) return
        if (!hasFocus()) requestFocus()
        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        imm.restartInput(this)
        imm.showSoftInput(this, 0)
    }

    companion object {
        fun install(flutterView: FlutterView, messenger: BinaryMessenger) {
            val proxy = ImeProxy(flutterView.context, flutterView)
            flutterView.addView(proxy, ViewGroup.LayoutParams(1, 1))
            flutterView.descendantFocusability = ViewGroup.FOCUS_AFTER_DESCENDANTS
            proxy.requestFocus()
            MethodChannel(messenger, "zerk/ime").setMethodCallHandler { call, result ->
                when (call.method) {
                    "editing" -> {
                        proxy.setEditing(call.arguments == true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
}

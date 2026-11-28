package cloud.zerk.play

fun scopeHeight(scope: Float, width: Int, height: Int): Int =
    if (scope <= 0f || height == 0 || scope <= width.toFloat() / height + 0.01f) height else (width / scope).toInt()

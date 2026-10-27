package cloud.zerk.play

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

object Updater {
    fun install(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, "zerk/updater").setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstall" -> result.success(
                    Build.VERSION.SDK_INT < 26 || activity.packageManager.canRequestPackageInstalls(),
                )
                "allowInstalls" -> result.success(
                    Build.VERSION.SDK_INT >= 26 && try {
                        activity.startActivity(
                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")),
                        )
                        true
                    } catch (e: ActivityNotFoundException) {
                        false
                    },
                )
                "install" -> {
                    val apk = File(call.arguments as String)
                    val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", apk)
                    val intent = Intent(Intent.ACTION_VIEW)
                        .setDataAndType(uri, "application/vnd.android.package-archive")
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                    try {
                        activity.startActivity(intent)
                        result.success(null)
                    } catch (e: ActivityNotFoundException) {
                        result.error("no_installer", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

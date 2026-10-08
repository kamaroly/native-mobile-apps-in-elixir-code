// mob_viewer plugin — Android bridge: open a file in the phone's viewer.
//
// Another app can't read a path inside ours, so the file is copied into
// the app's cache (the project's FileProvider shares the cache, for the
// camera) and handed over as a content:// address with a one-off
// permission to read it. Only a failure is delivered, as
// {:viewer, :error, json}.
//
// Registered by the generated MobPluginBootstrap (register() + setActivity).
// The native thunks are exported from the sibling zig NIF mob_viewer_nif.zig.
package io.mob.viewer

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File
import java.lang.ref.WeakReference

object MobViewerBridge : io.mob.plugin.MobActivityAware {
    private var activityRef: WeakReference<Activity>? = null

    @JvmStatic external fun nativeRegister()

    @JvmStatic external fun nativeDeliverError(pid: Long, json: String)

    @JvmStatic fun register() = nativeRegister()

    override fun setActivity(activity: Activity) {
        activityRef = WeakReference(activity)
    }

    // Signature matches the zig NIF call: (JLjava/lang/String;)V.
    @JvmStatic
    fun view_file(pid: Long, argsJson: String) {
        val activity = activityRef?.get()
        if (activity == null) {
            error(pid, "no_activity")
            return
        }

        val (path, mime) =
            try {
                val args = JSONObject(argsJson)
                args.getString("path") to args.getString("mime")
            } catch (e: Exception) {
                error(pid, "bad_arguments")
                return
            }

        val source = File(path)
        if (!source.isFile) {
            error(pid, "not_found")
            return
        }

        activity.runOnUiThread {
            try {
                // The same name each time for the same file, so opening a
                // report twice doesn't leave two copies behind.
                val shared = File(activity.cacheDir, "mob_viewer").apply { mkdirs() }
                val copy = File(shared, source.name)
                source.copyTo(copy, overwrite = true)

                val uri =
                    FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", copy)

                val intent =
                    Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, mime)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }

                activity.startActivity(intent)
            } catch (e: ActivityNotFoundException) {
                error(pid, "no_viewer")
            } catch (e: Exception) {
                error(pid, e.message ?: "failed")
            }
        }
    }

    private fun error(pid: Long, message: String) {
        nativeDeliverError(pid, JSONObject().put("message", message).toString())
    }
}

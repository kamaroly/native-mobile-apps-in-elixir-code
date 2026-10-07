// mob_google plugin — Android bridge: Sign in with Google.
//
// Shows the Google account chooser through Credential Manager (the
// "Sign in with Google" option, for a button the person tapped) and
// delivers {:google, :result, json} with the chosen account's ID token, or
// {:google, :error, json}. The token's audience is the server client id the
// app passes in: the server verifies the token against it.
//
// Registered by the generated MobPluginBootstrap (register() + setActivity).
// The native thunks are exported from the sibling zig NIF mob_google_nif.zig.
package io.mob.google

import android.app.Activity
import android.os.CancellationSignal
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialManagerCallback
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import org.json.JSONObject
import java.lang.ref.WeakReference
import java.util.concurrent.Executors

object MobGoogleBridge : io.mob.plugin.MobActivityAware {
    private var activityRef: WeakReference<Activity>? = null

    // Callbacks run here, off the main thread.
    private val worker = Executors.newSingleThreadExecutor()

    @JvmStatic external fun nativeRegister()

    @JvmStatic external fun nativeDeliverResult(pid: Long, json: String)

    @JvmStatic external fun nativeDeliverError(pid: Long, json: String)

    @JvmStatic fun register() = nativeRegister()

    override fun setActivity(activity: Activity) {
        activityRef = WeakReference(activity)
    }

    // Signature matches the zig NIF call: (JLjava/lang/String;)V.
    @JvmStatic
    fun google_sign_in(pid: Long, argsJson: String) {
        val activity = activityRef?.get()
        if (activity == null) {
            error(pid, "no_activity")
            return
        }

        val serverClientId =
            try {
                JSONObject(argsJson).getString("server_client_id")
            } catch (e: Exception) {
                error(pid, "bad_arguments")
                return
            }

        val request =
            GetCredentialRequest.Builder()
                .addCredentialOption(GetSignInWithGoogleOption.Builder(serverClientId).build())
                .build()

        // The chooser is UI: it has to start from the main thread.
        activity.runOnUiThread {
            CredentialManager.create(activity).getCredentialAsync(
                activity,
                request,
                CancellationSignal(),
                worker,
                object : CredentialManagerCallback<GetCredentialResponse, GetCredentialException> {
                    override fun onResult(result: GetCredentialResponse) = deliver(pid, result)

                    override fun onError(e: GetCredentialException) =
                        error(
                            pid,
                            when (e) {
                                is GetCredentialCancellationException -> "cancelled"
                                is NoCredentialException -> "no_accounts"
                                else -> e.message ?: e.type
                            }
                        )
                }
            )
        }
    }

    private fun deliver(pid: Long, result: GetCredentialResponse) {
        val credential = result.credential

        if (credential is CustomCredential &&
            credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
        ) {
            try {
                val google = GoogleIdTokenCredential.createFrom(credential.data)
                val json =
                    JSONObject()
                        .put("id_token", google.idToken)
                        .put("email", google.id)
                        .put("name", google.displayName ?: JSONObject.NULL)
                nativeDeliverResult(pid, json.toString())
            } catch (e: Exception) {
                error(pid, e.message ?: "unreadable_credential")
            }
        } else {
            error(pid, "unexpected_credential")
        }
    }

    private fun error(pid: Long, message: String) {
        nativeDeliverError(pid, JSONObject().put("message", message).toString())
    }
}

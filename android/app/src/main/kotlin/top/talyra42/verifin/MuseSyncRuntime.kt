package top.talyra42.verifin

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONObject

/** One scheduled job uses the same Flutter engine as the foreground ledger. */
object MuseSyncRuntime {
    private const val JOB_ID = 18791
    private const val KEY_ALIAS = "verifin.muse.read-token"
    private var channel: MethodChannel? = null
    private var ready = false
    private var completion: ((Boolean) -> Unit)? = null
    private var dispatched = false

    private fun prefs(context: Context) = context.getSharedPreferences("muse_sync", Context.MODE_PRIVATE)

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build())
        }.generateKey()
    }

    private fun saveToken(context: Context, origin: String, value: String) {
        require(Regex("[A-Za-z0-9_-]{32,128}").matches(value))
        val payload = JSONObject().put("origin", origin).put("token", value).toString()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val encoded = Base64.encodeToString(cipher.doFinal(payload.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
        check(prefs(context).edit().putString("token", encoded)
            .putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP)).commit())
    }

    private fun readToken(context: Context, origin: String): String {
        val settings = prefs(context)
        val encrypted = settings.getString("token", null) ?: return ""
        val iv = Base64.decode(settings.getString("iv", ""), Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv))
        val payload = JSONObject(String(cipher.doFinal(Base64.decode(encrypted, Base64.NO_WRAP)), Charsets.UTF_8))
        return if (payload.getString("origin") == origin) payload.getString("token") else ""
    }

    private fun schedule(context: Context, enabled: Boolean) {
        val scheduler = context.getSystemService(JobScheduler::class.java)
        if (!enabled) {
            scheduler.cancel(JOB_ID)
            return
        }
        if (scheduler.getPendingJob(JOB_ID) != null) return
        val job = JobInfo.Builder(JOB_ID, ComponentName(context, MuseSyncJobService::class.java))
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .setPeriodic(15 * 60 * 1000L)
            .setPersisted(true)
            .build()
        check(scheduler.schedule(job) == JobScheduler.RESULT_SUCCESS)
    }

    fun attach(context: Context, engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "verifin/muse_sync")
        channel!!.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "saveToken" -> {
                        saveToken(context, call.argument<String>("origin")!!, call.argument<String>("token")!!)
                        result.success(null)
                    }
                    "readToken" -> result.success(readToken(context, call.arguments as String))
                    "setEnabled" -> { schedule(context, call.arguments == true); result.success(null) }
                    "ready" -> { ready = true; result.success(null); dispatch() }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("MUSE_SYNC_FAILED", "Could not configure secure bill synchronization", null)
            }
        }
    }

    fun run(context: Context, done: (Boolean) -> Unit) {
        check(completion == null)
        completion = done
        LedgerRuntime.engine(context)
        dispatch()
    }

    private fun dispatch() {
        if (!ready || completion == null || dispatched) return
        dispatched = true
        channel!!.invokeMethod("sync", null, object : MethodChannel.Result {
            override fun success(result: Any?) = finish(result == true)
            override fun error(code: String, message: String?, details: Any?) = finish(false)
            override fun notImplemented() = finish(false)
        })
    }

    fun finish(success: Boolean) {
        val callback = completion
        completion = null
        dispatched = false
        callback?.invoke(success)
    }
}

class MuseSyncJobService : JobService() {
    private val handler = Handler(Looper.getMainLooper())
    private var params: JobParameters? = null
    private val timeout = Runnable { MuseSyncRuntime.finish(false) }

    override fun onStartJob(job: JobParameters): Boolean {
        params = job
        handler.postDelayed(timeout, 90_000)
        MuseSyncRuntime.run(this) { success ->
            handler.removeCallbacks(timeout)
            params?.let { jobFinished(it, !success) }
            params = null
        }
        return true
    }

    override fun onStopJob(job: JobParameters): Boolean {
        params = null
        handler.removeCallbacks(timeout)
        MuseSyncRuntime.finish(false)
        return true
    }
}

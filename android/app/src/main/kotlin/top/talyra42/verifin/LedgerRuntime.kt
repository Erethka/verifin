package top.talyra42.verifin

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/** 界面与账单同步共用控制器，避免两份状态覆盖同一个账本。 */
object LedgerRuntime {
    private var engine: FlutterEngine? = null

    fun engine(context: Context): FlutterEngine {
        engine?.let { return it }
        val app = context.applicationContext
        app.deleteSharedPreferences("payment_capture")
        val created = FlutterEngine(app)
        engine = created
        MuseSyncRuntime.attach(app, created)
        created.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        return created
    }
}

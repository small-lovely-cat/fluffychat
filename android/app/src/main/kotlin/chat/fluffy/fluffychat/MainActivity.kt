package chat.fluffy.fluffychat

import android.app.Application
import android.content.Context
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return provideEngine(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        HttpDnsChannel.attach(application as Application, flutterEngine)
        AppLockAuthChannel.attach(this, flutterEngine)
    }

    companion object {
        var engine: FlutterEngine? = null

        fun provideEngine(context: Context): FlutterEngine {
            val eng = engine ?: FlutterEngine(context, emptyArray(), true, false)
            HttpDnsChannel.attach(context.applicationContext as Application, eng)
            engine = eng
            return eng
        }
    }
}

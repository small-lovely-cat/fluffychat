package chat.fluffy.fluffychat

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class HttpDnsChannel private constructor(
    application: Application,
    flutterEngine: FlutterEngine,
) : MethodChannel.MethodCallHandler {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val manager = AndroidHttpDnsManager.getInstance(application)
    private val channel = MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        CHANNEL_NAME,
    )

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configure" -> handleConfigure(call, result)
            "lookup" -> handleLookup(call, result)
            else -> result.notImplemented()
        }
    }

    /**
     * Applies the latest provider and domain list configuration from Flutter.
     *
     * @param call Incoming method call carrying provider and domain list arguments.
     * @param result Method channel result callback.
     */
    private fun handleConfigure(call: MethodCall, result: MethodChannel.Result) {
        val provider = HttpDnsProvider.fromStorageValue(call.argument<String>("provider"))
        val keepAliveDomains = call.argument<List<String>>("keepAliveDomains") ?: emptyList()
        val preloadDomains = call.argument<List<String>>("preloadDomains") ?: emptyList()

        scope.launch {
            val status = manager.configure(provider, keepAliveDomains, preloadDomains)
            withContext(Dispatchers.Main) {
                result.success(status)
            }
        }
    }

    /**
     * Resolves the given host through the active native HTTPDNS SDK on an IO thread.
     *
     * @param call Incoming method call carrying the host name to resolve.
     * @param result Method channel result callback.
     */
    private fun handleLookup(call: MethodCall, result: MethodChannel.Result) {
        val host = call.argument<String>("host").orEmpty()
        scope.launch {
            val addresses = if (host.isBlank()) {
                emptyList()
            } else {
                manager.lookupIpv4Addresses(host)
            }
            withContext(Dispatchers.Main) {
                result.success(addresses)
            }
        }
    }

    companion object {
        private const val CHANNEL_NAME = "chat.fluffy.fluffychat/httpdns"
        private val attachedEngines = mutableSetOf<Int>()

        /**
         * Attaches the HTTPDNS method channel to the shared Flutter engine.
         *
         * @param application Application context used by the native manager.
         * @param flutterEngine Flutter engine that should expose the method channel.
         */
        fun attach(application: Application, flutterEngine: FlutterEngine) {
            val engineIdentity = System.identityHashCode(flutterEngine.dartExecutor.binaryMessenger)
            if (attachedEngines.add(engineIdentity)) {
                HttpDnsChannel(application, flutterEngine)
            }
        }
    }
}

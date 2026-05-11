package chat.fluffy.fluffychat

import android.app.Application
import android.util.Log
import com.alibaba.pdns.DNSResolver

class AndroidHttpDnsManager private constructor(
    private val application: Application,
) {
    private val stateLock = Any()
    private var sdkInitialized = false
    private var selectedProvider = HttpDnsProvider.NONE
    private var effectiveProvider = HttpDnsProvider.NONE
    private var keepAliveDomains = emptyList<String>()
    private var preloadDomains = emptyList<String>()
    private var statusMessage: String? = null

    /**
     * Returns the current bridge status that Flutter can render.
     *
     * @return A map describing platform support, credentials, active provider, and warnings.
     */
    fun status(): Map<String, Any?> = synchronized(stateLock) {
        statusLocked()
    }

    /**
     * Applies the provider selection and the effective domain lists from Flutter.
     *
     * @param provider The provider selected in Flutter settings.
     * @param keepAliveDomains Domain list that should stay warm in SDK cache.
     * @param preloadDomains Domain list that should be preloaded by the SDK.
     * @return A status payload describing the applied native state.
     */
    fun configure(
        provider: HttpDnsProvider,
        keepAliveDomains: List<String>,
        preloadDomains: List<String>,
    ): Map<String, Any?> = synchronized(stateLock) {
        selectedProvider = provider
        this.keepAliveDomains = keepAliveDomains.distinct()
        this.preloadDomains = preloadDomains.distinct()

        when (provider) {
            HttpDnsProvider.NONE -> deactivateLocked()
            HttpDnsProvider.ALIYUN -> activateAliyunLocked()
        }

        statusLocked()
    }

    /**
     * Resolves a host through the active HTTPDNS provider.
     *
     * @param host The original request host that Dart needs to resolve.
     * @return A list of IPv4 addresses from the native SDK, or an empty list when unavailable.
     */
    fun lookupIpv4Addresses(host: String): List<String> = synchronized(stateLock) {
        if (effectiveProvider != HttpDnsProvider.ALIYUN) {
            return emptyList()
        }
        if (!ensureAliyunInitializedLocked()) {
            return emptyList()
        }
        resolveIpv4AddressesLocked(host)
    }

    /**
     * Enables Aliyun HTTPDNS and pushes the latest domain lists into the SDK.
     */
    private fun activateAliyunLocked() {
        if (!credentialsConfigured()) {
            effectiveProvider = HttpDnsProvider.NONE
            statusMessage =
                "Aliyun HTTPDNS credentials are missing from this build. " +
                    "Set ALIYUN_HTTPDNS_ACCOUNT_ID, ALIYUN_HTTPDNS_ACCESS_KEY_ID, " +
                    "and ALIYUN_HTTPDNS_ACCESS_KEY_SECRET in CI."
            return
        }
        if (!ensureAliyunInitializedLocked()) {
            return
        }

        applyKeepAliveDomainsLocked()
        applyPreloadDomainsLocked()
        effectiveProvider = HttpDnsProvider.ALIYUN
        statusMessage = null
    }

    /**
     * Deactivates the current provider while clearing the keep-alive list.
     */
    private fun deactivateLocked() {
        effectiveProvider = HttpDnsProvider.NONE
        statusMessage = null
        if (!sdkInitialized) {
            return
        }
        runCatching {
            DNSResolver.setKeepAliveDomains(emptyArray())
        }.onFailure { throwable ->
            Log.w(LOG_TAG, "Unable to clear HTTPDNS keep-alive domains", throwable)
        }
    }

    /**
     * Initializes the Aliyun SDK when credentials are available.
     *
     * @return True when the SDK is ready for lookups, otherwise false.
     */
    private fun ensureAliyunInitializedLocked(): Boolean {
        if (sdkInitialized) {
            return true
        }
        if (!credentialsConfigured()) {
            statusMessage =
                "Aliyun HTTPDNS credentials are missing from this build."
            effectiveProvider = HttpDnsProvider.NONE
            return false
        }

        return runCatching {
            DNSResolver.setEnableLogger(BuildConfig.DEBUG)
            DNSResolver.Init(
                application,
                BuildConfig.ALIYUN_HTTPDNS_ACCOUNT_ID,
                BuildConfig.ALIYUN_HTTPDNS_ACCESS_KEY_ID,
                BuildConfig.ALIYUN_HTTPDNS_ACCESS_KEY_SECRET,
            )
            sdkInitialized = true
            true
        }.getOrElse { throwable ->
            effectiveProvider = HttpDnsProvider.NONE
            statusMessage =
                "Failed to initialize Aliyun HTTPDNS. Check credentials and SDK configuration."
            Log.e(LOG_TAG, "Unable to initialize Aliyun HTTPDNS", throwable)
            false
        }
    }

    /**
     * Applies the keep-alive list to the native SDK.
     */
    private fun applyKeepAliveDomainsLocked() {
        runCatching {
            DNSResolver.setKeepAliveDomains(keepAliveDomains.toTypedArray())
        }.onFailure { throwable ->
            statusMessage =
                "Aliyun HTTPDNS keep-alive configuration failed. Check the configured domains."
            Log.e(LOG_TAG, "Unable to apply HTTPDNS keep-alive domains", throwable)
        }
    }

    /**
     * Applies the preload list to the native SDK.
     */
    private fun applyPreloadDomainsLocked() {
        if (preloadDomains.isEmpty()) {
            return
        }
        runCatching {
            DNSResolver.getInstance().preLoadDomains(
                DNSResolver.QTYPE_IPV4,
                preloadDomains.toTypedArray(),
            )
        }.onFailure { throwable ->
            statusMessage =
                "Aliyun HTTPDNS preload configuration failed. Check the configured domains."
            Log.e(LOG_TAG, "Unable to apply HTTPDNS preload domains", throwable)
        }
    }

    /**
     * Resolves IPv4 addresses by checking SDK cache first and network second.
     *
     * @param host The host name that should be resolved through the SDK.
     * @return A list of IPv4 addresses from cache or live lookup.
     */
    private fun resolveIpv4AddressesLocked(host: String): List<String> {
        val resolver = DNSResolver.getInstance()
        val cachedAddresses = invokeStringArrayMethod(
            target = resolver,
            methodNames = listOf("getIpv4ByHostFromCache", "getIpsByHostFromCache"),
            arguments = arrayOf(host, true),
        )
        if (!cachedAddresses.isNullOrEmpty()) {
            return cachedAddresses
        }

        val networkAddresses = invokeStringArrayMethod(
            target = resolver,
            methodNames = listOf("getIPsV4ByHost", "getIpsV4ByHost", "getIpsByHost"),
            arguments = arrayOf(host),
        )
        if (!networkAddresses.isNullOrEmpty()) {
            return networkAddresses
        }

        val singleAddress = invokeStringMethod(
            target = resolver,
            methodNames = listOf("getIPV4ByHost", "getIpv4ByHost"),
            arguments = arrayOf(host),
        )
        return if (singleAddress.isNullOrBlank()) {
            emptyList()
        } else {
            listOf(singleAddress)
        }
    }

    /**
     * Invokes an SDK method that returns multiple string results.
     *
     * @param target The SDK instance hosting the method.
     * @param methodNames Possible method names across SDK versions.
     * @param arguments Arguments that should be passed to the SDK method.
     * @return A string list result, or null if no compatible method succeeds.
     */
    private fun invokeStringArrayMethod(
        target: Any,
        methodNames: List<String>,
        arguments: Array<Any>,
    ): List<String>? {
        for (methodName in methodNames) {
            val method = target.javaClass.methods.firstOrNull {
                it.name == methodName && it.parameterTypes.size == arguments.size
            } ?: continue
            val result = runCatching {
                method.invoke(target, *arguments)
            }.getOrNull() ?: continue
            when (result) {
                is Array<*> -> {
                    val values = result.filterIsInstance<String>().filter { it.isNotBlank() }
                    if (values.isNotEmpty()) {
                        return values
                    }
                }
                is Collection<*> -> {
                    val values = result.filterIsInstance<String>().filter { it.isNotBlank() }
                    if (values.isNotEmpty()) {
                        return values
                    }
                }
            }
        }
        return null
    }

    /**
     * Invokes an SDK method that returns a single string.
     *
     * @param target The SDK instance hosting the method.
     * @param methodNames Possible method names across SDK versions.
     * @param arguments Arguments that should be passed to the SDK method.
     * @return The resolved string, or null if no compatible method succeeds.
     */
    private fun invokeStringMethod(
        target: Any,
        methodNames: List<String>,
        arguments: Array<Any>,
    ): String? {
        for (methodName in methodNames) {
            val method = target.javaClass.methods.firstOrNull {
                it.name == methodName && it.parameterTypes.size == arguments.size
            } ?: continue
            val result = runCatching {
                method.invoke(target, *arguments)
            }.getOrNull() as? String
            if (!result.isNullOrBlank()) {
                return result
            }
        }
        return null
    }

    /**
     * Checks whether the current build contains all required Aliyun credentials.
     *
     * @return True when the build is ready to initialize the SDK.
     */
    private fun credentialsConfigured(): Boolean =
        BuildConfig.ALIYUN_HTTPDNS_CREDENTIALS_CONFIGURED

    /**
     * Builds the status payload shared back to Flutter.
     *
     * @return A method-channel friendly map that mirrors the native bridge state.
     */
    private fun statusLocked(): Map<String, Any?> = mapOf(
        "platformSupported" to true,
        "credentialsConfigured" to credentialsConfigured(),
        "selectedProvider" to selectedProvider.storageValue,
        "effectiveProvider" to effectiveProvider.storageValue,
        "keepAliveDomains" to keepAliveDomains,
        "preloadDomains" to preloadDomains,
        "message" to statusMessage,
    )

    companion object {
        private const val LOG_TAG = "FluffyHttpDns"

        @Volatile
        private var instance: AndroidHttpDnsManager? = null

        /**
         * Returns the singleton native HTTPDNS manager.
         *
         * @param application Application context used by the Aliyun SDK.
         * @return Shared manager instance for the current process.
         */
        fun getInstance(application: Application): AndroidHttpDnsManager =
            instance ?: synchronized(this) {
                instance ?: AndroidHttpDnsManager(application).also { createdManager ->
                    instance = createdManager
                }
            }
    }
}

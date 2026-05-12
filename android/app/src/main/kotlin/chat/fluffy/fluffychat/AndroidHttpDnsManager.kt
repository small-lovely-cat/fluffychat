package chat.fluffy.fluffychat

import android.app.Application
import android.util.Log
import com.alibaba.pdns.DNSResolver
import com.alibaba.pdns.log.HttpDnsLog
import com.alibaba.pdns.log.ILogger
import java.util.Locale

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
    private var lastLookupReport: String? = null

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
        resolveIpv4AddressesForCandidatesLocked(host)
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
        if (statusMessage.isNullOrBlank()) {
            statusMessage = "Aliyun HTTPDNS is active."
        }
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
            HttpDnsLog.setLogger(
                object : ILogger() {
                    override fun log(msg: String) {
                        Log.d(LOG_TAG, "AliyunSdk: $msg")
                    }
                },
            )
            DNSResolver.setSchemaType(DNSResolver.HTTPS)
            DNSResolver.setEnableCertificateValidation(true)
            DNSResolver.setTimeout(3)
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
        val cachedAddresses = runCatching {
            resolver.getIpv4ByHostFromCache(host, true)
        }.getOrElse { throwable ->
            Log.w(LOG_TAG, "HTTPDNS cache lookup failed for $host", throwable)
            emptyArray()
        }
        if (!cachedAddresses.isNullOrEmpty()) {
            return cachedAddresses
                .filter { it.isNotBlank() }
        }

        val networkAddresses = runCatching {
            resolver.getIPsV4ByHost(host)
        }.getOrElse { throwable ->
            Log.w(LOG_TAG, "HTTPDNS network lookup failed for $host", throwable)
            emptyArray()
        }
        if (!networkAddresses.isNullOrEmpty()) {
            return networkAddresses
                .filter { it.isNotBlank() }
        }

        val singleAddress = runCatching {
            resolver.getIPV4ByHost(host)
        }.getOrElse { throwable ->
            Log.w(LOG_TAG, "HTTPDNS single-address lookup failed for $host", throwable)
            null
        }
        return if (singleAddress.isNullOrBlank()) {
            emptyList()
        } else {
            listOf(singleAddress)
        }
    }

    /**
     * Tries all normalized variants of one host until the SDK returns IPv4 addresses.
     *
     * @param originalHost The host received from Flutter before normalization.
     * @return The first successful IPv4 address list, or an empty list when all variants fail.
     */
    private fun resolveIpv4AddressesForCandidatesLocked(originalHost: String): List<String> {
        val lookupCandidates = buildLookupCandidates(originalHost)
        if (lookupCandidates.isEmpty()) {
            Log.w(LOG_TAG, "Skip HTTPDNS lookup for invalid host: $originalHost")
            return emptyList()
        }

        for (candidateHost in lookupCandidates) {
            val resolvedAddresses = resolveIpv4AddressesLocked(candidateHost)
            if (resolvedAddresses.isNotEmpty()) {
                return resolvedAddresses
            }
        }

        logLookupFailureLocked(originalHost, lookupCandidates)
        return emptyList()
    }

    /**
     * Builds safe host variants for SDK lookup.
     *
     * @param originalHost The raw host from Flutter.
     * @return Distinct lookup candidates with trailing dots removed first.
     */
    private fun buildLookupCandidates(originalHost: String): List<String> {
        val trimmedHost = originalHost.trim()
        if (trimmedHost.isBlank()) {
            return emptyList()
        }

        val normalizedHost = trimmedHost
            .trimEnd('.')
            .lowercase(Locale.US)
        if (normalizedHost.isBlank()) {
            return emptyList()
        }

        return buildList {
            add(normalizedHost)
            if (trimmedHost != normalizedHost) {
                add(trimmedHost)
            }
        }.distinct()
    }

    /**
     * Prints the latest SDK request report after lookup failure for easier diagnosis.
     *
     * @param originalHost The raw host that Flutter asked to resolve.
     * @param lookupCandidates Candidate hosts already tried against the SDK.
     */
    private fun logLookupFailureLocked(
        originalHost: String,
        lookupCandidates: List<String>,
    ) {
        val requestReport = runCatching {
            DNSResolver.getInstance().getRequestReportInfo()
        }.getOrNull().orEmpty()
        lastLookupReport = requestReport.ifBlank { null }
        statusMessage =
            "Aliyun HTTPDNS lookup returned no IPv4 address for " +
                "$originalHost. requestReport=$requestReport"
        Log.w(
            LOG_TAG,
            "HTTPDNS returned no IPv4 address for host=$originalHost " +
                "candidates=$lookupCandidates requestReport=$requestReport",
        )
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
        "lastLookupReport" to lastLookupReport,
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

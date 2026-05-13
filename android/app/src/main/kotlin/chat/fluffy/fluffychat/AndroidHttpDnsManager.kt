package chat.fluffy.fluffychat

import android.app.Application
import android.util.Log
import com.alibaba.pdns.DNSResolver
import com.alibaba.pdns.log.HttpDnsLog
import com.alibaba.pdns.log.ILogger
import com.bytedancehttpdns.httpdns.DnsResult
import com.bytedancehttpdns.httpdns.HttpDns
import com.tencent.msdk.dns.DnsConfig
import com.tencent.msdk.dns.MSDKDnsResolver
import java.util.Locale

class AndroidHttpDnsManager private constructor(
    private val application: Application,
) {
    private val stateLock = Any()
    private var aliyunInitialized = false
    private var volcengineInitialized = false
    private var tencentInitialized = false
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
        val previousEffectiveProvider = effectiveProvider
        selectedProvider = provider
        this.keepAliveDomains = keepAliveDomains.distinct()
        this.preloadDomains = preloadDomains.distinct()
        statusMessage = null
        lastLookupReport = null

        if (previousEffectiveProvider != HttpDnsProvider.NONE &&
            previousEffectiveProvider != provider
        ) {
            deactivateProviderLocked(previousEffectiveProvider)
        }

        when (provider) {
            HttpDnsProvider.NONE -> deactivateProviderLocked(previousEffectiveProvider)
            HttpDnsProvider.ALIYUN -> activateAliyunLocked()
            HttpDnsProvider.VOLCENGINE -> activateVolcengineLocked()
            HttpDnsProvider.TENCENT -> activateTencentLocked()
        }

        return statusLocked()
    }

    /**
     * Resolves a host through the active HTTPDNS provider.
     *
     * @param host The original request host that Dart needs to resolve.
     * @return A list of IPv4 addresses from the native SDK, or an empty list when unavailable.
     */
    fun lookupIpv4Addresses(host: String): List<String> = synchronized(stateLock) {
        return when (effectiveProvider) {
            HttpDnsProvider.NONE -> emptyList()
            HttpDnsProvider.ALIYUN -> {
                if (!ensureAliyunInitializedLocked()) {
                    emptyList()
                } else {
                    resolveIpv4AddressesForCandidatesLocked(
                        originalHost = host,
                        provider = HttpDnsProvider.ALIYUN,
                        resolver = ::resolveAliyunIpv4AddressesLocked,
                    )
                }
            }

            HttpDnsProvider.VOLCENGINE -> {
                if (!ensureVolcengineInitializedLocked()) {
                    emptyList()
                } else {
                    resolveIpv4AddressesForCandidatesLocked(
                        originalHost = host,
                        provider = HttpDnsProvider.VOLCENGINE,
                        resolver = ::resolveVolcengineIpv4AddressesLocked,
                    )
                }
            }

            HttpDnsProvider.TENCENT -> {
                if (!ensureTencentInitializedLocked()) {
                    emptyList()
                } else {
                    resolveIpv4AddressesForCandidatesLocked(
                        originalHost = host,
                        provider = HttpDnsProvider.TENCENT,
                        resolver = ::resolveTencentIpv4AddressesLocked,
                    )
                }
            }
        }
    }

    /**
     * Enables Aliyun HTTPDNS and pushes the latest domain lists into the SDK.
     *
     * @return No return value.
     */
    private fun activateAliyunLocked() {
        if (!aliyunCredentialsConfigured()) {
            effectiveProvider = HttpDnsProvider.NONE
            statusMessage =
                "Aliyun HTTPDNS credentials are missing from this build. " +
                    "Set ALIYUN_HTTPDNS_ACCOUNT_ID, ALIYUN_HTTPDNS_ACCESS_KEY_ID, " +
                    "and ALIYUN_HTTPDNS_ACCESS_KEY_SECRET in CI or android/local.properties."
            return
        }
        if (!ensureAliyunInitializedLocked()) {
            return
        }

        applyAliyunKeepAliveDomainsLocked()
        applyAliyunPreloadDomainsLocked()
        effectiveProvider = HttpDnsProvider.ALIYUN
        if (statusMessage.isNullOrBlank()) {
            statusMessage = "Aliyun HTTPDNS is active."
        }
    }

    /**
     * Enables Volcengine HTTPDNS and pushes the latest preload list into the SDK.
     *
     * @return No return value.
     */
    private fun activateVolcengineLocked() {
        if (!volcengineCredentialsConfigured()) {
            effectiveProvider = HttpDnsProvider.NONE
            statusMessage =
                "Volcengine HTTPDNS credentials are missing from this build. " +
                    "Set VE_HTTPDNS_ACCOUNT_ID and VE_HTTPDNS_SECRET_KEY in CI or android/local.properties."
            return
        }
        if (!ensureVolcengineInitializedLocked()) {
            return
        }

        applyVolcenginePreloadDomainsLocked()
        effectiveProvider = HttpDnsProvider.VOLCENGINE
        if (statusMessage.isNullOrBlank()) {
            statusMessage = "Volcengine HTTPDNS is active."
        }
    }

    /**
     * Enables Tencent DNSPod HTTPDNS with the latest Flutter-managed domain lists.
     *
     * @return No return value.
     */
    private fun activateTencentLocked() {
        if (!tencentCredentialsConfigured()) {
            effectiveProvider = HttpDnsProvider.NONE
            statusMessage =
                "Tencent DNSPod HTTPDNS credentials are missing from this build. " +
                    "Set TENCENT_HTTPDNS_ID and TENCENT_HTTPDNS_KEY in CI or android/local.properties."
            return
        }
        if (!ensureTencentInitializedLocked(forceRefresh = true)) {
            return
        }

        effectiveProvider = HttpDnsProvider.TENCENT
        if (statusMessage.isNullOrBlank()) {
            statusMessage = "Tencent DNSPod HTTPDNS is active."
        }
    }

    /**
     * Deactivates one provider and clears its runtime configuration when needed.
     *
     * @param provider The provider that should be deactivated.
     * @return No return value.
     */
    private fun deactivateProviderLocked(provider: HttpDnsProvider) {
        when (provider) {
            HttpDnsProvider.NONE -> {
                effectiveProvider = HttpDnsProvider.NONE
                statusMessage = null
            }

            HttpDnsProvider.ALIYUN -> deactivateAliyunLocked()
            HttpDnsProvider.VOLCENGINE -> deactivateVolcengineLocked()
            HttpDnsProvider.TENCENT -> deactivateTencentLocked()
        }
    }

    /**
     * Clears Aliyun keep-alive configuration while keeping the SDK instance reusable.
     *
     * @return No return value.
     */
    private fun deactivateAliyunLocked() {
        effectiveProvider = HttpDnsProvider.NONE
        statusMessage = null
        if (!aliyunInitialized) {
            return
        }
        runCatching {
            DNSResolver.setKeepAliveDomains(emptyArray())
        }.onFailure { throwable ->
            Log.w(LOG_TAG, "Unable to clear Aliyun HTTPDNS keep-alive domains", throwable)
        }
    }

    /**
     * Clears Volcengine preload configuration while keeping the SDK instance reusable.
     *
     * @return No return value.
     */
    private fun deactivateVolcengineLocked() {
        effectiveProvider = HttpDnsProvider.NONE
        statusMessage = null
        if (!volcengineInitialized) {
            return
        }
        runCatching {
            HttpDns.getService().setPreloadHosts(null)
        }.onFailure { throwable ->
            Log.w(LOG_TAG, "Unable to clear Volcengine HTTPDNS preload domains", throwable)
        }
    }

    /**
     * Deactivates Tencent DNSPod HTTPDNS.
     *
     * Tencent's SDK configuration is init-time oriented, so the singleton is kept alive and only
     * the app-facing provider state is reset here.
     *
     * @return No return value.
     */
    private fun deactivateTencentLocked() {
        effectiveProvider = HttpDnsProvider.NONE
        statusMessage = null
        lastLookupReport = null
    }

    /**
     * Initializes the Aliyun SDK when credentials are available.
     *
     * @return True when the SDK is ready for lookups, otherwise false.
     */
    private fun ensureAliyunInitializedLocked(): Boolean {
        if (aliyunInitialized) {
            return true
        }
        if (!aliyunCredentialsConfigured()) {
            statusMessage = "Aliyun HTTPDNS credentials are missing from this build."
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
            aliyunInitialized = true
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
     * Initializes the Volcengine SDK when credentials are available.
     *
     * @return True when the SDK is ready for lookups, otherwise false.
     */
    private fun ensureVolcengineInitializedLocked(): Boolean {
        if (volcengineInitialized) {
            return true
        }
        if (!volcengineCredentialsConfigured()) {
            statusMessage = "Volcengine HTTPDNS credentials are missing from this build."
            effectiveProvider = HttpDnsProvider.NONE
            return false
        }
        if (BuildConfig.VE_HTTPDNS_USE_DOH && volcengineDohDomains().isEmpty()) {
            statusMessage =
                "Volcengine HTTPDNS DoH is enabled, but VE_HTTPDNS_DOH_DOMAINS is empty."
            effectiveProvider = HttpDnsProvider.NONE
            return false
        }

        return runCatching {
            HttpDns.getService().setEnableDebug(BuildConfig.DEBUG)
            HttpDns.getService().setHttpDnsPrefer(true)
            HttpDns.getService().setHttpDnsPreferTime(ALIYUN_TIMEOUT_MS)
            HttpDns.getService().setHttpDnsRequestTimeout(ALIYUN_TIMEOUT_SECONDS)
            if (BuildConfig.VE_HTTPDNS_USE_DOH) {
                HttpDns.getService().setHttpDnsDomainList(volcengineDohDomains())
            }
            HttpDns.getService().setHttpDnsDepend(VolcengineHttpDnsDepend(application))
            volcengineInitialized = true
            true
        }.getOrElse { throwable ->
            effectiveProvider = HttpDnsProvider.NONE
            statusMessage =
                "Failed to initialize Volcengine HTTPDNS. Check credentials and SDK configuration."
            Log.e(LOG_TAG, "Unable to initialize Volcengine HTTPDNS", throwable)
            false
        }
    }

    /**
     * Initializes Tencent DNSPod HTTPDNS with the current domain lists.
     *
     * @param forceRefresh True when the latest Flutter configuration should rebuild the SDK state.
     * @return True when the SDK is ready for lookups, otherwise false.
     */
    private fun ensureTencentInitializedLocked(forceRefresh: Boolean = false): Boolean {
        if (tencentInitialized && !forceRefresh) {
            return true
        }
        if (!tencentCredentialsConfigured()) {
            statusMessage = "Tencent DNSPod HTTPDNS credentials are missing from this build."
            effectiveProvider = HttpDnsProvider.NONE
            return false
        }

        return runCatching {
            val dnsConfig =
                DnsConfig.Builder()
                    .dnsId(BuildConfig.TENCENT_HTTPDNS_ID)
                    .dnsKey(BuildConfig.TENCENT_HTTPDNS_KEY)
                    .desHttp()
                    .logLevel(if (BuildConfig.DEBUG) Log.VERBOSE else Log.ERROR)
                    .preLookupDomains(*tencentPreloadDomains().toTypedArray())
                    .persistentCacheDomains(*tencentKeepAliveDomains().toTypedArray())
                    .timeoutMills(TENCENT_TIMEOUT_MS)
                    .build()
            MSDKDnsResolver.getInstance().init(application, dnsConfig)
            tencentInitialized = true
            true
        }.getOrElse { throwable ->
            effectiveProvider = HttpDnsProvider.NONE
            statusMessage =
                "Failed to initialize Tencent DNSPod HTTPDNS. Check credentials, cleartext policy, and SDK configuration."
            Log.e(LOG_TAG, "Unable to initialize Tencent DNSPod HTTPDNS", throwable)
            false
        }
    }

    /**
     * Applies the keep-alive list to the Aliyun SDK.
     *
     * @return No return value.
     */
    private fun applyAliyunKeepAliveDomainsLocked() {
        runCatching {
            DNSResolver.setKeepAliveDomains(keepAliveDomains.toTypedArray())
        }.onFailure { throwable ->
            statusMessage =
                "Aliyun HTTPDNS keep-alive configuration failed. Check the configured domains."
            Log.e(LOG_TAG, "Unable to apply Aliyun HTTPDNS keep-alive domains", throwable)
        }
    }

    /**
     * Applies the preload list to the Aliyun SDK.
     *
     * @return No return value.
     */
    private fun applyAliyunPreloadDomainsLocked() {
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
            Log.e(LOG_TAG, "Unable to apply Aliyun HTTPDNS preload domains", throwable)
        }
    }

    /**
     * Applies the preload list to the Volcengine SDK.
     *
     * @return No return value.
     */
    private fun applyVolcenginePreloadDomainsLocked() {
        runCatching {
            HttpDns.getService().setPreloadHosts(
                preloadDomains
                    .take(MAX_VOLCENGINE_PRELOAD_DOMAINS)
                    .takeIf { it.isNotEmpty() },
            )
        }.onFailure { throwable ->
            statusMessage =
                "Volcengine HTTPDNS preload configuration failed. Check the configured domains."
            Log.e(LOG_TAG, "Unable to apply Volcengine HTTPDNS preload domains", throwable)
        }
    }

    /**
     * Resolves IPv4 addresses through Tencent DNSPod HTTPDNS.
     *
     * @param host The host name that should be resolved through the SDK.
     * @return A list containing the resolved IPv4 address when available.
     */
    private fun resolveTencentIpv4AddressesLocked(host: String): List<String> {
        val addressPayload = runCatching {
            MSDKDnsResolver.getInstance().getAddrByName(host)
        }.getOrElse { throwable ->
            Log.w(LOG_TAG, "Tencent DNSPod HTTPDNS lookup failed for $host", throwable)
            null
        }
        updateTencentLookupReportLocked(host, addressPayload)
        val ipv4Address =
            addressPayload
                ?.split(';')
                ?.firstOrNull()
                ?.trim()
                ?.takeIf { it.isNotEmpty() && it != TENCENT_EMPTY_ADDRESS }
        return ipv4Address?.let(::listOf) ?: emptyList()
    }

    /**
     * Resolves IPv4 addresses through the Aliyun SDK.
     *
     * @param host The host name that should be resolved through the SDK.
     * @return A list of IPv4 addresses from cache or live lookup.
     */
    private fun resolveAliyunIpv4AddressesLocked(host: String): List<String> {
        val resolver = DNSResolver.getInstance()
        val cachedAddresses = runCatching {
            resolver.getIpv4ByHostFromCache(host, true)
        }.getOrElse { throwable ->
            Log.w(LOG_TAG, "Aliyun HTTPDNS cache lookup failed for $host", throwable)
            emptyArray()
        }
        if (!cachedAddresses.isNullOrEmpty()) {
            return cachedAddresses.filter { it.isNotBlank() }
        }

        val networkAddresses = runCatching {
            resolver.getIPsV4ByHost(host)
        }.getOrElse { throwable ->
            Log.w(LOG_TAG, "Aliyun HTTPDNS network lookup failed for $host", throwable)
            emptyArray()
        }
        if (!networkAddresses.isNullOrEmpty()) {
            return networkAddresses.filter { it.isNotBlank() }
        }

        val singleAddress = runCatching {
            resolver.getIPV4ByHost(host)
        }.getOrElse { throwable ->
            Log.w(LOG_TAG, "Aliyun HTTPDNS single-address lookup failed for $host", throwable)
            null
        }
        return if (singleAddress.isNullOrBlank()) {
            emptyList()
        } else {
            listOf(singleAddress)
        }
    }

    /**
     * Resolves IPv4 addresses through the Volcengine SDK.
     *
     * @param host The host name that should be resolved through the SDK.
     * @return A list of IPv4 addresses returned by the SDK.
     */
    private fun resolveVolcengineIpv4AddressesLocked(host: String): List<String> {
        val dnsResult = runCatching {
            HttpDns.getService().getHttpDnsResultForHostSyncBlock(host)
        }.getOrElse { throwable ->
            Log.w(LOG_TAG, "Volcengine HTTPDNS lookup failed for $host", throwable)
            null
        }
        updateVolcengineLookupReportLocked(dnsResult)
        return dnsResult?.ipv4List?.filter { it.isNotBlank() } ?: emptyList()
    }

    /**
     * Tries all normalized variants of one host until one provider returns IPv4 addresses.
     *
     * @param originalHost The host received from Flutter before normalization.
     * @param provider The provider currently performing the lookup.
     * @param resolver Provider-specific lookup function.
     * @return The first successful IPv4 address list, or an empty list when all variants fail.
     */
    private fun resolveIpv4AddressesForCandidatesLocked(
        originalHost: String,
        provider: HttpDnsProvider,
        resolver: (String) -> List<String>,
    ): List<String> {
        val lookupCandidates = buildLookupCandidates(originalHost)
        if (lookupCandidates.isEmpty()) {
            Log.w(LOG_TAG, "Skip HTTPDNS lookup for invalid host: $originalHost")
            return emptyList()
        }

        for (candidateHost in lookupCandidates) {
            val resolvedAddresses = resolver(candidateHost)
            if (resolvedAddresses.isNotEmpty()) {
                return resolvedAddresses
            }
        }

        logLookupFailureLocked(provider, originalHost, lookupCandidates)
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
     * Prints a provider-specific lookup report after lookup failure for easier diagnosis.
     *
     * @param provider The provider that returned no result.
     * @param originalHost The raw host that Flutter asked to resolve.
     * @param lookupCandidates Candidate hosts already tried against the SDK.
     * @return No return value.
     */
    private fun logLookupFailureLocked(
        provider: HttpDnsProvider,
        originalHost: String,
        lookupCandidates: List<String>,
    ) {
        val providerLabel = provider.displayName
        val requestReport = when (provider) {
            HttpDnsProvider.NONE -> ""
            HttpDnsProvider.ALIYUN -> runCatching {
                DNSResolver.getInstance().getRequestReportInfo()
            }.getOrNull().orEmpty()

            HttpDnsProvider.VOLCENGINE -> lastLookupReport.orEmpty()
            HttpDnsProvider.TENCENT -> lastLookupReport.orEmpty()
        }
        lastLookupReport = requestReport.ifBlank { null }
        statusMessage =
            "$providerLabel lookup returned no IPv4 address for $originalHost. " +
                "requestReport=$requestReport"
        Log.w(
            LOG_TAG,
            "$providerLabel returned no IPv4 address for host=$originalHost " +
                "candidates=$lookupCandidates requestReport=$requestReport",
        )
    }

    /**
     * Updates the cached Volcengine lookup report for diagnostics.
     *
     * @param dnsResult The latest Volcengine SDK result.
     * @return No return value.
     */
    private fun updateVolcengineLookupReportLocked(dnsResult: DnsResult?) {
        if (dnsResult == null) {
            lastLookupReport = null
            return
        }
        val taskReport = dnsResult.taskInfoList
            ?.joinToString(separator = "; ") { taskInfo ->
                runCatching { taskInfo.toJson().toString() }
                    .getOrElse { taskInfo.toString() }
            }
            .orEmpty()
        lastLookupReport =
            "source=${dnsResult.source}, ttl=${dnsResult.ttl}, rtt=${dnsResult.rtt}, " +
                "cip=${dnsResult.cip}, tasks=$taskReport"
    }

    /**
     * Updates the cached Tencent DNSPod lookup report for diagnostics.
     *
     * @param host The host resolved through Tencent DNSPod.
     * @param addressPayload The raw "IPv4;IPv6" payload returned by the SDK.
     * @return No return value.
     */
    private fun updateTencentLookupReportLocked(
        host: String,
        addressPayload: String?,
    ) {
        if (addressPayload.isNullOrBlank()) {
            lastLookupReport = null
            return
        }
        lastLookupReport = "host=$host, payload=$addressPayload"
    }

    /**
     * Parses the configured Volcengine DoH domain list.
     *
     * @return A de-duplicated list of configured DoH domains.
     */
    private fun volcengineDohDomains(): ArrayList<String> =
        BuildConfig.VE_HTTPDNS_DOH_DOMAINS
            .split(Regex("[,;\\s]+"))
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .distinct()
            .let(::ArrayList)

    /**
     * Builds the Tencent DNSPod pre-lookup domain list.
     *
     * @return Up to the Tencent SDK limit of preloaded domains.
     */
    private fun tencentPreloadDomains(): List<String> =
        preloadDomains
            .take(MAX_TENCENT_PRELOAD_DOMAINS)

    /**
     * Builds the Tencent DNSPod persistent-cache domain list.
     *
     * @return Up to the Tencent SDK limit of persistent-cache domains.
     */
    private fun tencentKeepAliveDomains(): List<String> =
        keepAliveDomains
            .take(MAX_TENCENT_KEEP_ALIVE_DOMAINS)

    /**
     * Checks whether the current build contains all required credentials for the selected provider.
     *
     * @return True when the selected provider is ready to initialize, otherwise false.
     */
    private fun credentialsConfigured(): Boolean =
        when (selectedProvider) {
            HttpDnsProvider.NONE -> true
            HttpDnsProvider.ALIYUN -> aliyunCredentialsConfigured()
            HttpDnsProvider.VOLCENGINE -> volcengineCredentialsConfigured()
            HttpDnsProvider.TENCENT -> tencentCredentialsConfigured()
        }

    /**
     * Checks whether the current build contains all required Aliyun credentials.
     *
     * @return True when the build is ready to initialize the Aliyun SDK.
     */
    private fun aliyunCredentialsConfigured(): Boolean =
        BuildConfig.ALIYUN_HTTPDNS_CREDENTIALS_CONFIGURED

    /**
     * Checks whether the current build contains all required Volcengine credentials.
     *
     * @return True when the build is ready to initialize the Volcengine SDK.
     */
    private fun volcengineCredentialsConfigured(): Boolean =
        BuildConfig.VE_HTTPDNS_CREDENTIALS_CONFIGURED

    /**
     * Checks whether the current build contains all required Tencent DNSPod credentials.
     *
     * @return True when the build is ready to initialize Tencent DNSPod HTTPDNS.
     */
    private fun tencentCredentialsConfigured(): Boolean =
        BuildConfig.TENCENT_HTTPDNS_CREDENTIALS_CONFIGURED

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
        private const val ALIYUN_TIMEOUT_MS = 3000
        private const val ALIYUN_TIMEOUT_SECONDS = 3
        private const val MAX_VOLCENGINE_PRELOAD_DOMAINS = 10
        private const val MAX_TENCENT_KEEP_ALIVE_DOMAINS = 8
        private const val MAX_TENCENT_PRELOAD_DOMAINS = 8
        private const val TENCENT_EMPTY_ADDRESS = "0"
        private const val TENCENT_TIMEOUT_MS = 2000

        @Volatile
        private var instance: AndroidHttpDnsManager? = null

        /**
         * Returns the singleton native HTTPDNS manager.
         *
         * @param application Application context used by the HTTPDNS SDKs.
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

/**
 * Returns a readable provider label for logs and status text.
 *
 * @return Provider display name.
 */
private val HttpDnsProvider.displayName: String
    get() = when (this) {
        HttpDnsProvider.NONE -> "HTTPDNS"
        HttpDnsProvider.ALIYUN -> "Aliyun HTTPDNS"
        HttpDnsProvider.VOLCENGINE -> "Volcengine HTTPDNS"
        HttpDnsProvider.TENCENT -> "Tencent DNSPod HTTPDNS"
    }

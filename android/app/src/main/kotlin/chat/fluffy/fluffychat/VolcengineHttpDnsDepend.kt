package chat.fluffy.fluffychat

import android.content.Context
import com.bytedancehttpdns.httpdns.AbsOptionalHttpDnsDepend
import com.bytedancehttpdns.httpdns.IHttpDnsDepend

/**
 * Supplies build-time Volcengine HTTPDNS credentials to the native SDK.
 *
 * @param context Application context required by the SDK.
 */
class VolcengineHttpDnsDepend(
    private val context: Context,
) : AbsOptionalHttpDnsDepend(), IHttpDnsDepend {
    /**
     * Returns the Android context used by the SDK.
     *
     * @return Application context.
     */
    override fun getContext(): Context = context

    /**
     * Returns the Volcengine HTTPDNS service id.
     *
     * @return Service id injected at build time.
     */
    override fun getHttpdnsAccountID(): String = BuildConfig.VE_HTTPDNS_ACCOUNT_ID

    /**
     * Returns the Volcengine HTTPDNS secret key.
     *
     * @return Secret key injected at build time.
     */
    override fun getHttpdnsSecretKey(): String = BuildConfig.VE_HTTPDNS_SECRET_KEY

    /**
     * Indicates whether the SDK should use temporary-key authentication.
     *
     * @return Always false because this integration uses the permanent secret key flow.
     */
    @Deprecated("Legacy temporary-key authentication is not used in this project.")
    override fun isTemporaryAuthentication(): Boolean = false

    /**
     * Returns the temporary-key timestamp when legacy auth is enabled.
     *
     * @return Always 0 because this integration does not use temporary keys.
     */
    @Deprecated("Legacy temporary-key authentication is not used in this project.")
    override fun getHttpdnsTemporaryKeyTimeStamp(): Long = 0L

    /**
     * Returns the optional Volcengine app id for traffic separation.
     *
     * @return Configured app id, or null when unset.
     */
    override fun getAppId(): String? =
        BuildConfig.VE_HTTPDNS_APP_ID.takeIf { it.isNotBlank() }

    /**
     * Indicates whether DoH is enabled for this build.
     *
     * @return True when the build enables DoH, otherwise false.
     */
    override fun useDoh(): Boolean = BuildConfig.VE_HTTPDNS_USE_DOH

    /**
     * Supplies an empty preload list because runtime configuration updates it later.
     *
     * @return Empty preload list during initial SDK dependency setup.
     */
    override fun getPreloadDomains(): Array<String> = emptyArray()
}

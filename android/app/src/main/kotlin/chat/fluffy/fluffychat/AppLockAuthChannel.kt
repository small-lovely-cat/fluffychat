package chat.fluffy.fluffychat

import android.app.Application
import android.util.Log
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import com.tencent.soter.core.SoterCore
import com.tencent.soter.core.model.ConstantsSoter
import com.tencent.soter.core.model.SoterErrCode
import com.tencent.soter.wrapper.SoterWrapperApi
import com.tencent.soter.wrapper.wrap_biometric.SoterBiometricCanceller
import com.tencent.soter.wrapper.wrap_biometric.SoterBiometricStateCallback
import com.tencent.soter.wrapper.wrap_callback.SoterProcessAuthenticationResult
import com.tencent.soter.wrapper.wrap_callback.SoterProcessCallback
import com.tencent.soter.wrapper.wrap_callback.SoterProcessKeyPreparationResult
import com.tencent.soter.wrapper.wrap_callback.SoterProcessNoExtResult
import com.tencent.soter.wrapper.wrap_core.SoterProcessErrCode
import com.tencent.soter.wrapper.wrap_task.AuthenticationParam
import com.tencent.soter.wrapper.wrap_task.InitializeParam
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class AppLockAuthChannel private constructor(
    private var activity: FlutterFragmentActivity,
    flutterEngine: FlutterEngine,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
    private var pendingResult: MethodChannel.Result? = null
    private val soterCapabilityLock = Any()
    @Volatile
    private var cachedSoterCapability: SoterCapability? = null
    @Volatile
    private var soterCapabilityWarmupInFlight = false

    init {
        channel.setMethodCallHandler(this)
        warmUpSoterCapability()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCapabilities" -> handleGetCapabilities(result)
            "prepareSoter" -> handlePrepareSoter(result)
            "authenticate" -> handleAuthenticate(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleGetCapabilities(result: MethodChannel.Result) {
        if (!startCall(result)) {
            return
        }
        val nativeCapability = nativeCapability()
        val soterCapability = soterCapability()
        logInfo(
            "getCapabilities nativeSupported=${nativeCapability.first} " +
                "nativeMessage=${nativeCapability.second} " +
                "soterSupported=${soterCapability.supported} " +
                "soterReady=${soterCapability.ready} " +
                "soterMessage=${soterCapability.message}",
        )
        finishPending(
            mapOf(
                "nativeSupported" to nativeCapability.first,
                "soterSupported" to soterCapability.supported,
                "soterReady" to soterCapability.ready,
                "message" to (nativeCapability.second ?: soterCapability.message),
            ),
        )
    }

    private fun handlePrepareSoter(result: MethodChannel.Result) {
        if (!startCall(result)) {
            return
        }
        logInfo("prepareSoter requested")
        prepareSoter(allowRetry = true, forceReinitialize = true) { prepareResult ->
            logInfo(
                "prepareSoter finished success=${prepareResult.success} " +
                    "errCode=${prepareResult.errCode} message=${prepareResult.message}",
            )
            finishPending(
                if (prepareResult.success) {
                    successPayload()
                } else {
                    failurePayload(
                        errorCode = "soter_prepare_${prepareResult.errCode ?: "failed"}",
                        message = prepareResult.message ?: "Tencent Soter initialization failed.",
                        shouldFallbackToNative = true,
                    )
                },
            )
        }
    }

    private fun prepareSoter(
        allowRetry: Boolean,
        forceReinitialize: Boolean,
        onComplete: (SoterPrepareResult) -> Unit,
    ) {
        logInfo(
            "prepareSoter start allowRetry=$allowRetry forceReinitialize=$forceReinitialize",
        )
        ensureSoterInitialized(forceReinitialize = forceReinitialize) { initialized, initMessage ->
            val soterAvailable = isSoterAvailable()
            logInfo(
                "prepareSoter after init initialized=$initialized " +
                    "soterAvailable=$soterAvailable initMessage=$initMessage",
            )
            if (!initialized || !soterAvailable) {
                onComplete(
                    SoterPrepareResult(
                        success = false,
                        errCode = SoterErrCode.ERR_SOTER_NOT_SUPPORTED,
                        message = initMessage ?: "Tencent Soter is not available on this device.",
                    ),
                )
                return@ensureSoterInitialized
            }

            runCatching {
                SoterWrapperApi.ensureConnection()
                logInfo("prepareSoter ensureConnection succeeded")
            }.onFailure { throwable ->
                logWarn("prepareSoter ensureConnection failed: ${throwable.message}")
            }

            prepareSoterInternal { prepareResult ->
                if (prepareResult.success) {
                    onComplete(prepareResult)
                    return@prepareSoterInternal
                }

                if (allowRetry && prepareResult.errCode in RECOVERABLE_SOTER_PREPARE_ERRORS) {
                    logWarn(
                        "prepareSoter retrying after recoverable error " +
                            "errCode=${prepareResult.errCode} message=${prepareResult.message}",
                    )
                    prepareSoter(
                        allowRetry = false,
                        forceReinitialize = true,
                        onComplete = onComplete,
                    )
                    return@prepareSoterInternal
                }

                onComplete(prepareResult)
            }
        }
    }

    private fun reinitializeAndPrepareSoter(onComplete: (Boolean, String?) -> Unit) {
        logInfo("reinitializeAndPrepareSoter requested")
        prepareSoter(allowRetry = false, forceReinitialize = true) { prepareResult ->
            onComplete(prepareResult.success, prepareResult.message)
        }
    }

    private fun handleAuthenticate(call: MethodCall, result: MethodChannel.Result) {
        if (!startCall(result)) {
            return
        }
        when (call.argument<String>("method")) {
            METHOD_SOTER -> authenticateWithSoter()
            METHOD_SYSTEM_BIOMETRIC -> authenticateWithSystemBiometric(call)
            else -> finishPending(
                failurePayload(
                    errorCode = "unsupported_method",
                    message = "Unsupported app lock authentication method.",
                ),
            )
        }
    }

    private fun authenticateWithSystemBiometric(call: MethodCall) {
        val nativeCapability = nativeCapability()
        logInfo(
            "authenticateWithSystemBiometric nativeSupported=${nativeCapability.first} " +
                "message=${nativeCapability.second}",
        )
        if (!nativeCapability.first) {
            finishPending(
                failurePayload(
                    errorCode = "biometric_unavailable",
                    message = nativeCapability.second ?: "Biometric authentication is not available.",
                ),
            )
            return
        }

        runCatching {
            val executor = ContextCompat.getMainExecutor(activity)
            val prompt = BiometricPrompt(
                activity,
                executor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                        logInfo("systemBiometric onAuthenticationSucceeded")
                        finishPending(successPayload())
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        val cancelled = errorCode == BiometricPrompt.ERROR_NEGATIVE_BUTTON ||
                            errorCode == BiometricPrompt.ERROR_USER_CANCELED ||
                            errorCode == BiometricPrompt.ERROR_CANCELED
                        logWarn(
                            "systemBiometric onAuthenticationError " +
                                "errorCode=$errorCode cancelled=$cancelled errString=$errString",
                        )
                        finishPending(
                            failurePayload(
                                errorCode = "biometric_error_$errorCode",
                                message = errString.toString(),
                                cancelled = cancelled,
                            ),
                        )
                    }
                }
            )

            val promptInfo = BiometricPrompt.PromptInfo.Builder()
                .setTitle(call.argument<String>("title") ?: "Unlock app")
                .setSubtitle(call.argument<String>("subtitle") ?: "Use biometric authentication")
                .setNegativeButtonText(call.argument<String>("negativeButton") ?: "Use PIN")
                .build()
            logInfo("systemBiometric authenticate prompt shown")
            prompt.authenticate(promptInfo)
        }.onFailure { throwable ->
            logError("systemBiometric failed to start", throwable)
            finishPending(
                failurePayload(
                    errorCode = "biometric_prompt_failed",
                    message = throwable.message ?: "Biometric authentication failed to start.",
                ),
            )
        }
    }

    private fun authenticateWithSoter() {
        logInfo("authenticateWithSoter requested")
        ensureSoterInitialized(forceReinitialize = false) { initialized, initMessage ->
            val soterAvailable = isSoterAvailable()
            logInfo(
                "authenticateWithSoter after init initialized=$initialized " +
                    "soterAvailable=$soterAvailable initMessage=$initMessage",
            )
            if (!initialized || !soterAvailable) {
                reinitializeAndPrepareSoter { success, message ->
                    logInfo(
                        "authenticateWithSoter reinitialize result " +
                            "success=$success message=$message",
                    )
                    if (success) {
                        requestSoterAuthentication(allowRetry = false)
                    } else {
                        finishPending(
                            failurePayload(
                                errorCode = "soter_unavailable",
                                message = message ?: initMessage ?: "Tencent Soter is not available on this device.",
                                shouldFallbackToNative = true,
                            ),
                        )
                    }
                }
                return@ensureSoterInitialized
            }
            requestSoterAuthentication(allowRetry = true)
        }
    }

    private fun requestSoterAuthentication(allowRetry: Boolean) {
        logInfo("requestSoterAuthentication start allowRetry=$allowRetry")
        val canceller = SoterBiometricCanceller()

        runCatching {
            SoterWrapperApi.ensureConnection()
            logInfo("requestSoterAuthentication ensureConnection succeeded")
        }.onFailure { throwable ->
            logWarn("requestSoterAuthentication ensureConnection failed: ${throwable.message}")
        }

        val authenticationParam = try {
            AuthenticationParam.AuthenticationParamBuilder()
                .setScene(SOTER_SCENE_APP_LOCK)
                .setBiometricType(ConstantsSoter.FINGERPRINT_AUTH)
                .setContext(activity)
                .setSoterBiometricCanceller(canceller)
                .setPrefilledChallenge(UUID.randomUUID().toString())
                .setSoterBiometricStateCallback(
                    object : SoterBiometricStateCallback {
                        override fun onStartAuthentication() {
                            logInfo("soter biometric callback onStartAuthentication")
                        }

                        override fun onAuthenticationHelp(
                            helpCode: Int,
                            helpString: CharSequence,
                        ) {
                            logInfo(
                                "soter biometric callback onAuthenticationHelp " +
                                    "helpCode=$helpCode helpString=$helpString",
                            )
                        }

                        override fun onAuthenticationSucceed() {
                            logInfo("soter biometric callback onAuthenticationSucceed")
                        }

                        override fun onAuthenticationFailed() {
                            logWarn("soter biometric callback onAuthenticationFailed")
                        }

                        override fun onAuthenticationCancelled() {
                            logInfo("soter biometric callback onAuthenticationCancelled")
                        }

                        override fun onAuthenticationError(
                            errorCode: Int,
                            errorString: CharSequence,
                        ) {
                            logWarn(
                                "soter biometric callback onAuthenticationError " +
                                    "errorCode=$errorCode errorString=$errorString",
                            )
                        }
                    },
                )
                .build()
        } catch (throwable: Throwable) {
            logError("requestSoterAuthentication failed to build AuthenticationParam", throwable)
            finishPending(
                failurePayload(
                    errorCode = "soter_auth_param_failed",
                    message = throwable.message ?: "Tencent Soter authentication setup failed.",
                    shouldFallbackToNative = true,
                ),
            )
            return
        }

        runCatching {
            SoterWrapperApi.requestAuthorizeAndSign(
                object : SoterProcessCallback<SoterProcessAuthenticationResult> {
                    override fun onResult(result: SoterProcessAuthenticationResult) {
                        logInfo(
                            "soter auth callback success=${result.isSuccess()} " +
                                "errCode=${result.errCode} errMsg=${result.errMsg}",
                        )
                        if (result.isSuccess()) {
                            finishPending(successPayload())
                            return
                        }

                        if (allowRetry && result.errCode in RECOVERABLE_SOTER_ERRORS) {
                            logWarn(
                                "soter auth retrying after recoverable error " +
                                    "errCode=${result.errCode} errMsg=${result.errMsg}",
                            )
                            reinitializeAndPrepareSoter { success, message ->
                                logInfo(
                                    "soter auth retry prepare result success=$success " +
                                        "message=$message",
                                )
                                if (success) {
                                    requestSoterAuthentication(allowRetry = false)
                                } else {
                                    finishPending(
                                        failurePayload(
                                            errorCode = "soter_prepare_failed",
                                            message = message ?: result.errMsg,
                                            shouldFallbackToNative = true,
                                        ),
                                    )
                                }
                            }
                            return
                        }

                        finishPending(
                            failurePayload(
                                errorCode = "soter_auth_${result.errCode}",
                                message = result.errMsg ?: "Tencent Soter authentication failed.",
                                cancelled = result.errCode == SoterProcessErrCode.ERR_USER_CANCELLED,
                                shouldFallbackToNative = result.errCode != SoterProcessErrCode.ERR_USER_CANCELLED,
                            ),
                        )
                    }
                },
                authenticationParam,
            )
        }.onFailure { throwable ->
            logError("requestSoterAuthentication failed to start", throwable)
            finishPending(
                failurePayload(
                    errorCode = "soter_auth_request_failed",
                    message = throwable.message ?: "Tencent Soter authentication failed to start.",
                    shouldFallbackToNative = true,
                ),
            )
        }
    }

    private fun prepareSoterInternal(onComplete: (SoterPrepareResult) -> Unit) {
        runCatching {
            SoterWrapperApi.prepareAuthKey(
                object : SoterProcessCallback<SoterProcessKeyPreparationResult> {
                    override fun onResult(result: SoterProcessKeyPreparationResult) {
                        logInfo(
                            "prepareSoterInternal callback success=${result.isSuccess()} " +
                                "errCode=${result.errCode} errMsg=${result.errMsg}",
                        )
                        onComplete(
                            SoterPrepareResult(
                                success = result.isSuccess(),
                                errCode = result.errCode,
                                message = result.errMsg,
                            ),
                        )
                    }
                },
                false,
                true,
                SOTER_SCENE_APP_LOCK,
                null,
                null,
            )
        }.onFailure { throwable ->
            logError("prepareSoterInternal failed to start", throwable)
            onComplete(
                SoterPrepareResult(
                    success = false,
                    message = throwable.message ?: "Tencent Soter initialization failed.",
                ),
            )
        }
    }

    private fun ensureSoterInitialized(
        forceReinitialize: Boolean = false,
        onComplete: (Boolean, String?) -> Unit,
    ) {
        logInfo("ensureSoterInitialized start forceReinitialize=$forceReinitialize")
        if (forceReinitialize) {
            runCatching {
                SoterWrapperApi.release()
                logInfo("ensureSoterInitialized release succeeded")
            }.onFailure { throwable ->
                logWarn("ensureSoterInitialized release failed: ${throwable.message}")
            }
        }

        if (!forceReinitialize && runCatching { SoterWrapperApi.isInitialized() }.getOrDefault(false)) {
            runCatching {
                SoterWrapperApi.ensureConnection()
                logInfo("ensureSoterInitialized reused existing initialization")
            }.onFailure { throwable ->
                logWarn("ensureSoterInitialized ensureConnection failed: ${throwable.message}")
            }
            onComplete(true, null)
            return
        }

        runCatching {
            if (!foregroundDetectionRegistered) {
                SoterWrapperApi.detectAppForeground(activity.application as Application)
                foregroundDetectionRegistered = true
                logInfo("ensureSoterInitialized registered foreground detector")
            }

            val initParam = InitializeParam.InitializeParamBuilder()
                .setScenes(SOTER_SCENE_APP_LOCK)
                .build()

            SoterWrapperApi.init(
                activity.applicationContext,
                object : SoterProcessCallback<SoterProcessNoExtResult> {
                    override fun onResult(result: SoterProcessNoExtResult) {
                        val initialized = result.isSuccess() ||
                            result.errCode == SoterProcessErrCode.ERR_ALREADY_INITIALIZED
                        logInfo(
                            "ensureSoterInitialized callback success=${result.isSuccess()} " +
                                "initialized=$initialized errCode=${result.errCode} " +
                                "errMsg=${result.errMsg}",
                        )
                        if (initialized) {
                            runCatching {
                                SoterWrapperApi.ensureConnection()
                                logInfo("ensureSoterInitialized callback ensureConnection succeeded")
                            }.onFailure { throwable ->
                                logWarn(
                                    "ensureSoterInitialized callback ensureConnection failed: " +
                                        throwable.message,
                                )
                            }
                        }
                        onComplete(
                            initialized,
                            if (initialized) {
                                null
                            } else {
                                result.errMsg ?: "Failed to initialize Tencent Soter."
                            },
                        )
                    }
                },
                initParam,
            )
        }.onFailure { throwable ->
            logError("ensureSoterInitialized failed to start init", throwable)
            onComplete(false, throwable.message ?: "Failed to initialize Tencent Soter.")
        }
    }

    private fun isSoterAvailable(): Boolean {
        val available = runCatching {
            SoterWrapperApi.isSupportSoter() &&
                SoterCore.isSupportBiometric(
                    activity.applicationContext,
                    ConstantsSoter.FINGERPRINT_AUTH,
                )
        }.getOrDefault(false)
        if (available) {
            synchronized(soterCapabilityLock) {
                cachedSoterCapability = SoterCapability(
                    supported = true,
                    ready = true,
                    message = null,
                )
            }
        }
        logInfo("isSoterAvailable=$available")
        return available
    }

    private fun isSoterNativeSupported(): Boolean {
        val supported = runCatching {
            SoterCore.tryToInitSoterBeforeTreble()
            SoterCore.tryToInitSoterTreble(activity.applicationContext)
            SoterCore.setUp()
            SoterCore.isNativeSupportSoter() &&
                SoterCore.isSupportBiometric(
                    activity.applicationContext,
                    ConstantsSoter.FINGERPRINT_AUTH,
                )
        }.getOrDefault(false)
        logInfo("isSoterNativeSupported=$supported")
        return supported
    }

    private fun soterCapability(): SoterCapability {
        cachedSoterCapability?.let { capability ->
            return capability.copy(
                ready = capability.ready || runCatching { SoterWrapperApi.isSupportSoter() }.getOrDefault(false),
            )
        }

        warmUpSoterCapability()

        val nativeSupported = nativeCapability().first
        return SoterCapability(
            supported = nativeSupported,
            ready = false,
            message = if (nativeSupported) {
                null
            } else {
                "Tencent Soter is not available on this device."
            },
        )
    }

    private fun warmUpSoterCapability(force: Boolean = false) {
        synchronized(soterCapabilityLock) {
            if (!force && (cachedSoterCapability != null || soterCapabilityWarmupInFlight)) {
                return
            }
            soterCapabilityWarmupInFlight = true
        }

        soterWarmupExecutor.execute {
            logInfo("warmUpSoterCapability start force=$force")
            val capability = runCatching {
                val supported = isSoterNativeSupported()
                if (!supported) {
                    SoterCapability(
                        supported = false,
                        ready = false,
                        message = "Tencent Soter is not available on this device.",
                    )
                } else {
                    SoterCapability(
                        supported = true,
                        ready = runCatching { SoterWrapperApi.isSupportSoter() }.getOrDefault(false),
                        message = null,
                    )
                }
            }.getOrElse { throwable ->
                logError("warmUpSoterCapability failed", throwable)
                SoterCapability(
                    supported = false,
                    ready = false,
                    message = throwable.message ?: "Tencent Soter is not available on this device.",
                )
            }

            synchronized(soterCapabilityLock) {
                cachedSoterCapability = capability.takeIf { it.supported }
                soterCapabilityWarmupInFlight = false
            }
            logInfo(
                "warmUpSoterCapability finished supported=${capability.supported} " +
                    "ready=${capability.ready} message=${capability.message}",
            )
        }
    }

    private fun nativeCapability(): Pair<Boolean, String?> {
        val canAuthenticate = BiometricManager.from(activity).canAuthenticate(
            BiometricManager.Authenticators.BIOMETRIC_WEAK,
        )
        return when (canAuthenticate) {
            BiometricManager.BIOMETRIC_SUCCESS -> true to null
            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> false to "No biometric credential is enrolled on this device."
            BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE -> false to "This device does not have biometric hardware."
            BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE -> false to "Biometric hardware is currently unavailable."
            BiometricManager.BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED -> false to "A security update is required before biometric authentication can be used."
            BiometricManager.BIOMETRIC_ERROR_UNSUPPORTED -> false to "Biometric authentication is unsupported on this device."
            BiometricManager.BIOMETRIC_STATUS_UNKNOWN -> false to "Unable to determine biometric availability on this device."
            else -> false to "Biometric authentication is not available on this device."
        }
    }

    private fun startCall(result: MethodChannel.Result): Boolean {
        if (pendingResult != null) {
            result.error("busy", "Another app lock authentication request is already running.", null)
            return false
        }
        pendingResult = result
        return true
    }

    private fun finishPending(payload: Map<String, Any?>) {
        val result = pendingResult ?: return
        pendingResult = null
        activity.runOnUiThread {
            result.success(payload)
        }
    }

    private fun successPayload(): Map<String, Any?> {
        return mapOf(
            "success" to true,
            "cancelled" to false,
            "shouldFallbackToNative" to false,
        )
    }

    private fun failurePayload(
        errorCode: String,
        message: String?,
        cancelled: Boolean = false,
        shouldFallbackToNative: Boolean = false,
    ): Map<String, Any?> {
        return mapOf(
            "success" to false,
            "cancelled" to cancelled,
            "shouldFallbackToNative" to shouldFallbackToNative,
            "errorCode" to errorCode,
            "message" to message,
        )
    }

    private fun logInfo(message: String) {
        Log.i(LOG_TAG, message)
    }

    private fun logWarn(message: String) {
        Log.w(LOG_TAG, message)
    }

    private fun logError(message: String, throwable: Throwable? = null) {
        if (throwable == null) {
            Log.e(LOG_TAG, message)
        } else {
            Log.e(LOG_TAG, message, throwable)
        }
    }

    private data class SoterCapability(
        val supported: Boolean,
        val ready: Boolean,
        val message: String?,
    )

    private data class SoterPrepareResult(
        val success: Boolean,
        val errCode: Int? = null,
        val message: String? = null,
    )

    companion object {
        private const val CHANNEL_NAME = "chat.fluffy.app_lock/auth"
        private const val LOG_TAG = "FluffySoter"
        private const val METHOD_SOTER = "soter"
        private const val METHOD_SYSTEM_BIOMETRIC = "system_biometric"
        private const val SOTER_SCENE_APP_LOCK = 0x4643
        private val RECOVERABLE_SOTER_ERRORS = setOf(
            SoterProcessErrCode.ERR_AUTHKEY_NOT_FOUND,
            SoterProcessErrCode.ERR_AUTHKEY_ALREADY_EXPIRED,
            SoterProcessErrCode.ERR_ASK_NOT_EXIST,
            SoterProcessErrCode.ERR_SIGNATURE_INVALID,
            SoterProcessErrCode.ERR_NOT_INIT_WRAPPER,
            SoterProcessErrCode.ERR_AUTH_KEY_NOT_IN_MAP,
            SoterErrCode.ERR_SOTER_NOT_SUPPORTED,
        )
        private val RECOVERABLE_SOTER_PREPARE_ERRORS = setOf(
            SoterProcessErrCode.ERR_NOT_INIT_WRAPPER,
            SoterProcessErrCode.ERR_AUTH_KEY_NOT_IN_MAP,
            SoterErrCode.ERR_SOTER_NOT_SUPPORTED,
            SoterErrCode.ERR_ASK_NOT_EXIST,
            SoterErrCode.ERR_AUTH_KEY_GEN_FAILED,
            SoterErrCode.ERR_ASK_GEN_FAILED,
        )

        private var instance: AppLockAuthChannel? = null
        private var foregroundDetectionRegistered = false
        private val soterWarmupExecutor: ExecutorService = Executors.newSingleThreadExecutor()

        fun attach(activity: FlutterFragmentActivity, flutterEngine: FlutterEngine) {
            val current = instance
            if (current == null) {
                instance = AppLockAuthChannel(activity, flutterEngine)
            } else {
                current.activity = activity
                current.warmUpSoterCapability()
            }
        }
    }
}

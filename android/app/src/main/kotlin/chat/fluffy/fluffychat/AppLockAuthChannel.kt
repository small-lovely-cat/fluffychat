package chat.fluffy.fluffychat

import android.app.Application
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import com.tencent.soter.core.SoterCore
import com.tencent.soter.core.model.ConstantsSoter
import com.tencent.soter.wrapper.SoterWrapperApi
import com.tencent.soter.wrapper.wrap_biometric.SoterBiometricCanceller
import com.tencent.soter.wrapper.wrap_biometric.SoterBiometricStateCallback
import com.tencent.soter.wrapper.wrap_callback.SoterProcessAuthenticationResult
import com.tencent.soter.wrapper.wrap_callback.SoterProcessCallback
import com.tencent.soter.wrapper.wrap_callback.SoterProcessKeyPreparationResult
import com.tencent.soter.wrapper.wrap_callback.SoterProcessNoExtResult
import com.tencent.soter.wrapper.wrap_core.SoterProcessErrCode
import com.tencent.soter.wrapper.wrap_net.ISoterNetCallback
import com.tencent.soter.wrapper.wrap_net.IWrapUploadKeyNet
import com.tencent.soter.wrapper.wrap_task.AuthenticationParam
import com.tencent.soter.wrapper.wrap_task.InitializeParam
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class AppLockAuthChannel private constructor(
    private var activity: FlutterFragmentActivity,
    flutterEngine: FlutterEngine,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
    private var pendingResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
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
        ensureSoterInitialized { _, initMessage ->
            finishPending(
                mapOf(
                    "nativeSupported" to nativeCapability.first,
                    "soterSupported" to isSoterAvailable(),
                    "soterReady" to isSoterAvailable(),
                    "message" to (initMessage ?: nativeCapability.second),
                ),
            )
        }
    }

    private fun handlePrepareSoter(result: MethodChannel.Result) {
        if (!startCall(result)) {
            return
        }
        ensureSoterInitialized { initialized, initMessage ->
            if (!initialized || !isSoterAvailable()) {
                finishPending(
                    failurePayload(
                        errorCode = "soter_unavailable",
                        message = initMessage ?: "Tencent Soter is not available on this device.",
                        shouldFallbackToNative = true,
                    ),
                )
                return@ensureSoterInitialized
            }
            prepareSoterInternal { success, message ->
                finishPending(
                    if (success) {
                        successPayload()
                    } else {
                        failurePayload(
                            errorCode = "soter_prepare_failed",
                            message = message ?: "Tencent Soter initialization failed.",
                            shouldFallbackToNative = true,
                        )
                    },
                )
            }
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
        if (!nativeCapability.first) {
            finishPending(
                failurePayload(
                    errorCode = "biometric_unavailable",
                    message = nativeCapability.second ?: "Biometric authentication is not available.",
                ),
            )
            return
        }

        val executor = ContextCompat.getMainExecutor(activity)
        val prompt = BiometricPrompt(
            activity,
            executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    finishPending(successPayload())
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    val cancelled = errorCode == BiometricPrompt.ERROR_NEGATIVE_BUTTON ||
                        errorCode == BiometricPrompt.ERROR_USER_CANCELED ||
                        errorCode == BiometricPrompt.ERROR_CANCELED
                    finishPending(
                        failurePayload(
                            errorCode = "biometric_error_$errorCode",
                            message = errString.toString(),
                            cancelled = cancelled,
                        ),
                    )
                }
            },
        )

        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle(call.argument<String>("title") ?: "Unlock app")
            .setSubtitle(call.argument<String>("subtitle") ?: "Use biometric authentication")
            .setNegativeButtonText(call.argument<String>("negativeButton") ?: "Use PIN")
            .build()
        prompt.authenticate(promptInfo)
    }

    private fun authenticateWithSoter() {
        ensureSoterInitialized { initialized, initMessage ->
            if (!initialized || !isSoterAvailable()) {
                finishPending(
                    failurePayload(
                        errorCode = "soter_unavailable",
                        message = initMessage ?: "Tencent Soter is not available on this device.",
                        shouldFallbackToNative = true,
                    ),
                )
                return@ensureSoterInitialized
            }
            requestSoterAuthentication(allowRetry = true)
        }
    }

    private fun requestSoterAuthentication(allowRetry: Boolean) {
        val canceller = SoterBiometricCanceller()
        val authenticationParam = AuthenticationParam.AuthenticationParamBuilder()
            .setScene(SOTER_SCENE_APP_LOCK)
            .setBiometricType(ConstantsSoter.FINGERPRINT_AUTH)
            .setContext(activity)
            .setSoterBiometricCanceller(canceller)
            .setPrefilledChallenge(UUID.randomUUID().toString())
            .setSoterBiometricStateCallback(
                object : SoterBiometricStateCallback {
                    override fun onStartAuthentication() = Unit

                    override fun onAuthenticationHelp(helpCode: Int, helpString: CharSequence) = Unit

                    override fun onAuthenticationSucceed() = Unit

                    override fun onAuthenticationFailed() = Unit

                    override fun onAuthenticationCancelled() = Unit

                    override fun onAuthenticationError(errorCode: Int, errorString: CharSequence) = Unit
                },
            )
            .build()

        SoterWrapperApi.requestAuthorizeAndSign(
            object : SoterProcessCallback<SoterProcessAuthenticationResult> {
                override fun onResult(result: SoterProcessAuthenticationResult) {
                    if (result.isSuccess()) {
                        finishPending(successPayload())
                        return
                    }

                    if (allowRetry && result.errCode in RECOVERABLE_SOTER_ERRORS) {
                        prepareSoterInternal { success, message ->
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
    }

    private fun prepareSoterInternal(onComplete: (Boolean, String?) -> Unit) {
        SoterWrapperApi.prepareAuthKey(
            object : SoterProcessCallback<SoterProcessKeyPreparationResult> {
                override fun onResult(result: SoterProcessKeyPreparationResult) {
                    onComplete(result.isSuccess(), result.errMsg)
                }
            },
            false,
            true,
            SOTER_SCENE_APP_LOCK,
            SuccessUploadKeyNet(),
            SuccessUploadKeyNet(),
        )
    }

    private fun ensureSoterInitialized(onComplete: (Boolean, String?) -> Unit) {
        if (SoterWrapperApi.isInitialized()) {
            onComplete(true, null)
            return
        }

        runCatching {
            SoterWrapperApi.detectAppForeground(activity.application as Application)
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
    }

    private fun isSoterAvailable(): Boolean {
        return runCatching {
            SoterWrapperApi.isSupportSoter() &&
                SoterCore.isSupportBiometric(
                    activity.applicationContext,
                    ConstantsSoter.FINGERPRINT_AUTH,
                )
        }.getOrDefault(false)
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

    private class SuccessUploadKeyNet : IWrapUploadKeyNet {
        private var callback: ISoterNetCallback<IWrapUploadKeyNet.UploadResult>? = null

        override fun setRequest(request: IWrapUploadKeyNet.UploadRequest) = Unit

        override fun execute() {
            callback?.onNetEnd(IWrapUploadKeyNet.UploadResult(true))
        }

        override fun setCallback(callback: ISoterNetCallback<IWrapUploadKeyNet.UploadResult>) {
            this.callback = callback
        }
    }

    companion object {
        private const val CHANNEL_NAME = "chat.fluffy.app_lock/auth"
        private const val METHOD_SOTER = "soter"
        private const val METHOD_SYSTEM_BIOMETRIC = "system_biometric"
        private const val SOTER_SCENE_APP_LOCK = 0x4643
        private val RECOVERABLE_SOTER_ERRORS = setOf(
            SoterProcessErrCode.ERR_AUTHKEY_NOT_FOUND,
            SoterProcessErrCode.ERR_AUTHKEY_ALREADY_EXPIRED,
            SoterProcessErrCode.ERR_ASK_NOT_EXIST,
            SoterProcessErrCode.ERR_SIGNATURE_INVALID,
            SoterProcessErrCode.ERR_NOT_INIT_WRAPPER,
        )

        private var instance: AppLockAuthChannel? = null

        fun attach(activity: FlutterFragmentActivity, flutterEngine: FlutterEngine) {
            val current = instance
            if (current == null) {
                instance = AppLockAuthChannel(activity, flutterEngine)
            } else {
                current.activity = activity
            }
        }
    }
}

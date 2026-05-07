import UIKit
import Flutter
import LocalAuthentication
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var appLockAuthChannel: AppLockAuthChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    appLockAuthChannel = AppLockAuthChannel(
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )

    // From https://pub.dev/packages/flutter_local_notifications#-ios-setup
    UNUserNotificationCenter.current().delegate = self
  }
}

private final class AppLockAuthChannel {
  private static let channelName = "chat.fluffy.app_lock/auth"
  private static let methodSystemBiometric = "system_biometric"

  private let channel: FlutterMethodChannel
  private var pendingResult: FlutterResult?

  init(binaryMessenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getCapabilities":
      guard startCall(result) else { return }
      handleGetCapabilities()
    case "prepareSoter":
      guard startCall(result) else { return }
      finishPending(
        failurePayload(
          errorCode: "soter_unavailable",
          message: "Tencent Soter is only available on Android.",
          shouldFallbackToNative: true
        )
      )
    case "authenticate":
      guard startCall(result) else { return }
      handleAuthenticate(call)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleGetCapabilities() {
    let nativeCapability = nativeCapability()
    var payload: [String: Any] = [
      "nativeSupported": nativeCapability.supported,
      "soterSupported": false,
      "soterReady": false,
    ]
    if let message = nativeCapability.message {
      payload["message"] = message
    }
    finishPending(payload)
  }

  private func handleAuthenticate(_ call: FlutterMethodCall) {
    guard
      let arguments = call.arguments as? [String: Any],
      let method = arguments["method"] as? String
    else {
      finishPending(
        failurePayload(
          errorCode: "unsupported_method",
          message: "Unsupported app lock authentication method."
        )
      )
      return
    }

    switch method {
    case Self.methodSystemBiometric:
      authenticateWithSystemBiometric(arguments)
    default:
      finishPending(
        failurePayload(
          errorCode: "unsupported_method",
          message: "Unsupported app lock authentication method."
        )
      )
    }
  }

  private func authenticateWithSystemBiometric(_ arguments: [String: Any]) {
    let context = LAContext()
    context.localizedCancelTitle =
      (arguments["negativeButton"] as? String) ?? "Use PIN"
    context.localizedFallbackTitle = ""

    var error: NSError?
    let policy = LAPolicy.deviceOwnerAuthenticationWithBiometrics
    guard context.canEvaluatePolicy(policy, error: &error) else {
      finishPending(
        failurePayload(
          errorCode: "biometric_unavailable",
          message: messageForAvailabilityError(error)
        )
      )
      return
    }

    context.evaluatePolicy(
      policy,
      localizedReason: localizedReason(arguments: arguments)
    ) { [weak self] success, evaluationError in
      guard let self else { return }
      if success {
        self.finishPending(self.successPayload())
        return
      }
      self.finishPending(
        self.failurePayloadForAuthenticationError(evaluationError as NSError?)
      )
    }
  }

  private func localizedReason(arguments: [String: Any]) -> String {
    let components = [
      arguments["title"] as? String,
      arguments["subtitle"] as? String,
    ]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    if components.isEmpty {
      return "Use biometric authentication to unlock the app."
    }
    return components.joined(separator: "\n")
  }

  private func nativeCapability() -> (supported: Bool, message: String?) {
    let context = LAContext()
    var error: NSError?
    let supported = context.canEvaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics,
      error: &error
    )
    return (supported, supported ? nil : messageForAvailabilityError(error))
  }

  private func messageForAvailabilityError(_ error: NSError?) -> String {
    guard let error, let code = LAError.Code(rawValue: error.code) else {
      return "Biometric authentication is not available on this device."
    }

    switch code {
    case .biometryNotAvailable:
      return "This device does not have biometric hardware."
    case .biometryNotEnrolled:
      return "No biometric credential is enrolled on this device."
    case .biometryLockout:
      return "Biometric authentication is locked. Unlock the device with its passcode and try again."
    case .passcodeNotSet:
      return "A device passcode must be set before biometric authentication can be used."
    default:
      return error.localizedDescription
    }
  }

  private func failurePayloadForAuthenticationError(_ error: NSError?) -> [String: Any] {
    guard let error, let code = LAError.Code(rawValue: error.code) else {
      return failurePayload(
        errorCode: "biometric_failed",
        message: "Biometric authentication failed."
      )
    }

    switch code {
    case .userCancel, .systemCancel, .appCancel, .userFallback:
      return failurePayload(
        errorCode: "biometric_cancelled",
        message: error.localizedDescription,
        cancelled: true
      )
    case .authenticationFailed:
      return failurePayload(
        errorCode: "biometric_auth_failed",
        message: error.localizedDescription
      )
    case .biometryLockout:
      return failurePayload(
        errorCode: "biometric_lockout",
        message: "Biometric authentication is locked. Unlock the device with its passcode and try again."
      )
    case .biometryNotAvailable:
      return failurePayload(
        errorCode: "biometric_not_available",
        message: "This device does not have biometric hardware."
      )
    case .biometryNotEnrolled:
      return failurePayload(
        errorCode: "biometric_not_enrolled",
        message: "No biometric credential is enrolled on this device."
      )
    case .passcodeNotSet:
      return failurePayload(
        errorCode: "biometric_passcode_not_set",
        message: "A device passcode must be set before biometric authentication can be used."
      )
    default:
      return failurePayload(
        errorCode: "biometric_error_\(error.code)",
        message: error.localizedDescription
      )
    }
  }

  private func startCall(_ result: @escaping FlutterResult) -> Bool {
    if pendingResult != nil {
      result(
        FlutterError(
          code: "busy",
          message: "Another app lock authentication request is already running.",
          details: nil
        )
      )
      return false
    }
    pendingResult = result
    return true
  }

  private func finishPending(_ payload: [String: Any]) {
    guard let result = pendingResult else { return }
    pendingResult = nil
    DispatchQueue.main.async {
      result(payload)
    }
  }

  private func successPayload() -> [String: Any] {
    [
      "success": true,
      "cancelled": false,
      "shouldFallbackToNative": false,
    ]
  }

  private func failurePayload(
    errorCode: String,
    message: String?,
    cancelled: Bool = false,
    shouldFallbackToNative: Bool = false
  ) -> [String: Any] {
    var payload: [String: Any] = [
      "success": false,
      "cancelled": cancelled,
      "shouldFallbackToNative": shouldFallbackToNative,
      "errorCode": errorCode,
    ]
    if let message {
      payload["message"] = message
    }
    return payload
  }
}

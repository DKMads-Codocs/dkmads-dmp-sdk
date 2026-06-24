import Flutter
import UIKit
import AppTrackingTransparency
import AdSupport

public class DmpFlutterPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.dkmads.dmp/sdk", binaryMessenger: registrar.messenger())
        let instance = DmpFlutterPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "requestATT":
            if #available(iOS 14, *) {
                ATTrackingManager.requestTrackingAuthorization { status in
                    switch status {
                    case .authorized: result("authorized")
                    case .denied: result("denied")
                    case .restricted: result("restricted")
                    case .notDetermined: result("not_determined")
                    @unknown default: result("not_determined")
                    }
                }
            } else {
                result("not_applicable")
            }
        case "isLatEnabled":
            result(false)
        case "getAdvertisingId":
            if #available(iOS 14, *) {
                let status = ATTrackingManager.trackingAuthorizationStatus
                guard status == .authorized else {
                    result(nil)
                    return
                }
            }
            let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
            if idfa == "00000000-0000-0000-0000-000000000000" {
                result(nil)
            } else {
                result(idfa)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

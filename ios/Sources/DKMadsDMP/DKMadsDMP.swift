// DKMadsDMP — Swift Package Manager
import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif
#if canImport(AdSupport)
import AdSupport
#endif

#if canImport(CryptoKit)
import CryptoKit
#endif

public struct DMPConsent: Codable, Sendable {
    public var gdprApplies: Bool?
    public var tcfString: String?
    public var usPrivacy: String?
    public var purposes: [String: Bool]?
    public init() {}
}

public struct DMPSharedIdentity: Sendable {
    public let devicePid: String
    public let userPid: String?

    public init(devicePid: String, userPid: String?) {
        self.devicePid = devicePid
        self.userPid = userPid
    }
}

public struct DMPInitConfig: Sendable {
    public let appKey: String
    public var workspaceId: String?
    public var propertyId: String?
    public var apiHost: String
    public var flushIntervalMs: Int
    public var batchSize: Int
    public var collectDeviceIds: Bool
    public var requestATT: Bool
    public var debug: Bool

    public init(appKey: String, workspaceId: String? = nil, propertyId: String? = nil,
                apiHost: String = "https://ingest.dmp.dkmads.com", flushIntervalMs: Int = 10000,
                batchSize: Int = 20, collectDeviceIds: Bool = true, requestATT: Bool = true,
                debug: Bool = false) {
        self.appKey = appKey
        self.workspaceId = workspaceId
        self.propertyId = propertyId
        self.apiHost = apiHost
        self.flushIntervalMs = flushIntervalMs
        self.batchSize = batchSize
        self.collectDeviceIds = collectDeviceIds
        self.requestATT = requestATT
        self.debug = debug
    }
}

@MainActor
public final class DMPClient {
    public static let shared = DMPClient()
    private var config: DMPInitConfig?
    private var workspaceId: String?
    private var propertyId: String?
    private var queue: [[String: Any]] = []
    private var traits: [String: Any] = [:]
    private var context: [String: Any] = [:]
    private var userId: String?
    private var optedOut = false
    private var consent: DMPConsent?
    private var attStatus: String = "not_determined"
    private var timer: Timer?

    private init() {}

    public func configure(_ config: DMPInitConfig) async throws {
        self.config = config
        optedOut = UserDefaults.standard.bool(forKey: "dkmads_dmp_opted_out")

        if let ws = config.workspaceId, let prop = config.propertyId {
            workspaceId = ws; propertyId = prop
        } else {
            try await resolveBridge(config: config)
        }

        if config.requestATT {
            attStatus = await Self.requestATTAuthorization()
        }

        await syncOptOutFromServer()

        timer = Timer.scheduledTimer(withTimeInterval: Double(config.flushIntervalMs) / 1000, repeats: true) { [weak self] _ in
            Task { await self?.flush() }
        }
        track("sdk_initialized", properties: ["platform": "ios", "attStatus": attStatus])
    }

    /** @deprecated Use `configure(_:)` — `init` is reserved in Swift 6. */
    @available(*, deprecated, renamed: "configure")
    public func `init`(_ config: DMPInitConfig) async throws {
        try await configure(config)
    }

    private func canCollect() -> Bool {
        guard !optedOut else { return false }
        if let usPrivacy = consent?.usPrivacy, usPrivacy.count >= 3, usPrivacy[usPrivacy.index(usPrivacy.startIndex, offsetBy: 2)] == "Y" {
            return false
        }
        if consent?.gdprApplies == true {
            return consent?.purposes?["1"] == true
        }
        return true
    }

    public func identify(_ userId: String, traits: [String: Any]? = nil) {
        guard canCollect() else { return }
        self.userId = userId
        if let traits { self.traits.merge(traits) { _, n in n } }
        enqueue("identify", properties: ["userId": userId])
    }

    public func track(_ event: String, properties: [String: Any]? = nil) {
        guard canCollect() else { return }
        enqueue(event, properties: properties)
    }

    public func setTrait(_ key: String, value: Any) {
        guard canCollect() else { return }
        traits[key] = value
    }

    public func setTraits(_ traits: [String: Any]) {
        guard canCollect() else { return }
        self.traits.merge(traits) { _, n in n }
    }

    public func setContext(_ context: [String: Any]) {
        guard canCollect() else { return }
        self.context.merge(context) { _, new in new }
    }

    public func optOut() {
        optedOut = true
        UserDefaults.standard.set(true, forKey: "dkmads_dmp_opted_out")
        Task { await syncOptOutToServer() }
        reset()
    }

    public func reset() { userId = nil; traits = [:]; context = [:]; queue = [] }

    public func setConsent(_ consent: DMPConsent) async throws {
        self.consent = consent
        guard let config else { return }
        var body: [String: Any] = [
            "gdprApplies": consent.gdprApplies as Any,
            "tcfString": consent.tcfString as Any,
            "usPrivacy": consent.usPrivacy as Any,
            "devicePid": getDevicePid(),
            "attStatus": attStatus,
        ].compactMapValues { $0 }
        if let purposes = consent.purposes { body["purposes"] = purposes }
        var req = URLRequest(url: URL(string: "\(config.apiHost)/v1/ingest/consent")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.appKey, forHTTPHeaderField: "X-DMP-App-Key")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await URLSession.shared.data(for: req)
    }

    public func flush() async {
        guard let config, canCollect(), !queue.isEmpty, let ws = workspaceId, let prop = propertyId else { return }
        let events = Array(queue.prefix(config.batchSize))
        queue.removeFirst(min(queue.count, config.batchSize))
        let body: [String: Any] = ["workspaceId": ws, "propertyId": prop, "sdkVersion": "0.1.0", "events": events]
        var req = URLRequest(url: URL(string: "\(config.apiHost)/v1/ingest/batch")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.appKey, forHTTPHeaderField: "X-DMP-App-Key")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    private func resolveBridge(config: DMPInitConfig) async throws {
        let url = URL(string: "\(config.apiHost)/v1/bridge/resolve?app_key=\(config.appKey)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        workspaceId = json["workspaceId"] as? String
        propertyId = json["propertyId"] as? String
    }

    private func syncOptOutFromServer() async {
        guard let config else { return }
        let pid = getDevicePid()
        guard let url = URL(string: "\(config.apiHost)/v1/opt-out/status?device_pid=\(pid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pid)") else { return }
        var req = URLRequest(url: url)
        req.setValue(config.appKey, forHTTPHeaderField: "X-DMP-App-Key")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["optedOut"] as? Bool == true else { return }
        optedOut = true
        UserDefaults.standard.set(true, forKey: "dkmads_dmp_opted_out")
    }

    private func syncOptOutToServer() async {
        guard let config else { return }
        let body: [String: Any] = ["devicePid": getDevicePid()]
        guard let url = URL(string: "\(config.apiHost)/v1/ingest/opt-out") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.appKey, forHTTPHeaderField: "X-DMP-App-Key")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    private func enqueue(_ event: String, properties: [String: Any]?) {
        guard canCollect() else { return }
        var ids: [[String: String]] = [
            ["type": "idfv", "value": Self.deviceVendorId()],
            ["type": "device_pid", "value": getDevicePid()],
        ]
        if config?.collectDeviceIds == true && attStatus == "authorized" {
            #if canImport(AdSupport)
            let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
            if idfa != "00000000-0000-0000-0000-000000000000" {
                ids.append(["type": "idfa", "value": idfa])
            }
            #endif
        }
        if let userId { ids.append(["type": "publisher_user_id", "value": userId]); ids.append(["type": "user_pid", "value": userId]) }
        ids.append(contentsOf: Self.matchIdentifiers(from: traits))
        var eventContext: [String: Any] = ["platform": "ios", "attStatus": attStatus]
        context.forEach { eventContext[$0.key] = $0.value }
        queue.append([
            "eventName": event,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "identifiers": ids,
            "traits": traits,
            "properties": properties ?? [:],
            "context": eventContext,
        ] as [String: Any])
    }

    private func resolveDevicePid() -> String {
        let key = "dkmads_dmp_device_pid"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = "dkmads_\(UUID().uuidString)"
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    public func getDevicePid() -> String { resolveDevicePid() }

    public func getUserPid() -> String? { userId }

    public func getSharedIdentity() -> DMPSharedIdentity {
        DMPSharedIdentity(devicePid: resolveDevicePid(), userPid: userId)
    }

    private static func requestATTAuthorization() async -> String {
        #if canImport(AppTrackingTransparency)
        if #available(iOS 14, *) {
            let status = await ATTrackingManager.requestTrackingAuthorization()
            switch status {
            case .authorized: return "authorized"
            case .denied: return "denied"
            case .restricted: return "restricted"
            case .notDetermined: return "not_determined"
            @unknown default: return "not_determined"
            }
        }
        #endif
        return "not_determined"
    }

    private static func deviceVendorId() -> String {
        #if canImport(UIKit)
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        return UUID().uuidString
        #endif
    }

    private static func sha256Hex(_ value: String) -> String {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        return value
        #endif
    }

    private static func matchIdentifiers(from traits: [String: Any]) -> [[String: String]] {
        var out: [[String: String]] = []
        let email = traits["email"] as? String ?? traits["trait.email"] as? String
        if let email, !email.isEmpty {
            let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = normalized.count == 64 && normalized.allSatisfy({ $0.isHexDigit }) ? normalized : sha256Hex(normalized)
            out.append(["type": "email_sha256", "value": value])
        }
        let phone = traits["phone"] as? String ?? traits["trait.phone"] as? String
        if let phone, !phone.isEmpty {
            let digits = phone.filter { $0.isNumber }
            let normalized = phone.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+") ? "+\(digits)" : digits
            let value = normalized.count == 64 && normalized.allSatisfy({ $0.isHexDigit }) ? normalized : sha256Hex(normalized)
            out.append(["type": "phone_sha256", "value": value])
        }
        let google = traits["googleSubId"] as? String ?? traits["google_sub_hash"] as? String
        if let google, !google.isEmpty {
            let trimmed = google.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = trimmed.count == 64 && trimmed.allSatisfy({ $0.isHexDigit }) ? trimmed.lowercased() : sha256Hex(trimmed)
            out.append(["type": "google_sub_hash", "value": value])
        }
        return out
    }
}

@MainActor
public enum DMP {
    /// Preferred entry point (Swift 6 — avoid `init` on enum).
    public static func configure(_ config: DMPInitConfig) async throws {
        try await DMPClient.shared.configure(config)
    }

    @available(*, deprecated, renamed: "configure")
    public static func `init`(_ config: DMPInitConfig) async throws {
        try await configure(config)
    }

    public static func identify(_ userId: String, traits: [String: Any]? = nil) { DMPClient.shared.identify(userId, traits: traits) }
    public static func track(_ event: String, properties: [String: Any]? = nil) { DMPClient.shared.track(event, properties: properties) }
    public static func setTrait(_ key: String, value: Any) { DMPClient.shared.setTrait(key, value: value) }
    public static func setTraits(_ traits: [String: Any]) { DMPClient.shared.setTraits(traits) }
    public static func setContext(_ context: [String: Any]) { DMPClient.shared.setContext(context) }
    public static func optOut() { DMPClient.shared.optOut() }
    public static func reset() { DMPClient.shared.reset() }
    public static func flush() async { await DMPClient.shared.flush() }
    public static func setConsent(_ consent: DMPConsent) async throws { try await DMPClient.shared.setConsent(consent) }
    public static func getDevicePid() -> String { DMPClient.shared.getDevicePid() }
    public static func getUserPid() -> String? { DMPClient.shared.getUserPid() }
    public static func getSharedIdentity() -> DMPSharedIdentity { DMPClient.shared.getSharedIdentity() }
}

import Foundation
import Cocoa
import ApplicationServices
import AsyncXPCConnection

final class XPCHelperClient {
    nonisolated static let shared = XPCHelperClient()

    private let serviceName = "theboringteam.boringnotch.BoringNotchXPCHelper"

    private var remoteService: RemoteXPCService<BoringNotchXPCHelperProtocol>?
    private var connection: NSXPCConnection?
    private var lastKnownAuthorization: Bool?

    nonisolated private init() {}

    deinit {
        connection?.invalidate()
    }

    // MARK: - Connection Management (Main Actor Isolated)

    @MainActor
    private func ensureRemoteService() -> RemoteXPCService<BoringNotchXPCHelperProtocol> {
        if let existing = remoteService {
            return existing
        }

        let conn = NSXPCConnection(serviceName: serviceName)

        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
            }
        }

        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
            }
        }

        conn.resume()

        let service = RemoteXPCService<BoringNotchXPCHelperProtocol>(
            connection: conn,
            remoteInterface: BoringNotchXPCHelperProtocol.self
        )

        connection = conn
        remoteService = service
        return service
    }

    @MainActor
    private func getRemoteService() -> RemoteXPCService<BoringNotchXPCHelperProtocol>? {
        remoteService
    }

    @MainActor
    private func notifyAuthorizationChange(_ granted: Bool) {
        guard lastKnownAuthorization != granted else { return }
        lastKnownAuthorization = granted
        NotificationCenter.default.post(
            name: .accessibilityAuthorizationChanged,
            object: nil,
            userInfo: ["granted": granted]
        )
    }

    // MARK: - Accessibility (checked in-process, app-side)
    //
    // The accessibility grant belongs to the app bundle — that is what users
    // add in System Settings, and what the MediaKeyInterceptor's CGEventTap
    // gate requires. Ad-hoc–signed builds have no stable code identity, so
    // TCC attribution does not carry over to the embedded XPC helper; asking
    // the helper therefore always returned false even after the user granted
    // the app. The helper keeps its real unique responsibility: the
    // unsandboxed brightness/backlight private-framework calls.

    nonisolated private static func promptForAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    nonisolated func requestAccessibilityAuthorization() {
        Task { @MainActor in
            _ = Self.promptForAccessibility()
        }
    }

    nonisolated func isAccessibilityAuthorized() async -> Bool {
        let granted = AXIsProcessTrusted()
        await MainActor.run {
            notifyAuthorizationChange(granted)
        }
        return granted
    }

    nonisolated func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        var granted = AXIsProcessTrusted()
        if !granted && promptIfNeeded {
            granted = Self.promptForAccessibility()
        }
        await MainActor.run {
            notifyAuthorizationChange(granted)
        }
        return granted
    }

    // MARK: - Keyboard Brightness
    
    nonisolated func isKeyboardBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isKeyboardBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }
    
    nonisolated func currentKeyboardBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentKeyboardBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    nonisolated func setKeyboardBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setKeyboardBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }
    
    // MARK: - Screen Brightness
    
    nonisolated func isScreenBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isScreenBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }
    
    nonisolated func currentScreenBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentScreenBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    nonisolated func setScreenBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setScreenBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }
}

extension Notification.Name {
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
}



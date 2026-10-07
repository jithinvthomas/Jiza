import SwiftUI
import UIKit
import Combine

struct SecuritySettingsView: View {
    @EnvironmentObject private var security: AppSecurity
    @State private var pin = ""
    @State private var confirmation = ""
    @State private var saved = false
    var body: some View {
        Form {
            Section("App lock") {
                Toggle("Face ID / iPhone passcode", isOn: Binding(get: { security.appLockEnabled }, set: { enabled in Task { await security.setAppLock(enabled) } })).disabled(security.busy)
                Text("Require device authentication when opening Jiza or returning from the background. Face ID is used where available, with your iPhone passcode as fallback.").font(.footnote)
            }
            Section(security.browserLockEnabled ? "Change browser PIN" : "Set browser PIN") {
                SecureField("Six-digit PIN", text: $pin).keyboardType(.numberPad).textContentType(.newPassword).accessibilityIdentifier("newBrowserPIN")
                SecureField("Confirm PIN", text: $confirmation).keyboardType(.numberPad).textContentType(.newPassword).accessibilityIdentifier("confirmBrowserPIN")
                Button("Save browser PIN") {
                    Task { saved = await security.setPIN(pin, confirmation: confirmation); pin = ""; confirmation = "" }
                }.disabled(security.busy)
                if saved { Text("Browser PIN saved.").foregroundStyle(.green) }
                if security.browserLockEnabled {
                    Button("Remove browser PIN", role: .destructive) { Task { _ = await security.removePIN() } }.disabled(security.busy)
                }
                Text("The browser locks when you leave it or background Jiza. Changing or removing the PIN requires Face ID or your iPhone passcode.").font(.footnote)
            }
            Section {
                Text("Locks protect access inside Jiza. Files saved to Downloads or exported to another folder remain accessible through Files.").font(.footnote).foregroundStyle(.secondary)
                if let error = security.error { Text(error).foregroundStyle(.red) }
            }
        }.navigationTitle("Privacy & locks")
    }
}

private struct SecurityShieldContent: View {
    @ObservedObject var security: AppSecurity
    @State private var pin = ""
    @State private var confirmReset = false
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "lock.shield.fill").font(.system(size: 56)).foregroundStyle(.blue)
                Text(security.needsAppUnlock ? "Jiza is locked" : "Browser is locked").font(.title2.bold())
                if !security.obscured || security.busy {
                    if security.storageUnavailable {
                        Text("Lock settings are unavailable. Unlock your iPhone and retry.")
                        Button("Retry") { security.reload() }
                    } else if security.needsAppUnlock {
                        Button("Unlock Jiza") { Task { await security.unlockApp() } }.buttonStyle(.borderedProminent)
                    } else if security.needsBrowserUnlock {
                        SecureField("Browser PIN", text: $pin).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("browserUnlockPIN").onSubmit(unlock)
                        Button("Unlock browser", action: unlock).buttonStyle(.borderedProminent)
                        Button("Forgot PIN?") { confirmReset = true }.font(.footnote)
                    }
                    if security.busy { ProgressView() }
                    if let error = security.error { Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
                }
            }.padding(32).frame(maxWidth: 420).disabled(security.busy)
        }
        .confirmationDialog("Reset browser PIN using Face ID or your iPhone passcode?", isPresented: $confirmReset) {
            Button("Authenticate and remove PIN", role: .destructive) { Task { _ = await security.removePIN(); pin = "" } }
        }
        .onChange(of: security.obscured) { _ in pin = "" }
    }
    private func unlock() { let value = pin; pin = ""; Task { await security.unlockBrowser(value) } }
}

/// A scene-level window covers sheets, media covers and the app-switcher snapshot.
struct SecurityShieldWindow: UIViewRepresentable {
    @ObservedObject var security: AppSecurity
    func makeCoordinator() -> Coordinator { Coordinator(security: security) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        DispatchQueue.main.async { [weak view, weak coordinator = context.coordinator] in coordinator?.attach(view?.window) }
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { context.coordinator.attach(view.window); context.coordinator.refresh() }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.window?.isHidden = true; coordinator.window = nil }
    @MainActor final class Coordinator {
        let security: AppSecurity
        var window: UIWindow?
        weak var host: UIWindow?
        private var subscriptions: [AnyCancellable] = []
        init(security: AppSecurity) {
            self.security = security
            security.objectWillChange.sink { [weak self] in
                DispatchQueue.main.async { [weak self] in self?.refresh() }
            }.store(in: &subscriptions)
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification).sink { [weak self] _ in
                self?.security.obscured = true; self?.refresh()
            }.store(in: &subscriptions)
            NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification).sink { [weak self] _ in
                self?.security.lock(); self?.refresh()
            }.store(in: &subscriptions)
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification).sink { [weak self] _ in
                self?.security.obscured = false; self?.refresh()
            }.store(in: &subscriptions)
        }
        func attach(_ host: UIWindow?) {
            guard window == nil, let host, let scene = host.windowScene else { return }
            self.host = host
            let shield = UIWindow(windowScene: scene)
            shield.windowLevel = .alert + 1
            let controller = UIHostingController(rootView: SecurityShieldContent(security: security))
            controller.view.accessibilityViewIsModal = true
            shield.rootViewController = controller
            window = shield
            refresh()
        }
        func refresh() {
            guard let window else { return }
            if security.needsShield {
                if window.isHidden { window.makeKeyAndVisible() }
            } else if !window.isHidden { window.isHidden = true; host?.makeKey() }
        }
    }
}

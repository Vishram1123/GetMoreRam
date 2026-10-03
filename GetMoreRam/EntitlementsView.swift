//
//  EntitlementsView.swift
//  GetMoreRam
//
//  Reads entitlements directly off this process's own code signature at runtime, via
//  SecTaskCopyValueForEntitlement. This reflects whatever was actually signed/enforced for the
//  current PID - note that under LiveContainer, guest bundles are dlopen'd into LiveContainer's own
//  signed process rather than being individually re-signed and exec'd, so what you're checking here
//  is the entitlement set of whichever binary is actually running as the process (LiveContainer
//  itself, if that's the host), not a per-guest-bundle entitlement.
//

import SwiftUI
import Security
import CoreFoundation

// SecTaskCreateFromSelf/SecTaskCopyValueForEntitlement are declared in Security.framework's
// headers on macOS but Apple does not expose them in the public iOS SDK headers, even though the
// symbols are present in the on-device framework. Bind straight to the C symbols instead of relying
// on the (absent) Swift overlay declaration.
@_silgen_name("SecTaskCreateFromSelf")
func SecTaskCreateFromSelf(_ allocator: CFAllocator?) -> CFTypeRef?

@_silgen_name("SecTaskCopyValueForEntitlement")
func SecTaskCopyValueForEntitlement(_ task: CFTypeRef, _ entitlement: CFString, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> CFTypeRef?

struct EntitlementCheck: Identifiable {
    let id = UUID()
    let name: String
    let rawValue: String
}

final class EntitlementsModel: ObservableObject {
    @Published var checks: [EntitlementCheck] = []
    @Published var processInfo: String = ""

    static let entitlementsToCheck: [String] = [
        "com.apple.security.hypervisor",
        "com.apple.developer.kernel.increased-memory-limit",
        "com.apple.developer.kernel.increased-debugging-memory-limit",
        "com.apple.developer.kernel.extended-virtual-addressing",
        "get-task-allow",
        "application-identifier",
        "com.apple.developer.team-identifier",
        "com.apple.private.security.no-sandbox",
        "com.apple.security.application-groups",
    ]

    func refresh() {
        guard let task = SecTaskCreateFromSelf(nil) else {
            processInfo = "Could not create SecTask for self"
            checks = []
            return
        }

        processInfo = "PID: \(ProcessInfo.processInfo.processIdentifier)  |  Executable: \(Bundle.main.executableURL?.lastPathComponent ?? "?")"

        checks = Self.entitlementsToCheck.map { name in
            var error: Unmanaged<CFError>?
            let value = SecTaskCopyValueForEntitlement(task, name as CFString, &error)

            let raw: String
            if let error {
                raw = "error: \(error.takeRetainedValue() as Error)"
            } else if let value {
                raw = "\(value)"
            } else {
                raw = "(absent)"
            }
            return EntitlementCheck(name: name, rawValue: raw)
        }
    }

    var hasHypervisor: Bool {
        checks.first { $0.name == "com.apple.security.hypervisor" }
            .map { $0.rawValue != "(absent)" && !$0.rawValue.hasPrefix("error:") }
            ?? false
    }
}

struct EntitlementsView: View {
    @StateObject private var model = EntitlementsModel()

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text(model.processInfo)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Section {
                    HStack {
                        Text("Hypervisor entitlement")
                        Spacer()
                        Image(systemName: model.hasHypervisor ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundColor(model.hasHypervisor ? .green : .red)
                    }
                } footer: {
                    Text("This is ground truth for whether com.apple.security.hypervisor actually landed in the running process's code signature - independent of whatever the App IDs tab's server call reported.")
                }

                Section {
                    ForEach(model.checks) { check in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.name)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(check.rawValue)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                } header: {
                    Text("All Checked Entitlements")
                }

                Section {
                    Button("Refresh") {
                        model.refresh()
                    }
                }
            }
            .navigationTitle("Diagnostics".loc)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear { model.refresh() }
    }
}

#Preview {
    EntitlementsView()
}

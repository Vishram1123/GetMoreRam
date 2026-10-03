//
//  AppIDViewModel.swift
//  GetMoreRam
//
//  Created by s s on 2025/3/15.
//
import SwiftUI
import StosSign_API
import StosSign_Auth
import StosSign_Common

class AppIDModel : ObservableObject, Hashable {
    static func == (lhs: AppIDModel, rhs: AppIDModel) -> Bool {
        return lhs === rhs
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
    
    var appID: AppID
    @Published var bundleID: String
    @Published var result: String = ""
    
    init(appID: AppID) {
        self.appID = appID
        bundleID = appID.bundleIdentifier
    }
    
    func addIncreasedMemory() async throws {
        guard let team = DataManager.shared.model.team, let session = DataManager.shared.model.session else {
            throw "Please Login First"
        }

        let cool = try await AppleAPI.shared.updateAppID(appID, capabilities: ["INCREASED_MEMORY_LIMIT"], team: team, session: session)

        result = "\(cool)"
    }

    // Experimental: `updateAppID` forwards whatever capability id string we give it straight to
    // Apple's bundleIdCapabilities endpoint (see StosSign's AppleAPI.updateAppID) - there is no
    // client-side allowlist like the legacy `freeDeveloperCanUseEntitlement` path uses. That means
    // the *only* thing standing between us and finding out whether this works is whichever string
    // Apple's backend recognizes as the Hypervisor capability's id, and whether it's offered for an
    // iOS-platform bundle ID at all (Hypervisor/Virtualization only ship on macOS, so this is
    // expected to fail with a platform-mismatch style error - that failure message is itself the
    // useful result).
    static let hypervisorCapabilityCandidates = [
        "HYPERVISOR",
        "VIRTUALIZATION",
        "com.apple.security.hypervisor",
    ]

    func addHypervisor() async throws {
        guard let team = DataManager.shared.model.team, let session = DataManager.shared.model.session else {
            throw "Please Login First"
        }

        var lines: [String] = []
        for candidate in Self.hypervisorCapabilityCandidates {
            do {
                let updated = try await AppleAPI.shared.updateAppID(appID, capabilities: [candidate], team: team, session: session)
                lines.append("\(candidate): OK -> \(updated)")
            } catch {
                lines.append("\(candidate): FAILED -> \(error.detailedDescription)")
            }
        }
        result = lines.joined(separator: "\n\n")
    }

}

class AppIDViewModel : ObservableObject {
    @Published var appIDs : [AppIDModel] = []
    
    func fetchAppIDs() async throws {
        guard let team = DataManager.shared.model.team, let session = DataManager.shared.model.session else {
            throw "Please Login First"
        }
        
        let ids = try await AppleAPI.shared.fetchAppIDsForTeam(team: team, session: session)
        await MainActor.run {
            appIDs.removeAll()
            for id in ids {
                appIDs.append(AppIDModel(appID: id))
            }
        }
    }
}

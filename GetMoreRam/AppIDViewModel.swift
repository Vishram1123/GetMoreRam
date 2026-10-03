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
            lines.append("\(candidate): \(await rawUpdateAppID(capability: candidate, team: team, session: session))")
        }
        result = lines.joined(separator: "\n\n")
    }

    // `updateAppID` only recognizes a top-level "data" key as success or a top-level "error"
    // *string* as failure, and throws a generic .badServerResponse for anything else - which
    // swallows Apple's actual JSON:API error payload (a top-level "errors" *array* of objects with
    // "code"/"title"/"detail"). sendEditRequest is the public primitive updateAppID calls
    // internally, so call it directly here and dump Apple's raw response verbatim instead.
    private func rawUpdateAppID(capability: String, team: Team, session: AppleAPISession) async -> String {
        let url = AppleAPI.shared.v1URL.appendingPathComponent("bundleIds").appendingPathComponent(appID.identifier)

        let payload: [String: Any] = [
            "data": [
                "type": "bundleIds",
                "id": appID.identifier,
                "attributes": [
                    "identifier": appID.bundleIdentifier,
                    "teamId": team.identifier,
                    "seedId": team.identifier,
                    "bundleType": "bundle",
                    "name": appID.name,
                    "hasExclusiveManagedCapabilities": false
                ],
                "relationships": [
                    "bundleIdCapabilities": ["data": [[
                        "type": "bundleIdCapabilities",
                        "attributes": ["enabled": true, "settings": []],
                        "relationships": [
                            "capability": ["data": ["type": "capabilities", "id": capability]]
                        ]
                    ]]]
                ]
            ]
        ]

        do {
            let response = try await AppleAPI.shared.sendEditRequest(requestURL: url, body: payload, session: session, json: true, appendClientId: false)
            if let jsonData = try? JSONSerialization.data(withJSONObject: response, options: [.prettyPrinted, .sortedKeys]),
               let pretty = String(data: jsonData, encoding: .utf8) {
                return pretty
            }
            return "\(response)"
        } catch {
            return "Request itself failed: \(error.detailedDescription)"
        }
    }

}

class AppIDViewModel : ObservableObject {
    @Published var appIDs : [AppIDModel] = []
    @Published var capabilityCatalogResult: String = ""

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

    // fetchCapabilitiesForTeam() (StosSign) hardcodes filter[platform]=IOS, which is useless for
    // finding macOS-only capabilities like Hypervisor/Virtualization. sendServicesRequest is
    // public, so replicate the same GET /v1/capabilities call with a different platform filter to
    // get Apple's real capability id strings (and their backing entitlement keys) instead of
    // guessing them.
    func fetchCapabilityCatalog(platform: String) async throws {
        guard let team = DataManager.shared.model.team, let session = DataManager.shared.model.session else {
            throw "Please Login First"
        }

        let url = AppleAPI.shared.v1URL.appendingPathComponent("capabilities")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let response = try await AppleAPI.shared.sendServicesRequest(originalRequest: request, additionalParameters: ["filter[platform]": platform], session: session, team: team)

        guard let rawData = response["data"] else {
            await MainActor.run { capabilityCatalogResult = "No \"data\" key. Raw response:\n\(response)" }
            return
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: rawData),
              let capabilities = try? JSONDecoder().decode([Capability].self, from: jsonData) else {
            await MainActor.run { capabilityCatalogResult = "Couldn't decode as [Capability]. Raw data:\n\(rawData)" }
            return
        }

        let lines = capabilities
            .sorted { $0.id < $1.id }
            .map { cap -> String in
                let entitlementKeys = (cap.attributes.entitlements ?? []).map { $0.key }.joined(separator: ", ")
                return "\(cap.id)  [\(entitlementKeys)]"
            }

        let highlighted = lines.filter { $0.lowercased().contains("hyperv") || $0.lowercased().contains("virtual") }

        await MainActor.run {
            capabilityCatalogResult = """
            Platform: \(platform)  |  Total capabilities: \(capabilities.count)

            --- Matches for "hyperv"/"virtual" ---
            \(highlighted.isEmpty ? "(none)" : highlighted.joined(separator: "\n"))

            --- Full catalog ---
            \(lines.joined(separator: "\n"))
            """
        }
    }
}

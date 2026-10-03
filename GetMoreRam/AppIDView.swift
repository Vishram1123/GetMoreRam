//
//  AppIDView.swift
//  GetMoreRam
//
//  Created by s s on 2025/3/15.
//
import SwiftUI

struct AppIDEditView : View {
    @StateObject var viewModel : AppIDModel
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    
    var body: some View {
        Form {
            Section {
                Button {
                    Task { await addIncreasedMemoryLimit() }
                } label: {
                    Text("Add Increased Memory Limit")
                }
            }

            Section {
                Button(role: .destructive) {
                    Task { await addHypervisor() }
                } label: {
                    Text("Add Hypervisor (Experimental)")
                }
            } footer: {
                Text("Tries several guesses at Apple's capability id for the Hypervisor entitlement. Expected to fail - the response below is the useful part.")
            }

            Section {
                Text(viewModel.result)
                    .font(.system(.subheadline, design: .monospaced))
            } header: {
                Text("Server Response")
            }
        }
        .alert("Error", isPresented: $errorShow){
            Button("OK".loc, action: {
            })
        } message: {
            Text(errorInfo)
        }
        .navigationTitle(viewModel.bundleID)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    func addIncreasedMemoryLimit() async {
        do {
            try await viewModel.addIncreasedMemory()
        } catch {
            errorInfo = error.detailedDescription
            errorShow = true
        }

    }

    func addHypervisor() async {
        do {
            try await viewModel.addHypervisor()
        } catch {
            errorInfo = error.detailedDescription
            errorShow = true
        }
    }
}


struct AppIDView : View {
    @StateObject var viewModel : AppIDViewModel
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    ForEach(viewModel.appIDs, id: \.self) { appID in
                        NavigationLink {
                            AppIDEditView(viewModel: appID)
                        } label: {
                            Text(appID.bundleID)
                        }
                    }
                } header: {
                    Text("App IDs")
                }
                
                Section {
                    Button("Refresh") {
                        Task { await refreshButtonClicked() }
                    }
                }

                Section {
                    Button("Dump macOS Capability Catalog") {
                        Task { await catalogButtonClicked(platform: "MAC_OS") }
                    }
                    Button("Dump iOS Capability Catalog") {
                        Task { await catalogButtonClicked(platform: "IOS") }
                    }
                } footer: {
                    Text("Looks up Apple's real capability id strings (and backing entitlement keys) instead of guessing them, by querying GET /v1/capabilities with a platform filter.")
                }

                if !viewModel.capabilityCatalogResult.isEmpty {
                    Section {
                        Text(viewModel.capabilityCatalogResult)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    } header: {
                        Text("Capability Catalog")
                    }
                }
            }
            .alert("Error", isPresented: $errorShow){
                Button("OK".loc, action: {
                })
            } message: {
                Text(errorInfo)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    func refreshButtonClicked() async {
        do {
            try await viewModel.fetchAppIDs()
        } catch {
            errorInfo = error.detailedDescription
            errorShow = true
        }
    }

    func catalogButtonClicked(platform: String) async {
        do {
            try await viewModel.fetchCapabilityCatalog(platform: platform)
        } catch {
            errorInfo = error.detailedDescription
            errorShow = true
        }
    }
}

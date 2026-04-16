import SwiftUI

struct MainTabView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var selectedTab = 0
    @State private var showProfileSelector = false
    @State private var pendingReportPitchIds: Set<String>?
    
    private var needsProfileSelection: Bool {
        AuthService.accountType == "team" && AuthService.currentProfileId == nil
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView(authViewModel: authViewModel, onPDFUploadComplete: { ids in
                pendingReportPitchIds = ids
                selectedTab = 2
            })
                .tabItem {
                    Image(systemName: "camera.fill")
                    Text("Analyzer")
                }
                .tag(0)
            
            HistoryView(authViewModel: authViewModel)
                .tabItem {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("History")
                }
                .tag(1)
            
            ReportView(authViewModel: authViewModel, initialPitchIdsToSelect: $pendingReportPitchIds)
                .tabItem {
                    Image(systemName: "folder.fill")
                    Text("Report")
                }
                .tag(2)

            AccountView(authViewModel: authViewModel)
                .tabItem {
                    Image(systemName: "person.crop.circle.fill")
                    Text("Account")
                }
                .tag(3)
        }
        .tint(Color(red: 0.53, green: 0.81, blue: 0.92))
        .preferredColorScheme(.dark)
        .task {
            if needsProfileSelection {
                showProfileSelector = true
            }
        }
        .fullScreenCover(isPresented: $showProfileSelector) {
            ProfilesView(authViewModel: authViewModel, isBlocking: true)
        }
    }
}

import SwiftUI

struct MainTabView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView(authViewModel: authViewModel)
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
        }
        .tint(Color(red: 0.53, green: 0.81, blue: 0.92))
        .preferredColorScheme(.dark)
    }
}

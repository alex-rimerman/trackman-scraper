import SwiftUI

struct ProfilesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var authViewModel: AuthViewModel
    var isBlocking: Bool = false  // When true, user must select/create before dismissing
    @State private var profiles: [Profile] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateProfile = false
    @State private var newProfileName = ""
    @State private var isCreating = false
    
    private var hasValidSelection: Bool {
        guard let currentId = AuthService.currentProfileId else { return false }
        return profiles.contains { $0.id == currentId }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.12, green: 0.23, blue: 0.54),
                        Color(red: 0.08, green: 0.16, blue: 0.38)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if isLoading && profiles.isEmpty {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Loading profiles...")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.top, 12)
                        Spacer()
                    } else {
                        if isBlocking && profiles.isEmpty {
                            VStack(spacing: 20) {
                                Spacer()
                                Image(systemName: "person.3.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.white.opacity(0.5))
                                Text("Create Your First Profile")
                                    .font(.title2.weight(.semibold))
                                    .foregroundColor(.white)
                                Text("Team accounts need at least one profile to get started.")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.6))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                                Button(action: { showCreateProfile = true }) {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Create Profile")
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundColor(.white)
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 24)
                                    .background(Color(red: 0.53, green: 0.81, blue: 0.92))
                                    .cornerRadius(12)
                                }
                                .padding(.top, 8)
                                Spacer()
                            }
                        } else {
                            List {
                                ForEach(profiles) { profile in
                                    HStack {
                                        Text(profile.name)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.white)
                                        
                                        Spacer()
                                        
                                        if AuthService.currentProfileId == profile.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                                        }
                                    }
                                    .listRowBackground(Color.white.opacity(0.05))
                                    .listRowSeparatorTint(Color.white.opacity(0.1))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectProfile(profile)
                                    }
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                        }
                    }
                    
                    if let err = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(10)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                }
            }
            .navigationTitle(isBlocking ? "Select Profile" : "Profiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isBlocking {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .foregroundColor(hasValidSelection ? Color(red: 0.53, green: 0.81, blue: 0.92) : .gray)
                            .disabled(!hasValidSelection)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showCreateProfile = true }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                    }
                }
            }
            .sheet(isPresented: $showCreateProfile) {
                CreateProfileSheet(
                    profileName: $newProfileName,
                    isCreating: $isCreating,
                    onCreate: { name in
                        Task { await createProfile(name: name) }
                    },
                    onDismiss: { showCreateProfile = false }
                )
            }
        }
        .task { await loadProfiles() }
    }
    
    private func selectProfile(_ profile: Profile) {
        AuthService.currentProfileId = profile.id
        AuthService.currentProfileName = profile.name
        authViewModel.objectWillChange.send()
    }
    
    private func loadProfiles() async {
        isLoading = true
        errorMessage = nil
        do {
            profiles = try await AuthService.getProfiles()
            // Sync currentProfileName from selected profile if we have id but not name
            if let id = AuthService.currentProfileId,
               let profile = profiles.first(where: { $0.id == id }) {
                AuthService.currentProfileName = profile.name
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    private func createProfile(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        
        isCreating = true
        errorMessage = nil
        do {
            let profile = try await AuthService.createProfile(name: trimmed)
            profiles.append(profile)
            AuthService.currentProfileId = profile.id
            AuthService.currentProfileName = profile.name
            authViewModel.objectWillChange.send()
            newProfileName = ""
            showCreateProfile = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreating = false
    }
}

// MARK: - Create Profile Sheet (reliable form instead of alert)

struct CreateProfileSheet: View {
    @Binding var profileName: String
    @Binding var isCreating: Bool
    var onCreate: (String) -> Void
    var onDismiss: () -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.16, blue: 0.38)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    TextField("Profile name", text: $profileName)
                        .textFieldStyle(.plain)
                        .padding(16)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                        .foregroundColor(.white)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 20)
                    
                    Text("Enter the pitcher's name for this profile.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                    
                    Spacer()
                }
                .padding(.top, 24)
            }
            .navigationTitle("New Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(profileName)
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(profileName.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : Color(red: 0.53, green: 0.81, blue: 0.92))
                    .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
        }
    }
}

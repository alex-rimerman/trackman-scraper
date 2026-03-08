import SwiftUI

struct ProfilesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var authViewModel: AuthViewModel
    var isBlocking: Bool = false
    @State private var profiles: [Profile] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateProfile = false
    @State private var newProfileName = ""
    @State private var isCreating = false
    @State private var showDeleteAccountConfirmation = false
    @State private var deleteAccountError: String?
    @State private var profileToDelete: Profile?
    @State private var isDeleting = false
    @State private var profileToRename: Profile?
    @State private var renameText = ""
    @State private var showMergeSheet = false
    @State private var mergeSource: Profile?
    @State private var mergeTarget: Profile?
    
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
                                Button {
                                    showCreateProfile = true
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Create Profile")
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundColor(.white)
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 24)
                                    .contentShape(Rectangle())
                                    .background(Color(red: 0.53, green: 0.81, blue: 0.92))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 8)
                                Button {
                                    authViewModel.logout()
                                } label: {
                                    Text("Sign Out")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.6))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 20)
                                Spacer()
                            }
                        } else {
                            List {
                                ForEach(profiles) { profile in
                                    profileRow(profile)
                                        .listRowBackground(Color.white.opacity(0.05))
                                        .listRowSeparatorTint(Color.white.opacity(0.1))
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectProfile(profile) }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                profileToDelete = profile
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                            Button {
                                                renameText = profile.name
                                                profileToRename = profile
                                            } label: {
                                                Label("Rename", systemImage: "pencil")
                                            }
                                            .tint(.orange)
                                        }
                                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                            Button {
                                                mergeSource = profile
                                                showMergeSheet = true
                                            } label: {
                                                Label("Merge", systemImage: "arrow.triangle.merge")
                                            }
                                            .tint(.purple)
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
                            .buttonStyle(.plain)
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .foregroundColor(hasValidSelection ? Color(red: 0.53, green: 0.81, blue: 0.92) : .gray)
                            .disabled(!hasValidSelection)
                            .buttonStyle(.plain)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateProfile = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Button("Sign Out", role: .destructive) { authViewModel.logout() }
                        Button("Delete Account", role: .destructive) { showDeleteAccountConfirmation = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
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
            .alert("Rename Profile", isPresented: Binding(
                get: { profileToRename != nil },
                set: { if !$0 { profileToRename = nil } }
            )) {
                TextField("Profile name", text: $renameText)
                Button("Save") {
                    if let profile = profileToRename {
                        Task { await renameProfile(profile, to: renameText) }
                    }
                }
                Button("Cancel", role: .cancel) { profileToRename = nil }
            } message: {
                Text("Enter a new name for this profile.")
            }
            .confirmationDialog("Delete Profile", isPresented: Binding(
                get: { profileToDelete != nil },
                set: { if !$0 { profileToDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Delete \"\(profileToDelete?.name ?? "")\"", role: .destructive) {
                    if let profile = profileToDelete {
                        Task { await deleteProfile(profile) }
                    }
                }
                Button("Cancel", role: .cancel) { profileToDelete = nil }
            } message: {
                Text("This will permanently delete this profile and all its pitch data. This cannot be undone.")
            }
            .sheet(isPresented: $showMergeSheet) {
                MergeProfileSheet(
                    source: mergeSource,
                    profiles: profiles,
                    onMerge: { target in
                        Task { await mergeProfile(into: target) }
                    },
                    onDismiss: {
                        showMergeSheet = false
                        mergeSource = nil
                    }
                )
            }
            .confirmationDialog("Delete Account", isPresented: $showDeleteAccountConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        do {
                            try await authViewModel.deleteAccount()
                        } catch {
                            deleteAccountError = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete your account and all pitch data. This action cannot be undone.")
            }
            .alert("Unable to Delete Account", isPresented: Binding(
                get: { deleteAccountError != nil },
                set: { if !$0 { deleteAccountError = nil } }
            )) {
                Button("OK") { deleteAccountError = nil }
            } message: {
                if let err = deleteAccountError {
                    Text(err)
                }
            }
        }
        .task { await loadProfiles() }
    }
    
    // MARK: - Profile Row
    
    private func profileRow(_ profile: Profile) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                HStack(spacing: 10) {
                    Text("\(profile.pitchCount) pitch\(profile.pitchCount == 1 ? "" : "es")")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                    
                    if let avg = profile.avgStuffPlus {
                        HStack(spacing: 3) {
                            Text("Avg S+")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                            Text(String(format: "%.0f", avg))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(stuffColor(avg))
                        }
                    }
                }
            }
            
            Spacer()
            
            if AuthService.currentProfileId == profile.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
            }
        }
    }
    
    private func stuffColor(_ v: Double) -> Color {
        switch v {
        case 120...: return .orange
        case 105..<120: return Color(red: 1.0, green: 0.75, blue: 0.0)
        case 95..<105: return Color(red: 0.53, green: 0.81, blue: 0.92)
        default: return .gray
        }
    }
    
    // MARK: - Actions
    
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
    
    private func deleteProfile(_ profile: Profile) async {
        isDeleting = true
        errorMessage = nil
        do {
            try await AuthService.deleteProfile(id: profile.id)
            profiles.removeAll { $0.id == profile.id }
            if AuthService.currentProfileId == profile.id {
                AuthService.currentProfileId = profiles.first?.id
                AuthService.currentProfileName = profiles.first?.name
                authViewModel.objectWillChange.send()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isDeleting = false
        profileToDelete = nil
    }
    
    private func renameProfile(_ profile: Profile, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        do {
            let updated = try await AuthService.renameProfile(id: profile.id, name: trimmed)
            if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[idx] = updated
            }
            if AuthService.currentProfileId == profile.id {
                AuthService.currentProfileName = trimmed
                authViewModel.objectWillChange.send()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        profileToRename = nil
    }
    
    private func mergeProfile(into target: Profile) async {
        guard let source = mergeSource, source.id != target.id else { return }
        errorMessage = nil
        do {
            try await AuthService.mergeProfiles(sourceId: source.id, targetId: target.id)
            await loadProfiles()
            if AuthService.currentProfileId == source.id {
                AuthService.currentProfileId = target.id
                AuthService.currentProfileName = target.name
                authViewModel.objectWillChange.send()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        showMergeSheet = false
        mergeSource = nil
    }
}

// MARK: - Create Profile Sheet

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
                        .buttonStyle(.plain)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(profileName)
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(profileName.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : Color(red: 0.53, green: 0.81, blue: 0.92))
                    .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Merge Profile Sheet

struct MergeProfileSheet: View {
    let source: Profile?
    let profiles: [Profile]
    var onMerge: (Profile) -> Void
    var onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var targets: [Profile] {
        profiles.filter { $0.id != source?.id }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.16, blue: 0.38).ignoresSafeArea()
                
                VStack(spacing: 16) {
                    if let source {
                        Text("Merge \"\(source.name)\" into:")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.top, 20)
                        
                        Text("All pitches will be moved to the target profile. \"\(source.name)\" will be deleted.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    
                    List {
                        ForEach(targets) { profile in
                            Button {
                                onMerge(profile)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(profile.name)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text("\(profile.pitchCount) pitches")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.4))
                                    Image(systemName: "arrow.right.circle.fill")
                                        .foregroundColor(.purple)
                                }
                            }
                            .listRowBackground(Color.white.opacity(0.05))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Merge Profiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                        .foregroundColor(.white.opacity(0.7))
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

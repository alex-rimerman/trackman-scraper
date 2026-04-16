import SwiftUI

struct AccountView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var me: AuthMeResponse?
    @State private var loadError: String?
    @State private var isLoading = true

    private let accent = Color(red: 0.53, green: 0.81, blue: 0.92)

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

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else if let err = loadError {
                            Text(err)
                                .font(.subheadline)
                                .foregroundColor(.orange)
                                .padding()
                        } else if let m = me {
                            sectionTitle("Profile")
                            infoRow(icon: "person.fill", title: "Name", value: m.name)
                            infoRow(icon: "envelope.fill", title: "Email", value: m.email)
                            infoRow(
                                icon: "person.fill",
                                title: "Account type",
                                value: (m.accountType ?? "personal") == "team" ? "Team" : "Personal"
                            )

                            sectionTitle("Subscription")
                            infoRow(
                                icon: "creditcard.fill",
                                title: "Plan",
                                value: SubscriptionService.subscriptionTierLabel(
                                    productId: m.subscriptionProductId,
                                    accountType: m.accountType ?? "personal"
                                )
                            )
                            infoRow(
                                icon: "checkmark.seal.fill",
                                title: "Status",
                                value: subscriptionStatusLabel(m)
                            )
                            infoRow(
                                icon: "calendar",
                                title: m.isSubscribed ? "Renews / expires" : "Expiration",
                                value: formattedExpires(m.subscriptionExpiresAt)
                            )

                            Button {
                                Task { await refresh() }
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Refresh status")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)

                            Button(role: .destructive) {
                                authViewModel.logout()
                            } label: {
                                Text("Sign Out")
                                    .font(.body.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .buttonStyle(.bordered)
                            .padding(.top, 16)
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(red: 0.1, green: 0.18, blue: 0.42), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task { await refresh() }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(.white.opacity(0.55))
            .textCase(.uppercase)
            .padding(.top, 4)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .foregroundColor(accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
                Text(value)
                    .font(.body)
                    .foregroundColor(.white)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func subscriptionStatusLabel(_ m: AuthMeResponse) -> String {
        let s = (m.subscriptionStatus ?? "").lowercased()
        if m.isSubscribed { return "Active" }
        if s == "expired" { return "Expired" }
        if s == "none" || s.isEmpty { return "None" }
        return m.subscriptionStatus?.capitalized ?? "—"
    }

    private func formattedExpires(_ iso: String?) -> String {
        guard let iso = iso, !iso.isEmpty else { return "—" }
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = isoFmt.date(from: iso)
        if date == nil {
            isoFmt.formatOptions = [.withInternetDateTime]
            date = isoFmt.date(from: iso)
        }
        guard let date = date else { return iso }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: date)
    }

    private func refresh() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let response = try await AuthService.getMe()
            me = response
            authViewModel.isSubscribed = response.isSubscribed
        } catch {
            loadError = error.localizedDescription
        }
    }
}

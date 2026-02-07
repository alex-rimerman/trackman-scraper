import SwiftUI

struct LoginView: View {
    @ObservedObject var authViewModel: AuthViewModel
    
    var body: some View {
        ZStack {
            // Background
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
                VStack(spacing: 32) {
                    Spacer().frame(height: 60)
                    
                    // Logo / Title
                    VStack(spacing: 8) {
                        Image(systemName: "baseball.diamond.bases")
                            .font(.system(size: 56))
                            .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                        
                        Text("Developing Baseball")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("Trackman Pitch Analyzer")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92).opacity(0.8))
                    }
                    
                    // Toggle Login / Signup
                    HStack(spacing: 0) {
                        Button(action: { withAnimation { authViewModel.isSignup = false } }) {
                            Text("Log In")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(!authViewModel.isSignup ? .white : .white.opacity(0.4))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(!authViewModel.isSignup ? Color.white.opacity(0.15) : Color.clear)
                                .cornerRadius(10)
                        }
                        
                        Button(action: { withAnimation { authViewModel.isSignup = true } }) {
                            Text("Sign Up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(authViewModel.isSignup ? .white : .white.opacity(0.4))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(authViewModel.isSignup ? Color.white.opacity(0.15) : Color.clear)
                                .cornerRadius(10)
                        }
                    }
                    .padding(4)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                    .padding(.horizontal, 32)
                    
                    // Form
                    VStack(spacing: 16) {
                        if authViewModel.isSignup {
                            formField(
                                icon: "person.fill",
                                placeholder: "Full Name",
                                text: $authViewModel.name,
                                isSecure: false
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        
                        formField(
                            icon: "envelope.fill",
                            placeholder: "Email",
                            text: $authViewModel.email,
                            isSecure: false,
                            keyboardType: .emailAddress,
                            autocapitalization: .never
                        )
                        
                        formField(
                            icon: "lock.fill",
                            placeholder: "Password",
                            text: $authViewModel.password,
                            isSecure: true
                        )
                        
                        if let error = authViewModel.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 32)
                    
                    // Submit button
                    Button(action: {
                        Task {
                            if authViewModel.isSignup {
                                await authViewModel.signup()
                            } else {
                                await authViewModel.login()
                            }
                        }
                    }) {
                        HStack {
                            if authViewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .padding(.trailing, 8)
                            }
                            Text(authViewModel.isSignup ? "Create Account" : "Log In")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.53, green: 0.81, blue: 0.92),
                                    Color(red: 0.39, green: 0.68, blue: 0.82)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                    }
                    .disabled(authViewModel.isLoading)
                    .padding(.horizontal, 32)
                    
                    Spacer()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Form Field
    
    private func formField(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool,
        keyboardType: UIKeyboardType = .default,
        autocapitalization: TextInputAutocapitalization = .sentences
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                .frame(width: 20)
            
            if isSecure {
                SecureField(placeholder, text: text)
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                TextField(placeholder, text: text)
                    .foregroundColor(.white)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
                    .autocorrectionDisabled()
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

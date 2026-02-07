import Foundation
import SwiftUI

@MainActor
class AuthViewModel: ObservableObject {
    
    @Published var isLoggedIn: Bool = AuthService.isLoggedIn
    @Published var userName: String = AuthService.currentUserName ?? ""
    @Published var userEmail: String = AuthService.currentUserEmail ?? ""
    
    // Login / Signup form state
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var name: String = ""
    @Published var isSignup: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    func login() async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await AuthService.login(email: email, password: password)
            userName = response.name
            userEmail = response.email
            isLoggedIn = true
            clearForm()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func signup() async {
        guard !email.isEmpty, !password.isEmpty, !name.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters"
            return
        }
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await AuthService.signup(email: email, name: name, password: password)
            userName = response.name
            userEmail = response.email
            isLoggedIn = true
            clearForm()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func logout() {
        AuthService.logout()
        isLoggedIn = false
        userName = ""
        userEmail = ""
        clearForm()
    }
    
    private func clearForm() {
        email = ""
        password = ""
        name = ""
        errorMessage = nil
    }
}

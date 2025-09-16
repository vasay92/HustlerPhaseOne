// Add this to ContentView.swift or create Views/Authentication/LoginView.swift
import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @StateObject private var firebase = FirebaseService.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Logo
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                Text("ClaudeHustler")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // Input fields
                VStack(spacing: 15) {
                    TextField("Email", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.horizontal)
                
                // Sign In/Up Button
                Button(action: {
                    Task {
                        if isSignUp {
                            try? await firebase.signUp(
                                email: email,
                                password: password,
                                name: email.split(separator: "@").first.map(String.init) ?? "User"
                            )
                        } else {
                            try? await firebase.signIn(email: email, password: password)
                        }
                    }
                }) {
                    Text(isSignUp ? "Sign Up" : "Sign In")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                
                // Toggle between Sign In/Up
                Button(action: { isSignUp.toggle() }) {
                    Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                        .foregroundColor(.blue)
                }
                
                Spacer()
            }
            .padding()
        }
    }
}


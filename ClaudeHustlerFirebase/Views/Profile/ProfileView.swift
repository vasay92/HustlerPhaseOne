// ProfileView.swift
// Path: ClaudeHustlerFirebase/Views/Profile/ProfileView.swift

import SwiftUI
import FirebaseFirestore

// This is now a wrapper that redirects to EnhancedProfileView for the current user
struct ProfileView: View {
    @StateObject private var firebase = FirebaseService.shared
    
    var body: some View {
        // Show the new EnhancedProfileView with current user's ID
        if let userId = firebase.currentUser?.id {
            EnhancedProfileView(userId: userId)
        } else {
            // Fallback if no user is logged in
            VStack {
                Image(systemName: "person.circle")
                    .font(.system(size: 80))
                    .foregroundColor(.gray)
                
                Text("Please log in to view your profile")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }
}

// Keep the SettingsView here since it's still being used
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    
    var body: some View {
        NavigationView {
            List {
                Section("Account") {
                    NavigationLink("Edit Profile") {
                        Text("Edit Profile View - Coming Soon")
                            .foregroundColor(.secondary)
                    }
                    
                    NavigationLink("Change Password") {
                        Text("Change Password View - Coming Soon")
                            .foregroundColor(.secondary)
                    }
                    
                    NavigationLink("Privacy") {
                        Text("Privacy Settings - Coming Soon")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Preferences") {
                    NavigationLink("Notifications") {
                        Text("Notification Settings - Coming Soon")
                            .foregroundColor(.secondary)
                    }
                    
                    NavigationLink("Language") {
                        Text("Language Settings - Coming Soon")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("About") {
                    NavigationLink("Terms of Service") {
                        ScrollView {
                            Text("Terms of Service")
                                .font(.largeTitle)
                                .padding()
                            
                            Text("Last updated: \(Date(), style: .date)")
                                .foregroundColor(.secondary)
                                .padding()
                            
                            Text("These terms of service will be updated soon.")
                                .padding()
                        }
                    }
                    
                    NavigationLink("Privacy Policy") {
                        ScrollView {
                            Text("Privacy Policy")
                                .font(.largeTitle)
                                .padding()
                            
                            Text("Last updated: \(Date(), style: .date)")
                                .foregroundColor(.secondary)
                                .padding()
                            
                            Text("Our privacy policy will be updated soon.")
                                .padding()
                        }
                    }
                    
                    NavigationLink("Help Center") {
                        VStack {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 60))
                                .foregroundColor(.blue)
                                .padding()
                            
                            Text("Help Center")
                                .font(.title)
                            
                            Text("Need help? Contact support@claudehustler.com")
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                }
                
                Section("Support") {
                    NavigationLink("Contact Us") {
                        VStack(spacing: 20) {
                            Image(systemName: "envelope")
                                .font(.system(size: 60))
                                .foregroundColor(.blue)
                            
                            Text("Contact Support")
                                .font(.title)
                            
                            Text("Email: support@claudehustler.com")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }
                    
                    NavigationLink("Report a Problem") {
                        VStack {
                            Text("Report a Problem")
                                .font(.title)
                                .padding()
                            
                            Text("Feature coming soon")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section {
                    Button(action: {
                        // Sign out action
                        try? firebase.signOut()
                    }) {
                        HStack {
                            Image(systemName: "arrow.right.square")
                            Text("Sign Out")
                        }
                        .foregroundColor(.red)
                    }
                }
                
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

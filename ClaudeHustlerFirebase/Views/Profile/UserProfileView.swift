// UserProfileView.swift
// Path: ClaudeHustlerFirebase/Views/Profile/UserProfileView.swift

import SwiftUI
import FirebaseFirestore

// This is now a simple wrapper that redirects to EnhancedProfileView
// We keep this file to maintain compatibility with existing navigation throughout the app
struct UserProfileView: View {
    let userId: String
    
    var body: some View {
        // Simply show the new EnhancedProfileView
        // EnhancedProfileView handles all the logic for displaying user profiles
        // It automatically detects if it's the current user's profile or another user's profile
        EnhancedProfileView(userId: userId)
    }
}

// All the old code has been moved to EnhancedProfileView and ProfileSupportingViews
// The ServicePostRow struct that was here is now replaced by better components in ProfileSupportingViews

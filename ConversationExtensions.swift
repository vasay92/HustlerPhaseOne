// ConversationExtensions.swift
// Path: ClaudeHustlerFirebase/Models/ConversationExtensions.swift

import Foundation
import FirebaseFirestore

extension Conversation {
    
    // MARK: - Convenience properties for ConversationsListView compatibility
    
    var participantIds: [String] {
        return participants
    }
    
    var participantNames: [String: String] {
        var names: [String: String] = [:]
        for (userId, info) in participantDetails {
            names[userId] = info.name
        }
        return names
    }
    
    var participantImages: [String: String] {
        var images: [String: String] = [:]
        for (userId, info) in participantDetails {
            if let imageURL = info.profileImageURL {
                images[userId] = imageURL
            }
        }
        return images
    }
    
    var lastMessageTime: Date {
        return lastMessage?.createdAt ?? updatedAt
    }
    
    // Use a different name to avoid collision with existing lastMessage property
    var lastMessageString: String {
        return lastMessage?.text ?? ""
    }
    
    // MARK: - Helper Methods for ConversationsListView
    
    /// Get the ID of the other participant in the conversation
    func otherParticipantId(currentUserId: String) -> String? {
        return participants.first { $0 != currentUserId }
    }
    
    /// Get the name of the other participant in the conversation
    func otherParticipantName(currentUserId: String) -> String? {
        guard let otherUserId = otherParticipantId(currentUserId: currentUserId) else {
            return nil
        }
        return participantDetails[otherUserId]?.name
    }
    
    /// Get the profile image URL of the other participant
    func otherParticipantImage(currentUserId: String) -> String? {
        guard let otherUserId = otherParticipantId(currentUserId: currentUserId) else {
            return nil
        }
        return participantDetails[otherUserId]?.profileImageURL
    }
    
    /// Get the timestamp of the last message as a Date
    var lastMessageTimestamp: Date {
        return lastMessage?.createdAt ?? updatedAt
    }
    
    /// Get unread count for a specific user
    func unreadCountForUser(_ userId: String) -> Int {
        return unreadCounts[userId] ?? 0
    }
    
    /// Check if the conversation has unread messages for a specific user
    func hasUnreadMessages(for userId: String) -> Bool {
        return unreadCountForUser(userId) > 0
    }
    
    /// Get a display-friendly title for the conversation
    func displayTitle(currentUserId: String) -> String {
        if let otherName = otherParticipantName(currentUserId: currentUserId), !otherName.isEmpty {
            return otherName
        }
        
        // Fallback: If no name is found, try to get the other participant's ID
        if let otherUserId = otherParticipantId(currentUserId: currentUserId) {
            // Use the first part of the email or the ID as fallback
            if otherUserId.contains("@") {
                return String(otherUserId.split(separator: "@").first ?? "User")
            }
            return "User"
        }
        
        return "Unknown User"
    }
    
    /// Get the initials of the other participant for avatar display
    func otherParticipantInitials(currentUserId: String) -> String {
        if let name = otherParticipantName(currentUserId: currentUserId), !name.isEmpty {
            let components = name.split(separator: " ")
            if components.count >= 2 {
                // First letter of first name and last name
                return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
            } else if components.count == 1 {
                // First letter of single name
                return String(components[0].prefix(1)).uppercased()
            }
        }
        return "?"
    }
    
    /// Check if the conversation is with a specific user
    func isWithUser(_ userId: String) -> Bool {
        return participants.contains(userId)
    }
    
    /// Get a preview-safe version of the last message
    var lastMessagePreview: String {
        // The lastMessage is a Message object, get its text
        let messageText = lastMessage?.text ?? ""
        
        // Truncate long messages
        if messageText.count > 100 {
            return String(messageText.prefix(97)) + "..."
        }
        
        // Replace newlines with spaces for preview
        return messageText.replacingOccurrences(of: "\n", with: " ")
    }
    
    /// Format the last message time for display
    var formattedLastMessageTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let timestamp = lastMessage?.createdAt ?? updatedAt
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
    
    /// Check if this is a service-related conversation (based on context)
    var isServiceRelated: Bool {
        return contextId != nil && contextType != nil
    }
    
    /// Get the avatar color based on the other participant's ID (for consistent coloring)
    func avatarColor(currentUserId: String) -> String {
        guard let otherUserId = otherParticipantId(currentUserId: currentUserId) else {
            return "#808080" // Gray as default
        }
        
        // Generate a consistent color based on the user ID
        let colors = [
            "#FF6B6B", // Red
            "#4ECDC4", // Teal
            "#45B7D1", // Blue
            "#96CEB4", // Green
            "#FFEAA7", // Yellow
            "#DDA0DD", // Plum
            "#98D8C8", // Mint
            "#F7DC6F", // Gold
            "#BB8FCE", // Purple
            "#85C1E2"  // Sky Blue
        ]
        
        // Use hash of userId to consistently pick a color
        let hashValue = abs(otherUserId.hashValue)
        let colorIndex = hashValue % colors.count
        return colors[colorIndex]
    }
}

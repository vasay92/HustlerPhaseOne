// DataModels.swift
// This should REPLACE your existing DataModels.swift file completely

import Foundation
import FirebaseFirestore

// MARK: - User Model
struct User: Codable, Identifiable {
    @DocumentID var id: String?
    let email: String
    var name: String
    var profileImageURL: String?
    var bio: String = ""
    var isServiceProvider: Bool = false
    var location: String = ""
    var rating: Double = 0.0
    var reviewCount: Int = 0
    var ratingBreakdown: [String: Int]? // "5": 10, "4": 5, etc.
    var lastRatingUpdate: Date?
    var following: [String] = []
    var followers: [String] = []
    var completedServices: Int? = 0
    var timesBooked: Int? = 0
    let createdAt: Date = Date()
    var lastActive: Date = Date()
    
    // Notification tokens
    var fcmToken: String?
    var notificationSettings: NotificationSettings?
}

// MARK: - Notification Settings
struct NotificationSettings: Codable {
    var newReviews: Bool = true
    var reviewReplies: Bool = true
    var reviewEdits: Bool = true
    var helpfulVotes: Bool = true
}

// MARK: - Portfolio Flash Card Model
struct PortfolioCard: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    var title: String
    var coverImageURL: String?
    var mediaURLs: [String] = []
    var description: String?
    let createdAt: Date = Date()
    var updatedAt: Date = Date()
    var displayOrder: Int = 0
}

// MARK: - Review Model
struct Review: Codable, Identifiable {
    @DocumentID var id: String?
    let reviewerId: String
    let reviewedUserId: String
    var reviewerName: String?
    var reviewerProfileImage: String?
    var rating: Int
    var text: String
    var mediaURLs: [String] = []
    var reply: ReviewReply?
    var helpfulVotes: [String] = []
    let createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isEdited: Bool = false
    var servicePostId: String? = nil
    var reviewNumber: Int? = nil
}

// MARK: - Review Reply Model
struct ReviewReply: Codable {
    let userId: String
    var text: String
    let repliedAt: Date = Date()
}

// MARK: - Review Notification Model
struct ReviewNotification: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String // Who receives the notification
    let reviewId: String
    let type: ReviewNotificationType
    let fromUserId: String
    let fromUserName: String
    let message: String
    var isRead: Bool = false
    let createdAt: Date = Date()
    
    enum ReviewNotificationType: String, Codable {
        case newReview = "new_review"
        case reviewReply = "review_reply"
        case reviewEdit = "review_edit"
        case helpfulVote = "helpful_vote"
    }
}

// MARK: - Saved Items Model
struct SavedItem: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    let itemId: String
    let itemType: SavedItemType
    let savedAt: Date = Date()
    
    enum SavedItemType: String, Codable {
        case reel, post
    }
}

// MARK: - Service Post Model
struct ServicePost: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    var userName: String?
    var userProfileImage: String?
    var title: String
    var description: String
    var category: ServiceCategory
    var price: Double?
    var location: String?
    var imageURLs: [String] = []
    var isRequest: Bool = false
    var status: PostStatus = .active
    let createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    enum PostStatus: String, Codable {
        case active, completed, cancelled
    }
}

// MARK: - Status Model (Stories-like feature)
struct Status: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    var userName: String?
    var userProfileImage: String?
    var mediaURL: String
    var caption: String?
    var mediaType: MediaType = .image
    let createdAt: Date = Date()
    let expiresAt: Date
    var viewedBy: [String] = []
    var isActive: Bool = true
    
    enum MediaType: String, Codable {
        case image, video
    }
    
    var isExpired: Bool {
        Date() > expiresAt
    }
}

// MARK: - Reel Model
struct Reel: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    var userName: String?
    var userProfileImage: String?
    var videoURL: String
    var thumbnailURL: String?
    var title: String
    var description: String
    var category: ServiceCategory?
    var hashtags: [String] = []
    let createdAt: Date = Date()
    var likes: [String] = []
    var comments: Int = 0
    var shares: Int = 0
    var views: Int = 0
    var isPromoted: Bool = false
}


// MARK: - Comment Model (Enhanced for Reels)
struct Comment: Codable, Identifiable {
    @DocumentID var id: String?
    let reelId: String
    let userId: String
    var userName: String?
    var userProfileImage: String?
    var text: String
    let timestamp: Date = Date()
    var likes: [String] = []
    
    // For nested replies
    var parentCommentId: String? = nil  // nil means it's a top-level comment
    var replyCount: Int = 0
    var isDeleted: Bool = false
    var deletedAt: Date?
    
    // Helper computed property
    var isReply: Bool {
        parentCommentId != nil
    }
}

// MARK: - Reel Like Model (for showing who liked)
struct ReelLike: Codable, Identifiable {
    @DocumentID var id: String?
    let reelId: String
    let userId: String
    var userName: String?
    var userProfileImage: String?
    let likedAt: Date = Date()
}


// MARK: - Service Category Enum
enum ServiceCategory: String, CaseIterable, Codable {
    case cleaning, tutoring, delivery, electrical, plumbing
    case carpentry, painting, landscaping, moving, technology, other
    
    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Message Model
struct Message: Codable, Identifiable {
    @DocumentID var id: String?
    let senderId: String
    let senderName: String
    let senderProfileImage: String?
    let conversationId: String
    let text: String
    var timestamp: Date = Date()
    
    var isDelivered: Bool = false
    var deliveredAt: Date?
    var isRead: Bool = false
    var readAt: Date?
    
    var contextType: MessageContextType?
    var contextId: String?
    var contextTitle: String?
    var contextImage: String?
    var contextUserId: String?
    
    var isEdited: Bool = false
    var editedAt: Date?
    var isDeleted: Bool = false
    
    enum MessageContextType: String, Codable {
        case post = "post"
        case reel = "reel"
        case status = "status"
    }
}

// MARK: - Conversation Model
struct Conversation: Codable, Identifiable {
    @DocumentID var id: String?
    var participantIds: [String]
    var participantNames: [String: String] = [:]
    var participantImages: [String: String] = [:]
    
    var lastMessage: String?
    var lastMessageTimestamp: Date = Date()
    var lastMessageSenderId: String?
    
    var unreadCounts: [String: Int] = [:]
    var lastReadTimestamps: [String: Date] = [:]
    
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    var blockedUsers: [String] = []
    
    func otherParticipantId(currentUserId: String) -> String? {
        participantIds.first { $0 != currentUserId }
    }
    
    func otherParticipantName(currentUserId: String) -> String? {
        guard let otherId = otherParticipantId(currentUserId: currentUserId) else { return nil }
        return participantNames[otherId]
    }
    
    func otherParticipantImage(currentUserId: String) -> String? {
        guard let otherId = otherParticipantId(currentUserId: currentUserId) else { return nil }
        return participantImages[otherId]
    }
    
    func isBlocked(by userId: String) -> Bool {
        blockedUsers.contains(userId)
    }
}

// MARK: - Message Report Model
struct MessageReport: Codable, Identifiable {
    @DocumentID var id: String?
    let reporterId: String
    let reportedUserId: String
    let messageId: String?
    let conversationId: String
    let reason: ReportReason
    let additionalDetails: String?
    let timestamp: Date = Date()
    var status: ReportStatus = .pending
    
    enum ReportReason: String, Codable, CaseIterable {
        case spam = "spam"
        case harassment = "harassment"
        case inappropriate = "inappropriate"
        case fake = "fake"
        case other = "other"
        
        var displayName: String {
            switch self {
            case .spam: return "Spam"
            case .harassment: return "Harassment"
            case .inappropriate: return "Inappropriate Content"
            case .fake: return "Fake Profile"
            case .other: return "Other"
            }
        }
    }
    
    enum ReportStatus: String, Codable {
        case pending = "pending"
        case reviewed = "reviewed"
        case resolved = "resolved"
    }
}

// DataModels.swift
// Complete production-ready data models with validation

import Foundation
import FirebaseFirestore

// MARK: - Validation Protocol
protocol Validatable {
    var isValid: Bool { get }
    var validationErrors: [String] { get }
}

// MARK: - Cacheable Protocol
protocol Cacheable {
    var cacheKey: String { get }
    var cacheExpiry: TimeInterval { get }
    var needsRefresh: Bool { get }
}

// MARK: - User Model
struct User: Codable, Identifiable, Validatable, Cacheable {
    @DocumentID var id: String?
    let email: String
    var name: String
    var username: String?
    var profileImageURL: String?
    var thumbnailImageURL: String?
    var bio: String = ""
    var isServiceProvider: Bool = false
    var location: String = ""
    var rating: Double = 0.0
    var reviewCount: Int = 0
    var ratingBreakdown: [String: Int]?
    var lastRatingUpdate: Date?
    var following: [String] = []
    var followers: [String] = []
    var blockedUsers: [String] = []
    var completedServices: Int = 0
    var timesBooked: Int = 0
    var responseTime: Double? // Average response time in hours
    var responseRate: Double? // Percentage of messages responded to
    var verificationStatus: VerificationStatus = .unverified
    var badges: [UserBadge] = []
    var socialLinks: SocialLinks?
    var availability: AvailabilityStatus = .available
    var lastActive: Date = Date()
    let createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    // Notification settings
    var fcmToken: String?
    var notificationSettings: NotificationSettings = NotificationSettings()
    
    // Privacy settings
    var privacySettings: PrivacySettings = PrivacySettings()
    
    // Subscription/Premium status
    var isPremium: Bool = false
    var premiumExpiryDate: Date?
    
    // Alias for backward compatibility
    var imageURLs: [String] {
        if let profileImageURL = self.profileImageURL {
            return [profileImageURL]
        }
        return []
    }
    
    // Validation
    var isValid: Bool {
        !email.isEmpty &&
        email.contains("@") &&
        email.count <= 255 &&
        !name.isEmpty &&
        name.count <= 100 &&
        bio.count <= 500 &&
        (username?.count ?? 0) <= 30
    }
    
    var validationErrors: [String] {
        var errors: [String] = []
        if email.isEmpty { errors.append("Email is required") }
        if !email.contains("@") { errors.append("Invalid email format") }
        if email.count > 255 { errors.append("Email too long") }
        if name.isEmpty { errors.append("Name is required") }
        if name.count > 100 { errors.append("Name too long (max 100 characters)") }
        if bio.count > 500 { errors.append("Bio too long (max 500 characters)") }
        if let username = username, username.count > 30 {
            errors.append("Username too long (max 30 characters)")
        }
        return errors
    }
    
    // Cacheable
    var cacheKey: String { "user_\(id ?? UUID().uuidString)" }
    var cacheExpiry: TimeInterval { 300 } // 5 minutes
    var needsRefresh: Bool {
        Date().timeIntervalSince(updatedAt) > cacheExpiry
    }
}

// MARK: - Supporting User Types
enum VerificationStatus: String, Codable {
    case unverified
    case pending
    case verified
    case rejected
}

enum AvailabilityStatus: String, Codable {
    case available
    case busy
    case away
    case offline
}

struct UserBadge: Codable {
    let type: BadgeType
    let earnedAt: Date
    
    enum BadgeType: String, Codable {
        case topRated
        case superProvider
        case verified
        case responsive
        case experienced
    }
}

struct SocialLinks: Codable {
    var website: String?
    var instagram: String?
    var linkedin: String?
    var twitter: String?
    
    var isValid: Bool {
        let urlPattern = #"^(https?://)?([\da-z\.-]+)\.([a-z\.]{2,6})([/\w \.-]*)*/?$"#
        let predicate = NSPredicate(format: "SELF MATCHES %@", urlPattern)
        
        return [website, instagram, linkedin, twitter].compactMap { $0 }.allSatisfy {
            predicate.evaluate(with: $0)
        }
    }
}

// MARK: - Notification Settings
struct NotificationSettings: Codable {
    var pushEnabled: Bool = true
    var emailEnabled: Bool = true
    var newMessages: Bool = true
    var newReviews: Bool = true
    var reviewReplies: Bool = true
    var newFollowers: Bool = true
    var serviceUpdates: Bool = true
    var marketing: Bool = false
    var soundEnabled: Bool = true
    var vibrationEnabled: Bool = true
}

// MARK: - Privacy Settings
struct PrivacySettings: Codable {
    var profileVisibility: ProfileVisibility = .public
    var showEmail: Bool = false
    var showPhone: Bool = false
    var showLocation: Bool = true
    var allowMessages: MessagePermission = .everyone
    var showActiveStatus: Bool = true
    
    enum ProfileVisibility: String, Codable {
        case `public`
        case followersOnly
        case `private`
    }
    
    enum MessagePermission: String, Codable {
        case everyone
        case followersOnly
        case noOne
    }
}

// MARK: - Service Post Model
struct ServicePost: Codable, Identifiable, Validatable, Cacheable {
    @DocumentID var id: String?
    let userId: String
    var title: String
    var description: String
    var category: ServiceCategory
    var tags: [String] = []
    var price: Double?
    var priceType: PriceType = .fixed
    var currency: String = "USD"
    var location: String?
    var coordinates: GeoPoint?
    var isRemote: Bool = false
    var mediaURLs: [String] = []
    var thumbnailURL: String?
    var videoURL: String?
    var availability: ServiceAvailability = ServiceAvailability()
    var requirements: [String] = []
    var deliverables: [String] = []
    var estimatedDuration: String?
    var isActive: Bool = true
    var isFeatured: Bool = false
    var status: PostStatus = .active
    var viewCount: Int = 0
    var likeCount: Int = 0
    var savedCount: Int = 0
    var shareCount: Int = 0
    var commentCount: Int = 0
    var reportCount: Int = 0
    var isRequest: Bool = false
    var urgency: UrgencyLevel?
    var budget: BudgetRange?
    let createdAt: Date = Date()
    var updatedAt: Date = Date()
    var expiresAt: Date?
    var completedAt: Date?
    var boostedUntil: Date?
    
    // SEO and Discovery
    var searchKeywords: [String] = []
    var impressions: Int = 0
    var clickThroughRate: Double = 0.0
    
    enum PostStatus: String, Codable {
        case draft
        case active
        case pending
        case completed
        case cancelled
        case expired
        case reported
    }
    
    // Validation
    var isValid: Bool {
        !title.isEmpty &&
        title.count <= 100 &&
        !description.isEmpty &&
        description.count <= 1000 &&
        (price ?? 0) >= 0 &&
        (price ?? 0) <= 1000000 &&
        tags.count <= 10 &&
        mediaURLs.count <= 10
    }
    
    var validationErrors: [String] {
        var errors: [String] = []
        if title.isEmpty { errors.append("Title is required") }
        if title.count > 100 { errors.append("Title too long (max 100 characters)") }
        if description.isEmpty { errors.append("Description is required") }
        if description.count > 1000 { errors.append("Description too long (max 1000 characters)") }
        if let price = price {
            if price < 0 { errors.append("Price cannot be negative") }
            if price > 1000000 { errors.append("Price too high (max 1,000,000)") }
        }
        if tags.count > 10 { errors.append("Too many tags (max 10)") }
        if mediaURLs.count > 10 { errors.append("Too many images (max 10)") }
        return errors
    }
    
    // Cacheable
    var cacheKey: String { "post_\(id ?? UUID().uuidString)" }
    var cacheExpiry: TimeInterval { 300 } // 5 minutes
    var needsRefresh: Bool {
        Date().timeIntervalSince(updatedAt) > cacheExpiry
    }
}

// MARK: - Service Supporting Types
enum ServiceCategory: String, Codable, CaseIterable {
    case cleaning
    case plumbing
    case electrical
    case painting
    case landscaping
    case moving
    case handyman
    case tutoring
    case personalTraining
    case photography
    case videography
    case webDesign
    case graphicDesign
    case writing
    case translation
    case petCare
    case childCare
    case delivery
    case assembly
    case other
    
    var icon: String {
        switch self {
        case .cleaning: return "sparkles"
        case .plumbing: return "wrench.and.screwdriver"
        case .electrical: return "bolt.fill"
        case .painting: return "paintbrush.fill"
        case .landscaping: return "leaf.fill"
        case .moving: return "truck.box.fill"
        case .handyman: return "hammer.fill"
        case .tutoring: return "book.fill"
        case .personalTraining: return "figure.run"
        case .photography: return "camera.fill"
        case .videography: return "video.fill"
        case .webDesign: return "globe"
        case .graphicDesign: return "paintpalette.fill"
        case .writing: return "pencil"
        case .translation: return "character.book.closed.fill"
        case .petCare: return "pawprint.fill"
        case .childCare: return "figure.and.child.holdinghands"
        case .delivery: return "bicycle"
        case .assembly: return "screwdriver.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
    
    var displayName: String {
        switch self {
        case .cleaning: return "Cleaning"
        case .plumbing: return "Plumbing"
        case .electrical: return "Electrical"
        case .painting: return "Painting"
        case .landscaping: return "Landscaping"
        case .moving: return "Moving"
        case .handyman: return "Handyman"
        case .tutoring: return "Tutoring"
        case .personalTraining: return "Personal Training"
        case .photography: return "Photography"
        case .videography: return "Videography"
        case .webDesign: return "Web Design"
        case .graphicDesign: return "Graphic Design"
        case .writing: return "Writing"
        case .translation: return "Translation"
        case .petCare: return "Pet Care"
        case .childCare: return "Child Care"
        case .delivery: return "Delivery"
        case .assembly: return "Assembly"
        case .other: return "Other"
        }
    }
}

enum PriceType: String, Codable {
    case fixed
    case hourly
    case daily
    case negotiable
    case free
}

enum UrgencyLevel: String, Codable {
    case low
    case medium
    case high
    case urgent
}

struct BudgetRange: Codable {
    let min: Double
    let max: Double
    
    var isValid: Bool {
        min >= 0 && max >= min && max <= 1000000
    }
}

struct ServiceAvailability: Codable {
    var monday: Bool = true
    var tuesday: Bool = true
    var wednesday: Bool = true
    var thursday: Bool = true
    var friday: Bool = true
    var saturday: Bool = true
    var sunday: Bool = false
    var startTime: String = "09:00"
    var endTime: String = "17:00"
}

// MARK: - Portfolio Card Model
struct PortfolioCard: Codable, Identifiable, Validatable, Cacheable {
    @DocumentID var id: String?
    let userId: String
    var title: String
    var description: String?
    var coverImageURL: String?
    var thumbnailURL: String?
    var mediaURLs: [String] = []
    var mediaType: MediaType = .image
    var tags: [String] = []
    var category: ServiceCategory?
    var projectDate: Date?
    var client: String?
    var testimonial: String?
    var likes: Int = 0
    var views: Int = 0
    var displayOrder: Int = 0
    var isHighlighted: Bool = false
    let createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    enum MediaType: String, Codable {
        case image
        case video
        case mixed
    }
    
    // Validation
    var isValid: Bool {
        !title.isEmpty &&
        title.count <= 100 &&
        (description?.count ?? 0) <= 500 &&
        mediaURLs.count <= 20 &&
        tags.count <= 10
    }
    
    var validationErrors: [String] {
        var errors: [String] = []
        if title.isEmpty { errors.append("Title is required") }
        if title.count > 100 { errors.append("Title too long (max 100 characters)") }
        if let desc = description, desc.count > 500 {
            errors.append("Description too long (max 500 characters)")
        }
        if mediaURLs.count > 20 { errors.append("Too many media items (max 20)") }
        if tags.count > 10 { errors.append("Too many tags (max 10)") }
        return errors
    }
    
    // Cacheable
    var cacheKey: String { "portfolio_\(id ?? UUID().uuidString)" }
    var cacheExpiry: TimeInterval { 600 } // 10 minutes
    var needsRefresh: Bool {
        Date().timeIntervalSince(updatedAt) > cacheExpiry
    }
}

// MARK: - Review Model
struct Review: Codable, Identifiable, Validatable, Cacheable {
    @DocumentID var id: String?
    let reviewerId: String
    let reviewedUserId: String
    var reviewerName: String?
    var reviewerProfileImage: String?
    var rating: Int
    var title: String?
    var text: String
    var mediaURLs: [String] = []
    var reply: ReviewReply?
    var helpfulVotes: [String] = []
    var unhelpfulVotes: [String] = []
    var verifiedPurchase: Bool = false
    var servicePostId: String?
    var transactionId: String?
    var aspects: ReviewAspects?
    var reviewNumber: Int?
    var isEdited: Bool = false
    var editHistory: [EditRecord] = []
    var reportCount: Int = 0
    var isHidden: Bool = false
    var isFlagged: Bool = false
    let createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    struct ReviewAspects: Codable {
        var quality: Int?
        var communication: Int?
        var timeliness: Int?
        var value: Int?
        var professionalism: Int?
    }
    
    struct EditRecord: Codable {
        let editedAt: Date
        let previousText: String
        let reason: String?
    }
    
    // Validation
    var isValid: Bool {
        rating >= 1 &&
        rating <= 5 &&
        !text.isEmpty &&
        text.count <= 1000 &&
        (title?.count ?? 0) <= 100 &&
        mediaURLs.count <= 5
    }
    
    var validationErrors: [String] {
        var errors: [String] = []
        if rating < 1 || rating > 5 { errors.append("Rating must be between 1 and 5") }
        if text.isEmpty { errors.append("Review text is required") }
        if text.count > 1000 { errors.append("Review too long (max 1000 characters)") }
        if let title = title, title.count > 100 {
            errors.append("Title too long (max 100 characters)")
        }
        if mediaURLs.count > 5 { errors.append("Too many images (max 5)") }
        return errors
    }
    
    // Cacheable
    var cacheKey: String { "review_\(id ?? UUID().uuidString)" }
    var cacheExpiry: TimeInterval { 300 } // 5 minutes
    var needsRefresh: Bool {
        Date().timeIntervalSince(updatedAt) > cacheExpiry
    }
}

// MARK: - Review Reply Model
struct ReviewReply: Codable {
    let userId: String
    var userName: String?
    var text: String
    let repliedAt: Date = Date()
    var editedAt: Date?
    
    var isValid: Bool {
        !text.isEmpty && text.count <= 500
    }
}

// MARK: - Message/Chat Models
struct Conversation: Codable, Identifiable, Cacheable {
    @DocumentID var id: String?
    var participants: [String] = []
    var participantDetails: [String: ParticipantInfo] = [:]
    var lastMessage: Message?
    var unreadCounts: [String: Int] = [:]
    var isTyping: [String: Bool] = [:]
    var isPinned: [String: Bool] = [:]
    var isMuted: [String: Bool] = [:]
    var isArchived: [String: Bool] = [:]
    var blockedUsers: [String: [String]] = [:] // userId: [blockedUserIds]
    var servicePostId: String?
    var contextType: ContextType?
    var contextId: String?
    let createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    struct ParticipantInfo: Codable {
        let userId: String
        var name: String
        var profileImageURL: String?
        var isOnline: Bool = false
        var lastSeen: Date?
    }
    
    enum ContextType: String, Codable {
        case service
        case portfolio
        case general
    }
    
    // Helper method to check if conversation is blocked
    func isBlocked(by userId: String) -> Bool {
        // Check if any participant has blocked the user
        for (participantId, blockedList) in blockedUsers {
            if blockedList.contains(userId) {
                return true
            }
            if participantId == userId {
                // Check if this user has blocked any participants
                for participant in participants {
                    if blockedList.contains(participant) {
                        return true
                    }
                }
            }
        }
        return false
    }
    
    // Cacheable
    var cacheKey: String { "conversation_\(id ?? UUID().uuidString)" }
    var cacheExpiry: TimeInterval { 60 } // 1 minute for real-time updates
    var needsRefresh: Bool {
        Date().timeIntervalSince(updatedAt) > cacheExpiry
    }
}

struct Message: Codable, Identifiable, Validatable {
    @DocumentID var id: String?
    let conversationId: String
    let senderId: String
    var text: String
    var mediaURLs: [String] = []
    var mediaType: MessageMediaType?
    var contextType: MessageContextType?
    var contextId: String?
    var contextTitle: String?  // Added
    var contextImage: String?  // Added
    var replyTo: String? // Message ID being replied to
    var isEdited: Bool = false
    var editedAt: Date?
    var isDeleted: Bool = false
    var deletedAt: Date?
    var readBy: [String] = []
    var deliveredTo: [String] = []
    var reactions: [String: String] = [:] // userId: emoji
    let createdAt: Date = Date()
    
    enum MessageMediaType: String, Codable {
        case image
        case video
        case audio
        case document
    }
    
    enum MessageContextType: String, Codable {
        case service
        case portfolio
        case general
        case post    // Added
        case reel    // Added
        case status  // Added
    }
    
    // Validation
    var isValid: Bool {
        (!text.isEmpty || !mediaURLs.isEmpty) &&
        text.count <= 1000 &&
        mediaURLs.count <= 10
    }
    
    var validationErrors: [String] {
        var errors: [String] = []
        if text.isEmpty && mediaURLs.isEmpty {
            errors.append("Message must contain text or media")
        }
        if text.count > 1000 { errors.append("Message too long (max 1000 characters)") }
        if mediaURLs.count > 10 { errors.append("Too many attachments (max 10)") }
        return errors
    }
}


// MARK: - Status Model (for Stories/Status updates)
struct Status: Codable, Identifiable, Validatable, Cacheable {
    @DocumentID var id: String?
    let userId: String
    var userName: String?
    var userProfileImage: String?
    var text: String?
    var mediaURL: String?
    var mediaType: StatusMediaType = .text
    var backgroundColor: String?
    var textColor: String?
    var viewers: [String] = []
    var isViewed: Bool = false
    let createdAt: Date = Date()
    var expiresAt: Date = Date().addingTimeInterval(24 * 60 * 60) // 24 hours
    
    enum StatusMediaType: String, Codable {
        case text
        case image
        case video
    }
    
    var isExpired: Bool {
        Date() > expiresAt
    }
    
    // Validation
    var isValid: Bool {
        (text != nil || mediaURL != nil) &&
        (text?.count ?? 0) <= 500
    }
    
    var validationErrors: [String] {
        var errors: [String] = []
        if text == nil && mediaURL == nil {
            errors.append("Status must have text or media")
        }
        if let text = text, text.count > 500 {
            errors.append("Status text too long (max 500 characters)")
        }
        return errors
    }
    
    // Cacheable
    var cacheKey: String { "status_\(id ?? UUID().uuidString)" }
    var cacheExpiry: TimeInterval { 60 } // 1 minute
    var needsRefresh: Bool {
        Date().timeIntervalSince(createdAt) > cacheExpiry || isExpired
    }
}

// MARK: - Reel/Status Model
struct Reel: Codable, Identifiable, Validatable, Cacheable {
    @DocumentID var id: String?
    let userId: String
    var userName: String?
    var userProfileImage: String?
    var caption: String?
    var mediaURL: String
    var thumbnailURL: String?
    var mediaType: ReelMediaType = .video
    var duration: TimeInterval?
    var aspectRatio: Double = 9/16
    var tags: [String] = []
    var mentions: [String] = []
    var location: String?
    var soundTrack: String?
    var likes: [String] = []
    var views: Int = 0
    var shares: Int = 0
    var comments: Int = 0
    var saves: [String] = []
    var isPromoted: Bool = false
    var promotionExpiry: Date?
    var reportCount: Int = 0
    var isHidden: Bool = false
    let createdAt: Date = Date()
    var expiresAt: Date // 24 hours for stories, never for reels
    
    enum ReelMediaType: String, Codable {
        case image
        case video
    }
    
    // Alias for backward compatibility
    var videoURL: String {
        mediaURL
    }
    
    var isExpired: Bool {
        Date() > expiresAt
    }
    
    // Validation
    var isValid: Bool {
        !mediaURL.isEmpty &&
        (caption?.count ?? 0) <= 500 &&
        tags.count <= 30 &&
        mentions.count <= 20
    }
    
    var validationErrors: [String] {
        var errors: [String] = []
        if mediaURL.isEmpty { errors.append("Media is required") }
        if let caption = caption, caption.count > 500 {
            errors.append("Caption too long (max 500 characters)")
        }
        if tags.count > 30 { errors.append("Too many tags (max 30)") }
        if mentions.count > 20 { errors.append("Too many mentions (max 20)") }
        return errors
    }
    
    // Cacheable
    var cacheKey: String { "reel_\(id ?? UUID().uuidString)" }
    var cacheExpiry: TimeInterval { 60 } // 1 minute for real-time engagement
    var needsRefresh: Bool {
        Date().timeIntervalSince(createdAt) > cacheExpiry || isExpired
    }
}

// MARK: - Comment Model
struct Comment: Codable, Identifiable, Validatable {
    @DocumentID var id: String?
    let postId: String
    let postType: PostType
    let userId: String
    var userName: String?
    var userProfileImage: String?
    var text: String
    var mediaURL: String?
    var parentCommentId: String? // For nested comments
    var mentions: [String] = []
    var likes: [String] = []
    var replyCount: Int = 0
    var isEdited: Bool = false
    var editedAt: Date?
    var isDeleted: Bool = false
    var isPinned: Bool = false
    var reportCount: Int = 0
    let createdAt: Date = Date()
    
    // Standard initializer
    init(
        id: String? = nil,
        postId: String,
        postType: PostType,
        userId: String,
        userName: String? = nil,
        userProfileImage: String? = nil,
        text: String,
        mediaURL: String? = nil,
        parentCommentId: String? = nil,
        mentions: [String] = [],
        likes: [String] = [],
        replyCount: Int = 0,
        isEdited: Bool = false,
        editedAt: Date? = nil,
        isDeleted: Bool = false,
        isPinned: Bool = false,
        reportCount: Int = 0
    ) {
        self.id = id
        self.postId = postId
        self.postType = postType
        self.userId = userId
        self.userName = userName
        self.userProfileImage = userProfileImage
        self.text = text
        self.mediaURL = mediaURL
        self.parentCommentId = parentCommentId
        self.mentions = mentions
        self.likes = likes
        self.replyCount = replyCount
        self.isEdited = isEdited
        self.editedAt = editedAt
        self.isDeleted = isDeleted
        self.isPinned = isPinned
        self.reportCount = reportCount
    }
    
    // Convenience initializer for reel comments (for backward compatibility)
    init(
        id: String? = nil,
        reelId: String,
        userId: String,
        userName: String? = nil,
        userProfileImage: String? = nil,
        text: String,
        mediaURL: String? = nil,
        parentCommentId: String? = nil,
        mentions: [String] = [],
        likes: [String] = [],
        replyCount: Int = 0,
        isEdited: Bool = false,
        editedAt: Date? = nil,
        isDeleted: Bool = false,
        isPinned: Bool = false,
        reportCount: Int = 0
    ) {
        self.init(
            id: id,
            postId: reelId,
            postType: .reel,
            userId: userId,
            userName: userName,
            userProfileImage: userProfileImage,
            text: text,
            mediaURL: mediaURL,
            parentCommentId: parentCommentId,
            mentions: mentions,
            likes: likes,
            replyCount: replyCount,
            isEdited: isEdited,
            editedAt: editedAt,
            isDeleted: isDeleted,
            isPinned: isPinned,
            reportCount: reportCount
        )
    }
    
    // Alias for backward compatibility
    var timestamp: Date {
        createdAt
    }
    
    enum PostType: String, Codable {
        case service
        case reel
        case portfolio
    }
    
    // Validation
    var isValid: Bool {
        !text.isEmpty &&
        text.count <= 500 &&
        mentions.count <= 10
    }
    
    var validationErrors: [String] {
        var errors: [String] = []
        if text.isEmpty { errors.append("Comment cannot be empty") }
        if text.count > 500 { errors.append("Comment too long (max 500 characters)") }
        if mentions.count > 10 { errors.append("Too many mentions (max 10)") }
        return errors
    }
}

// MARK: - Notification Model
struct AppNotification: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String // Recipient
    let type: NotificationType
    let title: String
    let body: String
    var imageURL: String?
    let fromUserId: String?
    var fromUserName: String?
    var fromUserImage: String?
    let referenceId: String? // ID of related content
    var deepLink: String?
    var data: [String: String] = [:]
    var isRead: Bool = false
    var isSeen: Bool = false
    let createdAt: Date = Date()
    var expiresAt: Date?
    
    enum NotificationType: String, Codable {
        case newMessage
        case newReview
        case reviewReply
        case newFollower
        case serviceBooked
        case serviceCompleted
        case paymentReceived
        case newComment
        case commentReply
        case mention
        case like
        case systemUpdate
        case promotion
    }
}

// MARK: - Saved Item Model
struct SavedItem: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    let itemId: String
    let itemType: SavedItemType
    var title: String?
    var description: String?
    var imageURL: String?
    var collectionId: String?
    var tags: [String] = []
    var note: String?
    let createdAt: Date = Date()
    
    enum SavedItemType: String, Codable {
        case service
        case post // Alias for service
        case portfolio
        case reel
        case user
    }
}

// MARK: - Report Model
struct Report: Codable, Identifiable {
    @DocumentID var id: String?
    let reporterId: String
    let reportedItemId: String
    let reportedItemType: ReportItemType
    let reportedUserId: String?
    let reason: ReportReason
    var details: String?
    var evidence: [String] = [] // Screenshot URLs
    var status: ReportStatus = .pending
    var reviewedBy: String?
    var reviewedAt: Date?
    var resolution: String?
    let createdAt: Date = Date()
    
    enum ReportItemType: String, Codable {
        case user
        case service
        case review
        case comment
        case message
        case reel
    }
    
    enum ReportReason: String, Codable {
        case spam
        case inappropriate
        case harassment
        case violence
        case nudity
        case fake
        case copyright
        case other
    }
    
    enum ReportStatus: String, Codable {
        case pending
        case reviewing
        case resolved
        case dismissed
    }
}

// MARK: - Analytics Model
struct AnalyticsEvent: Codable {
    let userId: String?
    let eventType: EventType
    let eventName: String
    var parameters: [String: String] = [:]
    let deviceInfo: DeviceInfo?
    let sessionId: String
    let timestamp: Date = Date()
    
    enum EventType: String, Codable {
        case pageView
        case action
        case engagement
        case conversion
        case error
    }
    
    struct DeviceInfo: Codable {
        let platform: String // iOS/iPadOS
        let osVersion: String
        let deviceModel: String
        let appVersion: String
        let buildNumber: String
    }
}

// MARK: - Pagination Helper
struct PaginatedResult<T: Codable>: Codable {
    let items: [T]
    let totalCount: Int
    let hasMore: Bool
    let lastDocument: String? // Document ID for pagination
    let nextPage: Int?
}

// MARK: - Additional Missing Types

// Reel Like Model
struct ReelLike: Codable, Identifiable {
    @DocumentID var id: String?
    let reelId: String
    let userId: String
    var userName: String?
    var userProfileImage: String?
    let likedAt: Date = Date()
}

// Message Report Model
struct MessageReport: Codable, Identifiable {
    @DocumentID var id: String?
    let messageId: String
    let conversationId: String
    let reporterId: String
    let reportedUserId: String
    let reason: ReportReason
    var details: String?
    var status: ReportStatus = .pending
    let createdAt: Date = Date()
    
    enum ReportReason: String, Codable {
        case spam
        case inappropriate
        case harassment
        case violence
        case other
    }
    
    enum ReportStatus: String, Codable {
        case pending
        case reviewing
        case resolved
        case dismissed
    }
}

// Review Notification Model (extending AppNotification)
struct ReviewNotification: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String // Who receives the notification
    let reviewId: String
    let type: ReviewNotificationType
    let fromUserId: String
    let fromUserName: String
    var fromUserImage: String?
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

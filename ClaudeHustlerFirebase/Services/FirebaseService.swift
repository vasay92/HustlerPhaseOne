// FirebaseService.swift
// Path: ClaudeHustlerFirebase/Services/FirebaseService.swift

import Firebase
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UIKit

typealias AppUser = User  // Your custom User model
typealias AuthUser = FirebaseAuth.User  // Firebase Auth User

@MainActor
class FirebaseService: ObservableObject {
    static let shared = FirebaseService()
    let db = Firestore.firestore()
    let auth = Auth.auth()
    let storage = Storage.storage()
    
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var posts: [ServicePost] = []
    @Published var offers: [ServicePost] = []
    @Published var requests: [ServicePost] = []
    @Published var statuses: [Status] = []
    @Published var reels: [Reel] = []
    @Published var isLoading = false
    
    // Listener properties for cleanup
    private var conversationsListener: ListenerRegistration?
    private var messagesListener: ListenerRegistration?
    
    private init() {
        setupAuthListener()
    }
    
    private func setupAuthListener() {
        auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                print("Auth state changed - User UID: \(user?.uid ?? "nil")")
                self?.isAuthenticated = user != nil
                if let userId = user?.uid {
                    print("Loading user with ID: \(userId)")
                    await self?.loadUser(userId: userId)
                    print("After loadUser - currentUser ID: \(self?.currentUser?.id ?? "nil")")
                } else {
                    self?.currentUser = nil
                }
            }
        }
    }
    
    // MARK: - Authentication
    
    func signIn(email: String, password: String) async throws {
        try await auth.signIn(withEmail: email, password: password)
    }
    
    func signUp(email: String, password: String, name: String) async throws {
        let result = try await auth.createUser(withEmail: email, password: password)
        
        let userData: [String: Any] = [
            "email": email,
            "name": name,
            "bio": "",
            "isServiceProvider": false,
            "location": "",
            "rating": 0.0,
            "reviewCount": 0,
            "following": [],
            "followers": [],
            "createdAt": Date()
        ]
        
        try await db.collection("users").document(result.user.uid).setData(userData)
    }
    
    func cleanupOnSignOut() {
        // Remove all listeners
        conversationsListener?.remove()
        messagesListener?.remove()
        
        // Clear cached data
        currentUser = nil
        posts = []
        offers = []
        requests = []
        statuses = []
        reels = []
        
        // Clear any additional cached data
        isLoading = false
    }
    
    func signOut() throws {
        cleanupOnSignOut()
        try auth.signOut()
    }
    
    // MARK: - User Management
    
    private func loadUser(userId: String) async {
        print("loadUser called with userId: \(userId)")
        
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            print("Document exists: \(document.exists)")
            
            if document.exists {
                let data = document.data() ?? [:]
                print("Document data keys: \(data.keys)")
                
                do {
                    currentUser = try document.data(as: User.self)
                    print("Successfully decoded user: \(currentUser?.id ?? "nil")")
                } catch {
                    print("Failed to decode user: \(error)")
                    
                    currentUser = User(
                        id: userId,
                        email: data["email"] as? String ?? "",
                        name: data["name"] as? String ?? "User",
                        profileImageURL: data["profileImageURL"] as? String,
                        bio: data["bio"] as? String ?? "",
                        isServiceProvider: data["isServiceProvider"] as? Bool ?? false,
                        location: data["location"] as? String ?? "",
                        rating: data["rating"] as? Double ?? 0.0,
                        reviewCount: data["reviewCount"] as? Int ?? 0,
                        following: data["following"] as? [String] ?? [],
                        followers: data["followers"] as? [String] ?? []
                    )
                    print("Manually created user: \(currentUser?.id ?? "nil")")
                }
            }
        } catch {
            print("Error in loadUser: \(error)")
        }
    }
    
    // MARK: - Service Posts
    
    func loadPosts() async {
        do {
            let snapshot = try await db.collection("posts")
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            posts = snapshot.documents.compactMap { doc in
                if var post = try? doc.data(as: ServicePost.self) {
                    // IMPORTANT: Set the document ID
                    post.id = doc.documentID
                    return post
                }
                return nil
            }
        } catch {
            print("Error loading posts: \(error)")
        }
    }
    
    func loadOffers() async {
        do {
            let snapshot = try await db.collection("posts")
                .getDocuments()
            
            offers = snapshot.documents.compactMap { doc in
                if var post = try? doc.data(as: ServicePost.self),
                   !post.isRequest {
                    post.id = doc.documentID
                    return post
                }
                return nil
            }
            offers.sort { $0.createdAt > $1.createdAt }
            
            print("Loaded \(offers.count) offers")
        } catch {
            print("Error loading offers: \(error)")
        }
    }
    
    func loadRequests() async {
        do {
            let snapshot = try await db.collection("posts")
                .getDocuments()
            
            requests = snapshot.documents.compactMap { doc in
                if var post = try? doc.data(as: ServicePost.self),
                   post.isRequest {
                    post.id = doc.documentID
                    return post
                }
                return nil
            }
            requests.sort { $0.createdAt > $1.createdAt }
            
            print("Loaded \(requests.count) requests")
        } catch {
            print("Error loading requests: \(error)")
        }
    }
    
    func loadAllServicePosts() async {
        isLoading = true
        
        async let postsTask: () = loadPosts()
        async let offersTask: () = loadOffers()
        async let requestsTask: () = loadRequests()
        
        await postsTask
        await offersTask
        await requestsTask
        
        isLoading = false
        
        print("All posts loaded - Total: \(posts.count), Offers: \(offers.count), Requests: \(requests.count)")
    }
    
    func createServicePost(
        title: String,
        description: String,
        category: ServiceCategory,
        price: Double? = nil,
        isRequest: Bool = false,
        location: String? = nil,
        isUrgent: Bool = false,
        imageURLs: [String] = []
    ) async throws -> String {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        var postData: [String: Any] = [
            "userId": userId,
            "userName": currentUser?.name ?? "Unknown",
            "userProfileImage": currentUser?.profileImageURL ?? "",
            "title": title,
            "description": description,
            "category": category.rawValue,
            "isRequest": isRequest,
            "status": ServicePost.PostStatus.active.rawValue,
            "createdAt": Date(),
            "updatedAt": Date(),
            "imageURLs": imageURLs
        ]
        
        if let price = price {
            postData["price"] = price
        }
        
        if let location = location, !location.isEmpty {
            postData["location"] = location
        }
        
        let docRef = try await db.collection("posts").addDocument(data: postData)
        
        await loadAllServicePosts()
        
        print("Created new post - Type: \(isRequest ? "Request" : "Offer"), ID: \(docRef.documentID)")
        return docRef.documentID
    }
    
    // MARK: - Status (Stories)
    
    func loadStatuses() async {
        do {
            let snapshot = try await db.collection("statuses")
                .whereField("expiresAt", isGreaterThan: Date())
                .whereField("isActive", isEqualTo: true)
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            statuses = snapshot.documents.compactMap { doc in
                if var status = try? doc.data(as: Status.self) {
                    status.id = doc.documentID
                    return status
                }
                return nil
            }
        } catch {
            print("Error loading statuses: \(error)")
        }
    }
    
    func createStatus(image: UIImage, caption: String?) async throws -> String {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        let imageURL = try await uploadImage(image, path: "statuses/\(userId)/\(UUID().uuidString).jpg")
        
        let statusData: [String: Any] = [
            "userId": userId,
            "userName": currentUser?.name ?? "Unknown",
            "userProfileImage": currentUser?.profileImageURL ?? "",
            "mediaURL": imageURL,
            "caption": caption ?? "",
            "mediaType": "image",
            "createdAt": Date(),
            "expiresAt": Date().addingTimeInterval(24 * 60 * 60),
            "viewedBy": [],
            "isActive": true
        ]
        
        let docRef = try await db.collection("statuses").addDocument(data: statusData)
        await loadStatuses()
        print("Created status with ID: \(docRef.documentID)")
        return docRef.documentID
    }
    
    // MARK: - Reels
    
    func loadReels() async {
        do {
            let snapshot = try await db.collection("reels")
                .order(by: "createdAt", descending: true)
                .limit(to: 50)
                .getDocuments()
            
            reels = snapshot.documents.compactMap { doc in
                if var reel = try? doc.data(as: Reel.self) {
                    reel.id = doc.documentID
                    print("Loaded reel with ID: \(reel.id ?? "nil")")
                    return reel
                }
                return nil
            }
        } catch {
            print("Error loading reels: \(error)")
        }
    }
    
    func createReel(
        videoURL: String,
        thumbnailImage: UIImage?,
        title: String,
        description: String,
        category: ServiceCategory?,
        hashtags: [String] = []
    ) async throws -> String {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        var thumbnailURL = ""
        if let thumbnail = thumbnailImage {
            thumbnailURL = try await uploadImage(thumbnail, path: "reels/\(userId)/thumbnails/\(UUID().uuidString).jpg")
        }
        
        let reelData: [String: Any] = [
            "userId": userId,
            "userName": currentUser?.name ?? "Unknown",
            "userProfileImage": currentUser?.profileImageURL ?? "",
            "videoURL": videoURL,
            "thumbnailURL": thumbnailURL,
            "title": title,
            "description": description,
            "category": category?.rawValue ?? "",
            "hashtags": hashtags,
            "createdAt": Date(),
            "likes": [],
            "comments": 0,
            "shares": 0,
            "views": 0,
            "isPromoted": false
        ]
        
        let docRef = try await db.collection("reels").addDocument(data: reelData)
        await loadReels()
        return docRef.documentID
    }
    
    func createImageReel(
        image: UIImage,
        title: String,
        description: String,
        category: ServiceCategory? = nil
    ) async throws -> String {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        let imageURL = try await uploadImage(image, path: "reels/\(userId)/\(UUID().uuidString).jpg")
        
        var reelData: [String: Any] = [
            "userId": userId,
            "userName": currentUser?.name ?? "Unknown",
            "userProfileImage": currentUser?.profileImageURL ?? "",
            "videoURL": imageURL,
            "thumbnailURL": imageURL,
            "title": title,
            "description": description,
            "hashtags": [],
            "createdAt": Date(),
            "likes": [],
            "comments": 0,
            "shares": 0,
            "views": 0,
            "isPromoted": false
        ]
        
        if let category = category {
            reelData["category"] = category.rawValue
        }
        
        let docRef = try await db.collection("reels").addDocument(data: reelData)
        await loadReels()
        print("Created reel with ID: \(docRef.documentID)")
        return docRef.documentID
    }
    
//    // MARK: - Reel Interactions
//    
//    func likeReel(_ reelId: String) async {
//        guard let userId = currentUser?.id else { return }
//        
//        do {
//            let reelRef = db.collection("reels").document(reelId)
//            try await reelRef.updateData([
//                "likes": FieldValue.arrayUnion([userId])
//            ])
//        } catch {
//            print("Error liking reel: \(error)")
//        }
//    }
//    
//    func unlikeReel(_ reelId: String) async {
//        guard let userId = currentUser?.id else { return }
//        
//        do {
//            let reelRef = db.collection("reels").document(reelId)
//            try await reelRef.updateData([
//                "likes": FieldValue.arrayRemove([userId])
//            ])
//        } catch {
//            print("Error unliking reel: \(error)")
//        }
//    }
    
    // MARK: - Status Interactions
    
    func viewStatus(_ statusId: String) async {
        guard let userId = currentUser?.id else { return }
        
        do {
            let statusRef = db.collection("statuses").document(statusId)
            try await statusRef.updateData([
                "viewedBy": FieldValue.arrayUnion([userId])
            ])
        } catch {
            print("Error marking status as viewed: \(error)")
        }
    }
    
    // MARK: - Image Upload
    
    func uploadImage(_ image: UIImage, path: String) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw NSError(domain: "ImageError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to data"])
        }
        
        let storageRef = storage.reference().child(path)
        
        _ = try await storageRef.putDataAsync(imageData, metadata: nil)
        let downloadURL = try await storageRef.downloadURL()
        
        return downloadURL.absoluteString
    }
    
    // MARK: - Clean up expired statuses
    
    func cleanupExpiredStatuses() async {
        do {
            let expiredStatuses = try await db.collection("statuses")
                .whereField("expiresAt", isLessThan: Date())
                .getDocuments()
            
            for document in expiredStatuses.documents {
                try await document.reference.updateData(["isActive": false])
            }
        } catch {
            print("Error cleaning up expired statuses: \(error)")
        }
    }
    
    // MARK: - Following System
    
    func followUser(_ targetUserId: String) async throws {
        guard let currentUserId = currentUser?.id else { return }
        
        try await db.collection("users").document(currentUserId).updateData([
            "following": FieldValue.arrayUnion([targetUserId])
        ])
        
        try await db.collection("users").document(targetUserId).updateData([
            "followers": FieldValue.arrayUnion([currentUserId])
        ])
        
        await loadUser(userId: currentUserId)
        await loadStatusesFromFollowing()
    }

    func unfollowUser(_ targetUserId: String) async throws {
        guard let currentUserId = currentUser?.id else { return }
        
        try await db.collection("users").document(currentUserId).updateData([
            "following": FieldValue.arrayRemove([targetUserId])
        ])
        
        try await db.collection("users").document(targetUserId).updateData([
            "followers": FieldValue.arrayRemove([currentUserId])
        ])
        
        await loadUser(userId: currentUserId)
        await loadStatusesFromFollowing()
    }
    
    func loadStatusesFromFollowing() async {
        guard let currentUser = currentUser else {
            print("No current user, can't load statuses")
            statuses = []
            return
        }
        
        do {
            var userIds = currentUser.following
            if let myId = currentUser.id {
                userIds.append(myId)
            }
            
            if userIds.isEmpty {
                print("Not following anyone, no statuses to show")
                statuses = []
                return
            }
            
            print("Loading statuses from users: \(userIds)")
            
            let snapshot = try await db.collection("statuses")
                .whereField("userId", in: userIds)
                .whereField("isActive", isEqualTo: true)
                .getDocuments()
            
            statuses = snapshot.documents.compactMap { doc in
                if var status = try? doc.data(as: Status.self),
                   status.expiresAt > Date() {
                    // IMPORTANT: Set the document ID
                    status.id = doc.documentID
                    print("Loaded status with ID: \(status.id ?? "nil")")
                    return status
                }
                return nil
            }
            
            print("Loaded \(statuses.count) statuses from following")
        } catch {
            print("Error loading statuses from following: \(error)")
            statuses = []
        }
    }
}

// MARK: - Profile Updates Extension
extension FirebaseService {
    
    func refreshCurrentUser() async {
        guard let userId = currentUser?.id else { return }
        await loadUser(userId: userId)
    }
    
    func updateUserProfile(name: String? = nil, bio: String? = nil, location: String? = nil) async throws {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        var updates: [String: Any] = [:]
        if let name = name { updates["name"] = name }
        if let bio = bio { updates["bio"] = bio }
        if let location = location { updates["location"] = location }
        
        if !updates.isEmpty {
            try await db.collection("users").document(userId).updateData(updates)
            await loadUser(userId: userId)
        }
    }
    
    func isFollowing(userId: String) -> Bool {
        return currentUser?.following.contains(userId) ?? false
    }
    
    func getFollowerCount(for userId: String) async -> Int {
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            if let user = try? document.data(as: User.self) {
                return user.followers.count
            }
        } catch {
            print("Error getting follower count: \(error)")
        }
        return 0
    }
    
    func getFollowingCount(for userId: String) async -> Int {
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            if let user = try? document.data(as: User.self) {
                return user.following.count
            }
        } catch {
            print("Error getting following count: \(error)")
        }
        return 0
    }
    
    func updateLastActive() async {
        guard let userId = currentUser?.id else { return }
        
        do {
            try await db.collection("users").document(userId).updateData([
                "lastActive": Date()
            ])
        } catch {
            print("Error updating last active: \(error)")
        }
    }
}

// MARK: - Portfolio Management Extension
extension FirebaseService {
    
    func loadPortfolioCards(for userId: String) async -> [PortfolioCard] {
        do {
            let snapshot = try await db.collection("portfolioCards")
                .whereField("userId", isEqualTo: userId)
                .order(by: "displayOrder")
                .getDocuments()
            
            return snapshot.documents.compactMap { doc in
                if var card = try? doc.data(as: PortfolioCard.self) {
                    card.id = doc.documentID
                    return card
                }
                return nil
            }
        } catch {
            print("Error loading portfolio cards: \(error)")
            return []
        }
    }
    
    func createPortfolioCard(title: String, coverImage: UIImage?, mediaImages: [UIImage], description: String?) async throws {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        var mediaURLs: [String] = []
        for (index, image) in mediaImages.enumerated() {
            let path = "portfolio/\(userId)/\(UUID().uuidString)_\(index).jpg"
            let url = try await uploadImage(image, path: path)
            mediaURLs.append(url)
        }
        
        var coverURL: String?
        if let cover = coverImage {
            let path = "portfolio/\(userId)/covers/\(UUID().uuidString).jpg"
            coverURL = try await uploadImage(cover, path: path)
        } else if !mediaURLs.isEmpty {
            coverURL = mediaURLs.first
        }
        
        let existingCards = await loadPortfolioCards(for: userId)
        
        let cardData: [String: Any] = [
            "userId": userId,
            "title": title,
            "coverImageURL": coverURL ?? "",
            "mediaURLs": mediaURLs,
            "description": description ?? "",
            "createdAt": Date(),
            "updatedAt": Date(),
            "displayOrder": existingCards.count
        ]
        
        try await db.collection("portfolioCards").addDocument(data: cardData)
    }
    
    func updatePortfolioCard(_ cardId: String, title: String? = nil, description: String? = nil) async throws {
        guard currentUser?.id != nil else { return }
        
        var updates: [String: Any] = ["updatedAt": Date()]
        if let title = title { updates["title"] = title }
        if let description = description { updates["description"] = description }
        
        try await db.collection("portfolioCards").document(cardId).updateData(updates)
    }
    
    func deletePortfolioCard(_ cardId: String) async throws {
        guard let userId = currentUser?.id else { return }
        
        let card = try await db.collection("portfolioCards").document(cardId).getDocument()
        guard let data = card.data(), data["userId"] as? String == userId else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized"])
        }
        
        try await db.collection("portfolioCards").document(cardId).delete()
    }
}

// MARK: - Enhanced Reviews Extension with Real-time Updates
extension FirebaseService {
    
    // Listener property for reviews
    private static var reviewsListeners: [String: ListenerRegistration] = [:]
    
    // MARK: - Real-time Review Listening
    
    func listenToReviews(for userId: String, completion: @escaping ([Review]) -> Void) -> ListenerRegistration {
        // Remove any existing listener for this user
        if let existingListener = Self.reviewsListeners[userId] {
            existingListener.remove()
        }
        
        let listener = db.collection("reviews")
            .whereField("reviewedUserId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to reviews: \(error)")
                    return
                }
                
                // Explicitly type the reviews array
                let reviews: [Review] = snapshot?.documents.compactMap { doc in
                    var review = try? doc.data(as: Review.self)
                    review?.id = doc.documentID
                    return review
                } ?? []
                
                completion(reviews)
            }
        
        Self.reviewsListeners[userId] = listener
        return listener
    }
    
    func stopListeningToReviews(for userId: String) {
        Self.reviewsListeners[userId]?.remove()
        Self.reviewsListeners.removeValue(forKey: userId)
    }
    
    // MARK: - Load Reviews (One-time fetch)
    
    // MARK: - Load Reviews (One-time fetch)

    func loadReviews(for userId: String) async -> [Review] {
        do {
            let snapshot = try await db.collection("reviews")
                .whereField("reviewedUserId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            let reviews = snapshot.documents.compactMap { doc in
                if var review = try? doc.data(as: Review.self) {
                    review.id = doc.documentID
                    return review
                }
                return nil
            }
            
            return reviews
        } catch {
            print("Error loading reviews: \(error)")
            return []
        }
    }
    
    // MARK: - Create Review with Optimistic Update
    
    func createReview(for userId: String, rating: Int, text: String, images: [UIImage] = []) async throws -> Review {
        guard let reviewerId = currentUser?.id else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Prevent self-reviews
        if reviewerId == userId {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "You cannot review yourself"])
        }
        
        // Upload review images
        var mediaURLs: [String] = []
        for (index, image) in images.enumerated() {
            let path = "reviews/\(reviewerId)/\(UUID().uuidString)_\(index).jpg"
            let url = try await uploadImage(image, path: path)
            mediaURLs.append(url)
        }
        
        // Get review count for this reviewer to this user
        let existingReviews = try await db.collection("reviews")
            .whereField("reviewerId", isEqualTo: reviewerId)
            .whereField("reviewedUserId", isEqualTo: userId)
            .getDocuments()
        
        let reviewNumber = existingReviews.documents.count + 1
        
        let reviewData: [String: Any] = [
            "reviewerId": reviewerId,
            "reviewedUserId": userId,
            "reviewerName": currentUser?.name ?? "User",
            "reviewerProfileImage": currentUser?.profileImageURL ?? "",
            "rating": rating,
            "text": text,
            "mediaURLs": mediaURLs,
            "helpfulVotes": [],
            "createdAt": Date(),
            "updatedAt": Date(),
            "isEdited": false,
            "reviewNumber": reviewNumber
        ]
        
        let docRef = try await db.collection("reviews").addDocument(data: reviewData)
        
        // Create review object for return
        var newReview = Review(
            id: docRef.documentID,
            reviewerId: reviewerId,
            reviewedUserId: userId,
            reviewerName: currentUser?.name,
            reviewerProfileImage: currentUser?.profileImageURL,
            rating: rating,
            text: text,
            mediaURLs: mediaURLs,
            reviewNumber: reviewNumber
        )
        
        // Update user rating
        await updateUserRating(userId: userId)
        
        // Create notification
        await createReviewNotification(
            for: userId,
            reviewId: docRef.documentID,
            type: .newReview,
            fromUserId: reviewerId,
            fromUserName: currentUser?.name ?? "Someone"
        )
        
        return newReview
    }
    
    // MARK: - Update Review with Optimistic Update
    
    func updateReview(_ reviewId: String, rating: Int? = nil, text: String? = nil) async throws -> Review? {
        guard let userId = currentUser?.id else { return nil }
        
        let review = try await db.collection("reviews").document(reviewId).getDocument()
        guard let data = review.data(), data["reviewerId"] as? String == userId else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized"])
        }
        
        var updates: [String: Any] = [
            "updatedAt": Date(),
            "isEdited": true
        ]
        if let rating = rating { updates["rating"] = rating }
        if let text = text { updates["text"] = text }
        
        try await db.collection("reviews").document(reviewId).updateData(updates)
        
        // Get updated review
        let updatedDoc = try await db.collection("reviews").document(reviewId).getDocument()
        var updatedReview = try? updatedDoc.data(as: Review.self)
        updatedReview?.id = updatedDoc.documentID
        
        // Update user rating if rating changed
        if rating != nil, let reviewedUserId = data["reviewedUserId"] as? String {
            await updateUserRating(userId: reviewedUserId)
            
            // Create notification for review edit
            await createReviewNotification(
                for: reviewedUserId,
                reviewId: reviewId,
                type: .reviewEdit,
                fromUserId: userId,
                fromUserName: currentUser?.name ?? "Someone"
            )
        }
        
        return updatedReview
    }
    
    // MARK: - Reply to Review
    
    func replyToReview(_ reviewId: String, replyText: String) async throws {
        guard let userId = currentUser?.id else { return }
        
        let review = try await db.collection("reviews").document(reviewId).getDocument()
        guard let data = review.data(),
              data["reviewedUserId"] as? String == userId,
              let reviewerId = data["reviewerId"] as? String else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "You can only reply to reviews about you"])
        }
        
        let reply: [String: Any] = [
            "userId": userId,
            "text": replyText,
            "repliedAt": Date()
        ]
        
        try await db.collection("reviews").document(reviewId).updateData([
            "reply": reply,
            "updatedAt": Date()
        ])
        
        // Create notification for reply
        await createReviewNotification(
            for: reviewerId,
            reviewId: reviewId,
            type: .reviewReply,
            fromUserId: userId,
            fromUserName: currentUser?.name ?? "Business Owner"
        )
    }
    
    // MARK: - Toggle Helpful Vote with Return Value
    
    func toggleHelpfulVote(for reviewId: String) async throws -> (isVoted: Bool, count: Int) {
        guard let userId = currentUser?.id else { return (false, 0) }
        
        let reviewRef = db.collection("reviews").document(reviewId)
        let review = try await reviewRef.getDocument()
        
        guard let data = review.data() else { return (false, 0) }
        
        var helpfulVotes = data["helpfulVotes"] as? [String] ?? []
        let wasVoted = helpfulVotes.contains(userId)
        
        if wasVoted {
            helpfulVotes.removeAll { $0 == userId }
        } else {
            helpfulVotes.append(userId)
            
            // Create notification for helpful vote (only on adding, not removing)
            if let reviewedUserId = data["reviewerId"] as? String {
                await createReviewNotification(
                    for: reviewedUserId,
                    reviewId: reviewId,
                    type: .helpfulVote,
                    fromUserId: userId,
                    fromUserName: currentUser?.name ?? "Someone"
                )
            }
        }
        
        try await reviewRef.updateData([
            "helpfulVotes": helpfulVotes
        ])
        
        return (!wasVoted, helpfulVotes.count)
    }
    
    // MARK: - Delete Review
    
    func deleteReview(_ reviewId: String) async throws {
        guard let userId = currentUser?.id else { return }
        
        let review = try await db.collection("reviews").document(reviewId).getDocument()
        guard let data = review.data() else { return }
        
        // Only allow deleting own reviews
        guard data["reviewerId"] as? String == userId else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized"])
        }
        
        let reviewedUserId = data["reviewedUserId"] as? String ?? ""
        
        try await db.collection("reviews").document(reviewId).delete()
        
        // Update user rating after deletion
        if !reviewedUserId.isEmpty {
            await updateUserRating(userId: reviewedUserId)
        }
    }
    
    // MARK: - Update User Rating with Breakdown
    
    // MARK: - Update User Rating with Breakdown

    private func updateUserRating(userId: String) async {
        // Load reviews for this user
        let reviews = await loadReviews(for: userId)
        
        guard !reviews.isEmpty else {
            // If no reviews, reset rating to 0
            do {
                try await db.collection("users").document(userId).updateData([
                    "rating": 0.0,
                    "reviewCount": 0,
                    "ratingBreakdown": [:] as [String: Int],
                    "lastRatingUpdate": Date()
                ])
            } catch {
                print("Error resetting user rating: \(error)")
            }
            return
        }
        
        // Calculate rating breakdown
        var ratingBreakdown: [String: Int] = [:]
        for rating in 1...5 {
            let count = reviews.filter { $0.rating == rating }.count
            if count > 0 {
                ratingBreakdown[String(rating)] = count
            }
        }
        
        let totalRating = reviews.reduce(0) { $0 + $1.rating }
        let averageRating = Double(totalRating) / Double(reviews.count)
        
        do {
            try await db.collection("users").document(userId).updateData([
                "rating": averageRating,
                "reviewCount": reviews.count,
                "ratingBreakdown": ratingBreakdown,
                "lastRatingUpdate": Date()
            ])
            
            print("Updated user rating: \(averageRating) from \(reviews.count) reviews")
        } catch {
            print("Error updating user rating: \(error)")
        }
    }
    
    // MARK: - Review Notifications
    
    private func createReviewNotification(
        for userId: String,
        reviewId: String,
        type: ReviewNotification.ReviewNotificationType,
        fromUserId: String,
        fromUserName: String
    ) async {
        // Don't send notification to self
        if userId == fromUserId { return }
        
        let message: String
        switch type {
        case .newReview:
            message = "\(fromUserName) left you a review"
        case .reviewReply:
            message = "\(fromUserName) replied to your review"
        case .reviewEdit:
            message = "\(fromUserName) edited their review"
        case .helpfulVote:
            message = "\(fromUserName) found your review helpful"
        }
        
        let notificationData: [String: Any] = [
            "userId": userId,
            "reviewId": reviewId,
            "type": type.rawValue,
            "fromUserId": fromUserId,
            "fromUserName": fromUserName,
            "message": message,
            "isRead": false,
            "createdAt": Date()
        ]
        
        do {
            try await db.collection("reviewNotifications").addDocument(data: notificationData)
            print("Created review notification: \(message)")
        } catch {
            print("Error creating review notification: \(error)")
        }
    }
    
    // MARK: - Load Review Notifications
    
    func loadReviewNotifications() async -> [ReviewNotification] {
        guard let userId = currentUser?.id else { return [] }
        
        do {
            let snapshot = try await db.collection("reviewNotifications")
                .whereField("userId", isEqualTo: userId)
                .whereField("isRead", isEqualTo: false)
                .order(by: "createdAt", descending: true)
                .limit(to: 20)
                .getDocuments()
            
            return snapshot.documents.compactMap { doc in
                var notification = try? doc.data(as: ReviewNotification.self)
                notification?.id = doc.documentID
                return notification
            }
        } catch {
            print("Error loading review notifications: \(error)")
            return []
        }
    }
    
    // MARK: - Mark Notification as Read
    
    func markReviewNotificationAsRead(_ notificationId: String) async {
        do {
            try await db.collection("reviewNotifications").document(notificationId).updateData([
                "isRead": true
            ])
        } catch {
            print("Error marking notification as read: \(error)")
        }
    }
    
    // MARK: - Get Review Stats
    
    // MARK: - Get Review Stats

    func getReviewStats(for userId: String) async -> (average: Double, count: Int, breakdown: [Int: Int]) {
        let reviews = await loadReviews(for: userId)
        
        guard !reviews.isEmpty else {
            return (0.0, 0, [:])
        }
        
        var breakdown: [Int: Int] = [:]
        for rating in 1...5 {
            let count = reviews.filter { $0.rating == rating }.count
            if count > 0 {
                breakdown[rating] = count
            }
        }
        
        let totalRating = reviews.reduce(0) { $0 + $1.rating }
        let average = Double(totalRating) / Double(reviews.count)
        
        return (average, reviews.count, breakdown)
    }
}

// MARK: - Saved Items Extension
extension FirebaseService {
    
    func isItemSaved(itemId: String, type: SavedItem.SavedItemType) async -> Bool {
        guard let userId = currentUser?.id else { return false }
        
        do {
            let snapshot = try await db.collection("savedItems")
                .whereField("userId", isEqualTo: userId)
                .whereField("itemId", isEqualTo: itemId)
                .whereField("itemType", isEqualTo: type.rawValue)
                .getDocuments()
            
            return !snapshot.documents.isEmpty
        } catch {
            print("Error checking saved status: \(error)")
            return false
        }
    }
    
    func saveItem(itemId: String, type: SavedItem.SavedItemType) async throws {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        let alreadySaved = await isItemSaved(itemId: itemId, type: type)
        if alreadySaved {
            print("Item already saved")
            return
        }
        
        let savedData: [String: Any] = [
            "userId": userId,
            "itemId": itemId,
            "itemType": type.rawValue,
            "savedAt": Date()
        ]
        
        try await db.collection("savedItems").addDocument(data: savedData)
        print("Item saved successfully")
    }
    
    func unsaveItem(itemId: String, type: SavedItem.SavedItemType) async throws {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        let snapshot = try await db.collection("savedItems")
            .whereField("userId", isEqualTo: userId)
            .whereField("itemId", isEqualTo: itemId)
            .whereField("itemType", isEqualTo: type.rawValue)
            .getDocuments()
        
        for document in snapshot.documents {
            try await document.reference.delete()
        }
        print("Item unsaved successfully")
    }
    
    func loadSavedReels() async -> [Reel] {
        guard let userId = currentUser?.id else { return [] }
        
        do {
            let savedItems = try await db.collection("savedItems")
                .whereField("userId", isEqualTo: userId)
                .whereField("itemType", isEqualTo: SavedItem.SavedItemType.reel.rawValue)
                .order(by: "savedAt", descending: true)
                .getDocuments()
            
            var reels: [Reel] = []
            
            for item in savedItems.documents {
                let data = item.data()
                if let itemId = data["itemId"] as? String {
                    let reelDoc = try await db.collection("reels").document(itemId).getDocument()
                    if var reel = try? reelDoc.data(as: Reel.self) {
                        reel.id = reelDoc.documentID
                        reels.append(reel)
                    }
                }
            }
            
            print("Loaded \(reels.count) saved reels")
            return reels
        } catch {
            print("Error loading saved reels: \(error)")
            return []
        }
    }
    
    func loadSavedPosts() async -> [ServicePost] {
        guard let userId = currentUser?.id else { return [] }
        
        do {
            let savedItems = try await db.collection("savedItems")
                .whereField("userId", isEqualTo: userId)
                .whereField("itemType", isEqualTo: SavedItem.SavedItemType.post.rawValue)
                .order(by: "savedAt", descending: true)
                .getDocuments()
            
            var posts: [ServicePost] = []
            
            for item in savedItems.documents {
                let data = item.data()
                if let itemId = data["itemId"] as? String {
                    let postDoc = try await db.collection("posts").document(itemId).getDocument()
                    if var post = try? postDoc.data(as: ServicePost.self) {
                        post.id = postDoc.documentID
                        posts.append(post)
                    }
                }
            }
            
            print("Loaded \(posts.count) saved posts")
            return posts
        } catch {
            print("Error loading saved posts: \(error)")
            return []
        }
    }
    
    func toggleReelSave(_ reelId: String) async throws -> Bool {
        let isSaved = await isItemSaved(itemId: reelId, type: .reel)
        
        if isSaved {
            try await unsaveItem(itemId: reelId, type: .reel)
            return false
        } else {
            try await saveItem(itemId: reelId, type: .reel)
            return true
        }
    }
    
    func togglePostSave(_ postId: String) async throws -> Bool {
        let isSaved = await isItemSaved(itemId: postId, type: .post)
        
        if isSaved {
            try await unsaveItem(itemId: postId, type: .post)
            return false
        } else {
            try await saveItem(itemId: postId, type: .post)
            return true
        }
    }
}

// MARK: - Enhanced Reels & Comments Extension
extension FirebaseService {
    
    // Listener storage
    private static var reelListeners: [String: ListenerRegistration] = [:]
    private static var commentsListeners: [String: ListenerRegistration] = [:]
    private static var likesListeners: [String: ListenerRegistration] = [:]
    
    // MARK: - Real-time Reel Listening
    
    func listenToReel(_ reelId: String, completion: @escaping (Reel?) -> Void) -> ListenerRegistration {
        // Remove existing listener
        Self.reelListeners[reelId]?.remove()
        
        let listener = db.collection("reels").document(reelId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to reel: \(error)")
                    completion(nil)
                    return
                }
                
                guard let document = snapshot, document.exists else {
                    completion(nil)
                    return
                }
                
                var reel = try? document.data(as: Reel.self)
                reel?.id = document.documentID
                completion(reel)
            }
        
        Self.reelListeners[reelId] = listener
        return listener
    }
    
    func stopListeningToReel(_ reelId: String) {
        Self.reelListeners[reelId]?.remove()
        Self.reelListeners.removeValue(forKey: reelId)
    }
    
    // MARK: - Comments Management
    
    func listenToComments(for reelId: String, completion: @escaping ([Comment]) -> Void) -> ListenerRegistration {
        Self.commentsListeners[reelId]?.remove()
        
        let listener = db.collection("comments")
            .whereField("reelId", isEqualTo: reelId)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to comments: \(error)")
                    completion([])
                    return
                }
                
                // Fix: Properly type the comments array
                let comments: [Comment] = snapshot?.documents.compactMap { doc in
                    var comment = try? doc.data(as: Comment.self)
                    comment?.id = doc.documentID
                    return comment
                } ?? []
                
                completion(comments)
            }
        
        Self.commentsListeners[reelId] = listener
        return listener
    }
    
    func postComment(on reelId: String, text: String, parentCommentId: String? = nil) async throws -> Comment {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        let commentData: [String: Any] = [
            "reelId": reelId,
            "userId": userId,
            "userName": currentUser?.name ?? "User",
            "userProfileImage": currentUser?.profileImageURL ?? "",
            "text": text,
            "timestamp": Date(),
            "likes": [],
            "parentCommentId": parentCommentId ?? NSNull(),
            "replyCount": 0,
            "isDeleted": false
        ]
        
        let docRef = try await db.collection("comments").addDocument(data: commentData)
        
        // Update parent comment's reply count if this is a reply
        if let parentId = parentCommentId {
            try await db.collection("comments").document(parentId).updateData([
                "replyCount": FieldValue.increment(Int64(1))
            ])
        }
        
        // Update reel's comment count
        try await db.collection("reels").document(reelId).updateData([
            "comments": FieldValue.increment(Int64(1))
        ])
        
        var newComment = Comment(
            id: docRef.documentID,
            reelId: reelId,
            userId: userId,
            userName: currentUser?.name,
            userProfileImage: currentUser?.profileImageURL,
            text: text,
            parentCommentId: parentCommentId
        )
        
        return newComment
    }
    
    func deleteComment(_ commentId: String, reelId: String) async throws {
        guard let userId = currentUser?.id else { return }
        
        let comment = try await db.collection("comments").document(commentId).getDocument()
        guard let data = comment.data() else { return }
        
        let commentUserId = data["userId"] as? String ?? ""
        
        // Get reel owner
        let reel = try await db.collection("reels").document(reelId).getDocument()
        let reelOwnerId = reel.data()?["userId"] as? String ?? ""
        
        // Check if user can delete (own comment or reel owner)
        guard userId == commentUserId || userId == reelOwnerId else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized to delete this comment"])
        }
        
        // Soft delete
        try await db.collection("comments").document(commentId).updateData([
            "isDeleted": true,
            "deletedAt": Date()
        ])
        
        // Update parent's reply count if this was a reply
        if let parentId = data["parentCommentId"] as? String {
            try await db.collection("comments").document(parentId).updateData([
                "replyCount": FieldValue.increment(Int64(-1))
            ])
        }
        
        // Update reel's comment count
        try await db.collection("reels").document(reelId).updateData([
            "comments": FieldValue.increment(Int64(-1))
        ])
    }
    
    func likeComment(_ commentId: String) async throws {
        guard let userId = currentUser?.id else { return }
        
        try await db.collection("comments").document(commentId).updateData([
            "likes": FieldValue.arrayUnion([userId])
        ])
    }
    
    func unlikeComment(_ commentId: String) async throws {
        guard let userId = currentUser?.id else { return }
        
        try await db.collection("comments").document(commentId).updateData([
            "likes": FieldValue.arrayRemove([userId])
        ])
    }
    
    // MARK: - Enhanced Likes Management
    
    func listenToReelLikes(_ reelId: String, completion: @escaping ([ReelLike]) -> Void) -> ListenerRegistration {
        Self.likesListeners[reelId]?.remove()
        
        let listener = db.collection("reelLikes")
            .whereField("reelId", isEqualTo: reelId)
            .order(by: "likedAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to likes: \(error)")
                    completion([])
                    return
                }
                
                // Fix: Properly type the likes array
                let likes: [ReelLike] = snapshot?.documents.compactMap { doc in
                    var like = try? doc.data(as: ReelLike.self)
                    like?.id = doc.documentID
                    return like
                } ?? []
                
                completion(likes)
            }
        
        Self.likesListeners[reelId] = listener
        return listener
    }
    
    func likeReel(_ reelId: String) async {
        guard let userId = currentUser?.id else { return }
        
        do {
            // Add to likes array
            let reelRef = db.collection("reels").document(reelId)
            try await reelRef.updateData([
                "likes": FieldValue.arrayUnion([userId])
            ])
            
            // Add to reelLikes collection for detailed tracking
            let likeData: [String: Any] = [
                "reelId": reelId,
                "userId": userId,
                "userName": currentUser?.name ?? "User",
                "userProfileImage": currentUser?.profileImageURL ?? "",
                "likedAt": Date()
            ]
            
            // Use userId-reelId as document ID to prevent duplicates
            let likeId = "\(userId)_\(reelId)"
            try await db.collection("reelLikes").document(likeId).setData(likeData)
        } catch {
            print("Error liking reel: \(error)")
        }
    }
    
    func unlikeReel(_ reelId: String) async {
        guard let userId = currentUser?.id else { return }
        
        do {
            // Remove from likes array
            let reelRef = db.collection("reels").document(reelId)
            try await reelRef.updateData([
                "likes": FieldValue.arrayRemove([userId])
            ])
            
            // Remove from reelLikes collection
            let likeId = "\(userId)_\(reelId)"
            try await db.collection("reelLikes").document(likeId).delete()
        } catch {
            print("Error unliking reel: \(error)")
        }
    }
    
    // MARK: - Update Reel Caption (remove placeholders)
    
    func updateReelCaption(_ reelId: String, title: String, description: String) async throws {
        guard let currentUserId = currentUser?.id else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Verify ownership
        let reel = try await db.collection("reels").document(reelId).getDocument()
        guard let data = reel.data(),
              data["userId"] as? String == currentUserId else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized to edit this reel"])
        }
        
        // Update the reel - allow empty strings (no placeholders)
        try await db.collection("reels").document(reelId).updateData([
            "title": title,
            "description": description,
            "updatedAt": Date()
        ])
    }
    
    // MARK: - Cleanup
    
    func stopListeningToComments(_ reelId: String) {
        Self.commentsListeners[reelId]?.remove()
        Self.commentsListeners.removeValue(forKey: reelId)
    }
    
    func stopListeningToLikes(_ reelId: String) {
        Self.likesListeners[reelId]?.remove()
        Self.likesListeners.removeValue(forKey: reelId)
    }
}

// MARK: - Followers/Following Lists Extension
extension FirebaseService {
    
    func getFollowers(for userId: String) async -> [User] {
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            if let user = try? document.data(as: User.self) {
                var followers: [User] = []
                for followerId in user.followers {
                    let followerDoc = try await db.collection("users").document(followerId).getDocument()
                    if var follower = try? followerDoc.data(as: User.self) {
                        follower.id = followerDoc.documentID
                        followers.append(follower)
                    }
                }
                return followers
            }
        } catch {
            print("Error getting followers: \(error)")
        }
        return []
    }

    func getFollowing(for userId: String) async -> [User] {
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            if let user = try? document.data(as: User.self) {
                var following: [User] = []
                for followingId in user.following {
                    let followingDoc = try await db.collection("users").document(followingId).getDocument()
                    if var followingUser = try? followingDoc.data(as: User.self) {
                        followingUser.id = followingDoc.documentID
                        following.append(followingUser)
                    }
                }
                return following
            }
        } catch {
            print("Error getting following: \(error)")
        }
        return []
    }
}

// MARK: - Messaging Extension for FirebaseService
extension FirebaseService {
    
    // MARK: - Conversation Management
    
    /// Find or create a conversation between two users
    func findOrCreateConversation(with otherUserId: String) async throws -> String {
        guard let currentUserId = currentUser?.id else {
            throw NSError(domain: "MessagingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Check if conversation already exists
        let participantIds = [currentUserId, otherUserId].sorted()
        
        let existingConversations = try await db.collection("conversations")
            .whereField("participantIds", isEqualTo: participantIds)
            .getDocuments()
        
        if let existingConversation = existingConversations.documents.first {
            return existingConversation.documentID
        }
        
        // Create new conversation
        let otherUser = try await getUserInfo(userId: otherUserId)
        
        let conversationData: [String: Any] = [
            "participantIds": participantIds,
            "participantNames": [
                currentUserId: currentUser?.name ?? "Unknown",
                otherUserId: otherUser?.name ?? "Unknown"
            ],
            "participantImages": [
                currentUserId: currentUser?.profileImageURL ?? "",
                otherUserId: otherUser?.profileImageURL ?? ""
            ],
            "unreadCounts": [
                currentUserId: 0,
                otherUserId: 0
            ],
            "createdAt": Date(),
            "updatedAt": Date(),
            "blockedUsers": []
        ]
        
        let newConversation = try await db.collection("conversations").addDocument(data: conversationData)
        return newConversation.documentID
    }
    
    /// Load all conversations for current user
    func loadConversations() async -> [Conversation] {
        guard let userId = currentUser?.id else { return [] }
        
        do {
            let snapshot = try await db.collection("conversations")
                .whereField("participantIds", arrayContains: userId)
                .order(by: "lastMessageTimestamp", descending: true)
                .getDocuments()
            
            let conversations = snapshot.documents.compactMap { doc in
                if var conversation = try? doc.data(as: Conversation.self) {
                    conversation.id = doc.documentID
                    return conversation
                }
                return nil
            }
            
            // Filter out conversations where user is blocked
            return conversations.filter { !$0.isBlocked(by: userId) }
        } catch {
            print("Error loading conversations: \(error)")
            return []
        }
    }
    
    // MARK: - Message Management
    
    /// Send a message with optional context
    func sendMessage(
        to recipientId: String,
        text: String,
        contextType: Message.MessageContextType? = nil,
        contextId: String? = nil,
        contextData: (title: String, image: String?, userId: String)? = nil
    ) async throws {
        guard let currentUserId = currentUser?.id else {
            throw NSError(domain: "MessagingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Debug logging
        if let contextType = contextType, let contextId = contextId {
            print("📤 Sending message with context - Type: \(contextType.rawValue), ID: \(contextId)")
        }
        
        // Find or create conversation
        let conversationId = try await findOrCreateConversation(with: recipientId)
        
        // Create message data
        var messageData: [String: Any] = [
            "senderId": currentUserId,
            "senderName": currentUser?.name ?? "Unknown",
            "conversationId": conversationId,
            "text": text,
            "timestamp": Date(),
            "isDelivered": false,
            "isRead": false,
            "isEdited": false,
            "isDeleted": false
        ]
        
        if let profileImage = currentUser?.profileImageURL {
            messageData["senderProfileImage"] = profileImage
        }
        
        // Add context if provided
        if let contextType = contextType,
           let contextId = contextId,
           let contextData = contextData {
            messageData["contextType"] = contextType.rawValue
            messageData["contextId"] = contextId  // This should be the actual document ID
            messageData["contextTitle"] = contextData.title
            messageData["contextUserId"] = contextData.userId
            
            if let image = contextData.image {
                messageData["contextImage"] = image
            }
            
            print("📤 Message data with context: contextId = \(contextId)")
        }
        
        // Save message
        let messageRef = try await db.collection("messages").addDocument(data: messageData)
        
        // Update conversation
        let conversationUpdate: [String: Any] = [
            "lastMessage": text,
            "lastMessageTimestamp": Date(),
            "lastMessageSenderId": currentUserId,
            "updatedAt": Date(),
            "unreadCounts.\(recipientId)": FieldValue.increment(Int64(1))
        ]
        
        try await db.collection("conversations")
            .document(conversationId)
            .updateData(conversationUpdate)
        
        // Mark as delivered (in real app, this would happen when recipient receives it)
        try await markMessageAsDelivered(messageRef.documentID)
    }
    
    /// Load messages for a conversation
    func loadMessages(for conversationId: String, limit: Int = 50) async -> [Message] {
        do {
            let snapshot = try await db.collection("messages")
                .whereField("conversationId", isEqualTo: conversationId)
                .whereField("isDeleted", isEqualTo: false)
                .order(by: "timestamp", descending: true)
                .limit(to: limit)
                .getDocuments()
            
            let messages = snapshot.documents.compactMap { doc in
                if var message = try? doc.data(as: Message.self) {
                    message.id = doc.documentID
                    return message
                }
                return nil
            }
            
            // Return in chronological order
            return messages.reversed()
        } catch {
            print("Error loading messages: \(error)")
            return []
        }
    }
    
    // MARK: - Read Receipts
    
    /// Mark message as delivered
    private func markMessageAsDelivered(_ messageId: String) async throws {
        try await db.collection("messages").document(messageId).updateData([
            "isDelivered": true,
            "deliveredAt": Date()
        ])
    }
    
    /// Mark messages as read
    func markMessagesAsRead(in conversationId: String) async throws {
        guard let userId = currentUser?.id else { return }
        
        // Get unread messages
        let unreadMessages = try await db.collection("messages")
            .whereField("conversationId", isEqualTo: conversationId)
            .whereField("senderId", isNotEqualTo: userId)
            .whereField("isRead", isEqualTo: false)
            .getDocuments()
        
        // Batch update messages as read
        let batch = db.batch()
        let readTime = Date()
        
        for document in unreadMessages.documents {
            batch.updateData([
                "isRead": true,
                "readAt": readTime
            ], forDocument: document.reference)
        }
        
        // Reset unread count for current user
        let conversationRef = db.collection("conversations").document(conversationId)
        batch.updateData([
            "unreadCounts.\(userId)": 0,
            "lastReadTimestamps.\(userId)": readTime
        ], forDocument: conversationRef)
        
        try await batch.commit()
    }
    
    // MARK: - Real-time Listeners
    
    /// Listen to conversation updates
    func listenToConversations(completion: @escaping ([Conversation]) -> Void) -> ListenerRegistration? {
        guard let userId = currentUser?.id else { return nil }
        
        // Remove any existing listener
        conversationsListener?.remove()
        
        // Create and store new listener
        conversationsListener = db.collection("conversations")
            .whereField("participantIds", arrayContains: userId)
            .order(by: "lastMessageTimestamp", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to conversations: \(error)")
                    return
                }
                
                let conversations: [Conversation] = snapshot?.documents.compactMap { doc in
                    if var conversation = try? doc.data(as: Conversation.self) {
                        conversation.id = doc.documentID
                        return conversation
                    }
                    return nil
                } ?? []
                
                // Filter out blocked conversations
                let filteredConversations = conversations.filter { conversation in
                    !conversation.isBlocked(by: userId)
                }
                completion(filteredConversations)
            }
        
        return conversationsListener
    }
    
    /// Listen to messages in a conversation
    func listenToMessages(in conversationId: String, completion: @escaping ([Message]) -> Void) -> ListenerRegistration {
        // Remove any existing listener
        messagesListener?.remove()
        
        // Create and store new listener
        messagesListener = db.collection("messages")
            .whereField("conversationId", isEqualTo: conversationId)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to messages: \(error)")
                    return
                }
                
                let messages: [Message] = snapshot?.documents.compactMap { doc in
                    if var message = try? doc.data(as: Message.self) {
                        message.id = doc.documentID
                        return message
                    }
                    return nil
                } ?? []
                
                completion(messages)
            }
        
        return messagesListener!
    }
    
    // MARK: - Blocking & Reporting
    
    /// Block a user
    func blockUser(_ userId: String, in conversationId: String) async throws {
        guard let currentUserId = currentUser?.id else { return }
        
        try await db.collection("conversations").document(conversationId).updateData([
            "blockedUsers": FieldValue.arrayUnion([currentUserId])
        ])
    }
    
    /// Unblock a user
    func unblockUser(_ userId: String, in conversationId: String) async throws {
        guard let currentUserId = currentUser?.id else { return }
        
        try await db.collection("conversations").document(conversationId).updateData([
            "blockedUsers": FieldValue.arrayRemove([currentUserId])
        ])
    }
    
    /// Report a message or conversation
    func reportMessage(
        messageId: String? = nil,
        conversationId: String,
        reportedUserId: String,
        reason: MessageReport.ReportReason,
        details: String? = nil
    ) async throws {
        guard let reporterId = currentUser?.id else { return }
        
        let reportData: [String: Any] = [
            "reporterId": reporterId,
            "reportedUserId": reportedUserId,
            "conversationId": conversationId,
            "reason": reason.rawValue,
            "timestamp": Date(),
            "status": MessageReport.ReportStatus.pending.rawValue
        ]
        
        var mutableReportData = reportData
        if let messageId = messageId {
            mutableReportData["messageId"] = messageId
        }
        if let details = details {
            mutableReportData["additionalDetails"] = details
        }
        
        try await db.collection("reports").addDocument(data: mutableReportData)
    }
    
    // MARK: - Helper Functions
    
    /// Get user info
    private func getUserInfo(userId: String) async throws -> User? {
        let document = try await db.collection("users").document(userId).getDocument()
        if var user = try? document.data(as: User.self) {
            user.id = document.documentID
            return user
        }
        return nil
    }
    
    /// Get total unread message count
    func getTotalUnreadCount() async -> Int {
        guard let userId = currentUser?.id else { return 0 }
        
        let conversations = await loadConversations()
        return conversations.reduce(0) { total, conversation in
            total + (conversation.unreadCounts[userId] ?? 0)
        }
    }
    
    /// Delete a message (soft delete)
    func deleteMessage(_ messageId: String) async throws {
        try await db.collection("messages").document(messageId).updateData([
            "isDeleted": true
        ])
    }
    
    /// Edit a message
    func editMessage(_ messageId: String, newText: String) async throws {
        try await db.collection("messages").document(messageId).updateData([
            "text": newText,
            "isEdited": true,
            "editedAt": Date()
        ])
    }
}

// MARK: - Chat Management Extension
extension FirebaseService {
    
    /// Clear all messages in a conversation (for testing)
    func clearConversation(_ conversationId: String) async throws {
        guard let currentUserId = currentUser?.id else {
            throw NSError(domain: "MessagingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Get all messages in the conversation
        let messagesSnapshot = try await db.collection("messages")
            .whereField("conversationId", isEqualTo: conversationId)
            .getDocuments()
        
        // Delete all messages using batch
        let batch = db.batch()
        for document in messagesSnapshot.documents {
            batch.deleteDocument(document.reference)
        }
        
        // Get the other participant's ID
        let conversationDoc = try await db.collection("conversations").document(conversationId).getDocument()
        guard let conversationData = conversationDoc.data(),
              let participantIds = conversationData["participantIds"] as? [String] else {
            throw NSError(domain: "MessagingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid conversation data"])
        }
        
        let otherUserId = participantIds.first { $0 != currentUserId } ?? ""
        
        // Reset conversation metadata
        let conversationRef = db.collection("conversations").document(conversationId)
        batch.updateData([
            "lastMessage": FieldValue.delete(),
            "lastMessageTimestamp": Date(),
            "lastMessageSenderId": FieldValue.delete(),
            "unreadCounts": [
                currentUserId: 0,
                otherUserId: 0
            ],
            "updatedAt": Date()
        ], forDocument: conversationRef)
        
        // Commit the batch
        try await batch.commit()
        
        print("Conversation \(conversationId) cleared successfully")
    }
    
    /// Delete a single conversation entirely (optional - for complete removal)
    func deleteConversation(_ conversationId: String) async throws {
        guard let currentUserId = currentUser?.id else {
            throw NSError(domain: "MessagingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Verify user is a participant
        let conversationDoc = try await db.collection("conversations").document(conversationId).getDocument()
        guard let data = conversationDoc.data(),
              let participantIds = data["participantIds"] as? [String],
              participantIds.contains(currentUserId) else {
            throw NSError(domain: "MessagingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not authorized to delete this conversation"])
        }
        
        // Delete all messages first
        let messagesSnapshot = try await db.collection("messages")
            .whereField("conversationId", isEqualTo: conversationId)
            .getDocuments()
        
        let batch = db.batch()
        
        // Delete all messages
        for document in messagesSnapshot.documents {
            batch.deleteDocument(document.reference)
        }
        
        // Delete the conversation itself
        batch.deleteDocument(conversationDoc.reference)
        
        // Commit the batch
        try await batch.commit()
        
        print("Conversation \(conversationId) and all messages deleted successfully")
    }
    
    /// Get message count for a conversation (for debugging)
    func getMessageCount(for conversationId: String) async -> Int {
        do {
            let snapshot = try await db.collection("messages")
                .whereField("conversationId", isEqualTo: conversationId)
                .getDocuments()
            return snapshot.documents.count
        } catch {
            print("Error getting message count: \(error)")
            return 0
        }
    }
}

// Add this extension to FirebaseService.swift

// MARK: - User Posts Extension
extension FirebaseService {
    
    /// Load all posts (offers and requests) created by a specific user
    func loadUserPosts(for userId: String) async -> [ServicePost] {
        do {
            let snapshot = try await db.collection("posts")
                .whereField("userId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            let posts = snapshot.documents.compactMap { doc in
                if var post = try? doc.data(as: ServicePost.self) {
                    // IMPORTANT: Set the document ID
                    post.id = doc.documentID
                    return post
                }
                return nil
            }
            
            print("Loaded \(posts.count) posts for user \(userId)")
            return posts
        } catch {
            print("Error loading user posts: \(error)")
            return []
        }
    }
    
    /// Get count of active posts for a user
    func getUserPostCount(for userId: String) async -> Int {
        do {
            let snapshot = try await db.collection("posts")
                .whereField("userId", isEqualTo: userId)
                .whereField("status", isEqualTo: ServicePost.PostStatus.active.rawValue)
                .getDocuments()
            
            return snapshot.documents.count
        } catch {
            print("Error getting user post count: \(error)")
            return 0
        }
    }
    
    /// Delete a post (only if user owns it)
    func deletePost(_ postId: String) async throws {
        guard let currentUserId = currentUser?.id else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Verify ownership
        let post = try await db.collection("posts").document(postId).getDocument()
        guard let data = post.data(),
              data["userId"] as? String == currentUserId else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized to delete this post"])
        }
        
        // Delete the post
        try await db.collection("posts").document(postId).delete()
        
        // Reload posts
        await loadAllServicePosts()
        
        print("Deleted post with ID: \(postId)")
    }
    
    /// Update post status (active, completed, cancelled)
    func updatePostStatus(_ postId: String, status: ServicePost.PostStatus) async throws {
        guard let currentUserId = currentUser?.id else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Verify ownership
        let post = try await db.collection("posts").document(postId).getDocument()
        guard let data = post.data(),
              data["userId"] as? String == currentUserId else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized to update this post"])
        }
        
        // Update status
        try await db.collection("posts").document(postId).updateData([
            "status": status.rawValue,
            "updatedAt": Date()
        ])
        
        // Reload posts
        await loadAllServicePosts()
        
        print("Updated post \(postId) status to: \(status.rawValue)")
    }
    
    /// Refresh user posts after creating a new one
    func refreshUserPosts() async {
        guard let userId = currentUser?.id else { return }
        
        // This will trigger a refresh of the user's posts in their profile
        await loadAllServicePosts()
    }
}

// Add these methods to FirebaseService.swift

// MARK: - Edit/Delete Operations Extension
extension FirebaseService {
    
    // MARK: - Service Posts
    
    /// Update an existing service post
    func updatePost(
        postId: String,
        title: String,
        description: String,
        category: ServiceCategory,
        price: Double? = nil,
        location: String? = nil,
        imageURLs: [String]
    ) async throws {
        guard let currentUserId = currentUser?.id else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Verify ownership
        let post = try await db.collection("posts").document(postId).getDocument()
        guard let data = post.data(),
              data["userId"] as? String == currentUserId else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized to edit this post"])
        }
        
        // Prepare update data
        var updateData: [String: Any] = [
            "title": title,
            "description": description,
            "category": category.rawValue,
            "imageURLs": imageURLs,
            "updatedAt": Date()
        ]
        
        if let price = price {
            updateData["price"] = price
        } else {
            updateData["price"] = FieldValue.delete()
        }
        
        if let location = location {
            updateData["location"] = location
        } else {
            updateData["location"] = FieldValue.delete()
        }
        
        // Update the post
        try await db.collection("posts").document(postId).updateData(updateData)
        
        // Refresh posts
        await loadAllServicePosts()
        
        print("Updated post with ID: \(postId)")
    }
    
    // MARK: - Reels
    
    /// Delete a reel
    func deleteReel(_ reelId: String) async throws {
        guard let currentUserId = currentUser?.id else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Verify ownership
        let reel = try await db.collection("reels").document(reelId).getDocument()
        guard let data = reel.data(),
              data["userId"] as? String == currentUserId else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized to delete this reel"])
        }
        
        // Delete the reel
        try await db.collection("reels").document(reelId).delete()
        
        // Also delete associated comments
        let comments = try await db.collection("comments")
            .whereField("reelId", isEqualTo: reelId)
            .getDocuments()
        
        for comment in comments.documents {
            try await comment.reference.delete()
        }
        
        // Refresh reels
        await loadReels()
        
        print("Deleted reel with ID: \(reelId)")
    }
    
//    /// Update reel caption
//    func updateReelCaption(_ reelId: String, title: String, description: String) async throws {
//        guard let currentUserId = currentUser?.id else {
//            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
//        }
//        
//        // Verify ownership
//        let reel = try await db.collection("reels").document(reelId).getDocument()
//        guard let data = reel.data(),
//              data["userId"] as? String == currentUserId else {
//            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized to edit this reel"])
//        }
//        
//        // Update the reel
//        try await db.collection("reels").document(reelId).updateData([
//            "title": title,
//            "description": description,
//            "updatedAt": Date()
//        ])
//        
//        // Refresh reels
//        await loadReels()
//        
//        print("Updated reel caption for ID: \(reelId)")
//    }
    
    // MARK: - Status
    
    /// Delete a status
    func deleteStatus(_ statusId: String) async throws {
        guard let currentUserId = currentUser?.id else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Verify ownership
        let status = try await db.collection("statuses").document(statusId).getDocument()
        guard let data = status.data(),
              data["userId"] as? String == currentUserId else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized to delete this status"])
        }
        
        // Delete the status
        try await db.collection("statuses").document(statusId).delete()
        
        // Refresh statuses
        await loadStatusesFromFollowing()
        
        print("Deleted status with ID: \(statusId)")
    }
    
    // MARK: - Batch Operations
    
    /// Delete all expired content for a user
    func cleanupUserContent() async {
        guard let userId = currentUser?.id else { return }
        
        do {
            // Clean up expired statuses
            let expiredStatuses = try await db.collection("statuses")
                .whereField("userId", isEqualTo: userId)
                .whereField("expiresAt", isLessThan: Date())
                .getDocuments()
            
            for document in expiredStatuses.documents {
                try await document.reference.delete()
            }
            
            print("Cleaned up \(expiredStatuses.documents.count) expired statuses")
        } catch {
            print("Error cleaning up user content: \(error)")
        }
    }
    
    /// Get user's content statistics
    func getUserContentStats() async -> (posts: Int, reels: Int, activeStatuses: Int) {
        guard let userId = currentUser?.id else { return (0, 0, 0) }
        
        do {
            // Count posts
            let posts = try await db.collection("posts")
                .whereField("userId", isEqualTo: userId)
                .whereField("status", isEqualTo: ServicePost.PostStatus.active.rawValue)
                .getDocuments()
            
            // Count reels
            let reels = try await db.collection("reels")
                .whereField("userId", isEqualTo: userId)
                .getDocuments()
            
            // Count active statuses
            let statuses = try await db.collection("statuses")
                .whereField("userId", isEqualTo: userId)
                .whereField("isActive", isEqualTo: true)
                .whereField("expiresAt", isGreaterThan: Date())
                .getDocuments()
            
            return (posts.documents.count, reels.documents.count, statuses.documents.count)
        } catch {
            print("Error getting user content stats: \(error)")
            return (0, 0, 0)
        }
    }
}



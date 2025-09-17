

// PostDetailView.swift
// Complete Production-Ready Implementation
// Path: ClaudeHustlerFirebase/Views/PostDetailView.swift

import SwiftUI
import FirebaseFirestore
import MapKit

struct PostDetailView: View {
    let post: ServicePost
    var currentUser: User? = nil
    
    @StateObject private var firebase = FirebaseService.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    private let cacheManager = CacheManager.shared
    
    @Environment(\.dismiss) var dismiss
    
    // User data
    @State private var posterInfo: User?
    @State private var relatedPosts: [ServicePost] = []
    @State private var isSaved = false
    @State private var isLiked = false
    @State private var likeCount: Int = 0
    
    // UI states
    @State private var showingEditPost = false
    @State private var showingDeleteAlert = false
    @State private var showingMessages = false
    @State private var showingShareSheet = false
    @State private var showingReportSheet = false
    @State private var showingImageViewer = false
    @State private var selectedImageIndex = 0
    
    // Loading & Error states
    @State private var isLoading = false
    @State private var isDeleting = false
    @State private var loadError: Error?
    
    // Real-time listeners
    @State private var postListener: ListenerRegistration?
    @State private var userListener: ListenerRegistration?
    
    // Validation
    private let validator = ValidationHelper()
    
    private var isOwnPost: Bool {
        firebase.currentUser?.id == post.userId
    }
    
    private var shareURL: URL {
        URL(string: "claudehustler://post/\(post.id ?? "")") ?? URL(string: "https://claudehustler.app")!
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                if networkMonitor.isConnected || posterInfo != nil {
                    mainContent
                } else {
                    OfflineView {
                        Task {
                            await loadData()
                        }
                    }
                }
                
                // Error banner
                if let error = loadError {
                    ErrorBanner(
                        error: error,
                        retry: {
                            Task {
                                loadError = nil
                                await loadData()
                            }
                        },
                        dismiss: { loadError = nil }
                    )
                    .transition(.move(edge: .top))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .fontWeight(.medium)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isOwnPost {
                        Menu {
                            Button(action: { showingEditPost = true }) {
                                Label("Edit", systemImage: "pencil")
                            }
                            
                            Button(role: .destructive, action: { showingDeleteAlert = true }) {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                    } else {
                        Menu {
                            Button(action: { showingShareSheet = true }) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            
                            Button(action: { toggleSave() }) {
                                Label(isSaved ? "Unsave" : "Save",
                                      systemImage: isSaved ? "bookmark.fill" : "bookmark")
                            }
                            
                            Button(action: { showingReportSheet = true }) {
                                Label("Report", systemImage: "flag")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                    }
                }
            }
            .task {
                await loadData()
                setupListeners()
            }
            .onDisappear {
                cleanupListeners()
            }
            .sheet(isPresented: $showingEditPost) {
                EditServicePostView(post: post)
            }
            .sheet(isPresented: $showingMessages) {
                if let posterInfo = posterInfo {
                    ChatView(
                        recipientId: posterInfo.id ?? "",
                        contextType: .service,
                        contextId: post.id,
                        contextData: (
                            title: post.title,
                            image: post.mediaURLs.first,
                            userId: post.userId
                        ),
                        isFromContentView: true
                    )
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: [shareURL])
            }
            .sheet(isPresented: $showingReportSheet) {
                ReportView(
                    itemId: post.id ?? "",
                    itemType: .service,
                    reportedUserId: post.userId
                )
            }
            .fullScreenCover(isPresented: $showingImageViewer) {
                ImageViewerView(
                    images: post.mediaURLs,
                    selectedIndex: $selectedImageIndex
                )
            }
            .alert("Delete Post", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task {
                        await deletePost()
                    }
                }
            } message: {
                Text("Are you sure you want to delete this post? This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Main Content
    
    @ViewBuilder
    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Images Section
                if !post.mediaURLs.isEmpty {
                    imageCarousel
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    // Title and Price
                    titleSection
                    
                    Divider()
                    
                    // User Info Section
                    if let posterInfo = posterInfo {
                        userInfoSection(user: posterInfo)
                    } else if isLoading {
                        userInfoSkeleton
                    }
                    
                    Divider()
                    
                    // Description Section
                    descriptionSection
                    
                    // Details Section
                    detailsSection
                    
                    // Location Section
                    if let location = post.location, !location.isEmpty {
                        locationSection(location: location)
                    }
                    
                    // Stats Section
                    statsSection
                    
                    // Action Buttons
                    if !isOwnPost {
                        actionButtonsSection
                    }
                    
                    // Related Posts
                    if !relatedPosts.isEmpty {
                        relatedPostsSection
                    }
                }
                .padding()
            }
        }
        .refreshable {
            await loadData()
        }
    }
    
    // MARK: - Image Carousel
    
    @ViewBuilder
    private var imageCarousel: some View {
        TabView(selection: $selectedImageIndex) {
            ForEach(Array(post.mediaURLs.enumerated()), id: \.offset) { index, imageURL in
                AsyncImage(url: URL(string: imageURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(height: 350)
                            .clipped()
                            .onTapGesture {
                                showingImageViewer = true
                            }
                    case .failure(_):
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 350)
                            .overlay(
                                VStack {
                                    Image(systemName: "photo.slash")
                                        .font(.largeTitle)
                                        .foregroundColor(.gray)
                                    Text("Failed to load image")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            )
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 350)
                            .overlay(
                                ProgressView()
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
                .tag(index)
            }
        }
        .frame(height: 350)
        .tabViewStyle(PageTabViewStyle())
        .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
    }
    
    // MARK: - Title Section
    
    @ViewBuilder
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(post.title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .lineLimit(3)
            
            HStack {
                CategoryBadge(category: post.category)
                
                if post.isRequest {
                    RequestBadge()
                }
                
                Spacer()
                
                if let price = post.price {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 2) {
                            Text("$")
                                .font(.title3)
                                .fontWeight(.medium)
                            Text(String(format: "%.2f", price))
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.green)
                        
                        if post.isRequest {
                            Text("Budget")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else if !post.isRequest {
                    Text("Contact for pricing")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
            }
        }
    }
    
    // MARK: - User Info Section
    
    @ViewBuilder
    private func userInfoSection(user: User) -> some View {
        NavigationLink(destination: EnhancedProfileView(userId: user.id ?? "")) {
            HStack(spacing: 12) {
                // Profile Image
                if let imageURL = user.profileImageURL {
                    AsyncImage(url: URL(string: imageURL)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                    } placeholder: {
                        userImagePlaceholder(name: user.name)
                    }
                } else {
                    userImagePlaceholder(name: user.name)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(user.name)
                            .font(.headline)
                        
                        if user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    if let memberSince = user.createdAt {
                        Text("Member since \(memberSince, format: .dateTime.year(.defaultDigits).month(.abbreviated))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Rating if available
                    if let rating = user.averageRating, rating > 0 {
                        HStack(spacing: 4) {
                            StarRatingView(rating: rating)
                            Text("(\(user.reviewCount ?? 0))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var userInfoSkeleton: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 56, height: 56)
            
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 120, height: 16)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 12)
            }
            
            Spacer()
        }
    }
    
    private func userImagePlaceholder(name: String) -> some View {
        Circle()
            .fill(LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .frame(width: 56, height: 56)
            .overlay(
                Text(String(name.prefix(1)))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            )
    }
    
    // MARK: - Description Section
    
    @ViewBuilder
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.headline)
            
            Text(post.description)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - Details Section
    
    @ViewBuilder
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
            
            VStack(spacing: 8) {
                DetailRow(
                    icon: "tag",
                    title: "Category",
                    value: post.category.displayName
                )
                
                DetailRow(
                    icon: "calendar",
                    title: "Posted",
                    value: post.createdAt.formatted(date: .abbreviated, time: .omitted)
                )
                
                if post.updatedAt != post.createdAt {
                    DetailRow(
                        icon: "clock.arrow.circlepath",
                        title: "Updated",
                        value: post.updatedAt.formatted(date: .abbreviated, time: .omitted)
                    )
                }
                
                DetailRow(
                    icon: "person.2",
                    title: "Type",
                    value: post.isRequest ? "Service Request" : "Service Offer"
                )
                
                if post.views > 0 {
                    DetailRow(
                        icon: "eye",
                        title: "Views",
                        value: "\(post.views)"
                    )
                }
            }
        }
    }
    
    // MARK: - Location Section
    
    @ViewBuilder
    private func locationSection(location: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Location")
                .font(.headline)
            
            HStack {
                Image(systemName: "location.circle.fill")
                    .foregroundColor(.blue)
                Text(location)
                    .font(.subheadline)
                Spacer()
            }
            .padding()
            .background(Color.gray.opacity(0.08))
            .cornerRadius(10)
        }
    }
    
    // MARK: - Stats Section
    
    @ViewBuilder
    private var statsSection: some View {
        HStack(spacing: 30) {
            StatItem(
                icon: "heart.fill",
                count: likeCount,
                color: isLiked ? .red : .gray
            ) {
                toggleLike()
            }
            
            StatItem(
                icon: "bubble.left",
                count: post.comments ?? 0,
                color: .gray
            ) {
                // Navigate to comments
            }
            
            StatItem(
                icon: "bookmark.fill",
                count: post.saves ?? 0,
                color: isSaved ? .blue : .gray
            ) {
                toggleSave()
            }
            
            Spacer()
            
            Button(action: { showingShareSheet = true }) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Action Buttons
    
    @ViewBuilder
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            // Contact Button
            Button(action: { showingMessages = true }) {
                HStack {
                    Image(systemName: "message.fill")
                    Text(post.isRequest ? "Send Offer" : "Contact Seller")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
            
            // Save Button
            Button(action: { toggleSave() }) {
                HStack {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    Text(isSaved ? "Saved" : "Save for Later")
                        .fontWeight(.medium)
                }
                .foregroundColor(isSaved ? .white : .blue)
                .frame(maxWidth: .infinity)
                .padding()
                .background(isSaved ? Color.blue : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 1)
                )
                .cornerRadius(12)
            }
        }
        .padding(.top)
    }
    
    // MARK: - Related Posts Section
    
    @ViewBuilder
    private var relatedPostsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Related Services")
                .font(.headline)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(relatedPosts) { relatedPost in
                        RelatedPostCard(post: relatedPost)
                    }
                }
            }
            .frame(height: 150)
        }
        .padding(.top)
    }
    
    // MARK: - Data Loading
    
    private func loadData() async {
        isLoading = true
        loadError = nil
        
        // Load from cache first
        if let cachedUser: User = await cacheManager.get(key: "user_\(post.userId)") {
            self.posterInfo = cachedUser
        }
        
        do {
            // Load fresh user data
            let userDoc = try await firebase.db
                .collection("users")
                .document(post.userId)
                .getDocument()
            
            if userDoc.exists {
                var user = try userDoc.data(as: User.self)
                user.id = post.userId
                
                await MainActor.run {
                    self.posterInfo = user
                }
                
                // Cache user data
                await cacheManager.set(user, key: "user_\(post.userId)", expiry: 300)
            }
            
            // Check if saved
            if let currentUserId = firebase.currentUser?.id {
                let savedDocs = try await firebase.db
                    .collection("savedItems")
                    .whereField("userId", isEqualTo: currentUserId)
                    .whereField("itemId", isEqualTo: post.id ?? "")
                    .getDocuments()
                
                await MainActor.run {
                    self.isSaved = !savedDocs.documents.isEmpty
                }
                
                // Check if liked
                await MainActor.run {
                    self.isLiked = post.likes.contains(currentUserId)
                    self.likeCount = post.likes.count
                }
            }
            
            // Load related posts
            await loadRelatedPosts()
            
            // Increment view count
            if let postId = post.id, !isOwnPost {
                try await firebase.db
                    .collection("servicePosts")
                    .document(postId)
                    .updateData([
                        "views": FieldValue.increment(Int64(1))
                    ])
            }
            
        } catch {
            await MainActor.run {
                self.loadError = error
            }
        }
        
        isLoading = false
    }
    
    private func loadRelatedPosts() async {
        do {
            let query = firebase.db
                .collection("servicePosts")
                .whereField("category", isEqualTo: post.category.rawValue)
                .whereField("id", isNotEqualTo: post.id ?? "")
                .limit(to: 5)
            
            let snapshot = try await query.getDocuments()
            
            let posts = snapshot.documents.compactMap { doc in
                try? doc.data(as: ServicePost.self)
            }
            
            await MainActor.run {
                self.relatedPosts = posts
            }
        } catch {
            print("Error loading related posts: \(error)")
        }
    }
    
    // MARK: - Real-time Listeners
    
    private func setupListeners() {
        guard let postId = post.id else { return }
        
        // Post listener for real-time updates
        postListener = firebase.db
            .collection("servicePosts")
            .document(postId)
            .addSnapshotListener { snapshot, error in
                guard let document = snapshot,
                      document.exists,
                      let updatedPost = try? document.data(as: ServicePost.self) else { return }
                
                DispatchQueue.main.async {
                    self.likeCount = updatedPost.likes.count
                    if let currentUserId = self.firebase.currentUser?.id {
                        self.isLiked = updatedPost.likes.contains(currentUserId)
                    }
                }
            }
    }
    
    private func cleanupListeners() {
        postListener?.remove()
        userListener?.remove()
    }
    
    // MARK: - Actions
    
    private func toggleLike() {
        guard let postId = post.id,
              let currentUserId = firebase.currentUser?.id else { return }
        
        Task {
            do {
                if isLiked {
                    try await firebase.db
                        .collection("servicePosts")
                        .document(postId)
                        .updateData([
                            "likes": FieldValue.arrayRemove([currentUserId])
                        ])
                    await MainActor.run {
                        isLiked = false
                        likeCount -= 1
                    }
                } else {
                    try await firebase.db
                        .collection("servicePosts")
                        .document(postId)
                        .updateData([
                            "likes": FieldValue.arrayUnion([currentUserId])
                        ])
                    await MainActor.run {
                        isLiked = true
                        likeCount += 1
                    }
                }
            } catch {
                print("Error toggling like: \(error)")
            }
        }
    }
    
    private func toggleSave() {
        guard let postId = post.id else { return }
        
        Task {
            do {
                if isSaved {
                    try await firebase.unsaveItem(postId, type: .service)
                    await MainActor.run {
                        isSaved = false
                    }
                } else {
                    try await firebase.saveItem(
                        itemId: postId,
                        itemType: .service,
                        title: post.title,
                        imageURL: post.mediaURLs.first
                    )
                    await MainActor.run {
                        isSaved = true
                    }
                }
            } catch {
                print("Error toggling save: \(error)")
            }
        }
    }
    
    private func deletePost() async {
        guard let postId = post.id else { return }
        
        isDeleting = true
        
        do {
            try await firebase.deletePost(postId)
            await MainActor.run {
                dismiss()
            }
        } catch {
            print("Error deleting post: \(error)")
            await MainActor.run {
                self.loadError = error
                self.isDeleting = false
            }
        }
    }
}

// MARK: - Supporting Views

struct CategoryBadge: View {
    let category: ServiceCategory
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: categoryIcon(for: category))
                .font(.caption)
            Text(category.displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.1))
        .foregroundColor(.blue)
        .cornerRadius(12)
    }
    
    private func categoryIcon(for category: ServiceCategory) -> String {
        switch category {
        case .cleaning: return "sparkles"
        case .plumbing: return "wrench.fill"
        case .electrical: return "bolt.fill"
        case .gardening: return "leaf.fill"
        case .painting: return "paintbrush.fill"
        case .landscaping: return "tree.fill"
        case .moving: return "box.truck.fill"
        case .personalTraining: return "figure.run"
        case .photography: return "camera.fill"
        case .videography: return "video.fill"
        case .webDesign: return "globe"
        case .graphicDesign: return "paintpalette.fill"
        case .writing: return "pencil"
        case .translation: return "character.book.closed.fill"
        case .petCare: return "pawprint.fill"
        case .childCare: return "figure.and.child.holdinghands"
        case .assembly: return "screwdriver.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

struct RequestBadge: View {
    var body: some View {
        Text("REQUEST")
            .font(.caption)
            .fontWeight(.bold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.1))
            .foregroundColor(.orange)
            .cornerRadius(12)
    }
}

struct DetailRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

struct StatItem: View {
    let icon: String
    let count: Int
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.body)
                if count > 0 {
                    Text("\(count)")
                        .font(.subheadline)
                }
            }
            .foregroundColor(color)
        }
    }
}

struct RelatedPostCard: View {
    let post: ServicePost
    
    var body: some View {
        NavigationLink(destination: PostDetailView(post: post)) {
            VStack(alignment: .leading, spacing: 8) {
                // Image
                if let firstImage = post.mediaURLs.first {
                    AsyncImage(url: URL(string: firstImage)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 150, height: 80)
                            .clipped()
                            .cornerRadius(8)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 150, height: 80)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(
                            gradient: Gradient(colors: [
                                Color.blue.opacity(0.3),
                                Color.purple.opacity(0.3)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 150, height: 80)
                        .overlay(
                            Image(systemName: categoryIcon(for: post.category))
                                .font(.title2)
                                .foregroundColor(.white)
                        )
                }
                
                // Title
                Text(post.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Price
                if let price = post.price {
                    Text("$\(String(format: "%.2f", price))")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .fontWeight(.semibold)
                }
            }
            .frame(width: 150)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func categoryIcon(for category: ServiceCategory) -> String {
        switch category {
        case .cleaning: return "sparkles"
        case .plumbing: return "wrench.fill"
        case .electrical: return "bolt.fill"
        case .gardening: return "leaf.fill"
        case .painting: return "paintbrush.fill"
        case .landscaping: return "tree.fill"
        case .moving: return "box.truck.fill"
        case .personalTraining: return "figure.run"
        case .photography: return "camera.fill"
        case .videography: return "video.fill"
        case .webDesign: return "globe"
        case .graphicDesign: return "paintpalette.fill"
        case .writing: return "pencil"
        case .translation: return "character.book.closed.fill"
        case .petCare: return "pawprint.fill"
        case .childCare: return "figure.and.child.holdinghands"
        case .assembly: return "screwdriver.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

// Note: ImageViewerView is defined in PortfolioGalleryView.swift

struct ReportView: View {
    let itemId: String
    let itemType: Report.ReportItemType
    let reportedUserId: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Text("Report Content - Implementation Pending")
                .navigationTitle("Report")
                .navigationBarItems(
                    trailing: Button("Cancel") { dismiss() }
                )
        }
    }
}

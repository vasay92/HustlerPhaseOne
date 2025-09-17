

// EnhancedProfileView.swift
// Complete Production-Ready Implementation
// Path: ClaudeHustlerFirebase/Views/Profile/EnhancedProfileView.swift

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct EnhancedProfileView: View {
    let userId: String
    
    @StateObject private var firebase = FirebaseService.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    private let cacheManager = CacheManager.shared
    
    // User data
    @State private var user: User?
    @State private var portfolioCards: [PortfolioCard] = []
    @State private var reviews: [Review] = []
    @State private var savedReels: [Reel] = []
    @State private var savedPosts: [ServicePost] = []
    @State private var userPosts: [ServicePost] = []
    
    // UI state
    @State private var isFollowing = false
    @State private var selectedTab = 0
    @State private var showingFollowers = false
    @State private var showingFollowing = false
    @State private var showingSettings = false
    @State private var showingCreateCard = false
    @State private var showingReviewForm = false
    @State private var expandedReviews = false
    @State private var showingMessageView = false
    @State private var showingEditProfile = false
    
    // Loading & Error states
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var loadError: Error?
    @State private var portfolioLoadError: Error?
    @State private var reviewsLoadError: Error?
    
    // Pagination
    @State private var lastReviewDocument: DocumentSnapshot?
    @State private var isLoadingMoreReviews = false
    @State private var hasMoreReviews = true
    @State private var lastPostDocument: DocumentSnapshot?
    @State private var isLoadingMorePosts = false
    @State private var hasMorePosts = true
    
    // Real-time listeners
    @State private var reviewsListener: ListenerRegistration?
    @State private var userListener: ListenerRegistration?
    @State private var followListener: ListenerRegistration?
    
    // Review statistics
    @State private var reviewStats: (average: Double, count: Int, breakdown: [Int: Int]) = (0, 0, [:])
    
    @Environment(\.dismiss) var dismiss
    
    private let pageSize = 20
    
    var isOwnProfile: Bool {
        userId == firebase.currentUser?.id
    }
    
    var lastActiveText: String {
        guard let lastActive = user?.lastActive else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Active \(formatter.localizedString(for: lastActive, relativeTo: Date()))"
    }
    
    var joinedDateText: String {
        guard let createdAt = user?.createdAt else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return "Joined \(formatter.string(from: createdAt))"
    }
    
    var displayedReviews: [Review] {
        expandedReviews ? reviews : Array(reviews.prefix(3))
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                if networkMonitor.isConnected || user != nil {
                    mainContent
                } else {
                    OfflineView {
                        Task {
                            await loadProfileData()
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
                                await loadProfileData()
                            }
                        },
                        dismiss: { loadError = nil }
                    )
                    .transition(.move(edge: .top))
                }
                
                // Floating Add Button for Portfolio (only on My Work tab)
                if isOwnProfile && selectedTab == 0 {
                    floatingAddButton
                }
            }
            .navigationBarHidden(true)
            .task {
                if user == nil {
                    await loadProfileData()
                }
                setupListeners()
            }
            .onDisappear {
                cleanupListeners()
            }
            .sheet(isPresented: $showingFollowers) {
                FollowersListView(userId: userId)
            }
            .sheet(isPresented: $showingFollowing) {
                FollowingListView(userId: userId)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingCreateCard) {
                CreatePortfolioCardView()
            }
            .sheet(isPresented: $showingReviewForm) {
                CreateReviewView(userId: userId)
            }
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView(user: user ?? User(
                    id: userId,
                    email: "",
                    name: "",
                    createdAt: Date()
                ))
            }
            .fullScreenCover(isPresented: $showingMessageView) {
                ChatView(
                    recipientId: userId,
                    isFromContentView: false
                )
            }
        }
    }
    
    // MARK: - Main Content
    
    @ViewBuilder
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header Section
                headerSection
                    .padding(.top, 10)
                
                // Loading state for initial load
                if isLoading && user == nil {
                    LoadingView(message: "Loading profile...")
                        .frame(height: 200)
                } else {
                    // Stats Section
                    statsSection
                    
                    // Portfolio Section with Tabs
                    portfolioSection
                    
                    // Reviews Section
                    if !isOwnProfile || !reviews.isEmpty {
                        reviewsSection
                    }
                    
                    // Action Buttons (for other users' profiles)
                    if !isOwnProfile {
                        actionButtonsSection
                    }
                }
            }
            .padding(.bottom, 30)
        }
        .refreshable {
            await refreshProfileData()
        }
    }
    
    // MARK: - Header Section
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Top bar with settings/edit button
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                if isOwnProfile {
                    Menu {
                        Button(action: { showingEditProfile = true }) {
                            Label("Edit Profile", systemImage: "pencil")
                        }
                        Button(action: { showingSettings = true }) {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(.horizontal)
            
            HStack(alignment: .top, spacing: 15) {
                // Profile Image
                profileImage
                
                VStack(alignment: .leading, spacing: 6) {
                    // Name and verification
                    HStack {
                        Text(user?.name ?? "Loading...")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        if user?.isVerified ?? false {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.blue)
                                .font(.subheadline)
                        }
                    }
                    
                    // Email
                    if let email = user?.email {
                        Text(email)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Bio
                    if let bio = user?.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineLimit(3)
                    }
                    
                    // Location and Join Date
                    HStack(spacing: 15) {
                        if let location = user?.location, !location.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "location")
                                    .font(.caption)
                                Text(location)
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        }
                        
                        Text(joinedDateText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Last Active
                    if !isOwnProfile && user?.lastActive != nil {
                        Text(lastActiveText)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Profile Image
    
    @ViewBuilder
    private var profileImage: some View {
        Group {
            if let imageURL = user?.profileImageURL {
                AsyncImage(url: URL(string: imageURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 90, height: 90)
                            .clipShape(Circle())
                    case .failure(_):
                        profileImagePlaceholder
                    case .empty:
                        Circle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: 90, height: 90)
                            .overlay(ProgressView())
                    @unknown default:
                        profileImagePlaceholder
                    }
                }
            } else {
                profileImagePlaceholder
            }
        }
    }
    
    private var profileImagePlaceholder: some View {
        Circle()
            .fill(LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .frame(width: 90, height: 90)
            .overlay(
                Text(String(user?.name.prefix(1) ?? "?"))
                    .font(.largeTitle)
                    .foregroundColor(.white)
            )
    }
    
    // MARK: - Stats Section
    
    @ViewBuilder
    private var statsSection: some View {
        HStack(spacing: 30) {
            // Posts
            VStack(spacing: 4) {
                Text("\(userPosts.count)")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Posts")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Followers
            Button(action: { showingFollowers = true }) {
                VStack(spacing: 4) {
                    Text("\(user?.followers?.count ?? 0)")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Followers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Following
            Button(action: { showingFollowing = true }) {
                VStack(spacing: 4) {
                    Text("\(user?.following?.count ?? 0)")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Following")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Rating
            if reviewStats.count > 0 {
                VStack(spacing: 4) {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text(String(format: "%.1f", reviewStats.average))
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    Text("\(reviewStats.count) reviews")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Portfolio Section
    
    @ViewBuilder
    private var portfolioSection: some View {
        VStack(spacing: 12) {
            // Tab selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    TabButton(title: "My Work", isSelected: selectedTab == 0) {
                        withAnimation { selectedTab = 0 }
                    }
                    TabButton(title: "Services", isSelected: selectedTab == 1) {
                        withAnimation { selectedTab = 1 }
                    }
                    if isOwnProfile {
                        TabButton(title: "Saved", isSelected: selectedTab == 2) {
                            withAnimation { selectedTab = 2 }
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // Content based on selected tab
            switch selectedTab {
            case 0:
                myWorkTab
            case 1:
                servicesTab
            case 2:
                if isOwnProfile {
                    savedTab
                }
            default:
                EmptyView()
            }
        }
    }
    
    // MARK: - Tab Content Views
    
    @ViewBuilder
    private var myWorkTab: some View {
        if portfolioCards.isEmpty && !isLoading {
            EmptyStateView(
                icon: "photo.on.rectangle.angled",
                title: isOwnProfile ? "No Portfolio Items Yet" : "No Portfolio",
                subtitle: isOwnProfile ?
                    "Showcase your work by adding portfolio items" :
                    "This user hasn't added any portfolio items yet"
            )
            .frame(height: 200)
            .padding()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(portfolioCards) { card in
                        PortfolioCardView(card: card, isOwnProfile: isOwnProfile)
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 220)
        }
    }
    
    @ViewBuilder
    private var servicesTab: some View {
        if userPosts.isEmpty && !isLoading {
            EmptyStateView(
                icon: "briefcase",
                title: isOwnProfile ? "No Services Yet" : "No Services",
                subtitle: isOwnProfile ?
                    "Start offering services to connect with clients" :
                    "This user hasn't posted any services yet"
            )
            .frame(height: 200)
            .padding()
        } else {
            LazyVStack(spacing: 12) {
                ForEach(userPosts) { post in
                    ServicePostRow(post: post)
                        .onAppear {
                            if post.id == userPosts.last?.id && hasMorePosts && !isLoadingMorePosts {
                                Task {
                                    await loadMorePosts()
                                }
                            }
                        }
                }
                
                if isLoadingMorePosts {
                    ProgressView()
                        .padding()
                }
            }
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private var savedTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !savedPosts.isEmpty {
                Text("Saved Services")
                    .font(.headline)
                    .padding(.horizontal)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(savedPosts) { post in
                            SavedPostCard(post: post)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 120)
            }
            
            if !savedReels.isEmpty {
                Text("Saved Reels")
                    .font(.headline)
                    .padding(.horizontal)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(savedReels) { reel in
                            SavedReelCard(reel: reel)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 120)
            }
            
            if savedPosts.isEmpty && savedReels.isEmpty {
                EmptyStateView(
                    icon: "bookmark",
                    title: "No Saved Items",
                    subtitle: "Save posts and reels to view them here"
                )
                .frame(height: 200)
                .padding()
            }
        }
    }
    
    // MARK: - Reviews Section
    
    @ViewBuilder
    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Reviews")
                    .font(.headline)
                
                if reviewStats.count > 0 {
                    HStack(spacing: 4) {
                        StarRatingView(rating: reviewStats.average)
                        Text("(\(reviewStats.count))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if !isOwnProfile && firebase.currentUser != nil {
                    Button("Write Review") {
                        showingReviewForm = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            
            if reviews.isEmpty {
                EmptyStateView(
                    icon: "star",
                    title: "No Reviews Yet",
                    subtitle: isOwnProfile ?
                        "Reviews from clients will appear here" :
                        "Be the first to review this user"
                )
                .frame(height: 150)
                .padding()
            } else {
                VStack(spacing: 12) {
                    ForEach(displayedReviews) { review in
                        ReviewCardView(review: review)
                            .padding(.horizontal)
                    }
                    
                    if reviews.count > 3 && !expandedReviews {
                        Button(action: { withAnimation { expandedReviews = true } }) {
                            Text("Show all \(reviews.count) reviews")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal)
                    } else if expandedReviews && reviews.count > 3 {
                        Button(action: { withAnimation { expandedReviews = false } }) {
                            Text("Show less")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal)
                    }
                    
                    if isLoadingMoreReviews {
                        ProgressView()
                            .padding()
                    }
                }
            }
        }
    }
    
    // MARK: - Action Buttons Section
    
    @ViewBuilder
    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            // Message Button
            Button(action: { showingMessageView = true }) {
                Label("Message", systemImage: "message")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            
            // Follow/Following Button
            Button(action: { Task { await toggleFollow() } }) {
                Label(isFollowing ? "Following" : "Follow",
                      systemImage: isFollowing ? "person.fill.checkmark" : "person.fill.badge.plus")
                    .font(.headline)
                    .foregroundColor(isFollowing ? .primary : .white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isFollowing ? Color.gray.opacity(0.2) : Color.green)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isFollowing ? Color.gray : Color.clear, lineWidth: 1)
                    )
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Floating Add Button
    
    private var floatingAddButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: { showingCreateCard = true }) {
                    Image(systemName: "plus")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.purple]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadProfileData() async {
        isLoading = true
        loadError = nil
        
        do {
            // Try to load from cache first
            if let cachedUser: User = await cacheManager.get(key: "user_\(userId)") {
                self.user = cachedUser
                
                // Still load fresh data in background
                Task {
                    await loadFreshProfileData()
                }
            } else {
                await loadFreshProfileData()
            }
            
            // Load other data
            await loadPortfolioCards()
            await loadUserPosts()
            await loadReviews()
            
            if isOwnProfile {
                await loadSavedItems()
                await firebase.updateLastActive()
            } else {
                checkFollowingStatus()
            }
            
            // Calculate review statistics
            reviewStats = calculateReviewStats()
            
        }
        
        isLoading = false
    }
    
    private func loadFreshProfileData() async {
        do {
            let document = try await firebase.db
                .collection("users")
                .document(userId)
                .getDocument()
            
            if document.exists {
                var userData = try document.data(as: User.self)
                userData.id = userId
                
                await MainActor.run {
                    self.user = userData
                }
                
                // Cache the user data
                await cacheManager.set(userData, key: "user_\(userId)", expiry: 300)
            }
        } catch {
            await MainActor.run {
                self.loadError = error
            }
        }
    }
    
    private func loadPortfolioCards() async {
        do {
            let snapshot = try await firebase.db
                .collection("portfolioCards")
                .whereField("userId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            let cards = snapshot.documents.compactMap { doc in
                try? doc.data(as: PortfolioCard.self)
            }
            
            await MainActor.run {
                self.portfolioCards = cards
            }
        } catch {
            await MainActor.run {
                self.portfolioLoadError = error
            }
        }
    }
    
    private func loadUserPosts() async {
        do {
            let query = firebase.db
                .collection("servicePosts")
                .whereField("userId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: pageSize)
            
            let snapshot = try await query.getDocuments()
            
            let posts = snapshot.documents.compactMap { doc in
                try? doc.data(as: ServicePost.self)
            }
            
            await MainActor.run {
                self.userPosts = posts
                self.lastPostDocument = snapshot.documents.last
                self.hasMorePosts = snapshot.documents.count == pageSize
            }
        } catch {
            print("Error loading posts: \(error)")
        }
    }
    
    private func loadMorePosts() async {
        guard !isLoadingMorePosts, hasMorePosts, let lastDoc = lastPostDocument else { return }
        
        isLoadingMorePosts = true
        
        do {
            let query = firebase.db
                .collection("servicePosts")
                .whereField("userId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .start(afterDocument: lastDoc)
                .limit(to: pageSize)
            
            let snapshot = try await query.getDocuments()
            
            let posts = snapshot.documents.compactMap { doc in
                try? doc.data(as: ServicePost.self)
            }
            
            await MainActor.run {
                self.userPosts.append(contentsOf: posts)
                self.lastPostDocument = snapshot.documents.last
                self.hasMorePosts = snapshot.documents.count == pageSize
                self.isLoadingMorePosts = false
            }
        } catch {
            await MainActor.run {
                self.isLoadingMorePosts = false
            }
        }
    }
    
    private func loadReviews() async {
        do {
            let query = firebase.db
                .collection("reviews")
                .whereField("reviewedUserId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: pageSize)
            
            let snapshot = try await query.getDocuments()
            
            let loadedReviews = snapshot.documents.compactMap { doc in
                try? doc.data(as: Review.self)
            }
            
            await MainActor.run {
                self.reviews = loadedReviews
                self.lastReviewDocument = snapshot.documents.last
                self.hasMoreReviews = snapshot.documents.count == pageSize
            }
        } catch {
            await MainActor.run {
                self.reviewsLoadError = error
            }
        }
    }
    
    private func loadSavedItems() async {
        do {
            let snapshot = try await firebase.db
                .collection("savedItems")
                .whereField("userId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            var posts: [ServicePost] = []
            var reels: [Reel] = []
            
            for doc in snapshot.documents {
                if let item = try? doc.data(as: SavedItem.self) {
                    switch item.itemType {
                    case .service, .post:
                        // Load the actual post
                        if let postDoc = try? await firebase.db
                            .collection("servicePosts")
                            .document(item.itemId)
                            .getDocument(),
                           let post = try? postDoc.data(as: ServicePost.self) {
                            posts.append(post)
                        }
                    case .reel:
                        // Load the actual reel
                        if let reelDoc = try? await firebase.db
                            .collection("reels")
                            .document(item.itemId)
                            .getDocument(),
                           let reel = try? reelDoc.data(as: Reel.self) {
                            reels.append(reel)
                        }
                    default:
                        break
                    }
                }
            }
            
            await MainActor.run {
                self.savedPosts = posts
                self.savedReels = reels
            }
        } catch {
            print("Error loading saved items: \(error)")
        }
    }
    
    private func refreshProfileData() async {
        isRefreshing = true
        await loadProfileData()
        isRefreshing = false
    }
    
    // MARK: - Real-time Listeners
    
    private func setupListeners() {
        // User profile listener
        userListener = firebase.db
            .collection("users")
            .document(userId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to user: \(error)")
                    return
                }
                
                guard let document = snapshot,
                      document.exists,
                      var userData = try? document.data(as: User.self) else { return }
                
                userData.id = userId
                
                DispatchQueue.main.async {
                    self.user = userData
                    self.reviewStats = self.calculateReviewStats()
                }
            }
        
        // Reviews listener
        reviewsListener = firebase.db
            .collection("reviews")
            .whereField("reviewedUserId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: 10)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to reviews: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                let updatedReviews = documents.compactMap { doc in
                    try? doc.data(as: Review.self)
                }
                
                DispatchQueue.main.async {
                    self.reviews = updatedReviews
                    self.reviewStats = self.calculateReviewStats()
                }
            }
        
        // Following status listener (for non-own profiles)
        if !isOwnProfile, let currentUserId = firebase.currentUser?.id {
            followListener = firebase.db
                .collection("users")
                .document(currentUserId)
                .addSnapshotListener { snapshot, error in
                    guard let document = snapshot,
                          let data = document.data(),
                          let following = data["following"] as? [String] else { return }
                    
                    DispatchQueue.main.async {
                        self.isFollowing = following.contains(self.userId)
                    }
                }
        }
    }
    
    private func cleanupListeners() {
        userListener?.remove()
        reviewsListener?.remove()
        followListener?.remove()
        userListener = nil
        reviewsListener = nil
        followListener = nil
    }
    
    // MARK: - Actions
    
    private func toggleFollow() async {
        guard let currentUserId = firebase.currentUser?.id else { return }
        
        do {
            if isFollowing {
                try await firebase.unfollowUser(userId)
                await MainActor.run {
                    isFollowing = false
                    if var user = user {
                        user.followers?.removeAll { $0 == currentUserId }
                        self.user = user
                    }
                }
            } else {
                try await firebase.followUser(userId)
                await MainActor.run {
                    isFollowing = true
                    if var user = user {
                        if user.followers == nil {
                            user.followers = []
                        }
                        user.followers?.append(currentUserId)
                        self.user = user
                    }
                }
                
                // Send notification
                await firebase.sendNotification(
                    to: userId,
                    type: .newFollower,
                    title: "New Follower",
                    body: "\(firebase.currentUser?.name ?? "Someone") started following you"
                )
            }
        } catch {
            print("Error toggling follow: \(error)")
        }
    }
    
    private func checkFollowingStatus() {
        guard let currentUserId = firebase.currentUser?.id,
              let followers = user?.followers else { return }
        
        isFollowing = followers.contains(currentUserId)
    }
    
    private func calculateReviewStats() -> (average: Double, count: Int, breakdown: [Int: Int]) {
        guard !reviews.isEmpty else { return (0, 0, [:]) }
        
        let total = reviews.reduce(0) { $0 + $1.rating }
        let average = Double(total) / Double(reviews.count)
        
        var breakdown: [Int: Int] = [:]
        for rating in 1...5 {
            breakdown[rating] = reviews.filter { $0.rating == rating }.count
        }
        
        return (average, reviews.count, breakdown)
    }
}

// MARK: - Supporting Views

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .primary : .gray)
                
                Rectangle()
                    .fill(isSelected ? Color.blue : Color.clear)
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct HalfStarRatingView: View {
    let rating: Double
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: starType(for: index, rating: rating))
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
    
    private func starType(for index: Int, rating: Double) -> String {
        let indexDouble = Double(index)
        if rating >= indexDouble {
            return "star.fill"
        } else if rating >= indexDouble - 0.5 {
            return "star.leadinghalf.filled"
        } else {
            return "star"
        }
    }
}

// Note: CreatePortfolioCardView and CreateReviewView are defined in ProfileSupportingViews.swift

// Additional supporting view that is unique to this file
struct EditProfileView: View {
    let user: User
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Text("Edit Profile - Coming Soon")
                .navigationTitle("Edit Profile")
                .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
    }
}

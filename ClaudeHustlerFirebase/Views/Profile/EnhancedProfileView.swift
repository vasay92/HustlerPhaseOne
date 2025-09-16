// EnhancedProfileView.swift
import SwiftUI
import FirebaseFirestore

struct EnhancedProfileView: View {
    let userId: String
    @StateObject private var firebase = FirebaseService.shared
    @State private var user: User?
    @State private var portfolioCards: [PortfolioCard] = []
    @State private var reviews: [Review] = []
    @State private var savedReels: [Reel] = []
    @State private var savedPosts: [ServicePost] = []
    @State private var userPosts: [ServicePost] = []
    @State private var isFollowing = false
    @State private var selectedTab = 0
    @State private var showingFollowers = false
    @State private var showingFollowing = false
    @State private var showingSettings = false
    @State private var showingCreateCard = false
    @State private var showingReviewForm = false
    @State private var expandedReviews = false
    @State private var showingMessageView = false
    @Environment(\.dismiss) var dismiss
    
    // Real-time review listener
    @State private var reviewsListener: ListenerRegistration?
    @State private var isRefreshingReviews = false
    @State private var reviewStats: (average: Double, count: Int, breakdown: [Int: Int]) = (0, 0, [:])
    
    var isOwnProfile: Bool {
        userId == firebase.currentUser?.id
    }
    
    var lastActiveText: String {
        guard let lastActive = user?.lastActive else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
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
                ScrollView {
                    VStack(spacing: 20) {
                        // Header Section - Now at the very top
                        headerSection
                            .padding(.top, 10)
                        
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
                    .padding(.bottom, 30)
                }
                .refreshable {
                    await refreshProfileData()
                }
                
                // Floating Add Button for Portfolio (only on My Work tab)
                if isOwnProfile && selectedTab == 0 {
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
                                    .background(Color.blue)
                                    .clipShape(Circle())
                                    .shadow(radius: 4)
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .task {
                await loadProfileData()
                if !isOwnProfile {
                    checkFollowingStatus()
                }
            }
            .onDisappear {
                // Clean up listener when view disappears
                reviewsListener?.remove()
                reviewsListener = nil
                firebase.stopListeningToReviews(for: userId)
                
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
            .fullScreenCover(isPresented: $showingMessageView) {
                ChatView(
                    recipientId: userId,
                    isFromContentView: false
                )
            }
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Settings button for own profile
            if isOwnProfile {
                HStack {
                    Spacer()
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal)
            }
            
            HStack(alignment: .top, spacing: 15) {
                // Profile Image
                if let imageURL = user?.profileImageURL {
                    AsyncImage(url: URL(string: imageURL)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                    } placeholder: {
                        profileImagePlaceholder
                    }
                } else {
                    profileImagePlaceholder
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    // Name
                    Text(user?.name ?? "Loading...")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    // Rating with enhanced display
                    HStack(spacing: 4) {
                        if reviewStats.count > 0 {
                            HalfStarRatingView(rating: reviewStats.average)
                            Text(String(format: "%.1f", reviewStats.average))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("(\(reviewStats.count) reviews)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("No ratings yet")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onTapGesture {
                        if !reviews.isEmpty {
                            withAnimation {
                                expandedReviews = true
                            }
                        }
                    }
                    
                    // Joined & Last Active
                    VStack(alignment: .leading, spacing: 2) {
                        Text(joinedDateText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if !isOwnProfile {
                            Text(lastActiveText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private var statsSection: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 0) {
                // Services
                VStack(spacing: 4) {
                    Text("\(user?.completedServices ?? 0)")
                        .font(.headline)
                    Text("Services")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                Divider()
                    .frame(height: 40)
                
                // Times Booked
                VStack(spacing: 4) {
                    Text("\(user?.timesBooked ?? 0)")
                        .font(.headline)
                    Text("Booked")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                Divider()
                    .frame(height: 40)
                
                // Followers
                Button(action: { showingFollowers = true }) {
                    VStack(spacing: 4) {
                        Text("\(user?.followers.count ?? 0)")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Followers")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                
                Divider()
                    .frame(height: 40)
                
                // Following
                Button(action: { showingFollowing = true }) {
                    VStack(spacing: 4) {
                        Text("\(user?.following.count ?? 0)")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Following")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12)
            
            Divider()
        }
    }
    
    @ViewBuilder
    private var portfolioSection: some View {
        VStack(spacing: 0) {
            // Tab Selector
            HStack(spacing: 0) {
                TabButton(title: "My Work", isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                
                TabButton(title: "My Posts", isSelected: selectedTab == 1) {
                    selectedTab = 1
                }
                
                // These tabs only show for own profile
                if isOwnProfile {
                    TabButton(title: "Saved Reels", isSelected: selectedTab == 2) {
                        selectedTab = 2
                    }
                    
                    TabButton(title: "Saved Posts", isSelected: selectedTab == 3) {
                        selectedTab = 3
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)
            
            // Content based on selected tab
            if selectedTab == 0 {
                // My Work (Portfolio Cards)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(portfolioCards) { card in
                            PortfolioCardView(card: card, isOwner: isOwnProfile)
                        }
                        
                        if portfolioCards.isEmpty && isOwnProfile {
                            Text("Tap + to add your work")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 20)
                        } else if portfolioCards.isEmpty && !isOwnProfile {
                            Text("No portfolio items yet")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
            } else if selectedTab == 1 {
                // My Posts
                if userPosts.isEmpty {
                    EmptyStateView(
                        icon: "briefcase",
                        title: "No Posts Yet",
                        subtitle: isOwnProfile ? "Your service offers and requests will appear here" : "No services posted yet"
                    )
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(userPosts) { post in
                            NavigationLink(destination: PostDetailView(post: post)) {
                                UserPostCard(post: post)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
            } else if selectedTab == 2 && isOwnProfile {
                // Saved Reels
                if savedReels.isEmpty {
                    EmptyStateView(
                        icon: "bookmark",
                        title: "No Saved Reels",
                        subtitle: "Reels you save will appear here"
                    )
                    .padding(.vertical, 40)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 2) {
                        ForEach(savedReels) { reel in
                            SavedReelThumbnail(reel: reel)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 10)
                }
            } else if selectedTab == 3 && isOwnProfile {
                // Saved Posts
                if savedPosts.isEmpty {
                    EmptyStateView(
                        icon: "bookmark",
                        title: "No Saved Posts",
                        subtitle: "Posts you save will appear here"
                    )
                    .padding(.vertical, 40)
                } else {
                    VStack(spacing: 10) {
                        ForEach(savedPosts) { post in
                            SavedPostCard(post: post)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
            }
        }
    }
    
    @ViewBuilder
    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reviews")
                        .font(.headline)
                    
                    // Rating breakdown
                    if reviewStats.count > 0 {
                        HStack(spacing: 4) {
                            HalfStarRatingView(rating: reviewStats.average)
                            Text(String(format: "%.1f", reviewStats.average))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("(\(reviewStats.count))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                if !isOwnProfile {
                    Button(action: { showingReviewForm = true }) {
                        Label("Write Review", systemImage: "square.and.pencil")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal)
            
            // Rating breakdown bars
            if reviewStats.count > 0 {
                VStack(spacing: 4) {
                    ForEach((1...5).reversed(), id: \.self) { rating in
                        HStack(spacing: 8) {
                            Text("\(rating)")
                                .font(.caption)
                                .frame(width: 15)
                            
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 8)
                                    
                                    let percentage = CGFloat(reviewStats.breakdown[rating] ?? 0) / CGFloat(reviewStats.count)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.orange)
                                        .frame(width: geometry.size.width * percentage, height: 8)
                                        .animation(.easeInOut(duration: 0.3), value: percentage)
                                }
                            }
                            .frame(height: 8)
                            
                            Text("\(reviewStats.breakdown[rating] ?? 0)")
                                .font(.caption)
                                .frame(width: 30, alignment: .trailing)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            
            if reviews.isEmpty {
                EmptyStateView(
                    icon: "star",
                    title: "No Reviews Yet",
                    subtitle: isOwnProfile ? "Reviews from customers will appear here" : "Be the first to leave a review"
                )
                .padding(.vertical, 30)
            } else {
                VStack(spacing: 12) {
                    ForEach(displayedReviews) { review in
                        ReviewCard(review: review, isProfileOwner: isOwnProfile)
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            ))
                    }
                    
                    if reviews.count > 3 && !expandedReviews {
                        Button(action: {
                            withAnimation {
                                expandedReviews = true
                            }
                        }) {
                            Text("Show All Reviews (\(reviews.count))")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                    } else if expandedReviews && reviews.count > 3 {
                        Button(action: {
                            withAnimation {
                                expandedReviews = false
                            }
                        }) {
                            Text("Show Less")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // Pull to refresh indicator
            if isRefreshingReviews {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
    }
    
    @ViewBuilder
    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            Button(action: {
                showingMessageView = true
            }) {
                Label("Message", systemImage: "message.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            
            Button(action: { toggleFollow() }) {
                Label(isFollowing ? "Following" : "Follow", systemImage: isFollowing ? "person.fill.checkmark" : "person.fill.badge.plus")
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
    
    var profileImagePlaceholder: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 80, height: 80)
            .overlay(
                Text(String(user?.name.first ?? "U"))
                    .font(.largeTitle)
                    .foregroundColor(.white)
            )
    }
    
    // MARK: - Helper Methods
    
    private func loadProfileData() async {
        print("Loading profile for userId: \(userId)")
        print("Current user ID: \(firebase.currentUser?.id ?? "nil")")
        print("Is own profile: \(isOwnProfile)")
        
        if isOwnProfile {
            await firebase.updateLastActive()
        }
        
        // Load user data
        do {
            let document = try await Firestore.firestore()
                .collection("users")
                .document(userId)
                .getDocument()
            
            if document.exists {
                user = try? document.data(as: User.self)
                user?.id = userId
            }
        } catch {
            print("Error loading user profile: \(error)")
        }
        
        // Load portfolio cards
        portfolioCards = await firebase.loadPortfolioCards(for: userId)
        
        // Load user's posts
        userPosts = await firebase.loadUserPosts(for: userId)
        
        // Start listening to reviews with real-time updates
        startListeningToReviews()
        
        // Load review stats
        reviewStats = await firebase.getReviewStats(for: userId)
        
        // Load saved items if own profile
        if isOwnProfile {
            savedReels = await firebase.loadSavedReels()
            savedPosts = await firebase.loadSavedPosts()
        }
    }
    
    private func refreshProfileData() async {
        isRefreshingReviews = true
        
        // Reload all data
        await loadProfileData()
        
        // Small delay for better UX
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        isRefreshingReviews = false
    }
    
    private func startListeningToReviews() {
        // Remove any existing listener
        reviewsListener?.remove()
        
        // Start new listener
        reviewsListener = firebase.listenToReviews(for: userId) { updatedReviews in
            withAnimation(.easeInOut(duration: 0.3)) {
                self.reviews = updatedReviews
            }
            
            // Update stats when reviews change
            Task {
                self.reviewStats = await firebase.getReviewStats(for: userId)
                
                // Update user rating display if available
                if let updatedUser = try? await Firestore.firestore()
                    .collection("users")
                    .document(userId)
                    .getDocument()
                    .data(as: User.self) {
                    self.user = updatedUser
                    self.user?.id = userId
                }
            }
        }
    }
    
    private func checkFollowingStatus() {
        isFollowing = firebase.isFollowing(userId: userId)
    }
    
    private func toggleFollow() {
        Task {
            do {
                if isFollowing {
                    try await firebase.unfollowUser(userId)
                } else {
                    try await firebase.followUser(userId)
                }
                isFollowing.toggle()
                await loadProfileData()
            } catch {
                print("Error toggling follow: \(error)")
            }
        }
    }
}

// MARK: - User Post Card View
struct UserPostCard: View {
    let post: ServicePost
    
    var body: some View {
        HStack(spacing: 12) {
            // Image or placeholder
            if !post.mediaURLs.isEmpty, let firstImageURL = post.mediaURLs.first {
                AsyncImage(url: URL(string: firstImageURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipped()
                            .cornerRadius(10)
                    case .failure(_):
                        imagePlaceholder
                    case .empty:
                        ZStack {
                            imagePlaceholder
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                    @unknown default:
                        imagePlaceholder
                    }
                }
            } else {
                imagePlaceholder
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(post.title)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // Request/Offer Badge
                    Text(post.isRequest ? "REQUEST" : "OFFER")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(post.isRequest ? Color.orange : Color.blue)
                        .cornerRadius(4)
                }
                
                Text(post.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    // Category
                    Text(post.category.displayName)
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    if let price = post.price {
                        Text("•")
                            .foregroundColor(.gray)
                        Text(post.isRequest ? "Budget: $\(Int(price))" : "$\(Int(price))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(post.isRequest ? .orange : .green)
                    }
                    
                    Spacer()
                    
                    Text(post.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    var imagePlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: post.isRequest
                        ? [Color.orange.opacity(0.3), Color.red.opacity(0.3)]
                        : [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 80, height: 80)
            .cornerRadius(10)
            .overlay(
                Image(systemName: "briefcase.fill")
                    .foregroundColor(.white)
            )
    }
}

// MARK: - Supporting Views

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
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

struct StarRatingView: View {
    let rating: Double
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: index <= Int(rating.rounded()) ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
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

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(.gray)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

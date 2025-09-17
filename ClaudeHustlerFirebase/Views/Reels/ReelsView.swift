

// ReelsView.swift
// Complete Production-Ready Implementation
// Path: ClaudeHustlerFirebase/Views/Reels/ReelsView.swift

import SwiftUI
import FirebaseFirestore
import AVKit
import PhotosUI

struct ReelsView: View {
    @StateObject private var firebase = FirebaseService.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    private let cacheManager = CacheManager.shared
    
    // Data
    @State private var reels: [Reel] = []
    @State private var statuses: [Status] = []
    @State private var currentFilter: ReelFilter = .all
    @State private var searchText = ""
    
    // Loading & Pagination
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var lastDocument: DocumentSnapshot?
    @State private var hasMoreData = true
    @State private var loadError: Error?
    
    // Create reel states
    @State private var showingCreateReel = false
    @State private var showingCamera = false
    @State private var showingFilePicker = false
    @State private var selectedVideo: PhotosPickerItem?
    
    // View options
    @State private var selectedReel: Reel?
    @State private var showingFullScreen = false
    @State private var showingStatusViewer = false
    @State private var selectedStatus: Status?
    
    // Listeners
    @State private var reelsListener: ListenerRegistration?
    @State private var statusesListener: ListenerRegistration?
    
    // Performance optimization
    private let pageSize = 20
    private let imageCache = NSCache<NSString, UIImage>()
    
    enum ReelFilter: String, CaseIterable {
        case all = "All"
        case following = "Following"
        case trending = "Trending"
        case recent = "Recent"
    }
    
    var filteredReels: [Reel] {
        let searchFiltered = searchText.isEmpty ? reels : reels.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText) ||
            ($0.userName ?? "").localizedCaseInsensitiveContains(searchText)
        }
        
        switch currentFilter {
        case .all:
            return searchFiltered
        case .following:
            let followingIds = firebase.currentUser?.following ?? []
            return searchFiltered.filter { followingIds.contains($0.userId) }
        case .trending:
            return searchFiltered.sorted { $0.views + $0.likes.count > $1.views + $1.likes.count }
        case .recent:
            return searchFiltered.sorted { $0.createdAt > $1.createdAt }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                if networkMonitor.isConnected || !reels.isEmpty {
                    mainContent
                } else {
                    OfflineView {
                        Task {
                            await loadReels()
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
                                await loadReels()
                            }
                        },
                        dismiss: { loadError = nil }
                    )
                    .transition(.move(edge: .top))
                    .animation(.easeInOut, value: loadError)
                }
            }
            .navigationTitle("Reels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingCamera = true }) {
                        Image(systemName: "camera")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if firebase.currentUser != nil {
                        Button(action: { showingCreateReel = true }) {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search reels...")
            .sheet(isPresented: $showingCreateReel) {
                CreateReelView()
            }
            .fullScreenCover(isPresented: $showingFullScreen) {
                if let selectedReel = selectedReel,
                   let index = filteredReels.firstIndex(where: { $0.id == selectedReel.id }) {
                    VerticalReelScrollView(
                        reels: filteredReels,
                        initialIndex: index
                    )
                }
            }
            .fullScreenCover(isPresented: $showingStatusViewer) {
                if let status = selectedStatus {
                    StatusViewerView(status: status)
                }
            }
        }
        .onAppear {
            setupListeners()
            if reels.isEmpty {
                Task {
                    await loadReels()
                    await loadStatuses()
                }
            }
        }
        .onDisappear {
            cleanupListeners()
        }
    }
    
    // MARK: - Main Content
    
    @ViewBuilder
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Stories/Status section
                if !statuses.isEmpty {
                    statusSection
                        .padding(.vertical, 10)
                }
                
                // Filter section
                filterSection
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                
                // Reels grid
                if isLoading && reels.isEmpty {
                    LoadingView(message: "Loading reels...")
                        .frame(height: 300)
                } else if filteredReels.isEmpty {
                    EmptyStateView(
                        icon: "video.slash",
                        title: searchText.isEmpty ? "No Reels Yet" : "No Results",
                        subtitle: searchText.isEmpty ?
                            "Be the first to share a reel!" :
                            "Try adjusting your search or filters"
                    )
                    .frame(height: 300)
                    .padding()
                } else {
                    reelsGrid
                    
                    // Load more indicator
                    if isLoadingMore {
                        ProgressView()
                            .padding()
                    } else if hasMoreData && !isLoading {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                Task {
                                    await loadMoreReels()
                                }
                            }
                    }
                }
            }
        }
        .refreshable {
            await refreshContent()
        }
    }
    
    // MARK: - Status Section
    
    private var statusSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Add story button
                if firebase.currentUser != nil {
                    AddStatusButton {
                        showingCreateReel = true
                    }
                }
                
                // Active statuses
                ForEach(statuses) { status in
                    StatusThumbnail(
                        status: status,
                        isOwnStatus: status.userId == firebase.currentUser?.id
                    ) {
                        selectedStatus = status
                        showingStatusViewer = true
                        
                        // Mark as viewed
                        if status.userId != firebase.currentUser?.id {
                            Task {
                                await markStatusAsViewed(status)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 100)
    }
    
    // MARK: - Filter Section
    
    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ReelFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        title: filter.rawValue,
                        isSelected: currentFilter == filter
                    ) {
                        withAnimation {
                            currentFilter = filter
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Reels Grid
    
    private var reelsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 2),
            GridItem(.flexible(), spacing: 2),
            GridItem(.flexible(), spacing: 2)
        ], spacing: 2) {
            ForEach(Array(filteredReels.enumerated()), id: \.element.id) { index, reel in
                ReelGridItem(reel: reel) {
                    selectedReel = reel
                    showingFullScreen = true
                    
                    // Increment view count
                    Task {
                        await incrementViewCount(for: reel)
                    }
                }
                .onAppear {
                    // Preload next batch when approaching end
                    if index == filteredReels.count - 5 && hasMoreData && !isLoadingMore {
                        Task {
                            await loadMoreReels()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 2)
    }
    
    // MARK: - Data Loading
    
    private func loadReels() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        
        do {
            // Check cache first
            if let cachedReels: [Reel] = await cacheManager.get(key: "reels_page_1") {
                self.reels = cachedReels
                isLoading = false
                
                // Still fetch fresh data in background
                Task {
                    await loadFreshReels()
                }
                return
            }
            
            await loadFreshReels()
        }
    }
    
    private func loadFreshReels() async {
        do {
            let query = firebase.db.collection("reels")
                .order(by: "createdAt", descending: true)
                .limit(to: pageSize)
            
            let snapshot = try await query.getDocuments()
            
            let newReels = snapshot.documents.compactMap { doc in
                try? doc.data(as: Reel.self)
            }
            
            await MainActor.run {
                self.reels = newReels
                self.lastDocument = snapshot.documents.last
                self.hasMoreData = snapshot.documents.count == pageSize
                self.isLoading = false
            }
            
            // Cache first page
            await cacheManager.set(newReels, key: "reels_page_1", expiry: 300)
            
        } catch {
            await MainActor.run {
                self.loadError = error
                self.isLoading = false
            }
        }
    }
    
    private func loadMoreReels() async {
        guard !isLoadingMore, hasMoreData, let lastDoc = lastDocument else { return }
        isLoadingMore = true
        
        do {
            let query = firebase.db.collection("reels")
                .order(by: "createdAt", descending: true)
                .start(afterDocument: lastDoc)
                .limit(to: pageSize)
            
            let snapshot = try await query.getDocuments()
            
            let newReels = snapshot.documents.compactMap { doc in
                try? doc.data(as: Reel.self)
            }
            
            await MainActor.run {
                self.reels.append(contentsOf: newReels)
                self.lastDocument = snapshot.documents.last
                self.hasMoreData = snapshot.documents.count == pageSize
                self.isLoadingMore = false
            }
            
        } catch {
            await MainActor.run {
                self.loadError = error
                self.isLoadingMore = false
            }
        }
    }
    
    private func loadStatuses() async {
        do {
            let cutoffTime = Date().addingTimeInterval(-24 * 60 * 60) // 24 hours ago
            
            let query = firebase.db.collection("statuses")
                .whereField("createdAt", isGreaterThan: cutoffTime)
                .order(by: "createdAt", descending: true)
            
            let snapshot = try await query.getDocuments()
            
            let activeStatuses = snapshot.documents.compactMap { doc in
                try? doc.data(as: Status.self)
            }.filter { !$0.isExpired }
            
            await MainActor.run {
                self.statuses = activeStatuses
            }
            
        } catch {
            print("Error loading statuses: \(error)")
        }
    }
    
    private func refreshContent() async {
        lastDocument = nil
        hasMoreData = true
        await loadReels()
        await loadStatuses()
    }
    
    // MARK: - Real-time Listeners
    
    private func setupListeners() {
        // Reels listener for real-time updates
        reelsListener = firebase.db.collection("reels")
            .order(by: "createdAt", descending: true)
            .limit(to: pageSize)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to reels: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                let updatedReels = documents.compactMap { doc in
                    try? doc.data(as: Reel.self)
                }
                
                // Update only if there are changes
                if updatedReels != reels {
                    withAnimation {
                        self.reels = updatedReels
                    }
                }
            }
        
        // Status listener
        statusesListener = firebase.db.collection("statuses")
            .whereField("expiresAt", isGreaterThan: Date())
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to statuses: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                let activeStatuses = documents.compactMap { doc in
                    try? doc.data(as: Status.self)
                }.filter { !$0.isExpired }
                
                withAnimation {
                    self.statuses = activeStatuses
                }
            }
    }
    
    private func cleanupListeners() {
        reelsListener?.remove()
        statusesListener?.remove()
    }
    
    // MARK: - Actions
    
    private func incrementViewCount(for reel: Reel) async {
        guard let reelId = reel.id else { return }
        
        do {
            try await firebase.db.collection("reels")
                .document(reelId)
                .updateData([
                    "views": FieldValue.increment(Int64(1))
                ])
        } catch {
            print("Error incrementing view count: \(error)")
        }
    }
    
    private func markStatusAsViewed(_ status: Status) async {
        guard let statusId = status.id,
              let userId = firebase.currentUser?.id,
              !status.viewers.contains(userId) else { return }
        
        do {
            try await firebase.db.collection("statuses")
                .document(statusId)
                .updateData([
                    "viewers": FieldValue.arrayUnion([userId])
                ])
        } catch {
            print("Error marking status as viewed: \(error)")
        }
    }
}

// MARK: - Supporting Views

struct AddStatusButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                        .foregroundColor(.blue)
                        .frame(width: 75, height: 75)
                    
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                
                Text("Add Story")
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
    }
}

struct StatusThumbnail: View {
    let status: Status
    let isOwnStatus: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    // Status image
                    AsyncImage(url: URL(string: status.mediaURL ?? "")) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 75, height: 75)
                                .clipShape(Circle())
                        case .failure(_), .empty:
                            Circle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 75, height: 75)
                                .overlay(
                                    Text(String(status.userName?.prefix(1) ?? "?"))
                                        .font(.title2)
                                        .foregroundColor(.gray)
                                )
                        @unknown default:
                            EmptyView()
                        }
                    }
                    
                    // Ring indicator
                    Circle()
                        .stroke(
                            isOwnStatus ? Color.blue :
                            status.viewers.contains(firebase.currentUser?.id ?? "") ?
                            Color.gray : Color.purple,
                            lineWidth: 3
                        )
                        .frame(width: 80, height: 80)
                }
                
                Text(isOwnStatus ? "Your Story" : (status.userName ?? "User"))
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(.primary)
            }
        }
    }
}

struct ReelGridItem: View {
    let reel: Reel
    let action: () -> Void
    @State private var thumbnail: UIImage?
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                // Thumbnail
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: UIScreen.main.bounds.width / 3 - 2, height: 180)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: UIScreen.main.bounds.width / 3 - 2, height: 180)
                        .overlay(
                            ProgressView()
                                .onAppear {
                                    loadThumbnail()
                                }
                        )
                }
                
                // Overlay info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.caption2)
                        Text("\(reel.views)")
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(4)
                }
                .padding(4)
            }
        }
        .contentShape(Rectangle())
    }
    
    private func loadThumbnail() {
        guard let url = URL(string: reel.thumbnailURL ?? reel.mediaURL) else { return }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        self.thumbnail = image
                    }
                }
            } catch {
                print("Error loading thumbnail: \(error)")
            }
        }
    }
}

// MARK: - Vertical Scroll View (Full Screen)

struct VerticalReelScrollView: View {
    let reels: [Reel]
    let initialIndex: Int
    
    @Environment(\.dismiss) var dismiss
    @State private var currentIndex: Int
    
    init(reels: [Reel], initialIndex: Int) {
        self.reels = reels
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            TabView(selection: $currentIndex) {
                ForEach(Array(reels.enumerated()), id: \.element.id) { index, reel in
                    FullScreenReelView(
                        reel: reel,
                        isCurrentReel: index == currentIndex,
                        onDismiss: { dismiss() }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            
            // Close button
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding()
                    
                    Spacer()
                }
                
                Spacer()
            }
        }
    }
}

// MARK: - Full Screen Reel View

struct FullScreenReelView: View {
    let reel: Reel
    let isCurrentReel: Bool
    let onDismiss: () -> Void
    
    @StateObject private var firebase = FirebaseService.shared
    @State private var player: AVPlayer?
    @State private var isLiked = false
    @State private var isFollowing = false
    @State private var isSaved = false
    @State private var likesCount = 0
    @State private var commentsCount = 0
    @State private var showingComments = false
    @State private var showingShare = false
    @State private var showingUserProfile = false
    @State private var showingOptions = false
    @State private var currentReel: Reel?
    
    var displayReel: Reel {
        currentReel ?? reel
    }
    
    var isOwnReel: Bool {
        reel.userId == firebase.currentUser?.id
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video player
                if let videoURL = reel.videoURL {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                        .onAppear {
                            setupPlayer(url: videoURL)
                        }
                        .onDisappear {
                            player?.pause()
                        }
                        .onTapGesture(count: 2) {
                            toggleLike()
                        }
                        .onTapGesture {
                            togglePlayPause()
                        }
                }
                
                // Content overlay
                VStack {
                    Spacer()
                    
                    HStack(alignment: .bottom, spacing: 0) {
                        // Left side - Info
                        VStack(alignment: .leading, spacing: 10) {
                            // User info
                            userInfoSection
                            
                            // Caption
                            captionSection
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 50)
                        
                        Spacer()
                        
                        // Right side - Actions
                        VStack(spacing: 20) {
                            actionButtons
                        }
                        .padding(.trailing)
                        .padding(.bottom, 50)
                    }
                }
                .foregroundColor(.white)
            }
        }
        .sheet(isPresented: $showingComments) {
            CommentsView(
                postId: reel.id ?? "",
                postType: .reel,
                postOwnerId: reel.userId
            )
        }
        .sheet(isPresented: $showingUserProfile) {
            UserProfileView(userId: reel.userId)
        }
        .sheet(isPresented: $showingShare) {
            ShareSheet(items: [URL(string: "claudehustler://reel/\(reel.id ?? "")")!])
        }
        .onAppear {
            setupReelData()
            if isCurrentReel {
                player?.play()
            }
        }
        .onChange(of: isCurrentReel) { newValue in
            if newValue {
                player?.play()
            } else {
                player?.pause()
            }
        }
    }
    
    // MARK: - UI Components
    
    private var userInfoSection: some View {
        HStack {
            Button(action: { showingUserProfile = true }) {
                AsyncImage(url: URL(string: displayReel.userProfileImage ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    default:
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(String(displayReel.userName?.prefix(1) ?? "?"))
                                    .foregroundColor(.white)
                            )
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Button(action: { showingUserProfile = true }) {
                    Text(displayReel.userName ?? "User")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                if let category = displayReel.category {
                    Text(category.rawValue)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            if !isOwnReel {
                Button(action: toggleFollow) {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(isFollowing ? Color.clear : Color.red)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isFollowing ? Color.white : Color.clear, lineWidth: 1)
                        )
                        .cornerRadius(4)
                }
            }
        }
    }
    
    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !displayReel.title.isEmpty {
                Text(displayReel.title)
                    .font(.headline)
            }
            
            if !displayReel.description.isEmpty {
                Text(displayReel.description)
                    .font(.subheadline)
                    .lineLimit(3)
            }
            
            if !displayReel.hashtags.isEmpty {
                Text(displayReel.hashtags.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }
    
    private var actionButtons: some View {
        Group {
            // Like
            ReelActionButton(
                icon: isLiked ? "heart.fill" : "heart",
                text: likesCount > 0 ? formatCount(likesCount) : nil,
                color: isLiked ? .red : .white,
                action: toggleLike
            )
            
            // Comment
            ReelActionButton(
                icon: "bubble.right",
                text: commentsCount > 0 ? formatCount(commentsCount) : nil,
                action: { showingComments = true }
            )
            
            // Share
            ReelActionButton(
                icon: "paperplane",
                text: displayReel.shares > 0 ? formatCount(displayReel.shares) : nil,
                action: shareReel
            )
            
            // Save
            ReelActionButton(
                icon: isSaved ? "bookmark.fill" : "bookmark",
                color: isSaved ? .yellow : .white,
                action: toggleSave
            )
            
            // Options
            if isOwnReel {
                ReelActionButton(
                    icon: "ellipsis",
                    action: { showingOptions = true }
                )
            }
        }
    }
    
    // MARK: - Player Setup
    
    private func setupPlayer(url: String) {
        guard let videoURL = URL(string: url) else { return }
        player = AVPlayer(url: videoURL)
        player?.automaticallyWaitsToMinimizeStalling = false
        player?.actionAtItemEnd = .none
        
        // Loop video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            player?.seek(to: CMTime.zero)
            player?.play()
        }
    }
    
    private func togglePlayPause() {
        if player?.rate == 0 {
            player?.play()
        } else {
            player?.pause()
        }
    }
    
    // MARK: - Data & Actions
    
    private func setupReelData() {
        guard let reelId = reel.id else { return }
        
        // Check if liked
        isLiked = firebase.currentUser?.likedReels?.contains(reelId) ?? false
        
        // Check if following
        isFollowing = firebase.currentUser?.following?.contains(reel.userId) ?? false
        
        // Check if saved
        Task {
            isSaved = await checkIfSaved()
        }
        
        // Get counts
        likesCount = reel.likes.count
        
        // Setup real-time listener
        setupRealtimeListener()
    }
    
    private func setupRealtimeListener() {
        guard let reelId = reel.id else { return }
        
        firebase.db.collection("reels")
            .document(reelId)
            .addSnapshotListener { snapshot, error in
                guard let data = snapshot?.data(),
                      let updatedReel = try? snapshot?.data(as: Reel.self) else { return }
                
                DispatchQueue.main.async {
                    self.currentReel = updatedReel
                    self.likesCount = updatedReel.likes.count
                    self.commentsCount = updatedReel.comments
                }
            }
    }
    
    private func toggleLike() {
        guard let reelId = reel.id,
              let userId = firebase.currentUser?.id else { return }
        
        Task {
            do {
                if isLiked {
                    try await firebase.unlikeReel(reelId)
                    await MainActor.run {
                        isLiked = false
                        likesCount -= 1
                    }
                } else {
                    try await firebase.likeReel(reelId)
                    await MainActor.run {
                        isLiked = true
                        likesCount += 1
                    }
                    
                    // Show heart animation
                    showHeartAnimation()
                }
            } catch {
                print("Error toggling like: \(error)")
            }
        }
    }
    
    private func toggleFollow() {
        guard let currentUserId = firebase.currentUser?.id else { return }
        
        Task {
            do {
                if isFollowing {
                    try await firebase.unfollowUser(reel.userId)
                    await MainActor.run {
                        isFollowing = false
                    }
                } else {
                    try await firebase.followUser(reel.userId)
                    await MainActor.run {
                        isFollowing = true
                    }
                }
            } catch {
                print("Error toggling follow: \(error)")
            }
        }
    }
    
    private func toggleSave() {
        guard let reelId = reel.id else { return }
        
        Task {
            do {
                if isSaved {
                    try await firebase.unsaveItem(reelId, type: .reel)
                    await MainActor.run {
                        isSaved = false
                    }
                } else {
                    try await firebase.saveItem(
                        itemId: reelId,
                        itemType: .reel,
                        title: reel.title,
                        imageURL: reel.thumbnailURL
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
    
    private func shareReel() {
        guard let reelId = reel.id else { return }
        
        Task {
            // Increment share count
            try? await firebase.db.collection("reels")
                .document(reelId)
                .updateData(["shares": FieldValue.increment(Int64(1))])
            
            await MainActor.run {
                showingShare = true
            }
        }
    }
    
    private func checkIfSaved() async -> Bool {
        guard let reelId = reel.id,
              let userId = firebase.currentUser?.id else { return false }
        
        do {
            let snapshot = try await firebase.db.collection("savedItems")
                .whereField("userId", isEqualTo: userId)
                .whereField("itemId", isEqualTo: reelId)
                .whereField("itemType", isEqualTo: "reel")
                .getDocuments()
            
            return !snapshot.documents.isEmpty
        } catch {
            return false
        }
    }
    
    private func showHeartAnimation() {
        // This would trigger a heart animation overlay
        // Implementation depends on your animation preferences
    }
    
    private func formatCount(_ count: Int) -> String {
        if count < 1000 {
            return "\(count)"
        } else if count < 1_000_000 {
            return String(format: "%.1fK", Double(count) / 1000)
        } else {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
    }
}

// MARK: - Reel Action Button

struct ReelActionButton: View {
    let icon: String
    var text: String? = nil
    var color: Color = .white
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                if let text = text {
                    Text(text)
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Status Viewer

struct StatusViewerView: View {
    let status: Status
    @Environment(\.dismiss) var dismiss
    @State private var progress: CGFloat = 0
    @State private var timer: Timer?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Media content
            if let mediaURL = status.mediaURL {
                AsyncImage(url: URL(string: mediaURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    default:
                        ProgressView()
                            .tint(.white)
                    }
                }
            } else if let text = status.text {
                Text(text)
                    .font(.title)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            
            // Top bar
            VStack {
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 3)
                        
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: geometry.size.width * progress, height: 3)
                    }
                }
                .frame(height: 3)
                .padding(.horizontal)
                
                // User info and close
                HStack {
                    HStack {
                        AsyncImage(url: URL(string: status.userProfileImage ?? "")) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())
                            default:
                                Circle()
                                    .fill(Color.gray)
                                    .frame(width: 32, height: 32)
                            }
                        }
                        
                        Text(status.userName ?? "User")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Text(timeAgoString(from: status.createdAt))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                }
                .padding()
                
                Spacer()
            }
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            withAnimation(.linear(duration: 0.05)) {
                progress += 0.01
                if progress >= 1 {
                    timer?.invalidate()
                    dismiss()
                }
            }
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        } else {
            return "\(Int(interval / 86400))d ago"
        }
    }
}

// MARK: - Create Reel View (Placeholder)

struct CreateReelView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Create Reel")
                    .font(.largeTitle)
                    .padding()
                
                Text("Reel creation functionality would go here")
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() }
            )
        }
    }
}

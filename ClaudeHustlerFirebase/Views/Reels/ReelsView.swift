// ReelsView.swift
// Path: ClaudeHustlerFirebase/Views/Reels/ReelsView.swift

import SwiftUI
import AVKit
import FirebaseFirestore

struct ReelsView: View {
    @StateObject private var firebase = FirebaseService.shared
    @State private var selectedStatus: Status?
    @State private var showingCreateOptions = false
    @State private var currentReelIndex = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isFullScreenMode = false
    
    let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // Status Section - Now at the very top without "Stories" label
                    statusSection
                    
                    Divider()
                        .padding(.vertical, 10)
                    
                    // Reels Grid Section
                    reelsGridSection
                }
            }
            .navigationBarHidden(true) // Hide the navigation bar completely
        }
        .task {
            await firebase.loadStatusesFromFollowing()
            await firebase.loadReels()
            await firebase.cleanupExpiredStatuses()
        }
        .refreshable {
            await firebase.loadStatusesFromFollowing()
            await firebase.loadReels()
        }
        .sheet(isPresented: $showingCreateOptions) {
            CreateContentOptionsSheet()
        }
        .fullScreenCover(item: $selectedStatus) { status in
            StatusViewerView(status: status)
        }
        .fullScreenCover(isPresented: $isFullScreenMode) {
            VerticalReelScrollView(
                reels: firebase.reels,
                initialIndex: currentReelIndex
            )
        }
    }
    
    // MARK: - Status Section
    @ViewBuilder
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Add Your Story button
                    if firebase.statuses.first(where: { $0.userId == firebase.currentUser?.id }) == nil {
                        AddStatusButton()
                    }
                    
                    // User's own status if exists
                    ForEach(firebase.statuses.filter { $0.userId == firebase.currentUser?.id }) { status in
                        StatusBubble(status: status, isOwnStatus: true) {
                            selectedStatus = status
                        }
                    }
                    
                    // Following users' statuses
                    ForEach(firebase.statuses.filter { $0.userId != firebase.currentUser?.id }) { status in
                        StatusBubble(status: status, isOwnStatus: false) {
                            selectedStatus = status
                        }
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 100)
            .padding(.top, 10)
        }
    }
    
    // MARK: - Reels Grid Section
    @ViewBuilder
    private var reelsGridSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Reels")
                    .font(.headline)
                    .padding(.horizontal)
                
                Spacer()
                
                // Add button for creating content
                Button(action: { showingCreateOptions = true }) {
                    Image(systemName: "plus.square")
                        .font(.title3)
                        .foregroundColor(.primary)
                        .padding(.trailing)
                }
            }
            
            if firebase.reels.isEmpty {
                EmptyReelsPlaceholder()
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(Array(firebase.reels.enumerated()), id: \.element.id) { index, reel in
                        ReelGridItem(reel: reel) {
                            currentReelIndex = index
                            isFullScreenMode = true
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}

// MARK: - Vertical Reel Scroll View (TikTok Style)
struct VerticalReelScrollView: View {
    let reels: [Reel]
    let initialIndex: Int
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var currentIndex: Int
    
    init(reels: [Reel], initialIndex: Int) {
        self.reels = reels
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if !reels.isEmpty {
                // Use regular TabView with page style for horizontal scrolling
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
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .ignoresSafeArea()
                
                // Top overlay with close button
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
                        
                        Text("Reels")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // Placeholder for balance
                        Color.clear
                            .frame(width: 44, height: 44)
                            .padding()
                    }
                    
                    Spacer()
                }
            } else {
                VStack {
                    Text("No reels available")
                        .foregroundColor(.white)
                    
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                }
            }
        }
    }
}

// MARK: - Full Screen Reel View (Individual Reel)
// In ReelsView.swift, replace the FullScreenReelView with this enhanced version:

// MARK: - Full Screen Reel View (Individual Reel)
struct FullScreenReelView: View {
    let reel: Reel
    let isCurrentReel: Bool
    let onDismiss: () -> Void
    
    @State private var isLiked = false
    @State private var isFollowing = false
    @State private var isSaved = false
    @State private var likesCount = 0
    @State private var commentsCount = 0
    @State private var showingUserProfile = false
    @State private var showingComments = false
    @State private var showingLikesList = false
    @State private var showingMessageView = false
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingShareSheet = false
    @State private var isDeleting = false
    
    // Real-time listeners
    @State private var reelListener: ListenerRegistration?
    @State private var currentReel: Reel?
    
    @StateObject private var firebase = FirebaseService.shared
    
    var isOwnReel: Bool {
        reel.userId == firebase.currentUser?.id
    }
    
    var displayReel: Reel {
        currentReel ?? reel
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                // Background image/video
                reelBackgroundContent
                
                // Content overlay
                VStack {
                    Spacer()
                    
                    HStack(alignment: .bottom, spacing: 0) {
                        // Left side - Info
                        VStack(alignment: .leading, spacing: 10) {
                            // User info
                            userInfoSection
                            
                            // Caption - No placeholders
                            if !(displayReel.caption ?? "").isEmpty {
                                captionSection
                            }
                            
                            // Category
                            if let category = displayReel.category {
                                Text("#\(category.displayName)")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .padding(.leading, 16)
                        .padding(.trailing, 8)
                        .padding(.bottom, 30)
                        .frame(maxWidth: geometry.size.width * 0.65)
                        
                        Spacer(minLength: 0)
                        
                        // Right side - Actions
                        actionButtonsSection
                    }
                }
            }
            
            // Loading overlay
            if isDeleting {
                deletingOverlay
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            if isCurrentReel {
                startListeningToReel()
                Task {
                    await checkInitialStates()
                }
            }
        }
        .onDisappear {
            reelListener?.remove()
            if let reelId = reel.id {
                firebase.stopListeningToReel(reelId)
            }
        }
        .onChange(of: isCurrentReel) { _, newValue in
            if newValue {
                startListeningToReel()
                Task {
                    await checkInitialStates()
                }
            } else {
                reelListener?.remove()
                if let reelId = reel.id {
                    firebase.stopListeningToReel(reelId)
                }
            }
        }
        .fullScreenCover(isPresented: $showingUserProfile) {
            NavigationView {
                EnhancedProfileView(userId: displayReel.userId)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Close") {
                                showingUserProfile = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingComments) {
            CommentsView(reelId: reel.id ?? "", reelOwnerId: reel.userId)
        }
        .sheet(isPresented: $showingLikesList) {
            LikesListView(reelId: reel.id ?? "")
        }
        .sheet(isPresented: $showingEditSheet) {
            EditReelCaptionView(reel: displayReel)
        }
        .fullScreenCover(isPresented: $showingMessageView) {
            ChatView(
                recipientId: displayReel.userId,
                contextType: .reel,
                contextId: displayReel.id,
                contextData: (
                    title: displayReel.title.isEmpty ? "Shared a reel" : displayReel.title,
                    image: displayReel.thumbnailURL ?? displayReel.videoURL,
                    userId: displayReel.userId
                ),
                isFromContentView: true
            )
        }
        .confirmationDialog("Delete Reel?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await deleteReel()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. Your reel will be permanently deleted.")
        }
        .sheet(isPresented: $showingShareSheet) {
            ReelShareSheet(items: [
                displayReel.title.isEmpty ? "Check out this reel!" : displayReel.title,
                displayReel.description,
                URL(string: displayReel.thumbnailURL ?? displayReel.videoURL) ?? URL(string: "https://claudehustler.com")!
            ])
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var reelBackgroundContent: some View {
        if let thumbnailURL = displayReel.thumbnailURL {
            AsyncImage(url: URL(string: thumbnailURL)) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        } else {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
    
    @ViewBuilder
    private var userInfoSection: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.white)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(displayReel.userName?.first ?? "U"))
                        .foregroundColor(.black)
                        .fontWeight(.semibold)
                )
            
            Button(action: { showingUserProfile = true }) {
                Text(displayReel.userName ?? "User")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            
            if !isOwnReel {
                Button(action: { toggleFollow() }) {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
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
    
    @ViewBuilder
    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !displayReel.title.isEmpty {
                Text(displayReel.title)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            if !displayReel.description.isEmpty {
                Text(displayReel.description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(3)
            }
        }
    }
    
    @ViewBuilder
    private var actionButtonsSection: some View {
        VStack(spacing: 20) {
            // Like with real-time count
            ReelActionButton(
                icon: isLiked ? "heart.fill" : "heart",
                text: likesCount > 0 ? "\(likesCount)" : nil,
                color: isLiked ? .red : .white,
                action: { toggleLike() },
                onLongPress: likesCount > 0 ? { showingLikesList = true } : nil
            )
            
            // Comment with real-time count
            ReelActionButton(
                icon: "bubble.right",
                text: commentsCount > 0 ? "\(commentsCount)" : nil,
                color: .white,
                action: { showingComments = true }
            )
            
            // Message
            if !isOwnReel {
                ReelActionButton(
                    icon: "message",
                    text: nil,
                    color: .white,
                    action: { showingMessageView = true }
                )
            }
            
            // Share
            ReelActionButton(
                icon: "paperplane",
                text: displayReel.shares > 0 ? "\(displayReel.shares)" : nil,
                color: .white,
                action: { shareReel() }
            )
            
            // Save
            ReelActionButton(
                icon: isSaved ? "bookmark.fill" : "bookmark",
                text: nil,
                color: isSaved ? .yellow : .white,
                action: { toggleSave() }
            )
            
            // More options
            Menu {
                if isOwnReel {
                    Button(action: { showingEditSheet = true }) {
                        Label("Edit Caption", systemImage: "pencil")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                        Label("Delete Reel", systemImage: "trash")
                    }
                } else {
                    Button(action: {}) {
                        Label("Report", systemImage: "flag")
                    }
                    
                    Button(action: {}) {
                        Label("Not Interested", systemImage: "hand.raised")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 30)
    }
    
    @ViewBuilder
    private var deletingOverlay: some View {
        Color.black.opacity(0.7)
            .ignoresSafeArea()
            .overlay(
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    Text("Deleting...")
                        .foregroundColor(.white)
                        .padding(.top)
                }
            )
    }
    
    // MARK: - Methods
    
    private func startListeningToReel() {
        guard let reelId = reel.id else { return }
        
        reelListener = firebase.listenToReel(reelId) { updatedReel in
            if let updatedReel = updatedReel {
                withAnimation {
                    self.currentReel = updatedReel
                    self.likesCount = updatedReel.likes.count
                    self.commentsCount = updatedReel.comments
                    self.isLiked = updatedReel.likes.contains(firebase.currentUser?.id ?? "")
                }
            }
        }
    }
    
    private func checkInitialStates() async {
        checkFollowingStatus()
        isLiked = displayReel.likes.contains(firebase.currentUser?.id ?? "")
        likesCount = displayReel.likes.count
        commentsCount = displayReel.comments
        
        if let reelId = displayReel.id {
            isSaved = await firebase.isItemSaved(itemId: reelId, type: .reel)
        }
    }
    
    private func toggleLike() {
        Task {
            if isLiked {
                await firebase.unlikeReel(reel.id ?? "")
            } else {
                await firebase.likeReel(reel.id ?? "")
            }
            
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isLiked.toggle()
                    
                }
            }
        }
    }
    
    private func toggleFollow() {
        Task {
            do {
                if isFollowing {
                    try await firebase.unfollowUser(displayReel.userId)
                } else {
                    try await firebase.followUser(displayReel.userId)
                }
                isFollowing.toggle()
            } catch {
                print("Error toggling follow: \(error)")
            }
        }
    }
    
    private func checkFollowingStatus() {
        guard let currentUser = firebase.currentUser else { return }
        isFollowing = currentUser.following.contains(displayReel.userId)
    }
    
    private func toggleSave() {
        guard let reelId = displayReel.id else { return }
        
        Task {
            do {
                isSaved = try await firebase.toggleReelSave(reelId)
            } catch {
                print("Error toggling save: \(error)")
            }
        }
    }
    
    private func shareReel() {
        showingShareSheet = true
        Task {
            if let reelId = displayReel.id {
                try? await firebase.db.collection("reels").document(reelId).updateData([
                    "shares": FieldValue.increment(Int64(1))
                ])
            }
        }
    }
    
    private func deleteReel() async {
        guard let reelId = displayReel.id else { return }
        
        isDeleting = true
        
        do {
            try await firebase.deleteReel(reelId)
            onDismiss()
        } catch {
            print("Error deleting reel: \(error)")
            isDeleting = false
        }
    }
}

// MARK: - Updated Reel Action Button Component
struct ReelActionButton: View {
    let icon: String
    let text: String?
    let color: Color
    let action: () -> Void
    var onLongPress: (() -> Void)? = nil
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundColor(color)
                    .scaleEffect(color == .red || color == .yellow ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: color)
                
                if let text = text {
                    Text(text)
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
        }
        .simultaneousGesture(
            LongPressGesture()
                .onEnded { _ in
                    onLongPress?()
                }
        )
    }
}
// MARK: - Add Status Button
struct AddStatusButton: View {
    @State private var showingCamera = false
    
    var body: some View {
        Button(action: { showingCamera = true }) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 75, height: 75)
                    
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.blue)
                }
                
                Text("Your Story")
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraView(mode: .status)
        }
    }
}

// MARK: - Status Bubble
struct StatusBubble: View {
    let status: Status
    let isOwnStatus: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    // Background image
                    AsyncImage(url: URL(string: status.mediaURL ?? "")) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 75, height: 75)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                        case .failure(_):
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 75, height: 75)
                        case .empty:
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: 75, height: 75)
                                .overlay(ProgressView())
                        @unknown default:
                            EmptyView()
                        }
                    }
                    
                    // Border for unviewed stories
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            isOwnStatus ? Color.blue : Color.purple,
                            lineWidth: status.viewedBy.contains(FirebaseService.shared.currentUser?.id ?? "") ? 1 : 3
                        )
                        .frame(width: 75, height: 75)
                }
                
                Text(isOwnStatus ? "Your Story" : (status.userName ?? "User"))
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(.primary)
            }
        }
    }
}

// MARK: - Reel Grid Item
struct ReelGridItem: View {
    let reel: Reel
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                // Thumbnail or video preview
                if let thumbnailURL = reel.thumbnailURL {
                    AsyncImage(url: URL(string: thumbnailURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: UIScreen.main.bounds.width / 3 - 2, height: 180)
                                .clipped()
                        case .failure(_):
                            placeholderView
                        case .empty:
                            placeholderView
                                .overlay(ProgressView())
                        @unknown default:
                            placeholderView
                        }
                    }
                } else {
                    placeholderView
                }
                
                // Overlay with play icon and view count
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.caption)
                            Text("\(reel.views)")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                        
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .frame(width: UIScreen.main.bounds.width / 3 - 2, height: 180)
            .background(Color.gray.opacity(0.2))
        }
    }
    
    var placeholderView: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: UIScreen.main.bounds.width / 3 - 2, height: 180)
    }
}

// MARK: - Empty Reels Placeholder
struct EmptyReelsPlaceholder: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Reels Yet")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Be the first to share your skills!")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Create Content Options Sheet
struct CreateContentOptionsSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var showingStatusCamera = false
    @State private var showingReelCamera = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Create Content")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top)
                
                // Status Option
                Button(action: {
                    showingStatusCamera = true
                }) {
                    HStack {
                        Image(systemName: "circle.dashed")
                            .font(.title2)
                            .foregroundColor(.orange)
                            .frame(width: 50)
                        
                        VStack(alignment: .leading) {
                            Text("Add Status")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Share a 24-hour update")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                // Reel Option
                Button(action: {
                    showingReelCamera = true
                }) {
                    HStack {
                        Image(systemName: "play.rectangle.fill")
                            .font(.title2)
                            .foregroundColor(.purple)
                            .frame(width: 50)
                        
                        VStack(alignment: .leading) {
                            Text("Create Reel")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Showcase your skills")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(.primary)
            }
            .padding()
            .navigationBarHidden(true)
        }
        .presentationDetents([.height(300)])
        .fullScreenCover(isPresented: $showingStatusCamera) {
            CameraView(mode: .status)
        }
        .fullScreenCover(isPresented: $showingReelCamera) {
            CameraView(mode: .reel)
        }
    }
}


// MARK: - Status Viewer View with Delete
struct StatusViewerView: View {
    let status: Status
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var showingUserProfile = false
    @State private var showingMessageView = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    
    // Check if current user owns this status
    var isOwnStatus: Bool {
        status.userId == firebase.currentUser?.id
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Status Image
            AsyncImage(url: URL(string: status.mediaURL ?? "")) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
            
            // Top bar
            VStack {
                HStack {
                    // User info - Make it tappable
                    Button(action: {
                        // Only show profile if it's not the current user's status
                        if !isOwnStatus {
                            showingUserProfile = true
                        }
                    }) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 35, height: 35)
                                .overlay(
                                    Text(String(status.userName?.first ?? "U"))
                                        .foregroundColor(.black)
                                )
                            
                            VStack(alignment: .leading) {
                                Text(status.userName ?? "User")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                
                                Text(status.createdAt, style: .relative)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    .disabled(isOwnStatus)
                    
                    Spacer()
                    
                    // Options menu for own status
                    if isOwnStatus {
                        Menu {
                            Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                                Label("Delete Status", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                    }
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding()
                
                Spacer()
                
                // Caption if exists
                if let caption = status.caption, !caption.isEmpty {
                    Text(caption)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(10)
                        .padding()
                }
                
                // Reply button (only show if not own status)
                if !isOwnStatus {
                    HStack {
                        Spacer()
                        Button(action: { showingMessageView = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "message.fill")
                                Text("Reply")
                            }
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .cornerRadius(20)
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                }
            }
            
            // Loading overlay
            if isDeleting {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                    .overlay(
                        VStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            Text("Deleting...")
                                .foregroundColor(.white)
                                .padding(.top)
                        }
                    )
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showingUserProfile) {
            NavigationView {
                EnhancedProfileView(userId: status.userId)
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarItems(
                        leading: Button("Close") {
                            showingUserProfile = false
                        }
                    )
            }
        }
        .fullScreenCover(isPresented: $showingMessageView) {
            ChatView(
                recipientId: status.userId,
                contextType: .status,
                contextId: status.id,
                contextData: (
                    title: status.text ?? "Status Update",
                    image: status.mediaURL,
                    userId: status.userId
                ),
                isFromContentView: true
            )
        }
        .confirmationDialog("Delete Status?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await deleteStatus()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This status will be permanently deleted.")
        }
        .task {
            if !isOwnStatus {
                await firebase.viewStatus(status.id ?? "")
            }
        }
    }
    
    private func deleteStatus() async {
        guard let statusId = status.id else { return }
        
        isDeleting = true
        
        do {
            try await firebase.deleteStatus(statusId)
            dismiss()
        } catch {
            print("Error deleting status: \(error)")
            isDeleting = false
        }
    }
}

// MARK: - Edit Reel Caption View
struct EditReelCaptionView: View {
    let reel: Reel
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var title: String
    @State private var description: String
    @State private var isSaving = false
    
    init(reel: Reel) {
        self.reel = reel
        _title = State(initialValue: reel.title)
        _description = State(initialValue: reel.description)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Title") {
                    TextField("Enter title", text: $title)
                }
                
                Section("Description") {
                    TextField("Enter description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Caption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await saveChanges()
                        }
                    }
                    .disabled(title.isEmpty || isSaving)
                }
            }
            .overlay(
                Group {
                    if isSaving {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .overlay(
                                ProgressView("Saving...")
                            )
                    }
                }
            )
        }
    }
    
    private func saveChanges() async {
        guard let reelId = reel.id else { return }
        
        isSaving = true
        
        do {
            try await firebase.updateReelCaption(reelId, title: title, description: description)
            dismiss()
        } catch {
            print("Error updating reel: \(error)")
            isSaving = false
        }
    }
}

// MARK: - Reel Viewer View with Edit/Delete (Original standalone view)
struct ReelViewerView: View {
    let reel: Reel
    @Environment(\.dismiss) var dismiss
    @State private var isLiked = false
    @State private var isFollowing = false
    @State private var isSaved = false
    @State private var showingUserProfile = false
    @State private var showingComments = false
    @State private var showingMessageView = false
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingMoreOptions = false
    @State private var isDeleting = false
    @State private var showingShareSheet = false
    @StateObject private var firebase = FirebaseService.shared
    
    // Check if current user owns this reel
    var isOwnReel: Bool {
        reel.userId == firebase.currentUser?.id
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Video/Image content
            if let thumbnailURL = reel.thumbnailURL {
                AsyncImage(url: URL(string: thumbnailURL)) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            VStack {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.white.opacity(0.8))
                                Text("Video Player")
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        )
                }
            } else {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        VStack {
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.8))
                            Text("Video Player")
                                .foregroundColor(.white.opacity(0.8))
                        }
                    )
            }
            
            // Overlay UI
            VStack {
                // Top bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.down")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    Text("Reels")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: {}) {
                        Image(systemName: "camera")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                
                Spacer()
                
                // Bottom info and actions
                HStack(alignment: .bottom) {
                    // Left side - Info
                    VStack(alignment: .leading, spacing: 10) {
                        // User info row
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text(String(reel.userName?.first ?? "U"))
                                        .foregroundColor(.black)
                                        .fontWeight(.semibold)
                                )
                            
                            // Username button
                            Button(action: {
                                showingUserProfile = true
                            }) {
                                Text(reel.userName ?? "User")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                            
                            // Follow button (only if not own content)
                            if !isOwnReel {
                                Button(action: { toggleFollow() }) {
                                    Text(isFollowing ? "Following" : "Follow")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                        .background(isFollowing ? Color.clear : Color.red)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(isFollowing ? Color.white : Color.clear, lineWidth: 1)
                                        )
                                        .cornerRadius(4)
                                }
                            }
                        }
                        
                        // Title and description
                        Text(reel.title)
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text(reel.description)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                        
                        // Category if exists
                        if let category = reel.category {
                            Text("#\(category.displayName)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding()
                    .padding(.bottom, 20)
                    
                    Spacer()
                    
                    // Right side - Actions
                    VStack(spacing: 25) {
                        // Like
                        VStack(spacing: 4) {
                            Button(action: { toggleLike() }) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .font(.title)
                                    .foregroundColor(isLiked ? .red : .white)
                                    .scaleEffect(isLiked ? 1.1 : 1.0)
                                    .animation(.easeInOut(duration: 0.2), value: isLiked)
                            }
                            Text("\(reel.likes.count)")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        
                        // Comment
                        VStack(spacing: 4) {
                            Button(action: { showingComments = true }) {
                                Image(systemName: "bubble.right")
                                    .font(.title)
                                    .foregroundColor(.white)
                            }
                            Text("\(reel.comments)")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        
                        // Message (only if not own reel)
                        if !isOwnReel {
                            VStack(spacing: 4) {
                                Button(action: {
                                    showingMessageView = true
                                }) {
                                    Image(systemName: "message")
                                        .font(.title)
                                        .foregroundColor(.white)
                                }
                                Text("Message")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Share
                        VStack(spacing: 4) {
                            Button(action: { shareReel() }) {
                                Image(systemName: "paperplane")
                                    .font(.title)
                                    .foregroundColor(.white)
                            }
                            Text("\(reel.shares)")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        
                        // Save
                        Button(action: { toggleSave() }) {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .font(.title)
                                .foregroundColor(isSaved ? .yellow : .white)
                                .scaleEffect(isSaved ? 1.1 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: isSaved)
                        }
                        
                        // More Options Menu
                        Menu {
                            if isOwnReel {
                                Button(action: { showingEditSheet = true }) {
                                    Label("Edit Caption", systemImage: "pencil")
                                }
                                
                                Divider()
                                
                                Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                                    Label("Delete Reel", systemImage: "trash")
                                }
                            } else {
                                Button(action: {}) {
                                    Label("Report", systemImage: "flag")
                                }
                                
                                Button(action: {}) {
                                    Label("Not Interested", systemImage: "hand.raised")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.title)
                                .foregroundColor(.white)
                        }
                    }
                    .padding()
                    .padding(.bottom, 20)
                }
            }
            
            // Loading overlay
            if isDeleting {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                    .overlay(
                        VStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            Text("Deleting...")
                                .foregroundColor(.white)
                                .padding(.top)
                        }
                    )
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showingUserProfile) {
            NavigationView {
                EnhancedProfileView(userId: reel.userId)
                    .navigationBarItems(
                        leading: Button("Close") {
                            showingUserProfile = false
                        }
                    )
            }
        }
        .sheet(isPresented: $showingComments) {
            CommentsView(reelId: reel.id ?? "", reelOwnerId: reel.userId)
        }
        .sheet(isPresented: $showingEditSheet) {
            EditReelCaptionView(reel: reel)
        }
        .fullScreenCover(isPresented: $showingMessageView) {
            ChatView(
                recipientId: reel.userId,
                contextType: .reel,
                contextId: reel.id,
                contextData: (
                    title: reel.title,
                    image: reel.thumbnailURL ?? reel.videoURL,
                    userId: reel.userId
                ),
                isFromContentView: true
            )
        }
        .confirmationDialog("Delete Reel?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await deleteReel()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. Your reel will be permanently deleted.")
        }
        .sheet(isPresented: $showingShareSheet) {
            ReelShareSheet(items: [
                "Check out this amazing reel: \(reel.title)",
                reel.description,
                URL(string: reel.thumbnailURL ?? reel.videoURL) ?? URL(string: "https://claudehustler.com")!
            ])
        }
        .task {
            await checkInitialStates()
        }
    }
    
    private func deleteReel() async {
        guard let reelId = reel.id else { return }
        
        isDeleting = true
        
        do {
            try await firebase.deleteReel(reelId)
            dismiss()
        } catch {
            print("Error deleting reel: \(error)")
            isDeleting = false
        }
    }
    
    private func checkInitialStates() async {
        checkFollowingStatus()
        isLiked = reel.likes.contains(firebase.currentUser?.id ?? "")
        
        if let reelId = reel.id {
            isSaved = await firebase.isItemSaved(itemId: reelId, type: .reel)
        }
    }
    
    private func toggleSave() {
        guard let reelId = reel.id else { return }
        
        Task {
            do {
                isSaved = try await firebase.toggleReelSave(reelId)
            } catch {
                print("Error toggling save: \(error)")
            }
        }
    }
    
    private func toggleLike() {
        Task {
            if isLiked {
                await firebase.unlikeReel(reel.id ?? "")
            } else {
                await firebase.likeReel(reel.id ?? "")
            }
            isLiked.toggle()
        }
    }
    
    private func toggleFollow() {
        Task {
            do {
                if isFollowing {
                    try await firebase.unfollowUser(reel.userId)
                } else {
                    try await firebase.followUser(reel.userId)
                }
                isFollowing.toggle()
            } catch {
                print("Error toggling follow: \(error)")
            }
        }
    }
    
    private func checkFollowingStatus() {
        guard let currentUser = firebase.currentUser else { return }
        isFollowing = currentUser.following.contains(reel.userId)
    }
    
    private func shareReel() {
        showingShareSheet = true
        // Increment share count in Firebase
        Task {
            if let reelId = reel.id {
                try? await firebase.db.collection("reels").document(reelId).updateData([
                    "shares": FieldValue.increment(Int64(1))
                ])
            }
        }
    }
}

// MARK: - Comments View

// MARK: - Reel Share Sheet
struct ReelShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

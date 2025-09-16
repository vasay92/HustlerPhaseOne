// PostDetailView.swift
// Path: ClaudeHustlerFirebase/Views/Post/PostDetailView.swift

import SwiftUI
import Firebase

struct PostDetailView: View {
    let post: ServicePost
    @StateObject private var firebase = FirebaseService.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedPhotoIndex = 0
    @State private var isSaved = false
    @State private var showingShareSheet = false
    @State private var showingMessageView = false
    @State private var posterInfo: User?
    @State private var showingEditView = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    
    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Photo Gallery
                        photoGallerySection
                        
                        // Post Details
                        postDetailsSection
                        
                        // User Info
                        userInfoSection
                        
                        // Action Buttons
                        actionButtonsSection
                        
                        Spacer(minLength: 100)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { dismiss() }) {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .foregroundColor(.primary)
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack {
                            Button(action: { showingShareSheet = true }) {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(.primary)
                            }
                            
                            // Options menu for post owner
                            if post.userId == firebase.currentUser?.id {
                                Menu {
                                    Button(action: { showingEditView = true }) {
                                        Label("Edit Post", systemImage: "pencil")
                                    }
                                    
                                    Divider()
                                    
                                    Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                                        Label("Delete Post", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                    }
                }
                
                // Bottom Action Buttons
                bottomActionButtons
            }
        }
        .navigationBarHidden(true)
        .task {
            await loadPosterInfo()
            await checkSaveStatus()
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [post.title, post.description])
        }
        .fullScreenCover(isPresented: $showingMessageView) {
            ChatView(
                recipientId: post.userId,
                contextType: .post,
                contextId: post.id,
                contextData: (
                    title: post.title,
                    image: post.imageURLs.first,
                    userId: post.userId
                ),
                isFromContentView: true
            )
        }
        .fullScreenCover(isPresented: $showingEditView) {
            EditServicePostView(post: post)
        }
        .confirmationDialog("Delete Post?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await deletePost()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. Your post will be permanently deleted.")
        }
        .overlay(
            Group {
                if isDeleting {
                    Color.black.opacity(0.4)
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
        )
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var photoGallerySection: some View {
        if !post.imageURLs.isEmpty {
            VStack(spacing: 0) {
                TabView(selection: $selectedPhotoIndex) {
                    ForEach(Array(post.imageURLs.enumerated()), id: \.offset) { index, imageURL in
                        AsyncImage(url: URL(string: imageURL)) { image in
                            image
                                .resizable()
                                .scaledToFit()
                        } placeholder: {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .overlay(
                                    ProgressView()
                                )
                        }
                        .frame(height: 350)
                        .tag(index)
                    }
                }
                .frame(height: 350)
                .tabViewStyle(PageTabViewStyle())
                
                // Thumbnail Strip
                if post.imageURLs.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(post.imageURLs.enumerated()), id: \.offset) { index, imageURL in
                                AsyncImage(url: URL(string: imageURL)) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                }
                                .frame(width: 60, height: 60)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedPhotoIndex == index ? Color.blue : Color.clear, lineWidth: 2)
                                )
                                .onTapGesture {
                                    withAnimation {
                                        selectedPhotoIndex = index
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 70)
                    .padding(.vertical, 10)
                }
            }
        } else {
            // Default image placeholder when no images
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            post.isRequest ? Color.orange.opacity(0.3) : Color.blue.opacity(0.3),
                            post.isRequest ? Color.red.opacity(0.3) : Color.purple.opacity(0.3)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 350)
                .overlay(
                    VStack(spacing: 10) {
                        Image(systemName: categoryIcon(for: post.category))
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.8))
                        Text(post.category.displayName)
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                )
        }
    }
    
    @ViewBuilder
    private var postDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(post.title)
                .font(.title2)
                .fontWeight(.bold)
            
            // Price
            if let price = post.price {
                Text(post.isRequest ? "Budget: $\(Int(price))" : "$\(Int(price))")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(post.isRequest ? .orange : .green)
            } else {
                Text(post.isRequest ? "Budget: Flexible" : "Contact for price")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.gray)
            }
            
            // Location
            if let location = post.location, !location.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(location)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            
            // Category Badge
            HStack {
                CategoryBadge(category: post.category)
                
                if post.isRequest {
                    RequestBadge()
                }
                
                Spacer()
                
                // Status badge
                if post.status == .active {
                    Text("ACTIVE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Description
            Text("Description")
                .font(.headline)
            
            Text(post.description)
                .font(.body)
                .foregroundColor(.primary.opacity(0.9))
            
            // Posted Date
            HStack {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("Posted \(post.createdAt, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    @ViewBuilder
    private var userInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Posted by")
                .font(.headline)
            
            NavigationLink(destination: EnhancedProfileView(userId: post.userId)) {
                HStack(spacing: 12) {
                    // Profile Photo
                    UserProfileImage(imageURL: posterInfo?.profileImageURL, userName: posterInfo?.name ?? post.userName)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // User Name
                        Text(posterInfo?.name ?? post.userName ?? "Unknown User")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        // Rating
                        HStack(spacing: 4) {
                            PostDetailStarRatingView(rating: posterInfo?.rating ?? 0.0, maxRating: 5)
                            Text("(\(posterInfo?.reviewCount ?? 0))")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        // Member Since
                        if let createdAt = posterInfo?.createdAt {
                            Text("Member since \(createdAt, formatter: yearFormatter)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    @ViewBuilder
    private var actionButtonsSection: some View {
        HStack(spacing: 20) {
            PostActionButton(
                icon: isSaved ? "bookmark.fill" : "bookmark",
                title: isSaved ? "Saved" : "Save",
                color: isSaved ? .blue : .gray,
                action: { toggleSave() }
            )
            
            PostActionButton(
                icon: "square.and.arrow.up",
                title: "Share",
                color: .gray,
                action: { showingShareSheet = true }
            )
            
            PostActionButton(
                icon: "flag",
                title: "Report",
                color: .gray,
                action: {
                    // TODO: Implement report functionality
                }
            )
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    @ViewBuilder
    private var bottomActionButtons: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Button(action: {
                    if post.userId != firebase.currentUser?.id {
                        showingMessageView = true
                    }
                }) {
                    Label("Message", systemImage: "message.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(post.userId == firebase.currentUser?.id ? Color.gray : Color.blue)
                        .cornerRadius(12)
                }
                .disabled(post.userId == firebase.currentUser?.id)
                
                if post.isRequest && post.userId != firebase.currentUser?.id {
                    Button(action: {
                        // TODO: Implement make offer functionality
                    }) {
                        Label("Make Offer", systemImage: "tag.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(12)
                    }
                } else if !post.isRequest && post.userId != firebase.currentUser?.id {
                    Button(action: {
                        // TODO: Implement book service functionality
                    }) {
                        Label("Book Service", systemImage: "calendar.badge.plus")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(12)
                    }
                }
            }
            .padding()
            .background(
                Color(.systemBackground)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
            )
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadPosterInfo() async {
        let userId = post.userId
        
        do {
            let document = try await Firestore.firestore()
                .collection("users")
                .document(userId)
                .getDocument()
            
            if document.exists {
                posterInfo = try? document.data(as: User.self)
                posterInfo?.id = document.documentID
            }
        } catch {
            print("Error loading poster info: \(error)")
        }
    }
    
    private func checkSaveStatus() async {
        if let postId = post.id {
            isSaved = await firebase.isItemSaved(itemId: postId, type: .post)
        }
    }
    
    private func toggleSave() {
        guard let postId = post.id else { return }
        
        Task {
            do {
                isSaved = try await firebase.togglePostSave(postId)
            } catch {
                print("Error toggling save: \(error)")
            }
        }
    }
    
    private func categoryIcon(for category: ServiceCategory) -> String {
        switch category {
        case .cleaning: return "sparkles"
        case .tutoring: return "book.fill"
        case .delivery: return "shippingbox.fill"
        case .electrical: return "bolt.fill"
        case .plumbing: return "drop.fill"
        case .carpentry: return "hammer.fill"
        case .painting: return "paintbrush.fill"
        case .landscaping: return "leaf.fill"
        case .moving: return "box.truck.fill"
        case .technology: return "desktopcomputer"
        case .other: return "ellipsis.circle.fill"
        }
    }
    
    private func deletePost() async {
        guard let postId = post.id else { return }
        
        isDeleting = true
        
        do {
            try await firebase.deletePost(postId)
            dismiss()
        } catch {
            print("Error deleting post: \(error)")
            isDeleting = false
        }
    }
    
    private var yearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }
}

// MARK: - Supporting Views

struct CategoryBadge: View {
    let category: ServiceCategory
    
    var body: some View {
        Text(category.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(12)
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

struct UserProfileImage: View {
    let imageURL: String?
    let userName: String?
    
    var body: some View {
        if let imageURL = imageURL {
            AsyncImage(url: URL(string: imageURL)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                    )
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 60, height: 60)
                .overlay(
                    Text(String(userName?.first ?? "U"))
                        .font(.title3)
                        .foregroundColor(.white)
                )
        }
    }
}

// RENAMED FROM ActionButton TO PostActionButton
struct PostActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(color)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

struct PostDetailStarRatingView: View {
    let rating: Double
    let maxRating: Int
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...maxRating, id: \.self) { index in
                Image(systemName: index <= Int(rating) ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
}

// MARK: - Sheet Views

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

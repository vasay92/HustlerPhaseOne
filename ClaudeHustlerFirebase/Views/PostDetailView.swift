// PostDetailView.swift
// Path: ClaudeHustlerFirebase/Views/PostDetailView.swift

import SwiftUI
import FirebaseFirestore

struct PostDetailView: View {
    let post: ServicePost
    var currentUser: User? = nil
    
    @StateObject private var firebase = FirebaseService.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var posterInfo: User?
    @State private var showingEditPost = false
    @State private var showingDeleteAlert = false
    @State private var isDeleting = false
    @State private var showingMessages = false
    @State private var isSaved = false
    @State private var showingShareSheet = false
    
    private var isOwnPost: Bool {
        firebase.currentUser?.id == post.userId
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Images Section - FIXED: using mediaURLs
                if !post.mediaURLs.isEmpty {
                    TabView {
                        ForEach(post.mediaURLs, id: \.self) { imageURL in
                            AsyncImage(url: URL(string: imageURL)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 300)
                                        .clipped()
                                case .failure(_):
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 300)
                                        .overlay(
                                            Image(systemName: "photo")
                                                .font(.largeTitle)
                                                .foregroundColor(.gray)
                                        )
                                case .empty:
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.1))
                                        .frame(height: 300)
                                        .overlay(
                                            ProgressView()
                                        )
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                    }
                    .frame(height: 300)
                    .tabViewStyle(PageTabViewStyle())
                    .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    // Title and Category
                    VStack(alignment: .leading, spacing: 8) {
                        Text(post.title)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        HStack {
                            CategoryBadge(category: post.category)
                            
                            if post.isRequest {
                                RequestBadge()
                            }
                            
                            Spacer()
                            
                            if let price = post.price {
                                HStack(spacing: 4) {
                                    Text("$")
                                        .font(.title2)
                                        .fontWeight(.medium)
                                        .foregroundColor(.green)
                                    Text("\(Int(price))")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // User Info Section
                    if let posterInfo = posterInfo {
                        NavigationLink(destination: UserProfileView(userId: posterInfo.id ?? "")) {
                            HStack {
                                UserProfileImage(
                                    imageURL: posterInfo.profileImageURL,
                                    userName: posterInfo.name
                                )
                                .frame(width: 50, height: 50)
                                
                                VStack(alignment: .leading) {
                                    Text(posterInfo.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    HStack(spacing: 4) {
                                        Image(systemName: "star.fill")
                                            .font(.caption)
                                            .foregroundColor(.yellow)
                                        Text(String(format: "%.1f", posterInfo.rating))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("(\(posterInfo.reviewCount) reviews)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    
                    Divider()
                    
                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.headline)
                        
                        Text(post.description)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    
                    // Additional Details
                    VStack(alignment: .leading, spacing: 12) {
                        if let location = post.location {
                            HStack {
                                Image(systemName: "location")
                                    .foregroundColor(.gray)
                                Text(location)
                                    .foregroundColor(.primary)
                            }
                        }
                        
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.gray)
                            Text("Posted \(post.createdAt, formatter: yearFormatter)")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Image(systemName: categoryIcon(for: post.category))
                                .foregroundColor(.gray)
                            Text(post.category.displayName)
                                .foregroundColor(.primary)
                        }
                    }
                    
                    // Action Buttons
                    HStack(spacing: 15) {
                        if !isOwnPost {
                            Button(action: {
                                showingMessages = true
                            }) {
                                Label("Message", systemImage: "message.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            
                            Button(action: {
                                toggleSave()
                            }) {
                                Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.gray.opacity(0.2))
                                    .foregroundColor(.primary)
                                    .cornerRadius(10)
                            }
                        } else {
                            Button(action: {
                                showingEditPost = true
                            }) {
                                Label("Edit Post", systemImage: "pencil")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            
                            Button(action: {
                                showingDeleteAlert = true
                            }) {
                                Label("Delete", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.red.opacity(0.1))
                                    .foregroundColor(.red)
                                    .cornerRadius(10)
                            }
                            .disabled(isDeleting)
                        }
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingShareSheet = true
                }) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .task {
            await loadPosterInfo()
            await checkSaveStatus()
        }
        .sheet(isPresented: $showingEditPost) {
            EditServicePostView(post: post)
        }
        .sheet(isPresented: $showingMessages) {
            if let posterInfo = posterInfo {
                ChatView(otherUserId: posterInfo.id ?? "")
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [generateShareText()])
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
    
    private func generateShareText() -> String {
        var shareText = post.title
        
        if let price = post.price {
            shareText += " - $\(Int(price))"
        }
        
        shareText += "\n\n\(post.description)"
        
        if let location = post.location {
            shareText += "\n\nLocation: \(location)"
        }
        
        return shareText
    }
    
    private func loadPosterInfo() async {
        do {
            let document = try await firebase.db.collection("users")
                .document(post.userId)
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
        case .handyman: return "hammer.fill"  // FIXED: changed from .carpentry
        case .painting: return "paintbrush.fill"
        case .landscaping: return "leaf.fill"
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
        if let imageURL = imageURL, !imageURL.isEmpty {
            AsyncImage(url: URL(string: imageURL)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                case .failure(_):
                    fallbackImage
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                @unknown default:
                    fallbackImage
                }
            }
        } else {
            fallbackImage
        }
    }
    
    @ViewBuilder
    private var fallbackImage: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
                Text(String(userName?.first ?? "U"))
                    .font(.headline)
                    .foregroundColor(.white)
            )
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

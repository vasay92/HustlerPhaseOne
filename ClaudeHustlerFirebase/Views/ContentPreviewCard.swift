// ContentPreviewCard.swift
// Path: ClaudeHustlerFirebase/Views/Messages/ContentPreviewCard.swift

import SwiftUI
import FirebaseFirestore

// MARK: - PostDetailView Wrapper with Close Button
struct PostDetailViewWithClose: View {
    let post: ServicePost
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        // Just show PostDetailView without any additional buttons
        PostDetailView(post: post)
            .onDisappear {
                // This ensures the view can still be dismissed programmatically if needed
            }
    }
}

// MARK: - Main ContentPreviewCard
struct ContentPreviewCard: View {
    let message: Message
    @State private var contentPost: ServicePost?
    @State private var contentReel: Reel?
    @State private var contentStatus: Status?
    @State private var isLoading = true
    @State private var showingContent = false
    @State private var loadError = false
    @StateObject private var firebase = FirebaseService.shared
    
    private var contentTitle: String {
        message.contextTitle ?? "Shared Content"
    }
    
    private var contentImage: String? {
        message.contextImage
    }
    
    private var contentTypeIcon: String {
        switch message.contextType {
        case .post:
            return "briefcase.fill"
        case .reel:
            return "play.rectangle.fill"
        case .status:
            return "circle.dashed"
        case .none:
            return "square.fill"
        }
    }
    
    private var contentTypeColor: Color {
        switch message.contextType {
        case .post:
            return .blue
        case .reel:
            return .purple
        case .status:
            return .orange
        case .none:
            return .gray
        }
    }
    
    private var contentTypeLabel: String {
        switch message.contextType {
        case .post:
            return "Service Post"
        case .reel:
            return "Reel"
        case .status:
            return "Status"
        case .none:
            return "Content"
        }
    }
    
    var body: some View {
        Button(action: {
            if !isLoading && !loadError {
                showingContent = true
            }
        }) {
            HStack(spacing: 12) {
                // Thumbnail
                ZStack {
                    if let imageURL = contentImage {
                        AsyncImage(url: URL(string: imageURL)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipped()
                            case .failure(_):
                                placeholderImage
                            case .empty:
                                Rectangle()
                                    .fill(Color.gray.opacity(0.1))
                                    .overlay(ProgressView())
                            @unknown default:
                                placeholderImage
                            }
                        }
                    } else {
                        placeholderImage
                    }
                    
                    // Type icon overlay
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: contentTypeIcon)
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(contentTypeColor)
                                .clipShape(Circle())
                                .offset(x: 4, y: 4)
                        }
                    }
                }
                .frame(width: 60, height: 60)
                .cornerRadius(8)
                
                // Content info
                VStack(alignment: .leading, spacing: 4) {
                    Text(contentTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Image(systemName: contentTypeIcon)
                            .font(.caption2)
                            .foregroundColor(contentTypeColor)
                        
                        Text(contentTypeLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.5)
                        } else if loadError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                Spacer()
                
                // Chevron
                if !isLoading && !loadError {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .opacity(loadError ? 0.6 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isLoading || loadError)
        .onAppear {
            Task {
                await loadContent()
            }
        }
        .fullScreenCover(isPresented: $showingContent) {
            contentDetailView
        }
    }
    
    @ViewBuilder
    private var placeholderImage: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [contentTypeColor.opacity(0.3), contentTypeColor.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: contentTypeIcon)
                    .font(.title3)
                    .foregroundColor(.white)
            )
    }
    
    @ViewBuilder
    private var contentDetailView: some View {
        Group {
            switch message.contextType {
            case .post:
                if let post = contentPost {
                    // Use the wrapper with close button for posts
                    PostDetailViewWithClose(post: post)
                } else {
                    ContentNotFoundView()
                }
            case .reel:
                if let reel = contentReel {
                    ReelViewerView(reel: reel)
                } else {
                    ContentNotFoundView()
                }
            case .status:
                if let status = contentStatus {
                    StatusViewerView(status: status)
                } else {
                    ContentNotFoundView()
                }
            case .none:
                ContentNotFoundView()
            }
        }
    }
    
    @MainActor
    private func loadContent() async {
        // Reset states
        loadError = false
        isLoading = true
        
        guard let contextId = message.contextId,
              let contextType = message.contextType else {
            print("⌠Missing context")
            isLoading = false
            loadError = true
            return
        }
        
        print("🔥 Loading content from Firestore")
        print("  - Collection: \(contextType.rawValue)s")
        print("  - Document ID: \(contextId)")
        
        do {
            let db = firebase.db
            
            switch contextType {
            case .post:
                let document = try await db.collection("posts")
                    .document(contextId)
                    .getDocument()
                
                if document.exists {
                    var post = try? document.data(as: ServicePost.self)
                    post?.id = document.documentID
                    
                    // Update on main thread
                    await MainActor.run {
                        self.contentPost = post
                        self.isLoading = false
                        self.loadError = (post == nil)
                    }
                    
                    print("✅ Successfully loaded post: \(post?.title ?? "nil")")
                } else {
                    await MainActor.run {
                        self.isLoading = false
                        self.loadError = true
                    }
                    print("⚠️ Post document doesn't exist")
                }
                
            case .reel:
                let document = try await db.collection("reels")
                    .document(contextId)
                    .getDocument()
                
                if document.exists {
                    var reel = try? document.data(as: Reel.self)
                    reel?.id = document.documentID
                    
                    // Update on main thread
                    await MainActor.run {
                        self.contentReel = reel
                        self.isLoading = false
                        self.loadError = (reel == nil)
                    }
                    
                    print("✅ Successfully loaded reel: \(reel?.title ?? "nil")")
                } else {
                    await MainActor.run {
                        self.isLoading = false
                        self.loadError = true
                    }
                    print("⚠️ Reel document doesn't exist")
                }
                
            case .status:
                let document = try await db.collection("statuses")
                    .document(contextId)
                    .getDocument()
                
                if document.exists {
                    var status = try? document.data(as: Status.self)
                    status?.id = document.documentID
                    
                    // Update on main thread
                    await MainActor.run {
                        self.contentStatus = status
                        self.isLoading = false
                        self.loadError = (status == nil)
                    }
                    
                    print("✅ Successfully loaded status")
                } else {
                    await MainActor.run {
                        self.isLoading = false
                        self.loadError = true
                    }
                    print("⚠️ Status document doesn't exist")
                }
            }
        } catch {
            print("⌠Error loading content: \(error)")
            await MainActor.run {
                self.isLoading = false
                self.loadError = true
            }
        }
        
        print("🔥 ContentPreviewCard: Loading complete, isLoading = \(isLoading), loadError = \(loadError)")
    }
}

// MARK: - Content Not Found View
struct ContentNotFoundView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Spacer()
                
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                
                Text("Content Not Found")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("This content may have been deleted or is no longer available.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button(action: { dismiss() }) {
                    Text("Return to Chat")
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Content Unavailable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.primary)
                    }
                }
            }
        }
    }
}

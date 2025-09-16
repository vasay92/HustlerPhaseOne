// CommentsView.swift
import SwiftUI
import FirebaseFirestore

struct CommentsView: View {
    let reelId: String
    let reelOwnerId: String
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var comments: [Comment] = []
    @State private var commentText = ""
    @State private var replyingTo: Comment?
    @State private var showingDeleteConfirmation = false
    @State private var commentToDelete: Comment?
    @State private var commentsListener: ListenerRegistration?
    @State private var isPosting = false
    
    var topLevelComments: [Comment] {
        comments.filter { $0.parentCommentId == nil }
    }
    
    func replies(for commentId: String) -> [Comment] {
        comments.filter { $0.parentCommentId == commentId }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Comments List
                if comments.isEmpty {
                    emptyStateView
                } else {
                    commentsList
                }
                
                // Reply indicator
                if let replyingTo = replyingTo {
                    replyIndicator(for: replyingTo)
                }
                
                // Comment Input Bar
                commentInputBar
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            startListeningToComments()
        }
        .onDisappear {
            commentsListener?.remove()
            firebase.stopListeningToComments(reelId)
        }
        .confirmationDialog("Delete Comment?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let comment = commentToDelete {
                    deleteComment(comment)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    
    // MARK: - Views
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("No comments yet")
                .font(.headline)
                .foregroundColor(.primary)
            Text("Be the first to comment!")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
    
    @ViewBuilder
    private var commentsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(topLevelComments) { comment in
                    CommentCell(
                        comment: comment,
                        replies: replies(for: comment.id ?? ""),
                        reelOwnerId: reelOwnerId,
                        onReply: { replyingTo = comment },
                        onDelete: {
                            commentToDelete = comment
                            showingDeleteConfirmation = true
                        }
                    )
                }
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private func replyIndicator(for comment: Comment) -> some View {
        HStack {
            Text("Replying to \(comment.userName ?? "User")")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: { replyingTo = nil }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
    
    @ViewBuilder
    private var commentInputBar: some View {
        HStack {
            TextField(replyingTo != nil ? "Reply..." : "Add a comment...", text: $commentText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Button(action: postComment) {
                if isPosting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(commentText.isEmpty ? .gray : .blue)
                }
            }
            .disabled(commentText.isEmpty || isPosting)
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    // MARK: - Methods
    
    private func startListeningToComments() {
        commentsListener = firebase.listenToComments(for: reelId) { updatedComments in
            withAnimation {
                self.comments = updatedComments
            }
        }
    }
    
    // In CommentsView, update postComment():
    private func postComment() {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        isPosting = true
        
        Task {
            do {
                _ = try await firebase.postComment(
                    on: reelId,
                    text: text,
                    parentCommentId: replyingTo?.id
                )
                
                await MainActor.run {
                    commentText = ""
                    replyingTo = nil
                    isPosting = false
                }
            } catch {
                await MainActor.run {
                    isPosting = false
                    // Show error to user
                    print("Error posting comment: \(error.localizedDescription)")
                    // You should add an @State var showingError and errorMessage to display this
                }
            }
        }
    }
    
    private func deleteComment(_ comment: Comment) {
        guard let commentId = comment.id else { return }
        
        Task {
            do {
                try await firebase.deleteComment(commentId, reelId: reelId)
            } catch {
                print("Error deleting comment: \(error)")
            }
        }
    }
}

// MARK: - Comment Cell

struct CommentCell: View {
    let comment: Comment
    let replies: [Comment]
    let reelOwnerId: String
    let onReply: () -> Void
    let onDelete: () -> Void
    
    @StateObject private var firebase = FirebaseService.shared
    @State private var isLiked = false
    @State private var showReplies = false
    
    var canDelete: Bool {
        comment.userId == firebase.currentUser?.id || reelOwnerId == firebase.currentUser?.id
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main comment
            HStack(alignment: .top, spacing: 10) {
                // Profile image
                NavigationLink(destination: EnhancedProfileView(userId: comment.userId)) {
                    profileImage
                }
                .buttonStyle(PlainButtonStyle())
                
                VStack(alignment: .leading, spacing: 4) {
                    // Username and time
                    HStack {
                        Text(comment.userName ?? "User")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text("• \(comment.timestamp, style: .relative)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if canDelete {
                            Menu {
                                Button(role: .destructive, action: onDelete) {
                                    Label("Delete", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    
                    // Comment text
                    Text(comment.text)
                        .font(.body)
                    
                    // Actions
                    HStack(spacing: 16) {
                        Button(action: toggleLike) {
                            HStack(spacing: 4) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .font(.caption)
                                if comment.likes.count > 0 {
                                    Text("\(comment.likes.count)")
                                        .font(.caption)
                                }
                            }
                            .foregroundColor(isLiked ? .red : .gray)
                        }
                        
                        Button(action: onReply) {
                            Text("Reply")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        if comment.replyCount > 0 {
                            Button(action: { showReplies.toggle() }) {
                                HStack(spacing: 4) {
                                    Text(showReplies ? "Hide" : "View")
                                    Text("\(comment.replyCount) \(comment.replyCount == 1 ? "reply" : "replies")")
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            
            // Replies
            if showReplies && !replies.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(replies) { reply in
                        ReplyCell(
                            comment: reply,
                            reelOwnerId: reelOwnerId,
                            onReply: onReply,
                            onDelete: onDelete
                        )
                        .padding(.leading, 40)
                    }
                }
            }
        }
        .onAppear {
            isLiked = comment.likes.contains(firebase.currentUser?.id ?? "")
        }
    }
    
    @ViewBuilder
    private var profileImage: some View {
        if let imageURL = comment.userProfileImage, !imageURL.isEmpty {
            AsyncImage(url: URL(string: imageURL)) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
            }
        } else {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 32, height: 32)
                .overlay(
                    Text(String(comment.userName?.first ?? "U"))
                        .font(.caption)
                        .foregroundColor(.white)
                )
        }
    }
    
    private func toggleLike() {
        guard let commentId = comment.id else { return }
        
        Task {
            do {
                if isLiked {
                    try await firebase.unlikeComment(commentId)
                    await MainActor.run {
                        isLiked = false
                    }
                } else {
                    try await firebase.likeComment(commentId)
                    await MainActor.run {
                        isLiked = true
                    }
                }
            } catch {
                print("Error toggling like: \(error)")
            }
        }
    }
}

// MARK: - Reply Cell

struct ReplyCell: View {
    let comment: Comment
    let reelOwnerId: String
    let onReply: () -> Void
    let onDelete: () -> Void
    
    @StateObject private var firebase = FirebaseService.shared
    
    var canDelete: Bool {
        comment.userId == firebase.currentUser?.id || reelOwnerId == firebase.currentUser?.id
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Profile image
            NavigationLink(destination: EnhancedProfileView(userId: comment.userId)) {
                if let imageURL = comment.userProfileImage, !imageURL.isEmpty {
                    AsyncImage(url: URL(string: imageURL)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 24, height: 24)
                    }
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text(String(comment.userName?.first ?? "U"))
                                .font(.caption2)
                                .foregroundColor(.white)
                        )
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(comment.userName ?? "User")
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    Text("• \(comment.timestamp, style: .relative)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if canDelete {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Text(comment.text)
                    .font(.caption)
            }
        }
    }
}

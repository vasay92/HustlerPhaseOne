// ConversationsListView.swift
// Path: ClaudeHustlerFirebase/Views/Messages/ConversationsListView.swift

import SwiftUI
import FirebaseFirestore

struct ConversationsListView: View {
    @StateObject private var firebase = FirebaseService.shared
    @State private var conversations: [Conversation] = []
    @State private var searchText = ""
    @State private var selectedConversation: Conversation?
    @State private var showingNewMessage = false
    @State private var conversationsListener: ListenerRegistration?
    @State private var totalUnreadCount = 0
    
    var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return conversations
        }
        
        guard let currentUserId = firebase.currentUser?.id else { return conversations }
        
        return conversations.filter { conversation in
            let otherName = conversation.otherParticipantName(currentUserId: currentUserId) ?? ""
            return otherName.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                if !conversations.isEmpty {
                    searchBar
                }
                
                // Conversations List
                if conversations.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredConversations) { conversation in
                                ConversationRow(conversation: conversation)
                                    .onTapGesture {
                                        selectedConversation = conversation
                                    }
                                
                                Divider()
                                    .padding(.leading, 76)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingNewMessage = true }) {
                        Image(systemName: "square.and.pencil")
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .task {
            await loadConversations()
            startListeningToConversations()
            await updateUnreadCount()
        }
        .onDisappear {
            conversationsListener?.remove()
        }
        .fullScreenCover(item: $selectedConversation) { conversation in
            ChatView(conversation: conversation)
        }
        .sheet(isPresented: $showingNewMessage) {
            NewMessageView()
        }
    }
    
    // MARK: - View Components
    
    private var searchBar: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                
                TextField("Search conversations", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .padding()
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "message")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Messages Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Start a conversation with other users")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: { showingNewMessage = true }) {
                Label("New Message", systemImage: "plus.message.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Functions
    
    private func loadConversations() async {
        conversations = await firebase.loadConversations()
    }
    
    private func startListeningToConversations() {
        conversationsListener = firebase.listenToConversations { updatedConversations in
            withAnimation {
                self.conversations = updatedConversations
            }
        }
    }
    
    private func updateUnreadCount() async {
        totalUnreadCount = await firebase.getTotalUnreadCount()
    }
}

// MARK: - Conversation Row Component

struct ConversationRow: View {
    let conversation: Conversation
    @StateObject private var firebase = FirebaseService.shared
    @State private var showingOptions = false
    
    private var currentUserId: String? {
        firebase.currentUser?.id
    }
    
    private var otherParticipantName: String {
        guard let userId = currentUserId else { return "Unknown" }
        return conversation.otherParticipantName(currentUserId: userId) ?? "Unknown"
    }
    
    private var otherParticipantImage: String? {
        guard let userId = currentUserId else { return nil }
        return conversation.otherParticipantImage(currentUserId: userId)
    }
    
    private var unreadCount: Int {
        guard let userId = currentUserId else { return 0 }
        return conversation.unreadCounts[userId] ?? 0
    }
    
    private var isUnread: Bool {
        unreadCount > 0
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile Image
            if let imageURL = otherParticipantImage {
                AsyncImage(url: URL(string: imageURL)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                } placeholder: {
                    profilePlaceholder
                }
            } else {
                profilePlaceholder
            }
            
            // Message Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(otherParticipantName)
                        .font(.headline)
                        .fontWeight(isUnread ? .semibold : .regular)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(conversation.lastMessageTimestamp, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    if let senderId = conversation.lastMessageSenderId,
                       senderId == currentUserId {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(conversation.lastMessage ?? "Start a conversation")
                        .font(.subheadline)
                        .foregroundColor(isUnread ? .primary : .secondary)
                        .fontWeight(isUnread ? .medium : .regular)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    if isUnread {
                        Text("\(unreadCount)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                // Delete conversation
            } label: {
                Label("Delete", systemImage: "trash")
            }
            
            Button {
                showingOptions = true
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .tint(.gray)
        }
        .actionSheet(isPresented: $showingOptions) {
            ActionSheet(
                title: Text("Conversation Options"),
                buttons: [
                    .destructive(Text("Block User")) {
                        Task {
                            if let conversationId = conversation.id,
                               let otherUserId = conversation.otherParticipantId(currentUserId: currentUserId ?? "") {
                                try? await firebase.blockUser(otherUserId, in: conversationId)
                            }
                        }
                    },
                    .destructive(Text("Report")) {
                        // Show report view
                    },
                    .cancel()
                ]
            )
        }
    }
    
    private var profilePlaceholder: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 56, height: 56)
            .overlay(
                Text(String(otherParticipantName.first ?? "U"))
                    .font(.title2)
                    .foregroundColor(.white)
            )
    }
}

// MARK: - New Message View

struct NewMessageView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var searchText = ""
    @State private var users: [User] = []
    @State private var selectedUser: User?
    
    var filteredUsers: [User] {
        if searchText.isEmpty {
            return users
        }
        return users.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.email.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Search Bar
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        
                        TextField("Search users", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                    }
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
                .padding()
                
                // Users List
                if users.isEmpty {
                    Spacer()
                    Text("No users found")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    List(filteredUsers) { user in
                        UserRow(user: user) {
                            selectedUser = user
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            await loadUsers()
        }
        .fullScreenCover(item: $selectedUser) { user in
            if let userId = user.id {
                ChatView(recipientId: userId)
            }
        }
    }
    
    private func loadUsers() async {
        // Load users from Firebase
        // This is a simplified version - you might want to paginate or filter
        do {
            let snapshot = try await Firestore.firestore()
                .collection("users")
                .limit(to: 50)
                .getDocuments()
            
            users = snapshot.documents.compactMap { doc in
                try? doc.data(as: User.self)
            }.filter { $0.id != firebase.currentUser?.id } // Exclude current user
        } catch {
            print("Error loading users: \(error)")
        }
    }
}

// MARK: - User Row Component

struct UserRow: View {
    let user: User
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Profile Image
                if let imageURL = user.profileImageURL {
                    AsyncImage(url: URL(string: imageURL)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } placeholder: {
                        profilePlaceholder
                    }
                } else {
                    profilePlaceholder
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(user.email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var profilePlaceholder: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 40, height: 40)
            .overlay(
                Text(String(user.name.first ?? "U"))
                    .foregroundColor(.white)
            )
    }
}


// ChatView.swift
// Path: ClaudeHustlerFirebase/Views/Messages/ChatView.swift

import SwiftUI
import FirebaseFirestore

struct ChatView: View {
    let conversation: Conversation?
    let recipientId: String?
    let contextType: Message.MessageContextType?
    let contextId: String?
    let contextData: (title: String, image: String?, userId: String)?
    
    @StateObject private var firebase = FirebaseService.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var messages: [Message] = []
    @State private var messageText = ""
    @State private var isLoadingMessages = false
    @State private var showingBlockConfirmation = false
    @State private var showingClearConfirmation = false
    @State private var showingReportSheet = false
    @State private var reportMessageId: String?
    @State private var messagesListener: ListenerRegistration?
    @State private var scrollToBottom = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var otherUser: User?
    @State private var currentConversationId: String?
    @State private var isFromContentView = false
    
    // Navigation context for returning from content
    @State private var navigatingToContent = false
    @State private var selectedContentMessage: Message?
    
    // For scroll view
    @Namespace private var bottomAnchor
    
    init(conversation: Conversation) {
        self.conversation = conversation
        self.recipientId = nil
        self.contextType = nil
        self.contextId = nil
        self.contextData = nil
    }
    
    init(recipientId: String,
         contextType: Message.MessageContextType? = nil,
         contextId: String? = nil,
         contextData: (title: String, image: String?, userId: String)? = nil,
         isFromContentView: Bool = false) {
        self.conversation = nil
        self.recipientId = recipientId
        self.contextType = contextType
        self.contextId = contextId
        self.contextData = contextData
        self._isFromContentView = State(initialValue: isFromContentView)
    }
    
    private var chatTitle: String {
        if let conversation = conversation {
            return conversation.otherParticipantName(currentUserId: firebase.currentUser?.id ?? "") ?? "Chat"
        } else if let otherUser = otherUser {
            return otherUser.name
        }
        return "Chat"
    }
    
    private var otherUserId: String? {
        if let conversation = conversation {
            return conversation.otherParticipantId(currentUserId: firebase.currentUser?.id ?? "")
        }
        return recipientId
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Custom Navigation Bar
                    customNavigationBar
                    
                    // Messages List
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(messages) { message in
                                    MessageBubbleView(
                                        message: message,
                                        isFromCurrentUser: message.senderId == firebase.currentUser?.id
                                    )
                                    .id(message.id)
                                }
                                
                                Color.clear
                                    .frame(height: 1)
                                    .id(bottomAnchor)
                            }
                            .padding()
                        }
                        .onChange(of: messages.count) { _, _ in
                            withAnimation {
                                scrollProxy.scrollTo(bottomAnchor, anchor: .bottom)
                            }
                        }
                        .onAppear {
                            scrollProxy.scrollTo(bottomAnchor, anchor: .bottom)
                        }
                    }
                    
                    // Message Composer
                    messageComposer
                }
            }
            .navigationBarHidden(true)
            .task {
                await setupChat()
            }
            .onDisappear {
                messagesListener?.remove()
            }
            .confirmationDialog("Block User?", isPresented: $showingBlockConfirmation) {
                Button("Block", role: .destructive) {
                    Task { await blockUser() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You won't receive messages from this user anymore.")
            }
            .confirmationDialog("Clear Chat?", isPresented: $showingClearConfirmation) {
                Button("Clear All Messages", role: .destructive) {
                    Task { await clearChat() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all messages in this conversation for both users. This action cannot be undone.")
            }
            .sheet(isPresented: $showingReportSheet) {
                ReportMessageView(
                    messageId: reportMessageId,
                    conversationId: currentConversationId ?? "",
                    reportedUserId: otherUserId ?? ""
                )
            }
        }
    }
    
    // MARK: - Custom Navigation Bar
    
    @ViewBuilder
    private var customNavigationBar: some View {
        HStack(spacing: 12) {
            // Back button
            Button(action: {
                dismiss()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    if isFromContentView {
                        Text("Back")
                            .font(.subheadline)
                    }
                }
                .foregroundColor(.blue)
            }
            
            // User info
            if let otherUser = otherUser {
                NavigationLink(destination: EnhancedProfileView(userId: otherUser.id ?? "")) {
                    HStack(spacing: 10) {
                        // Profile image
                        if let imageURL = otherUser.profileImageURL {
                            AsyncImage(url: URL(string: imageURL)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())
                            } placeholder: {
                                profileImagePlaceholder
                            }
                        } else {
                            profileImagePlaceholder
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(otherUser.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("Tap for profile")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Text(chatTitle)
                    .font(.headline)
            }
            
            Spacer()
            
            // More options
            Menu {
                Button(action: { showingClearConfirmation = true }) {
                    Label("Clear Chat", systemImage: "trash")
                }
                
                Divider()
                
                Button(action: { showingBlockConfirmation = true }) {
                    Label("Block User", systemImage: "hand.raised.fill")
                }
                
                Button(action: {
                    reportMessageId = nil
                    showingReportSheet = true
                }) {
                    Label("Report Conversation", systemImage: "flag.fill")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 2)
    }
    
    private var profileImagePlaceholder: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 36, height: 36)
            .overlay(
                Text(String(otherUser?.name.first ?? "U"))
                    .font(.subheadline)
                    .foregroundColor(.white)
            )
    }
    
    // MARK: - Message Composer
    
    @ViewBuilder
    private var messageComposer: some View {
        VStack(spacing: 0) {
            // Context indicator if replying to content
            if let contextType = contextType,
               let contextData = contextData,
               isFromContentView {
                HStack {
                    Image(systemName: "arrow.turn.up.right")
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    Text("Sharing \(contextTypeString(contextType))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(contextData.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
            }
            
            // Input field
            HStack(spacing: 12) {
                // Text field
                HStack {
                    TextField("Message...", text: $messageText, axis: .vertical)
                        .textFieldStyle(PlainTextFieldStyle())
                        .lineLimit(1...5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .background(Color(.systemGray6))
                .cornerRadius(20)
                
                // Send button
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                        .foregroundColor(messageText.isEmpty ? .gray : .white)
                        .frame(width: 36, height: 36)
                        .background(messageText.isEmpty ? Color(.systemGray4) : Color.blue)
                        .clipShape(Circle())
                }
                .disabled(messageText.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
    }
    
    // MARK: - Helper Functions
    
    private func setupChat() async {
        isLoadingMessages = true
        
        do {
            // Get or create conversation
            if let conversation = conversation {
                currentConversationId = conversation.id
            } else if let recipientId = recipientId {
                currentConversationId = try await firebase.findOrCreateConversation(with: recipientId)
            }
            
            // Load other user info
            if let otherUserId = otherUserId {
                let document = try await Firestore.firestore()
                    .collection("users")
                    .document(otherUserId)
                    .getDocument()
                otherUser = try? document.data(as: User.self)
                otherUser?.id = otherUserId
            }
            
            // Load messages
            if let conversationId = currentConversationId {
                messages = await firebase.loadMessages(for: conversationId)
                
                // Mark messages as read
                try await firebase.markMessagesAsRead(in: conversationId)
                
                // Start listening for new messages
                messagesListener = firebase.listenToMessages(in: conversationId) { newMessages in
                    withAnimation {
                        self.messages = newMessages
                    }
                    
                    // Mark new messages as read
                    Task {
                        try? await firebase.markMessagesAsRead(in: conversationId)
                    }
                }
            }
        } catch {
            print("Error setting up chat: \(error)")
        }
        
        isLoadingMessages = false
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !text.isEmpty else { return }
        guard let recipientId = otherUserId else { return }
        
        Task {
            do {
                // Include context only if coming from content view
                let shouldIncludeContext = isFromContentView && contextType != nil
                
                try await firebase.sendMessage(
                    to: recipientId,
                    text: text,
                    contextType: shouldIncludeContext ? contextType : nil,
                    contextId: shouldIncludeContext ? contextId : nil,
                    contextData: shouldIncludeContext ? contextData : nil
                )
                
                messageText = ""
                
                // Clear context after first message if from content view
                if isFromContentView {
                    isFromContentView = false
                }
            } catch {
                print("Error sending message: \(error)")
            }
        }
    }
    
    private func blockUser() async {
        guard let conversationId = currentConversationId,
              let userId = otherUserId else { return }
        
        do {
            try await firebase.blockUser(userId, in: conversationId)
            dismiss()
        } catch {
            print("Error blocking user: \(error)")
        }
    }
    
    private func clearChat() async {
        guard let conversationId = currentConversationId else { return }
        
        do {
            try await firebase.clearConversation(conversationId)
            messages = []
        } catch {
            print("Error clearing chat: \(error)")
        }
    }
    
    private func contextTypeString(_ type: Message.MessageContextType) -> String {
        switch type {
        case .post: return "Post"
        case .reel: return "Reel"
        case .status: return "Status"
        }
    }
}

// MARK: - Message Bubble View

struct MessageBubbleView: View {
    let message: Message
    let isFromCurrentUser: Bool
    
    var body: some View {
        HStack {
            if isFromCurrentUser { Spacer() }
            
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Content preview if exists - NO NavigationLink wrapping
                if message.contextType != nil {
                    ContentPreviewCard(message: message)
                }
                
                // Message bubble
                HStack {
                    Text(message.text)
                        .font(.body)
                        .foregroundColor(isFromCurrentUser ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .background(isFromCurrentUser ? Color.blue : Color(.systemGray5))
                .cornerRadius(18)
                
                // Timestamp and read receipt
                HStack(spacing: 4) {
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if isFromCurrentUser {
                        if message.isRead {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        } else if message.isDelivered {
                            Image(systemName: "checkmark.circle")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: isFromCurrentUser ? .trailing : .leading)
            
            if !isFromCurrentUser { Spacer() }
        }
    }
}

// MARK: - Report Message View

struct ReportMessageView: View {
    let messageId: String?
    let conversationId: String
    let reportedUserId: String
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var selectedReason: MessageReport.ReportReason = .spam
    @State private var additionalDetails = ""
    @State private var isSubmitting = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Reason for Report") {
                    Picker("Reason", selection: $selectedReason) {
                        ForEach(MessageReport.ReportReason.allCases, id: \.self) { reason in
                            Text(reason.displayName).tag(reason)
                        }
                    }
                    .pickerStyle(DefaultPickerStyle())
                }
                
                Section("Additional Details (Optional)") {
                    TextEditor(text: $additionalDetails)
                        .frame(minHeight: 100)
                }
                
                Section {
                    Button(action: submitReport) {
                        if isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Submit Report")
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                        }
                    }
                    .listRowBackground(Color.red)
                    .disabled(isSubmitting)
                }
            }
            .navigationTitle("Report Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func submitReport() {
        isSubmitting = true
        
        Task {
            do {
                try await firebase.reportMessage(
                    messageId: messageId,
                    conversationId: conversationId,
                    reportedUserId: reportedUserId,
                    reason: selectedReason,
                    details: additionalDetails.isEmpty ? nil : additionalDetails
                )
                dismiss()
            } catch {
                print("Error submitting report: \(error)")
                isSubmitting = false
            }
        }
    }
}

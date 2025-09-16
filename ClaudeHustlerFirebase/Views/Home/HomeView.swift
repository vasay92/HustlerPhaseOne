// HomeView.swift
// Path: ClaudeHustlerFirebase/Views/Home/HomeView.swift

import SwiftUI
import FirebaseFirestore

struct HomeView: View {
    @StateObject private var firebase = FirebaseService.shared
    @State private var showingFilters = false
    @State private var selectedPost: ServicePost?
    @State private var searchText = ""
    @State private var selectedTab = 0
    @State private var unreadMessageCount = 0
    @State private var showingMessages = false
    @State private var conversationsListener: ListenerRegistration?
    
    var filteredPosts: [ServicePost] {
        let posts = selectedTab == 0
            ? firebase.posts.filter { !$0.isRequest }
            : firebase.posts.filter { $0.isRequest }
        
        if searchText.isEmpty {
            return posts
        }
        return posts.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var trendingPosts: [ServicePost] {
        firebase.posts.prefix(5).map { $0 }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Custom Navigation Bar
                    HStack {
                        Text("Hustler") // Changed from "ClaudeHustler" to "Hustler"
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Spacer()
                        
                        Button(action: { showingFilters = true }) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.title2)
                                .foregroundColor(.primary)
                        }
                        
                        // Messages button with badge
                        Button(action: { showingMessages = true }) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "message")
                                    .font(.title2)
                                    .foregroundColor(.primary)
                                
                                // Unread badge
                                if unreadMessageCount > 0 {
                                    Text("\(min(unreadMessageCount, 99))\(unreadMessageCount > 99 ? "+" : "")")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .padding(.horizontal, unreadMessageCount > 9 ? 4 : 0)
                                        .background(Color.red)
                                        .clipShape(Capsule())
                                        .offset(x: 8, y: -8)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    
                    // Trending Services Section
                    if !trendingPosts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Trending", systemImage: "flame.fill")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }
                            .padding(.horizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 15) {
                                    ForEach(trendingPosts) { post in
                                        NavigationLink(destination: PostDetailView(post: post)) {
                                            MiniServiceCard(post: post)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    // Recent Activity
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent Activity")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        LazyVStack(spacing: 15) {
                            ForEach(filteredPosts) { post in
                                NavigationLink(destination: PostDetailView(post: post)) {
                                    ServicePostCard(post: post)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .navigationBarHidden(true)
            .refreshable {
                await firebase.loadPosts()
                await updateUnreadCount()
            }
            .sheet(isPresented: $showingFilters) {
                FilterView()
            }
            .fullScreenCover(isPresented: $showingMessages) {
                NavigationView {
                    ConversationsListView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Close") {
                                    showingMessages = false
                                }
                            }
                        }
                }
            }
            .onAppear {
                Task {
                    await firebase.loadPosts()
                    await updateUnreadCount()
                    startListeningToUnreadCount()
                }
            }
            .onDisappear {
                conversationsListener?.remove()
            }
        }
    }
    
    // MARK: - Real-time Unread Count
    
    private func startListeningToUnreadCount() {
        // Remove any existing listener
        conversationsListener?.remove()
        
        // Set up real-time listener for conversations
        conversationsListener = firebase.listenToConversations { conversations in
            Task { @MainActor in
                var total = 0
                if let userId = firebase.currentUser?.id {
                    for conversation in conversations {
                        total += conversation.unreadCounts[userId] ?? 0
                    }
                }
                
                // Animate the badge update
                withAnimation(.easeInOut(duration: 0.2)) {
                    unreadMessageCount = total
                }
                
                print("📬 Unread message count updated: \(total)")
            }
        }
    }
    
    private func updateUnreadCount() async {
        let count = await firebase.getTotalUnreadCount()
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.2)) {
                unreadMessageCount = count
            }
        }
    }
}

// Service Post Card
struct ServicePostCard: View {
    let post: ServicePost
    @StateObject private var firebase = FirebaseService.shared
    @State private var isSaved = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Image section if images exist
            if !post.imageURLs.isEmpty {
                TabView {
                    ForEach(post.imageURLs, id: \.self) { imageURL in
                        AsyncImage(url: URL(string: imageURL)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 200)
                                    .clipped()
                            case .failure(_):
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 200)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .foregroundColor(.gray)
                                    )
                            case .empty:
                                Rectangle()
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(height: 200)
                                    .overlay(
                                        ProgressView()
                                    )
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                }
                .frame(height: 200)
                .tabViewStyle(PageTabViewStyle())
                .cornerRadius(12)
            }
            
            // Header
            HStack {
                // User info
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(String(post.userName?.first ?? "U"))
                                .font(.caption)
                                .foregroundColor(.white)
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.userName ?? "User")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 4) {
                            if let location = post.location, !location.isEmpty {
                                Image(systemName: "location")
                                    .font(.caption2)
                                Text(location)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Image(systemName: "location")
                                    .font(.caption2)
                                Text("Aurora")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    if post.isRequest {
                        Text("REQUEST")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    Text(post.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Title and Description
            VStack(alignment: .leading, spacing: 6) {
                Text(post.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(post.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            // Footer
            HStack {
                // Price
                if let price = post.price {
                    Text("$\(Int(price))")
                        .font(.headline)
                        .foregroundColor(.green)
                }
                
                // Category
                Text(post.category.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
                
                Spacer()
                
                // Actions
                HStack(spacing: 15) {
                    Button(action: { toggleSave() }) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .foregroundColor(isSaved ? .blue : .gray)
                            .scaleEffect(isSaved ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.2), value: isSaved)
                    }
                    
                    Image(systemName: "bubble.right")
                        .foregroundColor(.gray)
                    
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .task {
            await checkSaveStatus()
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
}

// Mini Service Card (Trending)
struct MiniServiceCard: View {
    let post: ServicePost
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image placeholder
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 150, height: 150)
                .cornerRadius(10)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(.white)
                        .font(.largeTitle)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(post.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                
                if let price = post.price {
                    Text("$\(Int(price))")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
            }
        }
        .frame(width: 150)
        .padding(10)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Filter View
struct FilterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: ServiceCategory?
    @State private var minPrice = ""
    @State private var maxPrice = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        Text("All Categories").tag(nil as ServiceCategory?)
                        ForEach(ServiceCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category as ServiceCategory?)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                Section("Price Range") {
                    HStack {
                        TextField("Min", text: $minPrice)
                            .keyboardType(.numberPad)
                        
                        Text("-")
                        
                        TextField("Max", text: $maxPrice)
                            .keyboardType(.numberPad)
                    }
                }
                
                Section {
                    Button("Apply Filters") {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    
                    Button("Clear All") {
                        selectedCategory = nil
                        minPrice = ""
                        maxPrice = ""
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

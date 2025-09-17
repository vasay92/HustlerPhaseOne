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
                        Text("Hustler")
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
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Search services...", text: $searchText)
                    }
                    .padding(10)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    
                    // Tabs
                    Picker("Service Type", selection: $selectedTab) {
                        Text("Offers").tag(0)
                        Text("Requests").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    
                    // Posts List
                    LazyVStack(spacing: 15) {
                        ForEach(filteredPosts) { post in
                            NavigationLink(destination: PostDetailView(post: post)) {
                                ServicePostCard(post: post)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        if filteredPosts.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: selectedTab == 0 ? "briefcase" : "magnifyingglass")
                                    .font(.largeTitle)
                                    .foregroundColor(.gray)
                                
                                Text(selectedTab == 0 ? "No services available" : "No requests yet")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                                
                                Text(selectedTab == 0 ? "Be the first to offer a service!" : "Be the first to request help!")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 50)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 20)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingFilters) {
                FiltersView()
            }
            .sheet(isPresented: $showingMessages) {
                ConversationsListView()
            }
        }
        .task {
            await firebase.loadPosts()
            await setupConversationsListener()
            await updateUnreadCount()
        }
        .onDisappear {
            conversationsListener?.remove()
        }
    }
    
    private func setupConversationsListener() async {
        guard let userId = firebase.currentUser?.id else { return }
        
        conversationsListener = firebase.db.collection("conversations")
            .whereField("participantIds", arrayContains: userId)
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                var total = 0
                for document in documents {
                    if let unreadCounts = document.data()["unreadCounts"] as? [String: Int] {
                        total += unreadCounts[userId] ?? 0
                    }
                }
                
                // Animate the badge update
                withAnimation(.easeInOut(duration: 0.2)) {
                    unreadMessageCount = total
                }
                
                print("📬 Unread message count updated: \(total)")
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

// MARK: - Service Post Card
struct ServicePostCard: View {
    let post: ServicePost
    @StateObject private var firebase = FirebaseService.shared
    @State private var isSaved = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Image section if images exist - FIXED: using mediaURLs
            if !post.mediaURLs.isEmpty {
                TabView {
                    ForEach(post.mediaURLs, id: \.self) { imageURL in
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
            
            // Price and Category
            HStack {
                if let price = post.price {
                    Label("$\(Int(price))", systemImage: "tag.fill")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                Text(post.category.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
            }
            
            // Action Buttons
            HStack(spacing: 20) {
                Button(action: {
                    // Like action
                }) {
                    Label("\(post.likes.count)", systemImage: "heart")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                Button(action: {
                    // Comment action
                }) {
                    Label("0", systemImage: "bubble.left")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Button(action: {
                    isSaved.toggle()
                }) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.subheadline)
                        .foregroundColor(isSaved ? .blue : .gray)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

// MARK: - Mini Service Card
struct MiniServiceCard: View {
    let post: ServicePost
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image or placeholder - FIXED: using mediaURLs
            if !post.mediaURLs.isEmpty, let firstImageURL = post.mediaURLs.first {
                AsyncImage(url: URL(string: firstImageURL)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 150, height: 100)
                        .clipped()
                        .cornerRadius(8)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 150, height: 100)
                        .cornerRadius(8)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                }
            } else {
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
                    .frame(width: 150, height: 100)
                    .cornerRadius(8)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: post.isRequest ? "questionmark.circle" : "briefcase")
                                .font(.title2)
                                .foregroundColor(.white)
                            Text(post.isRequest ? "REQUEST" : "OFFER")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(post.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                if let price = post.price {
                    Text("$\(Int(price))")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .fontWeight(.bold)
                }
            }
        }
        .frame(width: 150)
    }
}

// MARK: - Filters View
struct FiltersView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedCategory: ServiceCategory?
    @State private var minPrice = ""
    @State private var maxPrice = ""
    @State private var location = ""
    
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
                }
                
                Section("Price Range") {
                    HStack {
                        TextField("Min", text: $minPrice)
                            .keyboardType(.numberPad)
                        Text("to")
                        TextField("Max", text: $maxPrice)
                            .keyboardType(.numberPad)
                    }
                }
                
                Section("Location") {
                    TextField("Enter location", text: $location)
                }
                
                Section {
                    Button("Apply Filters") {
                        // Apply filters logic
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        selectedCategory = nil
                        minPrice = ""
                        maxPrice = ""
                        location = ""
                    }
                }
            }
        }
    }
}

// Note: ServiceCategory.displayName extension is already defined in DataModels.swift
// No need to duplicate it here

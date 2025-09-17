// ServicesView.swift
// Path: ClaudeHustlerFirebase/Views/Services/ServicesView.swift

import SwiftUI
import FirebaseFirestore

struct ServicesView: View {
    @StateObject private var firebase = FirebaseService.shared
    @State private var selectedTab: ServiceTab = .offers
    @State private var showingFilters = false
    @State private var selectedCategory: ServiceCategory?
    @State private var searchText = ""
    @State private var viewMode: ViewMode = .grid
    
    enum ServiceTab {
        case offers, requests
    }
    
    enum ViewMode {
        case grid, list
    }
    
    var filteredPosts: [ServicePost] {
        let posts = selectedTab == .offers
            ? firebase.posts.filter { !$0.isRequest }
            : firebase.posts.filter { $0.isRequest }
        
        var filtered = posts
        
        if let category = selectedCategory {
            filtered = filtered.filter { $0.category == category }
        }
        
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return filtered
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom Header
                VStack(spacing: 15) {
                    // Title Bar
                    HStack {
                        Text(selectedTab == .offers ? "Service Offers" : "Service Requests")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        // View Mode Toggle
                        HStack(spacing: 8) {
                            Button(action: { viewMode = .grid }) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.title2)
                                    .foregroundColor(viewMode == .grid ? .blue : .gray)
                            }
                            
                            Button(action: { viewMode = .list }) {
                                Image(systemName: "list.bullet")
                                    .font(.title2)
                                    .foregroundColor(viewMode == .list ? .blue : .gray)
                            }
                        }
                        
                        Button(action: { showingFilters = true }) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal)
                    
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
                    
                    // Tab Selection
                    Picker("Service Type", selection: $selectedTab) {
                        Text("Offers").tag(ServiceTab.offers)
                        Text("Requests").tag(ServiceTab.requests)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    
                    // Category Filter Pills (optional)
                    if selectedCategory != nil {
                        HStack {
                            Text(selectedCategory!.displayName)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(15)
                            
                            Button(action: { selectedCategory = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 10)
                .background(Color(.systemBackground))
                
                // Content based on view mode
                if viewMode == .grid {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ], spacing: 10) {
                            ForEach(filteredPosts) { post in
                                NavigationLink(destination: PostDetailView(post: post)) {
                                    MinimalServiceCard(post: post, isRequest: post.isRequest)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 10)
                        
                        if filteredPosts.isEmpty {
                            EmptyStateServiceView(isRequest: selectedTab == .requests)
                                .padding(.top, 100)
                        }
                    }
                } else {
                    List {
                        ForEach(filteredPosts) { post in
                            NavigationLink(destination: PostDetailView(post: post)) {
                                ServiceListCard(post: post, isRequest: post.isRequest)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .listRowInsets(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
                        }
                        
                        if filteredPosts.isEmpty {
                            EmptyStateServiceView(isRequest: selectedTab == .requests)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 100)
                        }
                    }
                    .listStyle(PlainListStyle())
                    .refreshable {
                        if selectedTab == .offers {
                            await firebase.loadOffers()
                        } else {
                            await firebase.loadRequests()
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingFilters) {
                EnhancedFiltersView(
                    selectedCategory: $selectedCategory,
                    selectedTab: selectedTab
                )
            }
            .task {
                await firebase.loadAllServicePosts()
            }
        }
    }
}

// MARK: - Minimal Service Card (3 per row)
struct MinimalServiceCard: View {
    let post: ServicePost
    let isRequest: Bool
    
    private var cardWidth: CGFloat {
        (UIScreen.main.bounds.width - 40) / 3
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Image Section with Price Overlay - 80% of card
            ZStack(alignment: .bottomTrailing) {
                // Image or Placeholder - FIXED: using mediaURLs
                if !post.mediaURLs.isEmpty, let firstImageURL = post.mediaURLs.first {
                    AsyncImage(url: URL(string: firstImageURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: cardWidth, height: cardWidth * 1.2)
                                .clipped()
                        case .failure(_):
                            imagePlaceholder
                        case .empty:
                            ZStack {
                                imagePlaceholder
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                        @unknown default:
                            imagePlaceholder
                        }
                    }
                } else {
                    imagePlaceholder
                }
                
                // Price Overlay
                if let price = post.price {
                    Text("$\(Int(price))")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(4)
                        .offset(x: -4, y: -4)
                }
            }
            .frame(width: cardWidth, height: cardWidth * 1.2)
            .clipped()
            
            // Title - 20% of card
            VStack(spacing: 2) {
                Text(post.title)
                    .font(.system(size: 11))
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
            }
            .frame(height: cardWidth * 0.3)
            .background(Color(.systemBackground))
        }
        .frame(width: cardWidth)
        .cornerRadius(8)
        .shadow(radius: 2)
    }
    
    @ViewBuilder
    var imagePlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: isRequest
                        ? [Color.orange.opacity(0.3), Color.red.opacity(0.3)]
                        : [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: cardWidth, height: cardWidth * 1.2)
            .overlay(
                VStack(spacing: 4) {
                    Image(systemName: categoryIcon(for: post.category))
                        .font(.title2)
                        .foregroundColor(.white)
                    Text(isRequest ? "REQUEST" : "OFFER")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
            )
    }
    
    func categoryIcon(for category: ServiceCategory) -> String {
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
}

// MARK: - Service List Card (for list view)
struct ServiceListCard: View {
    let post: ServicePost
    let isRequest: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Image or placeholder - FIXED: using mediaURLs
            if !post.mediaURLs.isEmpty, let firstImageURL = post.mediaURLs.first {
                AsyncImage(url: URL(string: firstImageURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipped()
                            .cornerRadius(10)
                    case .failure(_):
                        imagePlaceholder
                    case .empty:
                        ZStack {
                            imagePlaceholder
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                    @unknown default:
                        imagePlaceholder
                    }
                }
            } else {
                imagePlaceholder
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(post.title)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // Request/Offer Badge
                    Text(isRequest ? "REQUEST" : "OFFER")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(isRequest ? .orange : .blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isRequest ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }
                
                Text(post.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    if let price = post.price {
                        Label("$\(Int(price))", systemImage: "tag.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    Spacer()
                    
                    if let location = post.location {
                        Label(location, systemImage: "location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(post.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    var imagePlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: isRequest
                        ? [Color.orange.opacity(0.3), Color.red.opacity(0.3)]
                        : [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 80, height: 80)
            .cornerRadius(10)
            .overlay(
                Image(systemName: "briefcase.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            )
    }
}

// MARK: - Enhanced Filters View
struct EnhancedFiltersView: View {
    @Binding var selectedCategory: ServiceCategory?
    let selectedTab: ServicesView.ServiceTab
    @Environment(\.dismiss) var dismiss
    
    @State private var priceRange: ClosedRange<Double> = 0...500
    @State private var location = ""
    @State private var sortBy: SortOption = .newest
    
    enum SortOption: String, CaseIterable {
        case newest = "Newest First"
        case oldest = "Oldest First"
        case priceLow = "Price: Low to High"
        case priceHigh = "Price: High to Low"
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Category") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            CategoryPill(
                                title: "All",
                                isSelected: selectedCategory == nil,
                                action: { selectedCategory = nil }
                            )
                            
                            ForEach(ServiceCategory.allCases, id: \.self) { category in
                                CategoryPill(
                                    title: category.displayName,
                                    isSelected: selectedCategory == category,
                                    action: { selectedCategory = category }
                                )
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
                
                Section("Price Range") {
                    VStack {
                        HStack {
                            Text("$\(Int(priceRange.lowerBound))")
                            Spacer()
                            Text("$\(Int(priceRange.upperBound))+")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        // Price slider would go here
                    }
                }
                
                Section("Location") {
                    TextField("City or ZIP code", text: $location)
                }
                
                Section("Sort By") {
                    Picker("Sort", selection: $sortBy) {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        selectedCategory = nil
                        priceRange = 0...500
                        location = ""
                        sortBy = .newest
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views
struct CategoryPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
    }
}

struct EmptyStateServiceView: View {
    let isRequest: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: isRequest ? "magnifyingglass" : "briefcase")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text(isRequest
                ? "No requests found"
                : "No services offered")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(isRequest
                ? "Be the first to request a service"
                : "Be the first to offer your services")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

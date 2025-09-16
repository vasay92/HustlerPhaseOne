// ProfileSupportingViews.swift
import SwiftUI
import PhotosUI
import FirebaseFirestore

// MARK: - Portfolio Card View
// Update this in ProfileSupportingViews.swift
// Replace the existing PortfolioCardView struct with this:

struct PortfolioCardView: View {
    let card: PortfolioCard
    let isOwner: Bool
    @State private var showingGallery = false
    @State private var showingEditMenu = false
    @StateObject private var firebase = FirebaseService.shared
    
    var body: some View {
        Button(action: { showingGallery = true }) {
            VStack(alignment: .leading, spacing: 8) {
                // Cover Image
                if let coverURL = card.coverImageURL {
                    AsyncImage(url: URL(string: coverURL)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 160)
                            .clipped()
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 120, height: 160)
                            .overlay(
                                ProgressView()
                            )
                    }
                } else if let firstImage = card.mediaURLs.first {
                    AsyncImage(url: URL(string: firstImage)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 160)
                            .clipped()
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 120, height: 160)
                            .overlay(
                                ProgressView()
                            )
                    }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 120, height: 160)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                }
                
                // Title
                Text(card.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                    .frame(width: 120, alignment: .leading)
            }
            .cornerRadius(12)
        }
        .fullScreenCover(isPresented: $showingGallery) {
            PortfolioGalleryView(card: card, isOwner: isOwner)
        }
    }
    
    private func deletePortfolio() async {
        guard let cardId = card.id else { return }
        
        do {
            try await Firestore.firestore()
                .collection("portfolioCards")
                .document(cardId)
                .delete()
            
            // Optionally refresh the parent view
        } catch {
            print("Error deleting portfolio: \(error)")
        }
    }
}

// MARK: - Portfolio Detail View
struct PortfolioDetailView: View {
    let card: PortfolioCard
    let isOwner: Bool
    @Environment(\.dismiss) var dismiss
    @State private var selectedImageIndex = 0
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Image Gallery
                    if !card.mediaURLs.isEmpty {
                        TabView(selection: $selectedImageIndex) {
                            ForEach(Array(card.mediaURLs.enumerated()), id: \.offset) { index, url in
                                AsyncImage(url: URL(string: url)) { image in
                                    image
                                        .resizable()
                                        .scaledToFit()
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .overlay(ProgressView())
                                }
                                .tag(index)
                            }
                        }
                        .frame(height: 400)
                        .tabViewStyle(PageTabViewStyle())
                    }
                    
                    // Description
                    if let description = card.description, !description.isEmpty {
                        Text(description)
                            .padding(.horizontal)
                    }
                }
            }
            .navigationTitle(card.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Create Portfolio Card View
struct CreatePortfolioCardView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var title = ""
    @State private var coverImage: UIImage?
    @State private var mediaImages: [UIImage] = []
    @State private var showingCoverPicker = false
    @State private var showingMediaPicker = false
    @State private var isCreating = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Portfolio Title") {
                    TextField("Enter title", text: $title)
                }
                
                Section("Cover Image (Optional)") {
                    if let cover = coverImage {
                        Image(uiImage: cover)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 200)
                            .cornerRadius(8)
                    }
                    
                    Button(action: { showingCoverPicker = true }) {
                        Label(coverImage == nil ? "Add Cover Image" : "Change Cover Image", systemImage: "photo")
                    }
                }
                
                Section("Portfolio Images") {
                    if !mediaImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(Array(mediaImages.enumerated()), id: \.offset) { index, image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .cornerRadius(8)
                                        .overlay(
                                            Button(action: {
                                                mediaImages.remove(at: index)
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.white)
                                                    .background(Color.black.opacity(0.6))
                                                    .clipShape(Circle())
                                            }
                                            .padding(4)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                        )
                                }
                            }
                        }
                    }
                    
                    Button(action: { showingMediaPicker = true }) {
                        Label("Add Images", systemImage: "photo.on.rectangle.angled")
                    }
                }
            }
            .navigationTitle("Create Portfolio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        Task {
                            await createCard()
                        }
                    }
                    .disabled(title.isEmpty || isCreating)
                }
            }
        }
        .sheet(isPresented: $showingCoverPicker) {
            ImagePicker(images: .constant([]), singleImage: $coverImage)
        }
        .sheet(isPresented: $showingMediaPicker) {
            ImagePicker(images: $mediaImages, singleImage: nil)
        }
    }
    
    private func createCard() async {
        isCreating = true
        do {
            try await firebase.createPortfolioCard(
                title: title,
                coverImage: coverImage,
                mediaImages: mediaImages,
                description: nil
            )
            dismiss()
        } catch {
            print("Error creating portfolio card: \(error)")
            isCreating = false
        }
    }
}

// MARK: - Review Card
struct ReviewCard: View {
    let review: Review
    let isProfileOwner: Bool
    @State private var showingReplyForm = false
    @State private var showingEditForm = false
    @State private var helpfulCount: Int
    @State private var isHelpful: Bool
    @State private var isUpdating = false
    @StateObject private var firebase = FirebaseService.shared
    
    init(review: Review, isProfileOwner: Bool) {
        self.review = review
        self.isProfileOwner = isProfileOwner
        _helpfulCount = State(initialValue: review.helpfulVotes.count)
        _isHelpful = State(initialValue: false)
    }
    
    var isOwnReview: Bool {
        review.reviewerId == firebase.currentUser?.id
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Reviewer Info
            reviewerSection
            
            // Review Text
            reviewTextSection
            
            // Review Images
            if !review.mediaURLs.isEmpty {
                reviewImagesSection
            }
            
            // Reply if exists
            if let reply = review.reply {
                replySection(reply: reply)
            }
            
            // Action Buttons
            actionButtonsSection
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .opacity(isUpdating ? 0.6 : 1.0)
        .sheet(isPresented: $showingReplyForm) {
            ReplyToReviewView(reviewId: review.id ?? "")
        }
        .sheet(isPresented: $showingEditForm) {
            EditReviewView(review: review)
        }
        .onAppear {
            isHelpful = review.helpfulVotes.contains(firebase.currentUser?.id ?? "")
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var reviewerSection: some View {
        Group {
            if !isOwnReview {
                NavigationLink(destination: EnhancedProfileView(userId: review.reviewerId)) {
                    reviewerInfoView
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                reviewerInfoView
            }
        }
    }
    
    @ViewBuilder
    private var reviewerInfoView: some View {
        HStack {
            // Profile image
            profileImageView
            
            // User info and rating
            VStack(alignment: .leading) {
                HStack {
                    Text(review.reviewerName ?? "User")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if !isOwnReview {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                
                HStack(spacing: 4) {
                    StarRatingView(rating: Double(review.rating))
                    if review.isEdited {
                        Text("(edited)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Text(review.createdAt, style: .date)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private var profileImageView: some View {
        if let profileImage = review.reviewerProfileImage, !profileImage.isEmpty {
            AsyncImage(url: URL(string: profileImage)) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.5)
                    )
            }
        } else {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(review.reviewerName?.first ?? "U"))
                        .foregroundColor(.white)
                )
        }
    }
    
    @ViewBuilder
    private var reviewTextSection: some View {
        Text(review.text)
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
    }
    
    @ViewBuilder
    private var reviewImagesSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(review.mediaURLs, id: \.self) { url in
                    AsyncImage(url: URL(string: url)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.5)
                            )
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func replySection(reply: ReviewReply) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text("Business Response")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }
            
            Text(reply.text)
                .font(.subheadline)
                .padding(10)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
        }
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        ))
    }
    
    @ViewBuilder
    private var actionButtonsSection: some View {
        HStack(spacing: 16) {
            // Reply button
            if isProfileOwner && review.reply == nil {
                replyButton
            }
            
            // Edit button
            if isOwnReview {
                editButton
            }
            
            // Helpful button
            helpfulButton
            
            Spacer()
            
            // Review number indicator
            if let reviewNumber = review.reviewNumber, reviewNumber > 1 {
                reviewNumberBadge(reviewNumber)
            }
        }
    }
    
    @ViewBuilder
    private var replyButton: some View {
        Button(action: { showingReplyForm = true }) {
            Label("Reply", systemImage: "bubble.left")
                .font(.caption)
                .foregroundColor(.blue)
        }
        .disabled(isUpdating)
    }
    
    @ViewBuilder
    private var editButton: some View {
        Button(action: { showingEditForm = true }) {
            Label("Edit", systemImage: "pencil")
                .font(.caption)
                .foregroundColor(.blue)
        }
        .disabled(isUpdating)
    }
    
    @ViewBuilder
    private var helpfulButton: some View {
        Button(action: { toggleHelpful() }) {
            HStack(spacing: 4) {
                Image(systemName: isHelpful ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.caption)
                    .scaleEffect(isHelpful ? 1.2 : 1.0)
                
                if helpfulCount > 0 {
                    Text("\(helpfulCount)")
                        .font(.caption)
                        .fontWeight(isHelpful ? .semibold : .regular)
                }
            }
            .foregroundColor(isHelpful ? .blue : .gray)
            .animation(.easeInOut(duration: 0.2), value: isHelpful)
        }
        .disabled(isOwnReview || isUpdating)
    }
    
    @ViewBuilder
    private func reviewNumberBadge(_ number: Int) -> some View {
        Text("Review #\(number)")
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(4)
    }
    
    // MARK: - Methods
    
    private func toggleHelpful() {
        guard let reviewId = review.id else { return }
        
        isUpdating = true
        
        Task {
            do {
                let result = try await firebase.toggleHelpfulVote(for: reviewId)
                
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHelpful = result.isVoted
                        helpfulCount = result.count
                    }
                    isUpdating = false
                }
            } catch {
                print("Error toggling helpful vote: \(error)")
                await MainActor.run {
                    isUpdating = false
                }
            }
        }
    }
}

// MARK: - Create Review View
struct CreateReviewView: View {
    let userId: String
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var rating = 5
    @State private var reviewText = ""
    @State private var reviewImages: [UIImage] = []
    @State private var showingImagePicker = false
    @State private var isSubmitting = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var submitProgress: Double = 0
    
    var body: some View {
        NavigationView {
            Form {
                ratingSection
                reviewTextSection
                photosSection
            }
            .navigationTitle("Write Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .disabled(isSubmitting)
            .overlay(submissionOverlay)
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(images: $reviewImages, singleImage: nil)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Sections
    
    @ViewBuilder
    private var ratingSection: some View {
        Section("Rating") {
            VStack(spacing: 10) {
                Text("Tap to rate")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ratingStars
                
                Text(ratingText(for: rating))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
    }
    
    @ViewBuilder
    private var ratingStars: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { star in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        rating = star
                    }
                }) {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.title)
                        .foregroundColor(star <= rating ? .orange : .gray)
                        .scaleEffect(star == rating ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: rating)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    @ViewBuilder
    private var reviewTextSection: some View {
        Section("Review") {
            TextEditor(text: $reviewText)
                .frame(minHeight: 150)
                .overlay(alignment: .topLeading) {
                    if reviewText.isEmpty {
                        Text("Share your experience...")
                            .foregroundColor(.gray.opacity(0.5))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
    
    @ViewBuilder
    private var photosSection: some View {
        Section("Photos (Optional)") {
            if !reviewImages.isEmpty {
                existingPhotosView
            } else {
                addPhotosButton
            }
            
            if !reviewImages.isEmpty {
                photoCountLabel
            }
        }
    }
    
    @ViewBuilder
    private var existingPhotosView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(reviewImages.enumerated()), id: \.offset) { index, image in
                    photoThumbnail(image: image, index: index)
                }
                
                if reviewImages.count < 5 {
                    addMorePhotosButton
                }
            }
        }
    }
    
    @ViewBuilder
    private func photoThumbnail(image: UIImage, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100)
                .cornerRadius(8)
            
            Button(action: {
                withAnimation {
                    // Be explicit about the array type
                    var updatedImages = reviewImages
                    updatedImages.remove(at: index)
                    reviewImages = updatedImages
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .padding(4)
        }
    }
    
    @ViewBuilder
    private var addMorePhotosButton: some View {
        Button(action: { showingImagePicker = true }) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 100, height: 100)
                
                VStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.title2)
                    Text("Add")
                        .font(.caption)
                }
                .foregroundColor(.gray)
            }
        }
    }
    
    @ViewBuilder
    private var addPhotosButton: some View {
        Button(action: { showingImagePicker = true }) {
            HStack {
                Image(systemName: "camera.fill")
                Text("Add Photos (Optional)")
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.blue)
        }
    }
    
    @ViewBuilder
    private var photoCountLabel: some View {
        Text("\(reviewImages.count)/5 photos")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Cancel") { dismiss() }
                .disabled(isSubmitting)
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Button("Submit") {
                Task {
                    await submitReview()
                }
            }
            .disabled(reviewText.isEmpty || isSubmitting)
        }
    }
    
    // MARK: - Submission Overlay
    
    @ViewBuilder
    private var submissionOverlay: some View {
        if isSubmitting {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .overlay(
                    submissionProgressView
                )
        }
    }
    
    @ViewBuilder
    private var submissionProgressView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Submitting review...")
                .font(.subheadline)
            
            ProgressView(value: submitProgress, total: 1.0)
                .frame(width: 150)
        }
        .padding(24)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 10)
    }
    
    // MARK: - Helper Methods
    
    private func ratingText(for rating: Int) -> String {
        switch rating {
        case 1: return "Poor"
        case 2: return "Fair"
        case 3: return "Good"
        case 4: return "Very Good"
        case 5: return "Excellent"
        default: return ""
        }
    }
    
    private func submitReview() async {
        isSubmitting = true
        submitProgress = 0.2
        
        do {
            // Simulate progress for better UX
            try await Task.sleep(nanoseconds: 200_000_000)
            submitProgress = 0.5
            
            _ = try await firebase.createReview(
                for: userId,
                rating: rating,
                text: reviewText,
                images: reviewImages
            )
            
            submitProgress = 1.0
            
            // Small delay to show completion
            try await Task.sleep(nanoseconds: 300_000_000)
            
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            isSubmitting = false
            submitProgress = 0
        }
    }
}
// MARK: - Followers/Following List Views
struct FollowersListView: View {
    let userId: String
    @Environment(\.dismiss) var dismiss
    @State private var followers: [User] = []
    @StateObject private var firebase = FirebaseService.shared
    
    var body: some View {
        NavigationView {
            List(followers) { follower in
                NavigationLink(destination: EnhancedProfileView(userId: follower.id ?? "")) {
                    HStack {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(String(follower.name.first ?? "U"))
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading) {
                            Text(follower.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text(follower.email)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Followers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                followers = await firebase.getFollowers(for: userId)
            }
        }
    }
}

struct FollowingListView: View {
    let userId: String
    @Environment(\.dismiss) var dismiss
    @State private var following: [User] = []
    @StateObject private var firebase = FirebaseService.shared
    
    var body: some View {
        NavigationView {
            List(following) { user in
                NavigationLink(destination: EnhancedProfileView(userId: user.id ?? "")) {
                    HStack {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(String(user.name.first ?? "U"))
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading) {
                            Text(user.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text(user.email)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Following")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                following = await firebase.getFollowing(for: userId)
            }
        }
    }
}

// MARK: - Additional Supporting Views
struct SavedReelThumbnail: View {
    let reel: Reel
    
    var body: some View {
        NavigationLink(destination: ReelViewerView(reel: reel)) {
            AsyncImage(url: URL(string: reel.thumbnailURL ?? reel.videoURL)) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: UIScreen.main.bounds.width / 3 - 2, height: 180)
                    .clipped()
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: UIScreen.main.bounds.width / 3 - 2, height: 180)
                    .overlay(
                        Image(systemName: "play.rectangle")
                            .foregroundColor(.gray)
                    )
            }
        }
    }
}

struct SavedPostCard: View {
    let post: ServicePost
    
    var body: some View {
        NavigationLink(destination: PostDetailView(post: post)) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(post.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(post.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    HStack {
                        if let price = post.price {
                            Text("$\(Int(price))")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                        
                        Spacer()
                        
                        Text(post.isRequest ? "REQUEST" : "OFFER")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(post.isRequest ? .orange : .blue)
                    }
                }
                
                Spacer()
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }
}

// MARK: - Reply/Edit Views
struct ReplyToReviewView: View {
    let reviewId: String
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var replyText = ""
    @State private var isSubmitting = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Your Reply") {
                    TextEditor(text: $replyText)
                        .frame(minHeight: 150)
                }
            }
            .navigationTitle("Reply to Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") {
                        Task {
                            isSubmitting = true
                            do {
                                try await firebase.replyToReview(reviewId, replyText: replyText)
                                dismiss()
                            } catch {
                                print("Error replying: \(error)")
                                isSubmitting = false
                            }
                        }
                    }
                    .disabled(replyText.isEmpty || isSubmitting)
                }
            }
        }
    }
}

struct EditReviewView: View {
    let review: Review
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var rating: Int
    @State private var reviewText: String
    @State private var isSubmitting = false
    
    init(review: Review) {
        self.review = review
        _rating = State(initialValue: review.rating)
        _reviewText = State(initialValue: review.text)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Rating") {
                    HStack {
                        ForEach(1...5, id: \.self) { star in
                            Button(action: { rating = star }) {
                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
                
                Section("Review") {
                    TextEditor(text: $reviewText)
                        .frame(minHeight: 150)
                }
            }
            .navigationTitle("Edit Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            isSubmitting = true
                            do {
                                try await firebase.updateReview(review.id ?? "", rating: rating, text: reviewText)
                                dismiss()
                            } catch {
                                print("Error updating review: \(error)")
                                isSubmitting = false
                            }
                        }
                    }
                    .disabled(reviewText.isEmpty || isSubmitting)
                }
            }
        }
    }
}

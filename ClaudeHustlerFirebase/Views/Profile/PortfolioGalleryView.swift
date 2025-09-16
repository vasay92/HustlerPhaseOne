// PortfolioGalleryView.swift
// Path: ClaudeHustlerFirebase/Views/Profile/PortfolioGalleryView.swift

import SwiftUI
import PhotosUI
import FirebaseFirestore

// MARK: - Identifiable Wrapper for String
// PortfolioGalleryView.swift
// Path: ClaudeHustlerFirebase/Views/Profile/PortfolioGalleryView.swift

import SwiftUI
import PhotosUI
import FirebaseFirestore

// MARK: - Identifiable Wrapper for String
struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
}

struct PortfolioGalleryView: View {
    let card: PortfolioCard
    let isOwner: Bool
    @StateObject private var firebase = FirebaseService.shared
    @Environment(\.dismiss) var dismiss
    @State private var selectedImageIndex = 0
    @State private var showingImagePicker = false
    @State private var showingDeleteConfirmation = false
    @State private var showingEditSheet = false
    @State private var isAddingImages = false
    @State private var newImages: [UIImage] = []
    @State private var imageToDelete: String?
    @State private var mediaURLs: [String] = []
    @State private var selectedImageURL: IdentifiableString?
    
    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                        imageGridSection
                    }
                    .padding(.vertical)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    toolbarContent
                }
                
                // Floating Add Button
                if isOwner {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: { showingImagePicker = true }) {
                                Image(systemName: "plus")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(width: 56, height: 56)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                                    .shadow(radius: 4)
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(images: $newImages, singleImage: nil)
        }
        .sheet(isPresented: $showingEditSheet) {
            EditPortfolioDetailsView(card: card)
        }
        .fullScreenCover(item: $selectedImageURL) { identifiableURL in
            ImageViewerView(
                imageURL: identifiableURL.value,
                allImageURLs: mediaURLs,
                currentIndex: $selectedImageIndex
            )
        }
        .alert("Delete Photo?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let urlToDelete = imageToDelete {
                    deleteImage(url: urlToDelete)
                }
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .onChange(of: newImages) { _, images in
            if !images.isEmpty {
                Task {
                    await addMoreImages(images)
                }
            }
        }
        .onAppear {
            mediaURLs = card.mediaURLs
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            if let description = card.description, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Text("Created \(card.createdAt, style: .date)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var imageGridSection: some View {
        if mediaURLs.isEmpty {
            emptyStateView
        } else {
            imageGrid
        }
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No photos yet")
                .font(.headline)
                .foregroundColor(.gray)
            
            if isOwner {
                Text("Tap + to add photos")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }
    
    @ViewBuilder
    private var imageGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 2),
            GridItem(.flexible(), spacing: 2),
            GridItem(.flexible(), spacing: 2)
        ], spacing: 2) {
            ForEach(Array(mediaURLs.enumerated()), id: \.offset) { index, url in
                gridImageItem(at: index, url: url)
            }
        }
        .padding(.horizontal, 2)
    }
    
    @ViewBuilder
    private func gridImageItem(at index: Int, url: String) -> some View {
        let imageSize = UIScreen.main.bounds.width / 3 - 2
        
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: imageSize, height: imageSize)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedImageIndex = index
                            selectedImageURL = IdentifiableString(value: url)
                        }
                case .failure(_):
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: imageSize, height: imageSize)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: imageSize, height: imageSize)
                        .overlay(ProgressView())
                @unknown default:
                    EmptyView()
                }
            }
            
            if isOwner {
                Button(action: {
                    imageToDelete = url
                    showingDeleteConfirmation = true
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
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Done") { dismiss() }
        }
        
        if isOwner {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showingEditSheet = true }) {
                        Label("Edit Title", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive, action: {
                        Task {
                            await deletePortfolioCard()
                        }
                    }) {
                        Label("Delete Portfolio", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
    
    private func addMoreImages(_ images: [UIImage]) async {
        isAddingImages = true
        
        do {
            guard let userId = firebase.currentUser?.id,
                  let cardId = card.id else { return }
            
            var newURLs: [String] = []
            for (index, image) in images.enumerated() {
                let path = "portfolio/\(userId)/\(cardId)/\(UUID().uuidString)_\(index).jpg"
                let url = try await firebase.uploadImage(image, path: path)
                newURLs.append(url)
            }
            
            // Update the card with new images
            mediaURLs.append(contentsOf: newURLs)
            
            // Update in Firestore
            try await Firestore.firestore()
                .collection("portfolioCards")
                .document(cardId)
                .updateData([
                    "mediaURLs": mediaURLs,
                    "updatedAt": Date()
                ])
            
            newImages = []
        } catch {
            print("Error adding images: \(error)")
        }
        
        isAddingImages = false
    }
    
    private func deleteImage(url: String) {
        guard let cardId = card.id else { return }
        
        mediaURLs.removeAll { $0 == url }
        
        Task {
            do {
                try await Firestore.firestore()
                    .collection("portfolioCards")
                    .document(cardId)
                    .updateData([
                        "mediaURLs": mediaURLs,
                        "updatedAt": Date()
                    ])
            } catch {
                print("Error deleting image: \(error)")
            }
        }
    }
    
    private func deletePortfolioCard() async {
        guard let cardId = card.id else { return }
        
        do {
            try await Firestore.firestore()
                .collection("portfolioCards")
                .document(cardId)
                .delete()
            
            dismiss()
        } catch {
            print("Error deleting portfolio card: \(error)")
        }
    }
}

// Rest of the file remains the same (ImageViewerView and EditPortfolioDetailsView)
// ... [Keep the rest of the code as is]
// MARK: - Image Viewer for full screen viewing
struct ImageViewerView: View {
    let imageURL: String
    let allImageURLs: [String]
    @Binding var currentIndex: Int
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            TabView(selection: $currentIndex) {
                ForEach(Array(allImageURLs.enumerated()), id: \.offset) { index, url in
                    AsyncImage(url: URL(string: url)) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle())
            
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    Text("\(currentIndex + 1) / \(allImageURLs.count)")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(20)
                    
                    Spacer()
                    
                    // Placeholder for share button
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding()
                
                Spacer()
            }
        }
    }
}

// MARK: - Edit Portfolio Details View
// MARK: - Edit Portfolio Details View
struct EditPortfolioDetailsView: View {
    let card: PortfolioCard
    @Environment(\.dismiss) var dismiss
    @State private var title: String = ""
    
    init(card: PortfolioCard) {
        self.card = card
        _title = State(initialValue: card.title)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Portfolio Title") {
                    TextField("Enter title", text: $title)
                }
            }
            .navigationTitle("Edit Title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await updateDetails()
                        }
                    }
                }
            }
        }
    }
    
    private func updateDetails() async {
        guard let cardId = card.id else { return }
        
        do {
            try await Firestore.firestore()
                .collection("portfolioCards")
                .document(cardId)
                .updateData([
                    "title": title,
                    "updatedAt": Date()
                ])
            dismiss()
        } catch {
            print("Error updating details: \(error)")
        }
    }
}

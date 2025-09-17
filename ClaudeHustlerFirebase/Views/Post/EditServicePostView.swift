// EditServicePostView.swift
// Path: ClaudeHustlerFirebase/Views/Post/EditServicePostView.swift

import SwiftUI
import PhotosUI

struct EditServicePostView: View {
    let post: ServicePost
    @StateObject private var firebase = FirebaseService.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var title: String
    @State private var description: String
    @State private var selectedCategory: ServiceCategory
    @State private var price: String
    @State private var location: String
    @State private var existingImageURLs: [String]
    @State private var newImages: [UIImage] = []
    @State private var showingImagePicker = false
    @State private var isSaving = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccessMessage = false
    
    init(post: ServicePost) {
        self.post = post
        _title = State(initialValue: post.title)
        _description = State(initialValue: post.description)
        _selectedCategory = State(initialValue: post.category)
        _price = State(initialValue: post.price != nil ? String(Int(post.price!)) : "")
        _location = State(initialValue: post.location ?? "")
        _existingImageURLs = State(initialValue: post.mediaURLs)  // FIXED: using mediaURLs
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(4...8)
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(ServiceCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                }
                
                Section("Pricing & Location") {
                    HStack {
                        Text("$")
                        TextField(post.isRequest ? "Budget" : "Price", text: $price)
                            .keyboardType(.numberPad)
                    }
                    TextField("Service location (optional)", text: $location)
                }
                
                Section("Photos") {
                    if !existingImageURLs.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Current Photos")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(Array(existingImageURLs.enumerated()), id: \.offset) { index, imageURL in
                                        AsyncImage(url: URL(string: imageURL)) { image in
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        } placeholder: {
                                            ProgressView()
                                        }
                                        .frame(width: 80, height: 80)
                                        .cornerRadius(8)
                                        .overlay(
                                            Button(action: {
                                                existingImageURLs.remove(at: index)
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.white)
                                                    .background(Circle().fill(Color.black.opacity(0.5)))
                                            }
                                            .offset(x: 30, y: -30)
                                        )
                                    }
                                }
                            }
                        }
                    }
                    
                    if !newImages.isEmpty {
                        VStack(alignment: .leading) {
                            Text("New Photos to Add")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(Array(newImages.enumerated()), id: \.offset) { index, image in
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .cornerRadius(8)
                                            .overlay(
                                                Button(action: {
                                                    newImages.remove(at: index)
                                                }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundColor(.white)
                                                        .background(Circle().fill(Color.black.opacity(0.5)))
                                                }
                                                .offset(x: 30, y: -30)
                                            )
                                    }
                                }
                            }
                        }
                    }
                    
                    Button(action: {
                        showingImagePicker = true
                    }) {
                        Label("Add Photos", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(existingImageURLs.count + newImages.count >= 10)
                    
                    if existingImageURLs.count + newImages.count >= 10 {
                        Text("Maximum 10 photos allowed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(isSaving || title.isEmpty || description.isEmpty)
                }
            }
            .overlay {
                if isSaving {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay {
                            VStack(spacing: 20) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)
                                
                                Text("Saving changes...")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            .padding(30)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(20)
                        }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .alert("Success", isPresented: $showingSuccessMessage) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your post has been updated successfully!")
            }
            .sheet(isPresented: $showingImagePicker) {
                EditImagePicker(images: $newImages, maxSelection: 10 - existingImageURLs.count)
            }
        }
    }
    
    private func saveChanges() {
        guard !title.isEmpty, !description.isEmpty else {
            errorMessage = "Title and description are required"
            showingError = true
            return
        }
        
        isSaving = true
        
        Task {
            do {
                // Upload new images if any
                var allImageURLs = existingImageURLs
                
                if !newImages.isEmpty {
                    for image in newImages {
                        // Generate a unique path for each image
                        let imagePath = "posts/\(post.id ?? UUID().uuidString)/\(UUID().uuidString).jpg"
                        let url = try await firebase.uploadImage(image, path: imagePath)
                        allImageURLs.append(url)
                    }
                }
                
                // Update the post
                var updatedPost = post
                updatedPost.title = title
                updatedPost.description = description
                updatedPost.category = selectedCategory
                updatedPost.price = Double(price)
                updatedPost.location = location.isEmpty ? nil : location
                updatedPost.mediaURLs = allImageURLs
                updatedPost.updatedAt = Date()
                
                try await firebase.updatePost(
                    postId: post.id ?? "",
                    title: title,
                    description: description,
                    category: selectedCategory,
                    price: Double(price),
                    location: location.isEmpty ? nil : location,
                    imageURLs: allImageURLs
                )
                
                await MainActor.run {
                    showingSuccessMessage = true
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isSaving = false
                }
            }
        }
    }
}

// MARK: - Image Picker (Renamed to EditImagePicker to avoid conflict)
struct EditImagePicker: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    let maxSelection: Int
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = maxSelection
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: EditImagePicker
        
        init(_ parent: EditImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.presentationMode.wrappedValue.dismiss()
            
            for result in results {
                let itemProvider = result.itemProvider
                
                if itemProvider.canLoadObject(ofClass: UIImage.self) {
                    itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                        if let image = image as? UIImage {
                            DispatchQueue.main.async {
                                self.parent.images.append(image)
                            }
                        }
                    }
                }
            }
        }
    }
}

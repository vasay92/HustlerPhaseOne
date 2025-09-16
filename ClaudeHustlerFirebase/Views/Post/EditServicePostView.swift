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
        _existingImageURLs = State(initialValue: post.imageURLs)
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
                                                    .background(Color.black.opacity(0.6))
                                                    .clipShape(Circle())
                                            }
                                            .padding(4),
                                            alignment: .topTrailing
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
                                                        .background(Color.black.opacity(0.6))
                                                        .clipShape(Circle())
                                                }
                                                .padding(4),
                                                alignment: .topTrailing
                                            )
                                    }
                                }
                            }
                        }
                    }
                    
                    Button(action: { showingImagePicker = true }) {
                        Label("Add Photos", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                
                Section("Post Status") {
                    if post.status == .active {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Active")
                                .foregroundColor(.green)
                            Spacer()
                            Text("Post is currently visible")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack {
                            Image(systemName: post.status == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(post.status == .completed ? .orange : .red)
                            Text(post.status == .completed ? "Completed" : "Cancelled")
                                .foregroundColor(post.status == .completed ? .orange : .red)
                            Spacer()
                        }
                    }
                }
                
                Section {
                    Button(action: {
                        Task {
                            await saveChanges()
                        }
                    }) {
                        if isSaving {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            Text("Save Changes")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(title.isEmpty || description.isEmpty || isSaving)
                }
            }
            .navigationTitle("Edit Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            EditPostImagePicker(images: $newImages)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert("Success!", isPresented: $showingSuccessMessage) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your post has been updated successfully!")
        }
    }
    
    private func saveChanges() async {
        guard let postId = post.id else { return }
        
        isSaving = true
        
        do {
            var newImageURLs: [String] = []
            if !newImages.isEmpty {
                for (index, image) in newImages.enumerated() {
                    let path = "services/\(post.userId)/\(UUID().uuidString)_\(index).jpg"
                    let url = try await firebase.uploadImage(image, path: path)
                    newImageURLs.append(url)
                }
            }
            
            let allImageURLs = existingImageURLs + newImageURLs
            let priceValue = Double(price) ?? 0
            
            try await firebase.updatePost(
                postId: postId,
                title: title,
                description: description,
                category: selectedCategory,
                price: priceValue > 0 ? priceValue : nil,
                location: location.isEmpty ? nil : location,
                imageURLs: allImageURLs
            )
            
            showingSuccessMessage = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            isSaving = false
        }
    }
}

// Local ImagePicker wrapper to avoid cross-file reference issues
struct EditPostImagePicker: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 10
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: EditPostImagePicker
        
        init(_ parent: EditPostImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard !results.isEmpty else { return }
            
            for result in results {
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
                        if let image = image as? UIImage {
                            DispatchQueue.main.async {
                                self?.parent.images.append(image)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MainTabView.swift
// Path: ClaudeHustlerFirebase/Views/MainTabView.swift

import SwiftUI
import PhotosUI

// MARK: - Enums
enum CameraMode {
    case status, reel
}

enum ActiveSheet: Identifiable {
    case serviceForm
    case camera(mode: CameraMode)
    
    var id: String {
        switch self {
        case .serviceForm:
            return "serviceForm"
        case .camera(let mode):
            return "camera_\(mode == .status ? "status" : "reel")"
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @StateObject private var firebase = FirebaseService.shared
    @State private var selectedTab = 0
    @State private var showingPostOptions = false
    @State private var previousTab = 0
    @State private var activeSheet: ActiveSheet?
    @State private var pendingSheet: ActiveSheet?
    
    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(0)
                
                ServicesView()
                    .tabItem {
                        Label("Services", systemImage: "briefcase.fill")
                    }
                    .tag(1)
                
                // Placeholder for Post tab - this view will never actually show
                Color.clear
                    .tabItem {
                        Label("Post", systemImage: "plus.circle.fill")
                    }
                    .tag(2)
                
                ReelsView()
                    .tabItem {
                        Label("Reels", systemImage: "play.rectangle.fill")
                    }
                    .tag(3)
                
                EnhancedProfileView(userId: firebase.currentUser?.id ?? "")
                    .tabItem {
                        Label("Profile", systemImage: "person.fill")
                    }
                    .tag(4)
            }
            .accentColor(.blue)
            .onChange(of: selectedTab) { oldValue, newValue in
                if newValue == 2 {
                    // Post tab was selected - show options and revert to previous tab
                    showingPostOptions = true
                    selectedTab = previousTab
                } else {
                    // Normal tab selection - store as previous tab
                    previousTab = newValue
                }
            }
        }
        .sheet(isPresented: $showingPostOptions, onDismiss: {
            // When sheet dismisses, show the pending sheet if any
            if let pending = pendingSheet {
                activeSheet = pending
                pendingSheet = nil
            }
        }) {
            PostOptionsSheet(pendingSheet: $pendingSheet)
        }
        .fullScreenCover(item: $activeSheet) { sheet in
            switch sheet {
            case .serviceForm:
                CreateServicePostView()
            case .camera(let mode):
                CameraView(mode: mode)
            }
        }
    }
}

// MARK: - Post Options Sheet
struct PostOptionsSheet: View {
    @Binding var pendingSheet: ActiveSheet?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Handle bar
                Capsule()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 40, height: 5)
                    .padding(.top, 10)
                
                Text("Create")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.vertical, 20)
                
                VStack(spacing: 16) {
                    // Services Option
                    PostOptionButton(
                        icon: "briefcase.fill",
                        title: "Services",
                        subtitle: "Offer or request a service",
                        color: .blue,
                        action: {
                            pendingSheet = .serviceForm
                            dismiss()
                        }
                    )
                    
                    // Status Option
                    PostOptionButton(
                        icon: "circle.dashed",
                        title: "Status",
                        subtitle: "Share what you're working on (24hr)",
                        color: .orange,
                        action: {
                            pendingSheet = .camera(mode: .status)
                            dismiss()
                        }
                    )
                    
                    // Reel Option
                    PostOptionButton(
                        icon: "play.rectangle.fill",
                        title: "Reel",
                        subtitle: "Create a video showcasing your skills",
                        color: .purple,
                        action: {
                            pendingSheet = .camera(mode: .reel)
                            dismiss()
                        }
                    )
                }
                .padding()
                
                Spacer()
                
                // Cancel Button
                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Post Option Button
struct PostOptionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(color)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

// Update this section in MainTabView.swift - CreateServicePostView

struct CreateServicePostView: View {
    @StateObject private var firebase = FirebaseService.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var isOfferingService = true  // true = Offer, false = Request
    @State private var title = ""
    @State private var description = ""
    @State private var selectedCategory: ServiceCategory = .other
    @State private var price = ""
    @State private var location = ""
    @State private var selectedImages: [UIImage] = []
    @State private var showingImagePicker = false
    @State private var isUrgent = false
    @State private var availability = ""
    @State private var isCreatingPost = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccessMessage = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab Selector
                HStack(spacing: 0) {
                    Button(action: { isOfferingService = true }) {
                        VStack(spacing: 8) {
                            Image(systemName: "storefront")
                                .font(.title2)
                            Text("Offer a Service")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isOfferingService ? Color.blue : Color.clear)
                        .foregroundColor(isOfferingService ? .white : .gray)
                    }
                    
                    Button(action: { isOfferingService = false }) {
                        VStack(spacing: 8) {
                            Image(systemName: "person.fill.questionmark")
                                .font(.title2)
                            Text("Request a Service")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(!isOfferingService ? Color.orange : Color.clear)
                        .foregroundColor(!isOfferingService ? .white : .gray)
                    }
                }
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding()
                
                // Form
                Form {
                    Section("Details") {
                        TextField(isOfferingService ? "Service Title" : "What do you need?", text: $title)
                        
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
                            TextField(isOfferingService ? "Your rate" : "Budget", text: $price)
                                .keyboardType(.decimalPad)
                        }
                        
                        TextField("Service location (optional)", text: $location)
                    }
                    
                    if !isOfferingService {
                        Section("Request Options") {
                            Toggle("Urgent Request", isOn: $isUrgent)
                            if isUrgent {
                                TextField("When do you need this?", text: $availability)
                            }
                        }
                    }
                    
                    Section("Photos") {
                        if selectedImages.isEmpty {
                            Button(action: { showingImagePicker = true }) {
                                HStack {
                                    Image(systemName: "camera.fill")
                                    Text("Add Photos")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 80, height: 80)
                                                .cornerRadius(8)
                                            
                                            // Remove button
                                            Button(action: {
                                                selectedImages.remove(at: index)
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.white)
                                                    .background(Color.black.opacity(0.6))
                                                    .clipShape(Circle())
                                            }
                                            .padding(4)
                                        }
                                    }
                                    
                                    Button(action: { showingImagePicker = true }) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(.systemGray5))
                                                .frame(width: 80, height: 80)
                                            Image(systemName: "plus")
                                                .foregroundColor(.gray)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Post Button
                Button(action: {
                    Task {
                        await createPost()
                    }
                }) {
                    if isCreatingPost {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray)
                            .cornerRadius(12)
                    } else {
                        Text(isOfferingService ? "Post Service" : "Post Request")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                (title.isEmpty || description.isEmpty) ? Color.gray :
                                (isOfferingService ? Color.blue : Color.orange)
                            )
                            .cornerRadius(12)
                    }
                }
                .disabled(title.isEmpty || description.isEmpty || isCreatingPost)
                .padding()
            }
            .navigationTitle(isOfferingService ? "Offer Service" : "Request Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreatingPost)
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(images: $selectedImages)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert("Success!", isPresented: $showingSuccessMessage) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your \(isOfferingService ? "service" : "request") has been posted successfully!")
        }
    }
    
    private func createPost() async {
        isCreatingPost = true
        let priceValue = Double(price) ?? 0
        
        do {
            // Upload images first and get URLs
            var imageURLs: [String] = []
            if !selectedImages.isEmpty {
                guard let userId = firebase.currentUser?.id else {
                    throw NSError(domain: "CreatePost", code: 0, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
                }
                
                // Upload each image individually
                for (index, image) in selectedImages.enumerated() {
                    let path = "services/\(userId)/\(UUID().uuidString)_\(index).jpg"
                    let url = try await firebase.uploadImage(image, path: path)
                    imageURLs.append(url)
                }
                
                print("Uploaded \(imageURLs.count) images successfully")
            }
            
            let postId = try await firebase.createServicePost(
                title: title,
                description: description,
                category: selectedCategory,
                price: priceValue > 0 ? priceValue : nil,
                isRequest: !isOfferingService,
                location: location.isEmpty ? nil : location,
                isUrgent: isUrgent,
                imageURLs: imageURLs
            )
            
            print("Created post with ID: \(postId)")
            
            // Refresh user posts to ensure the new post appears in My Posts tab
            await firebase.refreshUserPosts()
            
            // Show success message
            showingSuccessMessage = true
            
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            isCreatingPost = false
            print("Error creating post: \(error)")
        }
    }
}
// MARK: - Camera View
struct CameraView: View {
    let mode: CameraMode
    @Environment(\.dismiss) var dismiss
    @State private var capturedImage: UIImage?
    @State private var showingImagePicker = true
    @State private var caption = ""
    @State private var isPosting = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let image = capturedImage {
                    // Preview captured image
                    VStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                        
                        // Caption input
                        HStack {
                            TextField("Add a caption...", text: $caption)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Button(action: {
                                Task {
                                    await postContent()
                                }
                            }) {
                                if isPosting {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .frame(width: 20, height: 20)
                                } else {
                                    Text("Post")
                                }
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(isPosting ? Color.gray : Color.blue)
                            .cornerRadius(20)
                            .disabled(isPosting)
                        }
                        .padding()
                    }
                } else {
                    // Camera placeholder
                    VStack {
                        Image(systemName: mode == .status ? "circle.dashed" : "play.rectangle")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                        
                        Text(mode == .status ? "Take a photo for your status" : "Record a reel")
                            .foregroundColor(.white)
                        
                        Button("Open Camera") {
                            showingImagePicker = true
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                }
                
                // Close button
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
                        .padding()
                        .disabled(isPosting)
                        
                        Spacer()
                    }
                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(images: .constant([]), singleImage: $capturedImage)
        }
    }
    
    private func postContent() async {
        guard let image = capturedImage else { return }
        
        isPosting = true
        let firebase = FirebaseService.shared
        
        do {
            if mode == .status {
                let statusId = try await firebase.createStatus(image: image, caption: caption.isEmpty ? nil : caption)
                print("✅ Created status with ID: \(statusId)")
                // The status is now in firebase.statuses array with proper ID
            } else {
                let reelId = try await firebase.createImageReel(
                    image: image,
                    title: "New Reel",
                    description: caption.isEmpty ? "Check out my skills!" : caption
                )
                print("✅ Created reel with ID: \(reelId)")
                // The reel is now in firebase.reels array with proper ID
            }
            dismiss()
        } catch {
            print("❌ Error posting content: \(error)")
            isPosting = false
        }
    }
}

// MARK: - Image Picker
import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    var singleImage: Binding<UIImage?>?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = singleImage != nil ? 1 : 10 // Allow up to 10 images for multi-select
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
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
                                if let singleImage = self?.parent.singleImage {
                                    singleImage.wrappedValue = image
                                } else {
                                    self?.parent.images.append(image)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

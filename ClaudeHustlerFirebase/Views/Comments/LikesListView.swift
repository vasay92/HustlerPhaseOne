// LikesListView.swift
import SwiftUI
import FirebaseFirestore

struct LikesListView: View {
    let reelId: String
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var likes: [ReelLike] = []
    @State private var likesListener: ListenerRegistration?
    
    var body: some View {
        NavigationView {
            Group {
                if likes.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "heart")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("No likes yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    List(likes) { like in
                        NavigationLink(destination: EnhancedProfileView(userId: like.userId)) {
                            HStack {
                                // Profile image
                                if let imageURL = like.userProfileImage, !imageURL.isEmpty {
                                    AsyncImage(url: URL(string: imageURL)) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 40, height: 40)
                                            .clipShape(Circle())
                                    } placeholder: {
                                        Circle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 40, height: 40)
                                    }
                                } else {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Text(String(like.userName?.first ?? "U"))
                                                .foregroundColor(.white)
                                        )
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(like.userName ?? "User")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    Text(like.likedAt, style: .relative)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Likes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            startListeningToLikes()
        }
        .onDisappear {
            likesListener?.remove()
            firebase.stopListeningToLikes(reelId)
        }
    }
    
    private func startListeningToLikes() {
        likesListener = firebase.listenToReelLikes(reelId) { updatedLikes in
            withAnimation {
                self.likes = updatedLikes
            }
        }
    }
}

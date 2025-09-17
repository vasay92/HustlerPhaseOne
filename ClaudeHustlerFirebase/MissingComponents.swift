

// MissingComponents.swift
// Components that are referenced but not defined anywhere else
// Path: ClaudeHustlerFirebase/MissingComponents.swift

import SwiftUI
import FirebaseFirestore
import AVKit

// MARK: - Reel Viewer View (THIS IS THE ONLY ACTUALLY MISSING COMPONENT)
struct ReelViewerView: View {
    let reel: Reel
    @StateObject private var firebase = FirebaseService.shared
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let videoURL = URL(string: reel.videoURL) {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                        .onAppear {
                            player = AVPlayer(url: videoURL)
                            player?.play()
                            isPlaying = true
                        }
                        .onDisappear {
                            player?.pause()
                            player = nil
                        }
                        .onTapGesture {
                            if isPlaying {
                                player?.pause()
                            } else {
                                player?.play()
                            }
                            isPlaying.toggle()
                        }
                }
                
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
                    }
                    .padding()
                    
                    Spacer()
                    
                    // Reel info overlay
                    VStack(alignment: .leading, spacing: 12) {
                        // Caption instead of title
                        if let caption = reel.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.headline)
                                .foregroundColor(.white)
                                .lineLimit(3)
                        }
                        
                        // User info
                        HStack {
                            if let userName = reel.userName {
                                Text("@\(userName)")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            
                            Spacer()
                        }
                        
                        // Stats
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                            Text("\(reel.likes.count)")
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Text(reel.createdAt, style: .date)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.black.opacity(0.8), Color.clear]),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                }
            }
            .navigationBarHidden(true)
        }
    }
}

import SwiftUI

struct ContentView: View {
    @StateObject private var firebase = FirebaseService.shared
    
    var body: some View {
        Group {
            if firebase.isAuthenticated {
                MainTabView()
            } else {
                LoginView() // Use your existing authentication views
            }
        }
    }
}

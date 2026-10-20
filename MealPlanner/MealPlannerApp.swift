import SwiftUI
import CloudKit
import UIKit

@main @MainActor struct MealPlannerApp: App {
  @UIApplicationDelegateAdaptor(MealPlannerAppDelegate.self) private var appDelegate
  @Environment(\.scenePhase) private var scenePhase
  @State private var store = AppStore()
  @State private var confirmSkipLegacy = false
  var body: some Scene {
    WindowGroup {
      Group {
        if store.state != nil {
          TabView {
            NavigationStack { TripView() }.tabItem { Label("Ostoslista", systemImage: "cart") }
            NavigationStack { DishListView() }.tabItem {
              Label("Ruokalajit", systemImage: "fork.knife")
            }
          }
        } else {
          VStack(spacing: 16) {
            Text(store.loadFailed ? "Tietojen lataaminen epäonnistui." : "Ladataan…")
            if store.loadFailed {
              Button("Yritä uudelleen") { store.load() }
              Button("Jatka ilman vanhoja tietoja") { confirmSkipLegacy = true }
            }
          }
        }
      }
      .task { await store.activateSync() }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { Task { await store.activateSync() } }
      }
      .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
        Task { await store.iCloudAccountChanged() }
      }
      .environment(store)
      .tint(Theme.accent)
      .confirmationDialog(
        "Jatketaanko ilman vanhoja tietoja? Vanhat tiedot säilyvät puhelimessa, mutta niitä ei tuoda sovellukseen. Aloitetaan uusi, tyhjä lista.",
        isPresented: $confirmSkipLegacy, titleVisibility: .visible
      ) {
        Button("Jatka ilman vanhoja tietoja", role: .destructive) { store.load(skipLegacy: true) }
        Button("Peruuta", role: .cancel) {}
      }

    }
  }
}

@MainActor final class MealPlannerAppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    application.registerForRemoteNotifications()
    return true
  }
}

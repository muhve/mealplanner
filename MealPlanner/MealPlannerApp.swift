import SwiftUI

@main @MainActor struct MealPlannerApp: App {
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

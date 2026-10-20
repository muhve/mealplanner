import MealPlannerCore
import SwiftUI

@MainActor struct HistoryListView: View {
  @Environment(AppStore.self) private var store
  private var history: [ArchivedTrip] { store.state?.history ?? [] }
  var body: some View {
    List {
      if history.isEmpty {
        Section {
          Text("Ei vielä aiempia").font(.headline)
          Text("Kun painat ostoslistalla ”Valmis”, lista tallentuu tänne.").foregroundStyle(
            Theme.muted)
        }.listRowBackground(Theme.surface)
      }
      ForEach(history, id: \.id) { trip in
        NavigationLink {
          HistoryDetailView(id: trip.id)
        } label: {
          VStack(alignment: .leading, spacing: 6) {
            Text(formatDay(trip.archivedAt, timeZone: TimeZone(identifier: "Europe/Helsinki")!))
              .font(.headline)
            Text(
              "\(trip.meals.isEmpty ? "Ei ruokia" : trip.meals.joined(separator: ", ")) · \(tripCounts(trip.items, trip.extras).toBuy) tuotetta"
            ).font(.subheadline).foregroundStyle(Theme.muted)
          }
        }.listRowBackground(Theme.surface)
      }
    }.warmList().navigationTitle("Aiemmat ostosreissut")
  }
}
@MainActor struct HistoryDetailView: View {
  @Environment(AppStore.self) private var store
  let id: String
  private var trip: ArchivedTrip? { store.state?.history.first { $0.id == id } }
  var body: some View {
    List {
      if let trip {
        if !trip.meals.isEmpty {
          Text("Ruoat: \(trip.meals.joined(separator: ", "))").foregroundStyle(Theme.muted)
            .listRowBackground(Theme.surface)
        }
        if trip.items.isEmpty && trip.extras.isEmpty {
          Text("Listalla ei ollut tuotteita.").foregroundStyle(Theme.muted)
        } else {
          // Sort the combined snapshot, including extras, as in the original app.
          let combined =
            trip.items
            + trip.extras.map {
              ArchivedItem(name: $0.name, amount: nil, unit: "", checked: $0.checked, have: $0.have)
            }
          ForEach(Array(historyOrder(combined).enumerated()), id: \.offset) { _, item in
            HStack {
              Text(item.have ? "🏠" : item.checked ? "✓" : "").frame(width: 24)
              ItemLabel(
                name: item.name, amount: item.amount, unit: item.unit, checked: item.checked)
            }.listRowBackground(Theme.surface)
          }
        }
      } else {
        Text("Ostoslistaa ei löytynyt.")
      }
    }.warmList().navigationTitle(
      trip.map {
        "Ostosreissu \(formatDay($0.archivedAt, timeZone: TimeZone(identifier: "Europe/Helsinki")!))"
      } ?? "Aiemmat"
    ).navigationBarTitleDisplayMode(.inline)
  }
}

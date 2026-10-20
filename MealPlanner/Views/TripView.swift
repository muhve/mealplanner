import MealPlannerCore
import SwiftUI

private struct UndoMark: Identifiable {
  let id = UUID()
  let key: String
  let name: String
  let extra: Bool
}
@MainActor struct TripView: View {
  @Environment(AppStore.self) private var store
  @State private var picking = false
  @State private var creating = false
  @State private var createAfterPicker = false
  @State private var editing: ShopItem?
  @State private var confirming = false
  @State private var newExtra = ""
  @State private var toast: UndoMark?
  @State private var error: String?
  private var trip: ReadTrip { readTrip(store.state ?? emptyState(0)) }

  var body: some View {
    let trip = self.trip
    List {
      if let error { Text(error).foregroundStyle(Theme.error) }
      Section("Ruoat" + (trip.meals.isEmpty ? "" : " · \(trip.meals.count)")) {
        if trip.meals.isEmpty {
          Text("Lisää ruoat, joihin ostat ainekset. Niiden ainekset kootaan listaksi.")
            .foregroundStyle(Theme.muted)
        }
        ForEach(trip.meals, id: \.id) { meal in
          HStack {
            Text(meal.name)
            Spacer()
            Button {
              error = store.change { removeMeal($0, meal.id) }
              toast = nil
            } label: {
              Image(systemName: "xmark")
            }
            .accessibilityLabel("Poista \(meal.name)")
          }
        }
        Button("+ Lisää ruoka") { picking = true }
      }.listRowBackground(Theme.surface)
      if let status = statusText(tripCounts(trip.items, trip.extras)) {
        Text(status).font(.subheadline).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
          .listRowBackground(Color.clear)
      }
      Section {
        ForEach(uncheckedFirst(trip.items.filter { !$0.have }), id: \.key) { item in itemRow(item) }
      }.listRowBackground(Theme.surface)
      if !trip.removed.isEmpty {
        DisclosureGroup("Poistetut (\(trip.removed.count))") {
          ForEach(trip.removed, id: \.key) { item in
            HStack {
              ItemLabel(name: item.name, amount: item.amount, unit: item.unit)
              Spacer()
              Button("Palauta") { error = store.item(item.key, ItemPatch(removed: false)) }
            }
          }
        }.listRowBackground(Theme.surface)
      }
      Section("Muut ostokset") {
        HStack {
          TextField("esim. kahvi, vessapaperi", text: $newExtra).accessibilityLabel("Uusi tuote")
            .onSubmit(addExtraItem)
          Button("Lisää", action: addExtraItem).disabled(tidy(newExtra).isEmpty)
        }
        if !newExtra.isEmpty {
          SuggestionButtons(query: newExtra) { suggestion in newExtra = suggestion.name }
        }
        ForEach(uncheckedFirst(trip.extras.filter { !$0.have }), id: \.id) { extra in
          extraRow(extra)
        }
      }.listRowBackground(Theme.surface)
      if trip.items.contains(where: \.have) || trip.extras.contains(where: \.have) {
        DisclosureGroup("Kotona (\(tripCounts(trip.items, trip.extras).have))") {
          ForEach(trip.items.filter(\.have), id: \.key) { item in
            HStack {
              ItemLabel(name: item.name, amount: item.amount, unit: item.unit)
              Spacer()
              Button("Ostettava") { error = store.item(item.key, ItemPatch(have: false)) }
            }
          }
          ForEach(trip.extras.filter(\.have), id: \.id) { item in
            HStack {
              Text(item.name)
              Spacer()
              Button("Ostettava") { error = store.extra(item.id, Marks(have: false)) }
            }
          }
        }.listRowBackground(Theme.surface)
      }
      if !trip.meals.isEmpty || !trip.extras.isEmpty {
        Button("✓ Valmis – aloita uusi lista") { confirming = true }.listRowBackground(
          Theme.surface)
      }
    }
    .buttonStyle(.borderless)
    .warmList()
    .navigationTitle("Ostoslista")
    .onAppear { error = nil }
    .toolbar { NavigationLink("Aiemmat") { HistoryListView() } }
    .sheet(
      isPresented: $picking,
      onDismiss: {
        if createAfterPicker {
          createAfterPicker = false
          creating = true
        }
      }
    ) {
      DishPickerView {
        createAfterPicker = true
        picking = false
      }
      .presentationDetents([.medium, .large])
    }
    .sheet(isPresented: $creating) { NavigationStack { DishFormView(dish: nil) } }
    .sheet(item: $editing) { item in ItemEditorView(item: item).presentationDetents([.medium]) }
    .confirmationDialog(
      "Merkitäänkö ostosreissu valmiiksi? Lista siirtyy aiempiin ja aloitetaan uusi, tyhjä lista.",
      isPresented: $confirming, titleVisibility: .visible
    ) {
      Button("Valmis") {
        error = store.change {
          try archiveTrip($0, Date().timeIntervalSince1970 * 1000, store.id())
        }
        if error == nil {
          toast = nil
        }
      }
      Button("Peruuta", role: .cancel) {}
    }
    .safeAreaInset(edge: .bottom) {
      if let toast {
        HStack {
          Text("”\(toast.name)” on jo kotona.").font(.subheadline)
          Spacer()
          Button("Kumoa") {
            if toast.extra {
              error = store.extra(toast.key, Marks(have: false))
            } else {
              error = store.item(toast.key, ItemPatch(have: false))
            }
            self.toast = nil
          }
        }.padding().background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 12))
          .padding()
      }
    }
    .task(id: toast?.id) {
      guard toast != nil else { return }
      do {
        try await Task.sleep(for: .seconds(6))
        toast = nil
      } catch {}
    }
  }
  private func addExtraItem() {
    error = store.change { try addExtra($0, newExtra, store.id()) }
    if error == nil { newExtra = "" }
  }
  private func itemRow(_ item: ShopItem) -> some View {
    HStack(spacing: 12) {
      Button {
        error = store.item(item.key, ItemPatch(checked: !item.checked))
      } label: {
        HStack {
          Image(systemName: item.checked ? "checkmark.square.fill" : "square").font(.title2)
          VStack(alignment: .leading) {
            ItemLabel(name: item.name, amount: item.amount, unit: item.unit, checked: item.checked)
            Text((item.edited ? "Muokattu · " : "") + item.dishes.joined(separator: ", ")).font(
              .caption
            ).foregroundStyle(Theme.muted)
          }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
      }.accessibilityLabel(item.name).accessibilityValue(item.checked ? "Ostettu" : "Ostettava")
      if !item.checked {
        Button("On jo") {
          error = store.item(item.key, ItemPatch(have: true))
          if error == nil {
            toast = UndoMark(key: item.key, name: item.name, extra: false)
          }
        }.accessibilityLabel("On jo: \(item.name)")
      }
      Button {
        editing = item
      } label: {
        Image(systemName: "pencil").frame(minWidth: 44, minHeight: 44)
      }.accessibilityLabel("Muokkaa \(item.name)")
    }
  }
  private func extraRow(_ item: Extra) -> some View {
    HStack {
      Button {
        error = store.extra(item.id, Marks(checked: !item.checked))
      } label: {
        HStack {
          Image(systemName: item.checked ? "checkmark.square.fill" : "square").font(.title2)
          Text(item.name).strikethrough(item.checked).foregroundStyle(
            item.checked ? Theme.muted : Theme.text)
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.accessibilityLabel(item.name).accessibilityValue(item.checked ? "Ostettu" : "Ostettava")
      if !item.checked {
        Button("On jo") {
          error = store.extra(item.id, Marks(have: true))
          if error == nil {
            toast = UndoMark(key: item.id, name: item.name, extra: true)
          }
        }.accessibilityLabel("On jo: \(item.name)")
      }
      Button {
        error = store.change { removeExtra($0, item.id) }
      } label: {
        Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44)
      }.accessibilityLabel("Poista \(item.name)")
    }
  }
}
extension ShopItem: Identifiable { public var id: String { key } }
@MainActor struct ItemLabel: View {
  let name: String
  var amount: Double? = nil
  var unit = ""
  var checked = false
  var body: some View {
    Text([formatAmount(amount), unit, name].filter { !$0.isEmpty }.joined(separator: " "))
      .strikethrough(checked).foregroundStyle(checked ? Theme.muted : Theme.text)
  }
}
@MainActor struct ItemEditorView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let item: ShopItem
  @State private var text: String
  @State private var error: String?
  init(item: ShopItem) {
    self.item = item
    _text = State(initialValue: formatAmount(item.amount))
  }
  var body: some View {
    NavigationStack {
      Form {
        Section("Määrä" + (item.unit.isEmpty ? "" : " (\(item.unit))")) {
          TextField("ei määrää", text: $text).keyboardType(.decimalPad).accessibilityLabel("Määrä")
          Button("Tallenna") {
            guard case .value(let amount) = parseAmount(text) else {
              error = "Määrän pitää olla positiivinen luku, esim. 1,5."
              return
            }
            save(ItemPatch(amount: .some(amount)))
          }
          if let error { Text(error).foregroundStyle(Theme.error) }
          Text(
            "Reseptien mukaan: \(item.recipeAmount == nil ? "ei määrää" : [formatAmount(item.recipeAmount), item.unit].filter { !$0.isEmpty }.joined(separator: " ")) (\(item.dishes.joined(separator: ", ")))"
          ).font(.caption).foregroundStyle(Theme.muted)
        }.listRowBackground(Theme.surface)
        if item.edited {
          Button("Palauta reseptien määrä") { save(ItemPatch(resetAmount: true)) }
            .listRowBackground(Theme.surface)
        }
        Button("Poista listalta", role: .destructive) { save(ItemPatch(removed: true)) }
          .listRowBackground(Theme.surface)
      }.warmList().navigationTitle(item.name).navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Sulje") { dismiss() } }
        .onAppear { error = nil }
    }
  }
  private func save(_ patch: ItemPatch) {
    error = store.item(item.key, patch)
    if error == nil { dismiss() }
  }
}
@MainActor struct DishPickerView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var error: String?
  let create: () -> Void
  private var dishes: [Dish] { store.state?.dishes ?? [] }
  private var shown: [Dish] {
    dishes.filter { fold($0.name).contains(fold(tidy(query))) || tidy(query).isEmpty }
  }
  var body: some View {
    NavigationStack {
      List {
        if let error { Text(error).foregroundStyle(Theme.error) }
        if dishes.isEmpty {
          Text("Ei vielä ruokalajeja. Lisää ensin perheen suosikit.")
          Button("Lisää ruokalaji", action: create)
        } else {
          if dishes.count > 6 { TextField("Hae ruokalajia", text: $query) }
          ForEach(shown, id: \.id) { dish in
            Button {
              error = store.change { try addMeal($0, dish.id, store.id()) }
              if error == nil { dismiss() }
            } label: {
              HStack {
                Text(dish.name)
                Spacer()
                Image(systemName: "plus")
              }
            }
          }
          if shown.isEmpty { Text("Ei osumia.") }
        }
      }.warmList().navigationTitle("Lisää ruoka").navigationBarTitleDisplayMode(.inline)
        .onAppear { error = nil }
        .toolbar { Button("Sulje") { dismiss() } }
    }
  }
}

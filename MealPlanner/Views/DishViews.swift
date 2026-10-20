import MealPlannerCore
import SwiftUI
import PhotosUI
import AVFoundation

@MainActor struct DishListView: View {
  @Environment(AppStore.self) private var store
  @State private var query = ""
  private var dishes: [Dish] { store.state?.dishes ?? [] }
  private var shown: [Dish] {
    let q = fold(tidy(query))
    return dishes.filter {
      q.isEmpty || fold($0.name).contains(q)
        || $0.ingredients.contains { fold($0.name).contains(q) }
    }
  }
  var body: some View {
    List {
      if dishes.isEmpty {
        Section {
          Text("Ei vielä ruokalajeja").font(.headline)
          Text("Tallenna perheen suosikit ainesosineen, niin ostoslistan teko käy nopeasti.")
            .foregroundStyle(Theme.muted)
          NavigationLink("Lisää ensimmäinen ruokalaji") { DishFormView(dish: nil) }
        }.listRowBackground(Theme.surface)
      } else {
        TextField("Hae nimellä tai ainesosalla", text: $query).accessibilityLabel("Hae ruokalajeja")
          .listRowBackground(Theme.surface)
        if shown.isEmpty { Text("Ei osumia haulle ”\(tidy(query))”.").foregroundStyle(Theme.muted) }
        ForEach(shown, id: \.id) { dish in
          NavigationLink {
            DishFormView(dish: dish)
          } label: {
            HStack(spacing: 12) {
              if let photo = dish.photo { DishPhotoView(name: photo, height: 44, width: 44) }
              VStack(alignment: .leading, spacing: 6) {
                Text(dish.name).font(.headline)
                Text(dish.ingredients.isEmpty ? "Ei ainesosia" : ingredientSummary(dish.ingredients))
                  .font(.subheadline).foregroundStyle(Theme.muted)
              }
            }.padding(.vertical, 4)
          }.listRowBackground(Theme.surface)
        }
      }
    }.warmList().navigationTitle("Ruokalajit")
      .toolbar { NavigationLink("+ Uusi") { DishFormView(dish: nil) } }
  }
}
private struct IngredientFormRow: Identifiable {
  let id = UUID()
  var value: FormRow
  init(_ value: FormRow = FormRow(name: "", amount: "", unit: "")) { self.value = value }
}
@MainActor struct DishFormView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let dish: Dish?
  @State private var name: String
  @State private var rows: [IngredientFormRow]
  @State private var error: String?
  @State private var confirm = false
  @State private var editingInstructions = false
  @State private var instructions: String
  @State private var photo: String?
  @State private var createdPhoto: String?
  @State private var photoChoices = false
  @State private var library = false
  @State private var camera = false
  @State private var selection: PhotosPickerItem?
  @State private var loadingPhoto = false
  @FocusState private var focused: UUID?
  init(dish: Dish?) {
    self.dish = dish
    _instructions = State(initialValue: dish?.instructions ?? "")
    _photo = State(initialValue: dish?.photo)
    _name = State(initialValue: dish?.name ?? "")
    _rows = State(
      initialValue: (dish?.ingredients.map {
        IngredientFormRow(FormRow(name: $0.name, amount: formatAmount($0.amount), unit: $0.unit))
      } ?? []) + [IngredientFormRow()])
  }
  var body: some View {
    Form {
      Section("Kansikuva") {
        if let photo {
          DishPhotoView(name: photo, height: 180)
          Button("Vaihda kuva") { photoChoices = true }
          Button("Poista kuva", role: .destructive) { removePhoto() }
        } else {
          Button("Lisää kuva") { photoChoices = true }
        }
        if loadingPhoto { ProgressView("Ladataan kuvaa…") }
      }.disabled(loadingPhoto).listRowBackground(Theme.surface)
      Section("Nimi") {
        TextField("esim. Lohikeitto", text: $name).accessibilityLabel("Nimi")
      }.listRowBackground(Theme.surface)
      Section("Ainesosat") {
        ForEach($rows) { $row in
          VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
              TextField("Ainesosa", text: $row.value.name).focused($focused, equals: row.id)
                .accessibilityLabel("Ainesosa \(number(row.id))")
              Button {
                remove(row.id)
              } label: {
                Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44)
              }.accessibilityLabel("Poista ainesosa \(number(row.id))")
            }
            if focused == row.id {
              SuggestionButtons(query: row.value.name) { suggestion in
                row.value.name = suggestion.name
                if tidy(row.value.unit).isEmpty { row.value.unit = suggestion.unit }
                focused = nil
              }
            }
            HStack {
              TextField("Määrä", text: $row.value.amount).keyboardType(.decimalPad)
                .accessibilityLabel("Määrä \(number(row.id))")
              TextField("Yks.", text: $row.value.unit).autocorrectionDisabled()
                .textInputAutocapitalization(.never).accessibilityLabel("Yksikkö \(number(row.id))")
              Menu("Yks.") {
                ForEach(unitSuggestions(row.value.unit), id: \.self) { unit in
                  Button(unit) { row.value.unit = unit }
                }
              }.accessibilityLabel("Yksikköehdotukset")
            }
          }
        }
        Button("+ Lisää ainesosa") {
          let row = IngredientFormRow()
          rows.append(row)
          focused = row.id
        }.disabled(rows.count >= 100)
      }.listRowBackground(Theme.surface)
      Section("Ohjeet") {
        if dish != nil && !instructions.isEmpty && !editingInstructions {
          Text(instructions).textSelection(.enabled)
          Button("Muokkaa ohjeita") { editingInstructions = true }
        } else {
          TextEditor(text: $instructions)
            .frame(minHeight: 150)
            .scrollContentBackground(.hidden)
            .accessibilityLabel("Ohjeet")
        }
      }.listRowBackground(Theme.surface)
      if let error { Text(error).foregroundStyle(Theme.error) }
      Button("Tallenna", action: save).disabled(loadingPhoto).listRowBackground(Theme.surface)
      if dish != nil {
        Button("Poista ruokalaji", role: .destructive) { confirm = true }.listRowBackground(
          Theme.surface)
      }
    }
    .buttonStyle(.borderless)
    .warmList()
    .navigationTitle(dish == nil ? "Uusi ruokalaji" : "Muokkaa ruokalajia")
    .onAppear { error = nil }
    .confirmationDialog("Kansikuva", isPresented: $photoChoices, titleVisibility: .visible) {
      Button("Valitse kirjastosta") { library = true }
      if UIImagePickerController.isSourceTypeAvailable(.camera) {
        Button("Ota kuva") { requestCamera() }
      }
      Button("Peruuta", role: .cancel) {}
    }
    .photosPicker(isPresented: $library, selection: $selection, matching: .images)
    .onChange(of: selection) { _, item in
      guard let item else { return }
      loadingPhoto = true
      Task { @MainActor in
        defer { loadingPhoto = false; selection = nil }
        do {
          guard let data = try await item.loadTransferable(type: Data.self) else {
            throw CoreError("Kuvan lataaminen epäonnistui.")
          }
          let file = try await PhotoStore.save(data: data)
          acceptPhoto(file)
        } catch {
          self.error = "Kuvan lataaminen epäonnistui."
        }
      }
    }
    .sheet(isPresented: $camera) {
      CameraPicker { image in
        camera = false
        if let image {
          loadingPhoto = true
          Task { @MainActor in
            defer { loadingPhoto = false }
            do {
              let file = try await PhotoStore.save(cameraImage: image)
              acceptPhoto(file)
            } catch { self.error = "Kuvan tallentaminen epäonnistui." }
          }
        }
      }.ignoresSafeArea()
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if dish == nil {
        Button("Peruuta") {
          removePhoto()
          dismiss()
        }
      }
    }
    .confirmationDialog(
      "Poistetaanko ”\(tidy(name).isEmpty ? "ruokalaji" : tidy(name))” pysyvästi? Se poistuu myös nykyiseltä ostoslistalta.",
      isPresented: $confirm, titleVisibility: .visible
    ) {
      Button("Poista", role: .destructive) {
        if let dish {
          error = store.change { deleteDish($0, dish.id) }
          if error == nil { dismiss() }
        }
      }
      Button("Peruuta", role: .cancel) {}
    }
  }
  private func removePhoto() {
    if let createdPhoto { PhotoStore().delete(createdPhoto) }
    createdPhoto = nil
    photo = nil
  }
  private func acceptPhoto(_ file: String) {
    if let createdPhoto { PhotoStore().delete(createdPhoto) }
    createdPhoto = file
    photo = file
    error = nil
  }
  private func requestCamera() {
    Task { @MainActor in
      let status = AVCaptureDevice.authorizationStatus(for: .video)
      let allowed: Bool
      if status == .notDetermined {
        allowed = await AVCaptureDevice.requestAccess(for: .video)
      } else {
        allowed = status == .authorized
      }
      if allowed { camera = true }
      else { error = "Kameran käyttö on estetty. Salli se Asetuksista." }
    }
  }
  private func number(_ id: UUID) -> Int { (rows.firstIndex { $0.id == id } ?? 0) + 1 }
  private func unitSuggestions(_ query: String) -> [String] {
    let items = UNITS.filter { query.isEmpty || $0.contains(query) }
    return items.count == 1 && items[0] == query ? [] : items
  }
  private func remove(_ id: UUID) {
    if rows.count == 1 { rows = [IngredientFormRow()] } else { rows.removeAll { $0.id == id } }
  }
  private func save() {
    do {
      let body = try toDishBody(name, rows.map(\.value), instructions: instructions, photo: photo)
      let saved = Dish(id: dish?.id ?? store.id(), name: body.name, ingredients: body.ingredients,
                       photo: body.photo, instructions: body.instructions)
      error = store.change { try saveDish($0, saved) }
      if error == nil { createdPhoto = nil; dismiss() }
    } catch { self.error = error.localizedDescription }
  }
}
@MainActor struct SuggestionButtons: View {
  @Environment(AppStore.self) private var store
  let query: String
  let pick: (Suggestion) -> Void
  private var suggestions: [Suggestion] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }
    return visibleSuggestions(
      (trimmed, suggestIngredients(store.state?.dishes ?? [], trimmed)), trimmed)
  }
  var body: some View {
    if !suggestions.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack {
          ForEach(suggestions, id: \.name) { suggestion in
            Button(suggestion.name) { pick(suggestion) }.buttonStyle(.bordered)
          }
        }
      }
    }
  }
}

import MealPlannerCore
import SwiftUI

@MainActor struct ImportView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var preview = makeImportPreview("", state: emptyState())
  @State private var choices = ImportChoices()
  @State private var error: String?

  private var count: Int { importCount(preview, choices) }
  private var canSave: Bool {
    store.state != nil && count > 0 && !preview.dishes.contains {
      ($0.existingDishId == nil || choices.replace[$0.line] == true)
        && !importIssues($0, choices: choices).isEmpty
    }
  }
  var body: some View {
    Form {
      Section {
        Text("Erota ruokalajit tyhjällä rivillä. Ensimmäinen rivi on nimi, sen jälkeen ainesosat muodossa määrä yksikkö nimi.")
          .font(.subheadline).foregroundStyle(Theme.muted)
        ZStack(alignment: .topLeading) {
          if text.isEmpty {
            Text("Makaronilaatikko\n400 g makaroni\n3 dl kerma\nsuola")
              .foregroundStyle(Theme.muted).padding(.horizontal, 5).padding(.vertical, 8)
              .allowsHitTesting(false).accessibilityHidden(true)
          }
          TextEditor(text: $text).frame(minHeight: 220)
            .scrollContentBackground(.hidden)
            .autocorrectionDisabled().textInputAutocapitalization(.sentences)
            .accessibilityLabel("Tuotavat ruokalajit")
        }
      }.listRowBackground(Theme.surface)
      ForEach(preview.dishes, id: \.line) { dish in
        Section {
          if dish.existingDishId != nil {
            Text("on jo olemassa").font(.subheadline).foregroundStyle(Theme.muted)
            Picker("\(dish.name): tuontitapa", selection: Binding(
              get: { choices.replace[dish.line] ?? false },
              set: { choices.replace[dish.line] = $0 }
            )) {
              Text("Ohita").tag(false)
              Text("Korvaa").tag(true)
            }.pickerStyle(.segmented)
          }
          ForEach(dish.ingredients, id: \.line) { ingredient in
            ingredientRow(ingredient)
          }
          ForEach(Array(importIssues(dish, choices: choices).enumerated()), id: \.offset) { _, issue in
            Text("Rivi \(issue.line): \(issue.message)").foregroundStyle(Theme.error)
          }
        } header: {
          Text(dish.name.isEmpty ? "Rivi \(dish.line)" : dish.name)
        }.listRowBackground(Theme.surface)
      }
      if let error { Text(error).foregroundStyle(Theme.error) }
      Button("Tuo \(count) ruokalajia", action: save)
        .disabled(!canSave).listRowBackground(Theme.surface)
    }
    .warmList().navigationTitle("Tuo ruokalajeja")
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: text) { _, _ in refresh() }
    .onChange(of: store.state) { _, _ in refresh() }
  }
  private func ingredientRow(_ ingredient: ImportIngredient) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(formatAmount(ingredient.amount))
        .foregroundStyle(Theme.muted)
      spelling(typed: ingredient.typedUnit, silent: ingredient.silentUnit,
        suggestion: ingredient.unitSuggestion, line: ingredient.line, isName: false)
      spelling(typed: ingredient.typedName, silent: ingredient.silentName,
        suggestion: ingredient.nameSuggestion, line: ingredient.line, isName: true)
    }.padding(.vertical, 4)
  }
  @ViewBuilder private func spelling(typed: String, silent: String, suggestion: String?,
    line: Int, isName: Bool) -> some View {
    if let suggestion {
      let kept = isName ? choices.keepTypedNames.contains(line) : choices.keepTypedUnits.contains(line)
      Button {
        if isName {
          if kept { choices.keepTypedNames.remove(line) } else { choices.keepTypedNames.insert(line) }
        } else {
          if kept { choices.keepTypedUnits.remove(line) } else { choices.keepTypedUnits.insert(line) }
        }
      } label: {
        VStack(alignment: .leading, spacing: 4) {
          Text(kept ? typed : "\(typed) → \(suggestion)")
          if kept { Text("käytä: \(suggestion)").font(.caption).foregroundStyle(Theme.muted) }
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
      }.buttonStyle(.borderless)
        .accessibilityHint(kept ? "Käytä ehdotettua kirjoitusasua" : "Säilytä kirjoitettu muoto")
    } else if !silent.isEmpty {
      Text(silent)
    }
  }
  private func refresh() {
    let next = makeImportPreview(text, state: store.state ?? emptyState())
    choices = carryChoices(choices, from: preview, to: next)
    preview = next
    error = nil
  }
  private func save() {
    error = store.change { try applyImport($0, preview, choices: choices, newId: { store.id() }) }
    if error == nil { dismiss() }
  }
}

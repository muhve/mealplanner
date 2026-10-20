import Foundation

public enum SyncValue: Codable, Equatable, Sendable {
  case string(String), double(Double), bool(Bool), null, stringArray([String]), json(String)
}
public struct SyncRecord: Codable, Equatable, Sendable {
  public enum RecordType: String, Codable, Sendable { case dish, meal, item, extra, archivedTrip, trip }
  public var type: RecordType
  public var name: String
  public var fields: [String: SyncValue]
  public var modified: [String: Double]
  public var deletedAt: Double?
  public init(type: RecordType, name: String, fields: [String: SyncValue] = [:],
              modified: [String: Double] = [:], deletedAt: Double? = nil) {
    self.type = type; self.name = name; self.fields = fields
    self.modified = modified; self.deletedAt = deletedAt
  }
}
public let syncDocumentKey = "ruokalista-sync-v1"
public struct SyncLedger: Codable, Equatable, Sendable {
  public var records: [String: SyncRecord] = [:]
  public var pending: Set<String> = []
  public var serverState: String?
  public var lastSync: Double?
  // CKRecord system fields are needed for optimistic concurrency, also across launches.
  public var systemFields: [String: String] = [:]
  public var accountIdentifier: String?
  // Optional for decoding ledgers written before the first-fetch gate existed.
  public var bootstrapCompleted: Bool?
  public var bootstrapTimestamp: Double?
  public var bootstrapTripPending: Bool?
  public var bootstrapTripCreatedAt: Double?
  public var bootstrapServer: [String: SyncRecord]?
  public var needsBootstrap: Bool { bootstrapCompleted != true }
  public init() {}
}
public func syncHash(_ value: String) -> String {
  var hash: UInt64 = 14695981039346656037
  for byte in value.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
  return String(format: "%016llx", hash)
}
public func syncRecordName(_ prefix: String, _ id: String) -> String {
  let allowed = id.utf8.allSatisfy {
    (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95 || $0 == 45
  }
  return prefix + "-" + (!id.isEmpty && allowed && prefix.utf8.count + id.utf8.count < 255 ? id : syncHash(id))
}
private func json<T: Encodable>(_ value: T) -> String {
  let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
  // All inputs here are the app's finite, JSON-compatible model values.
  return String(decoding: try! encoder.encode(value), as: UTF8.self)
}
private func fields<T: Encodable>(_ value: T) -> [String: SyncValue] {
  let object = try! JSONSerialization.jsonObject(with: Data(json(value).utf8)) as! [String: Any]
  return object.mapValues { value in
    if value is NSNull { return .null }
    if let number = value as? NSNumber {
      if String(cString: number.objCType) == "c" { return .bool(number.boolValue) }
      return .double(number.doubleValue)
    }
    if let string = value as? String { return .string(string) }
    if let strings = value as? [String] { return .stringArray(strings) }
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    return .json(String(decoding: data, as: UTF8.self))
  }
}

private struct SyncQuantity: Codable {
  var edited: Bool
  var amount: Double?
}
private let itemDefaults: [String: SyncValue] = [
  "mark": .string("none"), "removed": .bool(false),
  "quantity": .json(json(SyncQuantity(edited: false, amount: nil)))
]
private func itemRecordName(trip: Double, key: String) -> String {
  "item-" + syncHash(json(trip) + ":" + key)
}
/// Migrate the previous wire representation without changing the local v1 model.
/// After migration each mutually exclusive choice has exactly one LWW timestamp.
private func grouped(_ source: SyncRecord) -> SyncRecord {
  guard source.type == .item || source.type == .extra else { return source }
  var record = source
  if record.fields["mark"] == nil, record.fields["checked"] != nil || record.fields["have"] != nil {
    let checked = record.fields["checked"] == .bool(true)
    let have = record.fields["have"] == .bool(true)
    let checkedTime = record.modified["checked"] ?? 0, haveTime = record.modified["have"] ?? 0
    let mark = have && (!checked || haveTime >= checkedTime) ? "have" : checked ? "checked" : "none"
    record.fields["mark"] = .string(mark)
    record.modified["mark"] = max(checkedTime, haveTime)
  }
  for key in ["checked", "have"] { record.fields[key] = nil; record.modified[key] = nil }
  if record.type == .item {
    if record.fields["quantity"] == nil, record.fields["edited"] != nil || record.fields["amount"] != nil {
      let amount: Double?
      if case .double(let value) = record.fields["amount"] { amount = value } else { amount = nil }
      record.fields["quantity"] = .json(json(SyncQuantity(edited: record.fields["edited"] == .bool(true), amount: amount)))
      record.modified["quantity"] = max(record.modified["edited"] ?? 0, record.modified["amount"] ?? 0)
    }
    for key in ["edited", "amount"] { record.fields[key] = nil; record.modified[key] = nil }
  }
  return record
}
private func groupedLedger(_ source: SyncLedger) -> SyncLedger {
  var ledger = source
  for (name, record) in source.records {
    let migrated = grouped(record)
    if migrated != record { ledger.records[name] = migrated; ledger.pending.insert(name) }
  }
  return ledger
}

private func decode<T: Decodable>(_ record: SyncRecord, as: T.Type) -> T? {
  var expanded = grouped(record).fields
  if record.type == .item || record.type == .extra {
    expanded["checked"] = .bool(expanded["mark"] == .string("checked"))
    expanded["have"] = .bool(expanded["mark"] == .string("have"))
    if case .json(let raw) = expanded["quantity"],
       let quantity = try? JSONDecoder().decode(SyncQuantity.self, from: Data(raw.utf8)) {
      expanded["edited"] = .bool(quantity.edited)
      expanded["amount"] = quantity.amount.map(SyncValue.double) ?? .null
    }
  }
  let object: [String: Any] = expanded.mapValues { value in
    switch value {
    case .string(let v): return v
    case .double(let v): return v
    case .bool(let v): return v
    case .null: return NSNull()
    case .stringArray(let v): return v
    case .json(let v): return (try? JSONSerialization.jsonObject(with: Data(v.utf8))) ?? NSNull()
    }
  }
  guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
  return try? JSONDecoder().decode(T.self, from: data)
}
private func number(_ record: SyncRecord, _ key: String) -> Double {
  if case .double(let n) = record.fields[key] { return n }; return 0
}

public func decompose(_ state: AppState) -> [String: SyncRecord] {
  var result: [String: SyncRecord] = [:]
  func add<T: Encodable>(_ type: SyncRecord.RecordType, _ name: String, _ value: T,
                         order: Int? = nil, trip: Bool = false) {
    var f = fields(value)
    if type == .dish {
      if f["photo"] == nil { f["photo"] = .null }
      if f["instructions"] == nil { f["instructions"] = .null }
    }
    if let order { f["order"] = .double(state.trip.createdAt + Double(order)) }
    if trip { f["tripCreatedAt"] = .double(state.trip.createdAt) }
    result[name] = grouped(SyncRecord(type: type, name: name, fields: f))
    result[name]?.modified = [:]
  }
  for dish in state.dishes { add(.dish, syncRecordName("dish", dish.id), dish) }
  for (i, meal) in state.trip.meals.enumerated() { add(.meal, syncRecordName("meal", meal.id), meal, order: i, trip: true) }
  for (i, extra) in state.trip.extras.enumerated() { add(.extra, syncRecordName("extra", extra.id), extra, order: i, trip: true) }
  // Include default item states so unchecking/resetting is a field edit, not a deletion.
  for key in Set(generatedItems(state).map(\.key)).union(state.trip.items.keys) {
    let item = state.trip.items[key] ?? ItemState(edited: false, amount: nil, removed: false, checked: false, have: false)
    // A new trip must not reuse an item tombstone from an archived trip.
    let name = itemRecordName(trip: state.trip.createdAt, key: key)
    add(.item, name, item, trip: true)
    result[name]?.fields["key"] = .string(key)
  }
  for archive in state.history { add(.archivedTrip, syncRecordName("archive", archive.id), archive) }
  result["trip-current"] = SyncRecord(type: .trip, name: "trip-current", fields: ["createdAt": .double(state.trip.createdAt)])
  return result
}
public func compose(_ records: [SyncRecord]) -> AppState {
  let live = records.filter { $0.deletedAt == nil }
  let created = live.first { $0.name == "trip-current" }.map { number($0, "createdAt") } ?? 0
  let current = live.filter { number($0, "tripCreatedAt") == created }
  func ordered(_ type: SyncRecord.RecordType) -> [SyncRecord] {
    current.filter { $0.type == type }.sorted {
      let a = number($0, "order"), b = number($1, "order")
      return a == b ? $0.name < $1.name : a < b
    }
  }
  var items: [String: ItemState] = [:]
  for record in current where record.type == .item {
    if case .string(let key) = record.fields["key"], let item = decode(record, as: ItemState.self) { items[key] = item }
  }
  let dishes = live.filter { $0.type == .dish }.compactMap { decode($0, as: Dish.self) }.sorted {
    let comparison = $0.name.compare($1.name, locale: Locale(identifier: "fi"))
    return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
  }
  let history = live.filter { $0.type == .archivedTrip }.compactMap { decode($0, as: ArchivedTrip.self) }.sorted {
    $0.archivedAt == $1.archivedAt ? $0.id < $1.id : $0.archivedAt > $1.archivedAt
  }
  return normalize(AppState(version: 1, dishes: dishes,
    trip: Trip(createdAt: created, meals: ordered(.meal).compactMap { decode($0, as: Meal.self) },
               items: items, extras: ordered(.extra).compactMap { decode($0, as: Extra.self) }), history: history))
}
public func bootstrapLedger(state: AppState, now: Double) -> SyncLedger {
  var ledger = SyncLedger()
  // These values predate sync setup, so they have no field clocks yet. Stamp
  // unknown server records only after the first fetch; recordLocalChange gives
  // genuine edits made while that fetch is running their own clocks immediately.
  ledger.records = decompose(state)
  ledger.bootstrapTimestamp = now
  ledger.pending = Set(ledger.records.keys)
  return ledger
}
public func recordLocalChange(_ ledger: SyncLedger, old: AppState, new: AppState, now: Double) -> SyncLedger {
  var ledger = groupedLedger(ledger)
  let before = decompose(old), after = decompose(new)
  for name in Set(before.keys).union(after.keys) {
    guard let fresh = after[name] else {
      if var record = ledger.records[name] ?? before[name] {
        if record.type == .item && old.trip.createdAt == new.trip.createdAt {
          // Removing the last meal temporarily removes generated items. Reset their
          // marks rather than poisoning that ingredient for the rest of this trip.
          for (key, value) in itemDefaults where record.fields[key] != value {
            record.fields[key] = value; record.modified[key] = now
          }
        } else {
          record.deletedAt = max(record.deletedAt ?? now, now)
        }
        ledger.records[name] = record; ledger.pending.insert(name)
      }
      continue
    }
    var record = ledger.records[name] ?? fresh
    var touched = ledger.records[name] == nil
    for (key, value) in fresh.fields where before[name]?.fields[key] != value {
      // Preserve insertion order when a preceding meal/extra is removed.
      if key == "order", before[name] != nil { continue }
      record.fields[key] = value
      record.modified[key] = now
      touched = true
    }
    if before[name] == nil, let known = ledger.records[name], known.deletedAt == nil {
      // Re-added (e.g. an item whose last meal was removed and added back): unchanged values keep
      // their clocks, so a newer reset is not undone by an older remote value.
      record.modified = record.fields.mapValues { _ in now }
      for (key, value) in record.fields where known.fields[key] == value {
        record.modified[key] = known.modified[key] ?? 0
      }
    } else if before[name] == nil {
      record.modified = record.fields.mapValues { _ in now }
      if record.type == .item {
        // New default item fields are not user edits. A second phone adding a
        // meal must not erase a check made on the first phone.
        for (key, value) in itemDefaults where record.fields[key] == value { record.modified[key] = 0 }
      }
      if record.fields["order"] != nil { record.fields["order"] = .double(now) }
    }
    if touched { ledger.records[name] = record; ledger.pending.insert(name) }
  }
  return ledger
}
public func mergeRemote(_ ledger: SyncLedger, incoming: [SyncRecord]) -> (ledger: SyncLedger, changed: Bool) {
  var result = groupedLedger(ledger)
  for remote in incoming.map(grouped) {
    guard var local = result.records[remote.name] else {
      result.records[remote.name] = remote; continue
    }
    for (key, value) in remote.fields {
      let a = local.modified[key] ?? 0, b = remote.modified[key] ?? 0
      if local.fields[key] == nil || b > a || (a == b && json(value) > json(local.fields[key]!)) {
        local.fields[key] = value; local.modified[key] = b
      }
    }
    // Tombstones win even over a later edit on a phone that has not seen the archive.
    if let deletion = remote.deletedAt { local.deletedAt = max(local.deletedAt ?? deletion, deletion) }
    result.records[remote.name] = local
    if local != remote { result.pending.insert(remote.name) }
  }
  return (result, result.records != ledger.records)
}

/// A successful request only acknowledges the snapshot sent, never a newer local edit.
public func acknowledgeUploaded(_ ledger: SyncLedger, saved: [SyncRecord]) -> SyncLedger {
  var result = ledger
  for record in saved {
    if result.records[record.name] == record { result.pending.remove(record.name) }
    else { result.pending.insert(record.name) }
  }
  return result
}
public func recordServerDeletion(_ ledger: SyncLedger, name: String,
                                 type: SyncRecord.RecordType, now: Double) -> SyncLedger {
  var deletion = ledger.records[name] ?? SyncRecord(type: type, name: name)
  deletion.deletedAt = max(deletion.deletedAt ?? now, now)
  var result = mergeRemote(ledger, incoming: [deletion]).ledger
  result.systemFields[name] = nil
  result.pending.insert(name)
  return result
}

/// Run only after the first complete server fetch, before queuing any local upload.
/// Bootstrap is an import into the server's active trip, not a competing trip reset.
public func rebaseBootstrap(local: SyncLedger, server: [SyncRecord], now: Double = 0) -> SyncLedger {
  var result = groupedLedger(local)
  let server = server.map(grouped)
  var relocated: Set<String> = []
  if let trip = server.first(where: { $0.name == "trip-current" && $0.deletedAt == nil }),
     let localTrip = result.records["trip-current"], localTrip.deletedAt == nil,
     (localTrip.modified["createdAt"] ?? 0) == 0
       || (result.bootstrapTripPending == true && result.bootstrapTripCreatedAt == number(localTrip, "createdAt")) {
    let oldTime = number(localTrip, "createdAt"), newTime = number(trip, "createdAt")
    if oldTime != newTime {
      for record in Array(result.records.values) where record.deletedAt == nil
          && [.meal, .extra, .item].contains(record.type)
          && number(record, "tripCreatedAt") == oldTime {
        var moved = record
        moved.fields["tripCreatedAt"] = .double(newTime)
        // Membership relocation must beat every version already observed, even
        // when this device's clock is behind or an old upload is fetched later.
        let observed = [record] + server.filter { $0.name == record.name }
        let latest = observed.flatMap { Array($0.modified.values) + [$0.deletedAt ?? 0] }.max() ?? 0
        let relocatedAt = max(now, latest.nextUp)
        moved.modified["tripCreatedAt"] = relocatedAt
        if record.type == .item, case .string(let key) = record.fields["key"] {
          moved.name = itemRecordName(trip: newTime, key: key)
          // The old name may already exist on the server or another phone.
          // Keep its system fields so this tombstone updates that record safely.
          var tombstone = record
          tombstone.deletedAt = relocatedAt
          result.records[record.name] = tombstone
          result.pending.insert(record.name)
          result = mergeRemote(result, incoming: [moved]).ledger
        } else {
          // This is an explicit relocation, not a same-time conflict with the
          // old local trip value. Replace it before merging server fields.
          result.records[moved.name] = moved
        }
        result.pending.insert(moved.name)
        relocated.insert(moved.name)
      }
    }
    // Adopt even an older server trip timestamp. It is the shared destination.
    result.records[trip.name] = trip
    result.pending.remove(trip.name)
  }
  let serverByName = Dictionary(server.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
  let initialTime = max(now, result.bootstrapTimestamp ?? 0)
  for (name, source) in result.records {
    var record = source
    if serverByName[name] == nil || relocated.contains(name) {
      // A new record (including a relocated entry) may upload the pre-sync data.
      // Preserve clocks belonging to actual edits, and keep default marks weak.
      for key in record.fields.keys where record.modified[key] == nil {
        let isDefaultMark = (record.type == .item || record.type == .extra)
          && key == "mark" && record.fields[key] == .string("none")
        let isDefaultItem = record.type == .item && record.fields[key] == itemDefaults[key]
        record.modified[key] = isDefaultMark || isDefaultItem ? 0 : initialTime
      }
    }
    if let remote = serverByName[name] {
      // Only unclocked pre-sync fields defer to the server. A real local edit
      // merges through normal LWW below, even if bootstrap is still in progress.
      for key in record.fields.keys where (record.modified[key] ?? 0) == 0 {
        if let value = remote.fields[key] {
          record.fields[key] = value
          record.modified[key] = remote.modified[key]
        } else {
          record.modified[key] = 0
        }
      }
    }
    result.records[name] = record
  }
  result = mergeRemote(result, incoming: server).ledger
  // Only acknowledge a record whose complete winning snapshot is on the server.
  // A locally winning field or tombstone must remain queued for upload.
  for remote in server {
    if result.records[remote.name] == remote { result.pending.remove(remote.name) }
    else { result.pending.insert(remote.name) }
  }
  // If two first-time devices both fetched an empty server, a conflict saving
  // trip-current still needs this rebase instead of ordinary trip-reset LWW.
  result.bootstrapTripPending = !server.contains { $0.name == "trip-current" && $0.deletedAt == nil }
  // Track the original unconfirmed trip value, so a genuine archive/change
  // after the empty-server fetch is not mistaken for the initial import race.
  result.bootstrapTripCreatedAt = result.bootstrapTripPending == true
    ? result.records["trip-current"].map { number($0, "createdAt") } : nil
  for record in server where record.deletedAt != nil { result.pending.insert(record.name) }
  result.bootstrapCompleted = true
  result.bootstrapTimestamp = nil
  result.bootstrapServer = nil
  return result
}

/// Signing out retains the account identity, clocks and queue. Signing back into
/// that same account resumes sync. A different (or first known) account keeps
/// local live data as never-synced input: old account clocks and tombstones must
/// not overwrite/delete that account's server data during its bootstrap.
public func prepareSyncAccount(_ ledger: SyncLedger, accountIdentifier: String?, now: Double) -> SyncLedger {
  guard let accountIdentifier, accountIdentifier != ledger.accountIdentifier else { return ledger }
  var result = SyncLedger()
  result.accountIdentifier = accountIdentifier
  result.bootstrapTimestamp = now
  result.records = ledger.records.filter { $0.value.deletedAt == nil }.mapValues { record in
    var record = record
    record.modified = [:]
    return record
  }
  result.pending = Set(result.records.keys)
  return result
}

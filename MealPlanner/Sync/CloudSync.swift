import CloudKit
import Foundation
import MealPlannerCore
import Network
import OSLog

enum SyncStatus: Equatable {
  case synced, syncing, offline, noAccount, error(String)
  var text: String {
    switch self {
    case .synced: return "Synkronoitu"
    case .syncing: return "Synkronoidaan…"
    case .offline: return "Ei yhteyttä"
    case .noAccount: return "iCloud ei käytössä"
    case .error: return "Synkronointivirhe"
    }
  }
  var symbol: String {
    switch self {
    case .synced: return "checkmark.icloud"
    case .syncing: return "arrow.triangle.2.circlepath.icloud"
    case .offline: return "wifi.slash"
    case .noAccount: return "icloud.slash"
    case .error: return "exclamationmark.icloud"
    }
  }
}

@MainActor final class CloudSync: CKSyncEngineDelegate {
  private weak var store: AppStore?
  private let logger = Logger(subsystem: "fi.muhve.mealplanner", category: "CloudSync")
  private let container = CKContainer(identifier: "iCloud.fi.muhve.mealplanner")
  private let zoneID = CKRecordZone.ID(zoneName: "MealPlanner")
  private var engine: CKSyncEngine?
  private var activating = false
  private var accountRefreshPending = false
  private var halted = false
  private var online = true
  private let monitor = NWPathMonitor()
  private var stagedPhotos: [URL] = []
  private var deferredNames: Set<String> = []
  private var fetchFailed = false
  private var sendFailed = false
  private var bootstrapEngineState: String?

  init(store: AppStore) {
    self.store = store
    monitor.pathUpdateHandler = { [weak self] path in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.online = path.status == .satisfied
        if !self.online, self.engine != nil { self.store?.syncStatus = .offline }
        if self.online { await self.activate() }
      }
    }
    monitor.start(queue: DispatchQueue(label: "MealPlanner.network"))
  }
  deinit { monitor.cancel() }

  func pause() { engine = nil }

  func activate() async {
    guard !activating, let store else { return }
    activating = true
    deferredNames = []
    defer {
      activating = false
      if accountRefreshPending {
        accountRefreshPending = false
        Task { [weak self] in await self?.activate() }
      }
    }
    do {
      guard try await container.accountStatus() == .available else {
        engine = nil; store.syncStatus = .noAccount; return
      }
      if halted {
        // A delegate persistence failure must not allow a later stateUpdate to skip
        // that event. Reset tokens and fetch everything after local recovery.
        var ledger = store.ledger; ledger.serverState = nil
        try store.saveLedger(ledger)
        halted = false
      }
      if engine == nil {
        let account = try await container.userRecordID().recordName
        let prepared = prepareSyncAccount(store.ledger, accountIdentifier: account,
                                          now: Date().timeIntervalSince1970 * 1000)
        if prepared != store.ledger { try store.saveLedger(prepared) }
        if store.ledger.needsBootstrap {
          // Never resume a partial bootstrap fetch from a token: its server view
          // must be complete before the local trip can be safely rebased.
          var ledger = store.ledger
          ledger.bootstrapServer = [:]; ledger.serverState = nil
          try store.saveLedger(ledger)
          bootstrapEngineState = nil
        }
        engine = makeEngine(ledger: store.ledger)
        if !store.ledger.needsBootstrap {
          engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        }
      }
      guard let fetchingEngine = engine else { return }
      store.syncStatus = online ? .syncing : .offline
      try await fetchingEngine.fetchChanges()
      guard engine === fetchingEngine, !halted else { return }
      guard !fetchFailed else { return }
      if store.ledger.needsBootstrap {
        let server = Array((store.ledger.bootstrapServer ?? [:]).values)
        var rebased = rebaseBootstrap(local: store.ledger, server: server, now: Date().timeIntervalSince1970 * 1000)
        rebased.serverState = bootstrapEngineState
        try store.applySync(rebased)
        // The first engine has automatic sync disabled. Only after the complete
        // fetch and durable rebase may a normal automatic engine upload anything.
        engine = makeEngine(ledger: store.ledger)
        bootstrapEngineState = nil
        engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
      }
      enqueue()
      try await engine?.sendChanges()
    } catch { report(error) }
  }

  func accountChanged() async {
    engine = nil
    if activating { accountRefreshPending = true; return }
    // activate() checks the actual account identity. The same account resumes
    // its timestamps/pending work; only another account clears clocks for import.
    await activate()
  }

  func enqueue(showStatus: Bool = true) {
    guard !halted, let engine, let store, !store.ledger.needsBootstrap else { return }
    engine.state.add(pendingRecordZoneChanges: store.ledger.pending.subtracting(deferredNames).sorted().map {
      .saveRecord(CKRecord.ID(recordName: $0, zoneID: zoneID))
    })
    if showStatus, !store.ledger.pending.isEmpty { store.syncStatus = online ? .syncing : .offline }
  }

  func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    guard engine === syncEngine, !halted, let store else { return }
    do {
      switch event {
      case .stateUpdate(let update):
        let serialization = try JSONEncoder().encode(update.stateSerialization).base64EncodedString()
        if store.ledger.needsBootstrap {
          bootstrapEngineState = serialization
        } else {
          var ledger = store.ledger; ledger.serverState = serialization
          try store.saveLedger(ledger)
        }
      case .accountChange(let change):
        // An initial sign-in event needs no new engine. Recreating an empty engine
        // for that event could repeatedly trigger initial sign-in events.
        switch change.changeType {
        case .signOut, .switchAccounts:
          Task { [weak self] in await self?.accountChanged() }
        case .signIn: enqueue(showStatus: false)
        @unknown default: break
        }
      case .fetchedRecordZoneChanges(let changes):
        var ledger = store.ledger
        let incoming = try changes.modifications.map { try decode($0.record) }
        var received = ledger
        if ledger.needsBootstrap {
          received = SyncLedger()
          received.records = ledger.bootstrapServer ?? [:]
        }
        for deletion in changes.deletions {
          if let type = SyncRecord.RecordType(rawValue: deletion.recordType) {
            received = recordServerDeletion(received, name: deletion.recordID.recordName,
              type: type, now: Date().timeIntervalSince1970 * 1000)
            ledger.systemFields[deletion.recordID.recordName] = nil
          }
        }
        if !ledger.needsBootstrap, received.bootstrapTripPending == true,
           incoming.contains(where: { $0.name == "trip-current" && $0.deletedAt == nil }) {
          received = rebaseBootstrap(local: received, server: incoming, now: Date().timeIntervalSince1970 * 1000)
        } else {
          received = mergeRemote(received, incoming: incoming).ledger
        }
        for modification in changes.modifications {
          let record = modification.record
          if ledger.needsBootstrap {
            ledger.systemFields[record.recordID.recordName] = try systemFields(record)
          } else {
            received.systemFields[record.recordID.recordName] = try systemFields(record)
          }
          try installPhoto(record, winner: received.records[record.recordID.recordName])
        }
        if ledger.needsBootstrap {
          // Keep the local UI document and edits intact throughout a paginated fetch.
          ledger.bootstrapServer = received.records
          try store.saveLedger(ledger)
        } else {
          try store.applySync(received)
          enqueue(showStatus: false)
        }
      case .sentRecordZoneChanges(let changes):
        var ledger = store.ledger
        // A local edit may have happened while the request was in flight. Only
        // acknowledge exactly the values/times that were actually saved.
        for record in changes.savedRecords {
          let saved = try decode(record)
          ledger.systemFields[saved.name] = try systemFields(record)
          ledger = acknowledgeUploaded(ledger, saved: [saved])
          if saved.name == "trip-current" { ledger.bootstrapTripPending = false }
          deferredNames.remove(saved.name)
        }
        for failure in changes.failedRecordSaves {
          let name = failure.record.recordID.recordName
          switch failure.error.code {
          case .serverRecordChanged:
            if let server = failure.error.serverRecord {
              let remote = try decode(server)
              if name == "trip-current", ledger.bootstrapTripPending == true {
                ledger = rebaseBootstrap(local: ledger, server: [remote], now: Date().timeIntervalSince1970 * 1000)
              } else {
                ledger = mergeRemote(ledger, incoming: [remote]).ledger
              }
              ledger.systemFields[name] = try systemFields(server)
              try installPhoto(server, winner: ledger.records[name])
            }
            ledger.pending.insert(name)
          case .zoneNotFound:
            resetZone(&ledger, engine: syncEngine)
          case .unknownItem:
            // A physical server deletion must become a travelling tombstone.
            ledger.records[name]?.deletedAt = Date().timeIntervalSince1970 * 1000
            ledger.systemFields[name] = nil
            ledger.pending.insert(name)
          default:
            // The engine itself retries transient failures. Do not immediately
            // re-add permanent failures in this event and create a tight send loop.
            deferredNames.insert(name)
            sendFailed = true
            report(failure.error)
          }
        }
        try store.applySync(ledger)
        enqueue(showStatus: false)
        clearStagedPhotos(for: changes.savedRecords + changes.failedRecordSaves.map(\.record))
      case .fetchedDatabaseChanges(let changes):
        if changes.deletions.contains(where: { $0.zoneID == zoneID }) {
          var ledger = store.ledger
          resetZone(&ledger, engine: syncEngine)
          try store.saveLedger(ledger)
          enqueue(showStatus: false)
        }
      case .sentDatabaseChanges(let changes):
        for failure in changes.failedZoneSaves {
          sendFailed = true
          report(failure.error)
        }
      case .didFetchRecordZoneChanges(let result):
        if let error = result.error {
          fetchFailed = true
          if error.code == .zoneNotFound, result.zoneID == zoneID {
            var ledger = store.ledger
            resetZone(&ledger, engine: syncEngine)
            try store.saveLedger(ledger)
            enqueue(showStatus: false)
          } else { report(error) }
        }
      case .willFetchChanges:
        fetchFailed = false
        if deferredNames.isEmpty { store.syncStatus = online ? .syncing : .offline }
      case .willSendChanges:
        sendFailed = false
        if deferredNames.isEmpty { store.syncStatus = online ? .syncing : .offline }
      case .didFetchChanges:
        // Fetch completion alone does not acknowledge pending uploads.
        if !fetchFailed, store.ledger.pending.isEmpty { try completed() }
      case .didSendChanges:
        if !sendFailed, store.ledger.pending.isEmpty { try completed() }
      default: break
      }
    } catch { stop(error) }
  }

  func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
    guard engine === syncEngine, !halted, let store, !store.ledger.needsBootstrap else { return nil }
    let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
    var records: [CKRecord] = []
    do {
      for change in pending.prefix(100) {
        guard case .saveRecord(let id) = change else { continue }
        guard let value = store.ledger.records[id.recordName] else {
          syncEngine.state.remove(pendingRecordZoneChanges: [change]); continue
        }
        records.append(try encode(value, ledger: store.ledger))
      }
      return records.isEmpty ? nil : CKSyncEngine.RecordZoneChangeBatch(
        recordsToSave: records, recordIDsToDelete: [], atomicByZone: false)
    } catch { stop(error); return nil }
  }

  private func makeEngine(ledger: SyncLedger) -> CKSyncEngine {
    let serialization: CKSyncEngine.State.Serialization? = ledger.needsBootstrap ? nil : ledger.serverState
      .flatMap { Data(base64Encoded: $0) }
      .flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
    var configuration = CKSyncEngine.Configuration(database: container.privateCloudDatabase,
      stateSerialization: serialization, delegate: self)
    configuration.automaticallySync = !ledger.needsBootstrap
    return CKSyncEngine(configuration)
  }

  private func completed() throws {
    guard let store, !store.ledger.needsBootstrap else { return }
    // Preserve an error surfaced by the operation's other events.
    if case .error = store.syncStatus { return }
    var ledger = store.ledger; ledger.lastSync = Date().timeIntervalSince1970 * 1000
    try store.saveLedger(ledger)
    store.syncStatus = online ? .synced : .offline
  }
  private func resetZone(_ ledger: inout SyncLedger, engine: CKSyncEngine) {
    ledger.systemFields = [:]; ledger.pending = Set(ledger.records.keys)
    if ledger.needsBootstrap { ledger.bootstrapServer = [:] }
    engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
  }
  private func report(_ error: Error) {
    if let ck = error as? CKError, [.networkFailure, .networkUnavailable].contains(ck.code) {
      store?.syncStatus = .offline
    } else { store?.syncStatus = .error(error.localizedDescription) }
  }
  private func stop(_ error: Error) {
    halted = true; engine = nil; report(error)
  }
  private func systemFields(_ record: CKRecord) throws -> String {
    let coder = NSKeyedArchiver(requiringSecureCoding: true)
    record.encodeSystemFields(with: coder); coder.finishEncoding()
    return coder.encodedData.base64EncodedString()
  }
  private func encode(_ value: SyncRecord, ledger: SyncLedger) throws -> CKRecord {
    let record: CKRecord
    if let raw = ledger.systemFields[value.name], let data = Data(base64Encoded: raw) {
      let coder = try NSKeyedUnarchiver(forReadingFrom: data)
      coder.requiresSecureCoding = true
      guard let restored = CKRecord(coder: coder) else { throw CoreError("iCloud-tietueen lukeminen epäonnistui.") }
      coder.finishDecoding(); record = restored
    } else {
      record = CKRecord(recordType: value.type.rawValue,
        recordID: CKRecord.ID(recordName: value.name, zoneID: zoneID))
    }
    record["payload"] = String(decoding: try JSONEncoder().encode(value.fields), as: UTF8.self) as CKRecordValue
    record["modified"] = String(decoding: try JSONEncoder().encode(value.modified), as: UTF8.self) as CKRecordValue
    record["deletedAt"] = value.deletedAt.map { NSNumber(value: $0) }
    record["photo"] = nil
    if value.deletedAt == nil, value.type == .dish, case .string(let name) = value.fields["photo"] {
      guard let source = PhotoStore().url(for: name), FileManager.default.fileExists(atPath: source.path) else {
        logger.warning("Photo file is missing; uploading the dish without an asset.")
        return record
      }
      // CKAsset reads the file later. Keep an immutable copy while local edits clean up originals.
      let staged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
      do { try FileManager.default.copyItem(at: source, to: staged) }
      catch {
        if !FileManager.default.fileExists(atPath: source.path) {
          logger.warning("Photo disappeared before staging; uploading the dish without an asset.")
          return record
        }
        throw error
      }
      stagedPhotos.append(staged)
      record["photo"] = CKAsset(fileURL: staged)
    }
    return record
  }
  private func decode(_ record: CKRecord) throws -> SyncRecord {
    guard let type = SyncRecord.RecordType(rawValue: record.recordType),
          let payload = record["payload"] as? String,
          let modified = record["modified"] as? String else { throw CoreError("Tuntematon iCloud-tietue.") }
    return SyncRecord(type: type, name: record.recordID.recordName,
      fields: try JSONDecoder().decode([String: SyncValue].self, from: Data(payload.utf8)),
      modified: try JSONDecoder().decode([String: Double].self, from: Data(modified.utf8)),
      deletedAt: (record["deletedAt"] as? NSNumber)?.doubleValue)
  }
  private func installPhoto(_ record: CKRecord, winner: SyncRecord?) throws {
    guard let winner, winner.deletedAt == nil, winner.type == .dish,
          case .string(let name) = winner.fields["photo"] else { return }
    let incoming = try decode(record)
    // No asset is valid when the source file was missing. Keep the filename in
    // the ledger; DishPhotoView renders an empty frame when the local file is absent.
    guard incoming.fields["photo"] == winner.fields["photo"],
          let asset = record["photo"] as? CKAsset, let url = asset.fileURL else { return }
    try PhotoStore().install(assetURL: url, name: name)
  }
  private func clearStagedPhotos(for records: [CKRecord]) {
    let completed = Set(records.compactMap { ($0["photo"] as? CKAsset)?.fileURL })
    for url in stagedPhotos where completed.contains(url) { try? FileManager.default.removeItem(at: url) }
    stagedPhotos.removeAll { completed.contains($0) }
  }
}

import Foundation
import CryptoKit

struct ReceiptAttachment: Equatable {
    var metadata: DriveLineReceiptMetadata
    var data: Data
}

struct LocalStore {
    let url: URL
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CANConnect/state.json")
    }
    var receiptsURL:URL { url.deletingLastPathComponent().appendingPathComponent("Receipts",isDirectory:true) }
    var backupURL:URL { url.deletingPathExtension().appendingPathExtension("backup.json") }
    var recoveryURL:URL { url.deletingLastPathComponent().appendingPathComponent("Recovery",isDirectory:true) }
    func receiptURL(_ metadata:DriveLineReceiptMetadata)->URL { receiptsURL.appendingPathComponent(metadata.sha256.lowercased()) }
    func load() throws -> StoredState? {
        guard FileManager.default.fileExists(atPath:url.path) else { return nil }
        var state = try JSONDecoder().decode(StoredState.self, from:Data(contentsOf:url))
        guard (1...4).contains(state.schemaVersion) else { throw AppFailure("This saved data needs a newer app. Your file has been preserved.") }
        state.migrateVehicles()
        return state
    }
    func save(_ state: StoredState) throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(), withIntermediateDirectories:true)
        let data = try JSONEncoder().encode(state)
        _ = try JSONDecoder().decode(StoredState.self,from:data)
        if FileManager.default.fileExists(atPath:url.path),
           let current=try? Data(contentsOf:url),
           let decoded=try? JSONDecoder().decode(StoredState.self,from:current),
           (1...4).contains(decoded.schemaVersion) {
            try current.write(to:backupURL,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        }
        try data.write(to:url, options:[.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func validBackup() ->StoredState? {
        guard let data=try? Data(contentsOf:backupURL),
              var value=try? JSONDecoder().decode(StoredState.self,from:data),
              (1...4).contains(value.schemaVersion) else { return nil }
        value.migrateVehicles();return value
    }
    @discardableResult func preserveUnreadableSource() throws ->URL? {
        guard FileManager.default.fileExists(atPath:url.path) else { return nil }
        try FileManager.default.createDirectory(at:recoveryURL,withIntermediateDirectories:true)
        let destination=recoveryURL.appendingPathComponent("state-unreadable-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at:url,to:destination)
        return destination
    }
    func restoreBackup() throws ->StoredState {
        guard let value=validBackup(),let bytes=try? Data(contentsOf:backupURL) else {
            throw AppFailure("The backup is unavailable or invalid. Original files remain preserved.")
        }
        _ = try preserveUnreadableSource()
        try bytes.write(to:url,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        return value
    }
    func prepareReceipt(_ input:URL) throws ->ReceiptAttachment {
        let access=input.startAccessingSecurityScopedResource();defer { if access { input.stopAccessingSecurityScopedResource() } }
        let data=try Data(contentsOf:input,options:.mappedIfSafe)
        guard !data.isEmpty,data.count<=20*1024*1024 else { throw AppFailure("Choose a non-empty receipt file no larger than 20 MB.") }
        let digest=SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
        let ext=input.pathExtension.lowercased()
        let mediaType:String
        switch ext { case "pdf":mediaType="application/pdf";case "jpg","jpeg":mediaType="image/jpeg";case "png":mediaType="image/png";case "heic","heif":mediaType="image/heic";default:mediaType="application/octet-stream" }
        let name=String(input.lastPathComponent.prefix(180))
        return ReceiptAttachment(metadata:DriveLineReceiptMetadata(fileName:name.isEmpty ? "receipt":name,mediaType:mediaType,byteCount:data.count,sha256:digest,capturedAt:Date()),data:data)
    }
    func storeReceipt(_ attachment:ReceiptAttachment) throws {
        guard attachment.metadata.sha256.lowercased()==SHA256.hash(data:attachment.data).map({String(format:"%02x",$0)}).joined(),
              attachment.metadata.byteCount==attachment.data.count else { throw AppFailure("Receipt metadata does not match the selected file.") }
        try FileManager.default.createDirectory(at:receiptsURL,withIntermediateDirectories:true)
        let destination=receiptURL(attachment.metadata)
        if FileManager.default.fileExists(atPath:destination.path) {
            guard try Data(contentsOf:destination)==attachment.data else { throw AppFailure("A different receipt already uses this content hash.") }
            return
        }
        try attachment.data.write(to:destination,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
    }
    func receiptData(_ metadata:DriveLineReceiptMetadata)->Data? {
        guard let data=try? Data(contentsOf:receiptURL(metadata)),data.count==metadata.byteCount,
              SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined()==metadata.sha256.lowercased() else { return nil }
        return data
    }
    func receiptFiles(_ fills:[FuelEntry])->[String:Data] {
        fills.reduce(into:[String:Data]()) { result,fill in
            guard let metadata=fill.receipt,let data=receiptData(metadata) else { return }
            result[metadata.sha256.lowercased()]=data
        }
    }
    func restoreReceipts(_ files:[String:Data],for fills:[FuelEntry]) throws {
        var metadata:[String:DriveLineReceiptMetadata]=[:]
        for value in fills.compactMap(\.receipt) {
            let digest=value.sha256.lowercased()
            if let existing=metadata[digest],existing.byteCount != value.byteCount { throw AppFailure("Duplicate receipt metadata disagrees about the file size.") }
            metadata[digest]=value
        }
        for (digest,data) in files {
            guard let value=metadata[digest.lowercased()] else { continue }
            try storeReceipt(ReceiptAttachment(metadata:value,data:data))
        }
    }
}

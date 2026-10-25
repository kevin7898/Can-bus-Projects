import Foundation
import CryptoKit

struct PreparedRecording {
    let url:URL
    let cleanup:URL?
}
enum FilePreparation {
    // A selected SQLite file is a bundle when WAL/SHM sidecars exist. Keep them
    // together in the preserved original, including when the picker selected db.sqlite.
    static func archiveInput(_ url:URL) throws -> PreparedRecording {
        guard ["sqlite","db"].contains(url.pathExtension.lowercased()) else { return PreparedRecording(url:url,cleanup:nil) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CANConnect-"+UUID().uuidString+".scanlogs",isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        do {
            for suffix in ["","-wal","-shm"] {
                let source = URL(fileURLWithPath:url.path+suffix)
                if FileManager.default.fileExists(atPath:source.path) {
                    try FileManager.default.copyItem(at:source,to:root.appendingPathComponent("db.sqlite"+suffix))
                }
            }
            return PreparedRecording(url:root,cleanup:root)
        } catch { try? FileManager.default.removeItem(at:root);throw error }
    }
    static func byteCount(_ url:URL) throws -> Int {
        let values = try url.resourceValues(forKeys:[.isDirectoryKey,.fileSizeKey])
        if values.isDirectory != true { return values.fileSize ?? 0 }
        guard let files = FileManager.default.enumerator(at:url,includingPropertiesForKeys:[.fileSizeKey,.isRegularFileKey]) else { return 0 }
        var count = 0
        for case let file as URL in files { let v = try file.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey]); if v.isRegularFile==true { count += v.fileSize ?? 0 }; if count>RecordingImporter.maxBytes { break } }
        return count
    }
    static func hash(_ url:URL) throws -> String {
        var isDir: ObjCBool = false; FileManager.default.fileExists(atPath:url.path,isDirectory:&isDir)
        var hasher = SHA256()
        if isDir.boolValue {
            let files = (FileManager.default.enumerator(at:url,includingPropertiesForKeys:[.isRegularFileKey])?.allObjects as? [URL] ?? []).sorted { $0.path<$1.path }
            for file in files where (try file.resourceValues(forKeys:[.isRegularFileKey])).isRegularFile==true {
                hasher.update(data:Data(file.path.replacingOccurrences(of:url.path,with:"").utf8)); hasher.update(data:try Data(contentsOf:file))
            }
        } else { hasher.update(data:try Data(contentsOf:url,options:.mappedIfSafe)) }
        return hasher.finalize().map { String(format:"%02x",$0) }.joined()
    }
    static func prepare(_ url:URL) throws -> PreparedRecording {
        guard url.pathExtension.lowercased()=="zip" else {
            let values = try url.resourceValues(forKeys:[.isDirectoryKey])
            if ["sqlite","db"].contains(url.pathExtension.lowercased()) { return try archiveInput(url) }
            if values.isDirectory==true {
                // SQLite read-only connections can update SHM. Parse a working copy
                // so the acknowledged original remains byte-for-byte unchanged.
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("CANConnect-"+UUID().uuidString+".scanlogs",isDirectory:true)
                try FileManager.default.copyItem(at:url,to:root)
                return PreparedRecording(url:root,cleanup:root)
            }
            return PreparedRecording(url:url,cleanup:nil)
        }
        let listing = try run("/usr/bin/unzip",["-Z1",url.path])
        let names = listing.components(separatedBy:.newlines).filter { !$0.isEmpty }
        guard names.count<=10_000, !names.isEmpty, names.allSatisfy({ !$0.hasPrefix("/") && !$0.components(separatedBy:"/").contains("..") && !$0.contains("\\") }) else { throw CANError.invalid("Archive contains unsupported paths or too many entries.") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CANConnect-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        do {
            _ = try run("/usr/bin/ditto",["-x","-k",url.path,root.path])
            guard try byteCount(root)<=RecordingImporter.maxBytes else { throw CANError.invalid("Expanded archive exceeds 50 MB.") }
            let files = FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.isSymbolicLinkKey])?.allObjects as? [URL] ?? []
            guard !files.contains(where:{ (try? $0.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink)==true }) else { throw CANError.invalid("Symlink entries are not supported in recording archives.") }
            guard let database = files.first(where:{$0.lastPathComponent=="db.sqlite" && !$0.path.contains("__MACOSX")}) else { throw CANError.invalid("This ZIP does not contain a Pelican scanlogs database. Extract CSV/JSON logs and import those files directly.") }
            return PreparedRecording(url:database,cleanup:root)
        } catch { try? FileManager.default.removeItem(at:root); throw error }
    }
    private static func run(_ executable:String,_ arguments:[String]) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath:executable); p.arguments = arguments
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
        try p.run(); let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        guard p.terminationStatus==0 else { throw CANError.invalid("Could not read the recording archive.") }
        return String(data:data,encoding:.utf8) ?? ""
    }
}

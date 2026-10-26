import Foundation

/// Immutable value snapshot crossing the persistence queue. No shared mutable
/// references are stored in RecordingDraft or its raw samples/route points.
private struct DraftCheckpointSnapshot:@unchecked Sendable { let draft:RecordingDraft }

/// At most one active and one pending snapshot per repository. Superseded
/// checkpoints are not acknowledged as saved; the newest snapshot contains all
/// of their observations. A blocked disk cannot create an unbounded queue.
private final class CheckpointInbox:@unchecked Sendable {
    struct Job:Sendable {
        let store:LocalStore
        let snapshot:DraftCheckpointSnapshot
        let completion:@Sendable (String?)->Void
    }
    private let lock=NSLock()
    private var active=Set<URL>()
    private var pending:[URL:Job]=[:]
    func submit(_ job:Job,write:@escaping @Sendable (Job)->Void) {
        lock.lock()
        if active.contains(job.store.url) {
            let replaced=pending.updateValue(job,forKey:job.store.url)
            lock.unlock()
            replaced?.completion("Recording checkpoint writes are delayed. Evidence is retained in memory; keep the app open.")
            return
        }
        active.insert(job.store.url);lock.unlock()
        LocalStore.persistenceQueue.async { [self] in
            var current:Job?=job
            while let item=current {
                write(item)
                lock.lock();current=pending.removeValue(forKey:item.store.url)
                if current == nil { active.remove(item.store.url) }
                lock.unlock()
            }
        }
    }
}

extension LocalStore {
    private static let checkpointInbox=CheckpointInbox()
    func prepareFinalTrip(_ draft:RecordingDraft,endedAt:Date) async ->Trip {
        let snapshot=DraftCheckpointSnapshot(draft:draft)
        return await withCheckedContinuation { continuation in
            Self.persistenceQueue.async { continuation.resume(returning:snapshot.draft.trip(endedAt:endedAt)) }
        }
    }
    static let persistenceQueue=DispatchQueue(label:"DriveLine.persistence",qos:.utility)
    var activeJournalURL:URL { url.deletingLastPathComponent().appendingPathComponent("active-recording.journal") }
    private var finalizedJournalURL:URL { url.deletingLastPathComponent().appendingPathComponent("active-recording.finalized") }
    private var finalizedJournalID:UUID? {
        (try? String(contentsOf:finalizedJournalURL,encoding:.utf8)).flatMap(UUID.init(uuidString:))
    }
    private struct Cursor {
        var id:UUID
        var samples:Int
        var points:Int
        var sequence:Int
        var validBytes:Int
    }
    // Accessed exclusively on persistenceQueue; bounded metadata, no telemetry.
    nonisolated(unsafe) private static var cursors:[URL:Cursor]=[:]

    private struct Frame:Codable {
        var sequence:Int
        var draft:RecordingDraft
        var sampleOffset:Int
        var pointOffset:Int
        var samples:[OBDSample]
        var points:[RoutePoint]
    }

    /// Five-second checkpoints append only new observations. A length-prefixed
    /// JSON frame is durable before acknowledgement. A torn final frame is
    /// ignored on recovery; earlier complete frames are never rewritten.
    func checkpoint(_ draft:RecordingDraft,completion:@escaping @Sendable (String?)->Void) {
        let snapshot=DraftCheckpointSnapshot(draft:draft)
        Self.checkpointInbox.submit(.init(store:self,snapshot:snapshot,completion:completion)) { job in
            do { try job.store.appendCheckpoint(job.snapshot.draft);job.completion(nil) }
            catch { job.completion("The recording checkpoint could not be saved. Keep the app open and retry Finish.") }
        }
    }

    private func appendCheckpoint(_ draft:RecordingDraft) throws {
        if Self.cursors[activeJournalURL] == nil,let recovered=try readCheckpoint() {
            Self.cursors[activeJournalURL]=Cursor(id:recovered.draft.id,samples:recovered.draft.samples?.count ?? 0,
                points:recovered.draft.route.count,sequence:recovered.sequence,validBytes:recovered.validBytes)
        }
        let cursor=Self.cursors[activeJournalURL]
        let same=cursor?.id == draft.id
        if let cursor,!same {
            let stored=try JSONDecoder().decode(StoredState.self,from:Data(contentsOf:url))
            guard finalizedJournalID == cursor.id || stored.trips.contains(where:{$0.id == cursor.id}) else {
                throw AppFailure("An unfinished recording journal already exists. Both recordings remain preserved.")
            }
        }
        let sampleOffset=same ? cursor!.samples:0
        let pointOffset=same ? cursor!.points:0
        guard sampleOffset <= (draft.samples?.count ?? 0),pointOffset <= draft.route.count else {
            throw AppFailure("Checkpoint evidence shrank unexpectedly; original journal preserved.")
        }
        var header=draft;header.samples=nil;header.route=[];header.liveEvidence=LiveRecordingEvidence()
        let frame=Frame(sequence:same ? cursor!.sequence+1:0,draft:header,sampleOffset:sampleOffset,pointOffset:pointOffset,
            samples:Array((draft.samples ?? []).dropFirst(sampleOffset)),points:Array(draft.route.dropFirst(pointOffset)))
        let payload=try JSONEncoder().encode(frame)
        guard payload.count <= 64*1024*1024 else { throw AppFailure("Recording checkpoint exceeds the safe frame limit.") }
        var size=UInt64(payload.count).bigEndian
        var bytes=withUnsafeBytes(of:&size) { Data($0) };bytes.append(payload)
        try FileManager.default.createDirectory(at:activeJournalURL.deletingLastPathComponent(),withIntermediateDirectories:true)
        if !same {
            try bytes.write(to:activeJournalURL,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            let handle=try FileHandle(forWritingTo:activeJournalURL);defer { try? handle.close() }
            try handle.synchronize()
        } else {
            let handle=try FileHandle(forWritingTo:activeJournalURL);defer { try? handle.close() }
            // Repair only an incomplete tail, retaining every validated frame.
            try handle.truncate(atOffset:UInt64(cursor!.validBytes))
            try handle.seekToEnd();try handle.write(contentsOf:bytes);try handle.synchronize()
        }
        if Self.cursors.count >= 64,let key=Self.cursors.keys.first { Self.cursors.removeValue(forKey:key) }
        Self.cursors[activeJournalURL]=Cursor(id:draft.id,samples:draft.samples?.count ?? 0,points:draft.route.count,
            sequence:frame.sequence,validBytes:(same ? cursor!.validBytes:0)+bytes.count)
    }

    private func readCheckpoint() throws ->(draft:RecordingDraft,sequence:Int,validBytes:Int)? {
        guard FileManager.default.fileExists(atPath:activeJournalURL.path) else { return nil }
        let bytes=try Data(contentsOf:activeJournalURL)
        var offset=0,result:RecordingDraft?,sequence = -1
        while bytes.count-offset >= 8 {
            let length=bytes[offset..<offset+8].reduce(UInt64(0)) { ($0 << 8)|UInt64($1) }
            guard length <= 64*1024*1024,length <= UInt64(bytes.count-offset-8) else { break }
            let end=offset+8+Int(length)
            guard let frame=try? JSONDecoder().decode(Frame.self,from:bytes[(offset+8)..<end]),
                  frame.sequence == sequence+1 else { break }
            if let previous=result {
                guard previous.id == frame.draft.id,previous.vehicleID == frame.draft.vehicleID,
                      frame.sampleOffset == (previous.samples?.count ?? 0),frame.pointOffset == previous.route.count else { break }
            } else if frame.sampleOffset != 0 || frame.pointOffset != 0 { break }
            var next=frame.draft
            next.samples=(result?.samples ?? [])+frame.samples
            next.route=(result?.route ?? [])+frame.points
            result=next;sequence=frame.sequence;offset=end
        }
        if result == nil,!bytes.isEmpty { throw AppFailure("The recording journal has no complete valid frame. Original bytes are preserved.") }
        return result.map { ($0,sequence,offset) }
    }

    func recoveredCheckpoint() throws ->RecordingDraft? {
        let draft=try readCheckpoint()?.draft
        return draft?.id == finalizedJournalID ? nil:draft
    }
    func markFinalizedCheckpoint(in state:StoredState) throws {
        guard state.draft == nil,FileManager.default.fileExists(atPath:activeJournalURL.path) else { return }
        let id=try Self.cursors[activeJournalURL]?.id ?? readCheckpoint()?.draft.id
        guard let id,finalizedJournalID != id,state.trips.contains(where:{$0.id == id}) else { return }
        try Data(id.uuidString.utf8).write(to:finalizedJournalURL,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
    }
}

import Foundation

/// Immutable value snapshot crossing the persistence queue. No shared mutable
/// references are stored in RecordingDraft or its raw samples/route points.
private struct DraftCheckpointSnapshot:@unchecked Sendable { let draft:RecordingDraft }

extension LocalStore {
    static let persistenceQueue=DispatchQueue(label:"DriveLine.persistence",qos:.utility)
    var activeJournalURL:URL { url.deletingLastPathComponent().appendingPathComponent("active-recording.journal") }
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
        Self.persistenceQueue.async {
            do { try self.appendCheckpoint(snapshot.draft);completion(nil) }
            catch { completion("The recording checkpoint could not be saved. Keep the app open and retry Finish.") }
        }
    }

    private func appendCheckpoint(_ draft:RecordingDraft) throws {
        if Self.cursors[activeJournalURL] == nil,let recovered=try readCheckpoint() {
            Self.cursors[activeJournalURL]=Cursor(id:recovered.draft.id,samples:recovered.draft.samples?.count ?? 0,
                points:recovered.draft.route.count,sequence:recovered.sequence,validBytes:recovered.validBytes)
        }
        let cursor=Self.cursors[activeJournalURL]
        let same=cursor?.id == draft.id
        let sampleOffset=same ? cursor!.samples:0
        let pointOffset=same ? cursor!.points:0
        guard sampleOffset <= (draft.samples?.count ?? 0),pointOffset <= draft.route.count else {
            throw AppFailure("Checkpoint evidence shrank unexpectedly; original journal preserved.")
        }
        var header=draft;header.samples=nil;header.route=[];header.liveEvidence=LiveRecordingEvidence()
        let frame=Frame(sequence:same ? cursor!.sequence+1:0,draft:header,sampleOffset:sampleOffset,pointOffset:pointOffset,
            samples:Array((draft.samples ?? []).dropFirst(sampleOffset)),points:Array(draft.route.dropFirst(pointOffset)))
        let payload=try JSONEncoder().encode(frame)
        var size=UInt64(payload.count).bigEndian
        var bytes=withUnsafeBytes(of:&size) { Data($0) };bytes.append(payload)
        try FileManager.default.createDirectory(at:activeJournalURL.deletingLastPathComponent(),withIntermediateDirectories:true)
        if !same {
            try bytes.write(to:activeJournalURL,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
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
        return result.map { ($0,sequence,offset) }
    }

    func recoveredCheckpoint() throws ->RecordingDraft? { try readCheckpoint()?.draft }
}

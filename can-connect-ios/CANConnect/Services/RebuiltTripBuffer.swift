import Foundation
import CryptoKit

/// Bounded producer queue, append-only samples, durable checkpoints. The legacy
/// envelope is materialized once at Finish, off the main actor. No whole-trip
/// sample array is retained by the published active draft.
final class RebuiltTripBuffer: @unchecked Sendable {
    private let queue=DispatchQueue(label:"DriveLine.trip-log",qos:.utility)
    private let lock=NSLock()
    private var pending=0
    private var failure:Error?
    private var retryFrames:[Data]=[]
    private var validOffset:UInt64=0
    private var finalized=false
    private let recordingID:UUID
    private let writeFrame:(FileHandle,Data)throws->Void
    private var handle:FileHandle?
    private var lastSync=ProcessInfo.processInfo.systemUptime
    let url:URL
    init(url:URL,draft:RecordingDraft,writeFrame:@escaping (FileHandle,Data)throws->Void = { try $0.write(contentsOf:$1) }) throws {
        self.url=url;self.recordingID=draft.id;self.writeFrame=writeFrame
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        guard !FileManager.default.fileExists(atPath:url.path) else { throw TelemetryFailure.storage }
        var bytes=TelemetryLog.magic
        var metadata=draft;metadata.samples=nil;metadata.route=[];metadata.liveEvidence=LiveRecordingEvidence();metadata.rebuiltBuffer=nil
        bytes.append(try TelemetryLog.frame(type:10,body:JSONEncoder().encode(metadata)))
        for sample in draft.samples ?? [] { bytes.append(try TelemetryLog.frame(type:11,body:JSONEncoder().encode(sample))) }
        for point in draft.route { bytes.append(try TelemetryLog.frame(type:12,body:JSONEncoder().encode(point))) }
        validOffset=UInt64(bytes.count)
        try bytes.write(to:url,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        handle=try FileHandle(forWritingTo:url);try handle?.seekToEnd();try handle?.synchronize()
    }
    func append(_ sample:OBDSample) throws { try enqueue(type:11,body:JSONEncoder().encode(sample)) }
    func append(_ point:RoutePoint) throws { try enqueue(type:12,body:JSONEncoder().encode(point)) }
    private func enqueue(type:UInt8,body:Data) throws {
        lock.lock()
        if let failure { lock.unlock();throw failure }
        guard pending < 128,!finalized else { lock.unlock();throw TelemetryFailure.storage }
        pending += 1;lock.unlock()
        queue.async { [self] in
            defer { lock.lock();pending -= 1;lock.unlock() }
            do {
                let frame=try TelemetryLog.frame(type:type,body:body)
                lock.lock();let failed=failure != nil;lock.unlock()
                if failed { retryFrames.append(frame);return }
                var appended=false
                do {
                    guard let handle,!finalized else { throw TelemetryFailure.storage }
                    try writeFrame(handle,frame);validOffset += UInt64(frame.count);appended=true
                    let now=ProcessInfo.processInfo.systemUptime
                    if now-lastSync >= 1 { try handle.synchronize();lastSync=now }
                } catch {
                    // A full write followed by failed sync is already present.
                    if !appended { retryFrames.append(frame) }
                    lock.lock();failure=error;lock.unlock()
                }
            } catch { lock.lock();failure=error;lock.unlock() }
        }
    }
    func checkpoint(_ draft:RecordingDraft,completion:@escaping @Sendable (String?)->Void) {
        lock.lock()
        // Finish supersedes stale checkpoint requests; they are not save errors.
        if finalized { lock.unlock();completion(nil);return }
        guard pending < 128,failure == nil else { lock.unlock();completion("Recording storage is unavailable or its bounded queue is full.");return }
        pending += 1;lock.unlock()
        var metadata=draft;metadata.samples=nil;metadata.route=[];metadata.liveEvidence=LiveRecordingEvidence();metadata.rebuiltBuffer=nil
        let snapshot=BufferSnapshot(draft:metadata)
        queue.async { [self] in
            defer { lock.lock();pending -= 1;lock.unlock() }
            do {
                // A checkpoint admitted before Finish can be queued behind it.
                // Finalized bytes and their checksum must remain immutable.
                if finalized { completion(nil);return }
                lock.lock();let prior=failure;lock.unlock();if let prior { throw prior }
                guard let handle else { throw TelemetryFailure.storage }
                let frame=try TelemetryLog.frame(type:10,body:JSONEncoder().encode(snapshot.draft))
                try handle.write(contentsOf:frame);validOffset += UInt64(frame.count)
                try handle.synchronize();lastSync=ProcessInfo.processInfo.systemUptime
                completion(nil)
            } catch { lock.lock();failure=error;lock.unlock();completion("Recording storage failed. Finish can be retried after storage is available.") }
        }
    }
    func materialize(_ draft:RecordingDraft) throws -> RecordingDraft {
        try queue.sync {
            lock.lock();let needsRepair=failure != nil;lock.unlock()
            if needsRepair {
                // Preserve original bytes before repairing a failed append.
                try FileManager.default.copyItem(at:url,to:url.appendingPathExtension("damaged-"+UUID().uuidString))
                guard let handle else { throw TelemetryFailure.storage }
                try handle.truncate(atOffset:validOffset);try handle.seekToEnd()
                while let frame=retryFrames.first {
                    try handle.write(contentsOf:frame);validOffset += UInt64(frame.count);retryFrames.removeFirst()
                }
                try handle.synchronize();lock.lock();failure=nil;lock.unlock()
            }
            try handle?.synchronize()
            var result=draft; result.rebuiltBuffer=nil;result.samples=[];result.route=[]
            let recovery=try TelemetryLog.recover(url:url) { type,data in
                if type == 11 { result.samples?.append(try JSONDecoder().decode(OBDSample.self,from:data)) }
                if type == 12 { result.route.append(try JSONDecoder().decode(RoutePoint.self,from:data)) }
            }
            guard !recovery.damagedTail else { throw TelemetryFailure.storage }
            return result
        }
    }
    func finalize(_ draft:RecordingDraft? = nil) throws {
        try queue.sync {
            if finalized { return }
            if var metadata=draft {
                metadata.samples=nil;metadata.route=[];metadata.liveEvidence=LiveRecordingEvidence();metadata.rebuiltBuffer=nil
                let frame=try TelemetryLog.frame(type:10,body:JSONEncoder().encode(metadata))
                try handle?.write(contentsOf:frame);validOffset += UInt64(frame.count)
            }
            try handle?.synchronize()
            let reader=try FileHandle(forReadingFrom:url);defer { try? reader.close() }
            var hash=SHA256(), length:UInt64=0
            while let bytes=try reader.read(upToCount:65536),!bytes.isEmpty { hash.update(data:bytes);length += UInt64(bytes.count) }
            let count=try TelemetryLog.recover(url:url).records
            let marker:[String:String] = ["recordingID":recordingID.uuidString,"sha256":hash.finalize().map { String(format:"%02x",$0) }.joined(),"bytes":String(length),"records":String(count)]
            let destination=url.appendingPathExtension("finalized")
            try JSONEncoder().encode(marker).write(to:destination,options:.atomic)
            let markerHandle=try FileHandle(forWritingTo:destination);try markerHandle.synchronize();try markerHandle.close()
            lock.lock();finalized=true;lock.unlock()
        }
    }
    static func recover(url:URL) throws -> RecordingDraft? {
        var draft:RecordingDraft?,samples:[OBDSample]=[],points:[RoutePoint]=[]
        _ = try TelemetryLog.recover(url:url) { type,data in
            if type == 10 { draft=try JSONDecoder().decode(RecordingDraft.self,from:data) }
            if type == 11 { samples.append(try JSONDecoder().decode(OBDSample.self,from:data)) }
            if type == 12 { points.append(try JSONDecoder().decode(RoutePoint.self,from:data)) }
        }
        draft?.samples=samples;draft?.route=points
        if let last=samples.last { let updated=max(draft?.updatedAt ?? last.timestamp,last.timestamp);draft?.updatedAt=updated }
        return draft
    }
    deinit { try? handle?.close() }
}
private struct BufferSnapshot:@unchecked Sendable { let draft:RecordingDraft }

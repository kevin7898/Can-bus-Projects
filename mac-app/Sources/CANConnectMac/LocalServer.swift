import Foundation
import Network
import Security

final class LocalServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label:"can.connect.http")
    private var connections: [UUID:NWConnection] = [:]
    var onState: ((String) -> Void)?
    func start(port:UInt16, allowLAN:Bool, token:String, handler:@escaping (HTTPRequest) async -> HTTPResponse) throws {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue:port) else { throw CANError.invalid("Choose a port from 1 to 65535.") }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        if !allowLAN { params.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:nwPort) }
        // The explicit local endpoint already supplies the port; passing it twice is EINVAL.
        let listener = allowLAN ? try NWListener(using:params,on:nwPort) : try NWListener(using:params)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.onState?("Listening")
            case .failed(let error): self?.onState?("Failed: \(error.localizedDescription)")
            case .cancelled: self?.onState?("Stopped")
            default: break
            }
        }
        if allowLAN { listener.service = NWListener.Service(name:"CAN CONNECT",type:"_canconnect._tcp") }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self else { connection.cancel(); return }
            let id = UUID(); self.connections[id] = connection; connection.start(queue:self.queue)
            self.queue.asyncAfter(deadline:.now()+30) { [weak self,weak connection] in connection?.cancel(); self?.connections.removeValue(forKey:id) }
            self.receive(connection,id:id,buffer:Data(),token:token,handler:handler)
        }
        listener.start(queue:queue)
    }
    func stop() {
        listener?.cancel(); listener = nil
        queue.async { [weak self] in self?.connections.values.forEach { $0.cancel() }; self?.connections.removeAll() }
    }
    private func receive(_ connection:NWConnection,id:UUID,buffer:Data,token:String,handler:@escaping (HTTPRequest) async -> HTTPResponse) {
        connection.receive(minimumIncompleteLength:1,maximumLength:65536) { [weak self] data,_,complete,error in
            guard let self = self else { connection.cancel(); return }
            var next = buffer; if let data = data { next.append(data) }
            if next.count > RecordingImporter.maxBytes+16_388 { self.send(HTTPResponse(413,json:["error":"Body exceeds 50 MB"]),connection,id); return }
            do {
                if let request = try HTTPRequest.parse(next) {
                    guard request.isAuthorized(token:token) else { self.send(HTTPResponse(401,json:["error":"Bearer token required"]),connection,id); return }
                    Task { let response = await handler(request); self.send(response,connection,id) }; return
                }
                if complete || error != nil { connection.cancel(); self.connections.removeValue(forKey:id); return }
                self.receive(connection,id:id,buffer:next,token:token,handler:handler)
            } catch { self.send(HTTPResponse(400,json:["error":error.localizedDescription]),connection,id) }
        }
    }
    private func send(_ response:HTTPResponse,_ connection:NWConnection,_ id:UUID) {
        queue.async { [weak self] in
            connection.send(content:response.wire,completion:.contentProcessed { [weak self] _ in
                connection.cancel(); self?.queue.async { self?.connections.removeValue(forKey:id) }
            })
        }
    }
}

enum PairingKeychain {
    static let service = "ca.canconnect.mac.pairing"
    static func token() throws -> String {
        let query:[String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"companion-api",kSecReturnData as String:true]
        var result:CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary,&result)
        if status==errSecSuccess, let data = result as? Data, let token = String(data:data,encoding:.utf8) { return token }
        guard status==errSecItemNotFound else { throw CANError.invalid("Cannot read the pairing token from Keychain (\(status)).") }
        var bytes = [UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes)==errSecSuccess else { throw CANError.invalid("Cannot generate a secure pairing token.") }
        let token = Data(bytes).base64EncodedString()
        let add:[String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"companion-api",kSecValueData as String:Data(token.utf8),kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        guard SecItemAdd(add as CFDictionary,nil)==errSecSuccess else { throw CANError.invalid("Cannot save the pairing token in Keychain.") }
        return token
    }
}

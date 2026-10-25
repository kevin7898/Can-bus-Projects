import XCTest
@testable import CANConnectCore

final class ScannerTests:XCTestCase {
    func testVINFromIndexedELMResponse() throws {
        let response = "014\r0:490201314847434D\r1:3832363333413030\r2:34333532\r>"
        XCTAssertEqual(try ScannerVINReader.parseVIN(response),"1HGCM82633A004352")
    }
    func testPhase7HeaderVINPreservesRespondingECUAndRejectsPartialReply() throws {
        let response="7E8 10 14 49 02 01 33 56 57\r7E8 21 41 41 41 41 41 30 45\r7E8 22 4D 30 30 30 30 30 31\r>"
        XCTAssertEqual(try ScannerVINReader.parseVIN(response),"3VWAAAAA0EM000001")
        XCTAssertEqual(ScannerVINReader.respondingAddress(response),"7E8")
        XCTAssertThrowsError(try ScannerVINReader.parseVIN("7E8 06 49 02 01 33 56 57\r>"))
    }
    func testUnsupportedAndTruncatedVINStayUnavailable() {
        for response in ["NO DATA\r>","490201314847\r>","?"] {
            XCTAssertThrowsError(try ScannerVINReader.parseVIN(response))
        }
    }
}

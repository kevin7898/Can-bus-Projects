import XCTest
@testable import CANConnectCore

final class ScannerTests:XCTestCase {
    func testVINFromIndexedELMResponse() throws {
        let response = "014\r0:490201314847434D\r1:3832363333413030\r2:34333532\r>"
        XCTAssertEqual(try ScannerVINReader.parseVIN(response),"1HGCM82633A004352")
    }
    func testUnsupportedAndTruncatedVINStayUnavailable() {
        for response in ["NO DATA\r>","490201314847\r>","?"] {
            XCTAssertThrowsError(try ScannerVINReader.parseVIN(response))
        }
    }
}

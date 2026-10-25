import XCTest
import MapKit
@testable import CANConnect

final class RouteMapTests: XCTestCase {
    @MainActor
    func testLiveMapUpdatesLocationAndRouteWithoutBridgingGPSGaps() {
        let map = MKMapView(frame:CGRect(x:0,y:0,width:360,height:180))
        let coordinator = NativeRouteMap.Coordinator()
        map.delegate = coordinator
        let start = Date(timeIntervalSince1970:1_700_000_000)
        func point(_ offset: Double, _ seconds: Double) -> RoutePoint {
            RoutePoint(latitude:49+offset,longitude:-124,timestamp:start.addingTimeInterval(seconds),accuracy:5,speed:5)
        }
        coordinator.update(map,route:[],isLive:true,isSample:false)
        XCTAssertTrue(map.annotations.isEmpty)
        XCTAssertTrue(map.overlays.isEmpty)
        XCTAssertFalse(map.showsUserLocation, "Use recorded fixes, not a second location service")
        let first = point(0,0)
        coordinator.update(map,route:[first],isLive:true,isSample:false)
        XCTAssertEqual(map.annotations.count,1)
        XCTAssertEqual(map.annotations.first?.coordinate.latitude,49)
        XCTAssertTrue(map.overlays.isEmpty)
        let route = [first,point(0.0001,10),point(0.0002,60),point(0.0003,70)]
        coordinator.update(map,route:route,isLive:true,isSample:false)
        XCTAssertEqual(map.annotations.count,1)
        XCTAssertEqual(map.annotations.first?.coordinate.latitude,49.0003)
        XCTAssertEqual(map.overlays.compactMap { ($0 as? MKPolyline)?.pointCount },[2,2])
        XCTAssertEqual(map.accessibilityValue,"4 GPS points")
        for point in route {
            XCTAssertTrue(map.visibleMapRect.contains(MKMapPoint(CLLocationCoordinate2D(latitude:point.latitude,longitude:point.longitude))))
        }
        coordinator.update(map,route:route,isLive:false,isSample:false)
        XCTAssertTrue(map.annotations.isEmpty, "History must not imply a current location")
        coordinator.update(map,route:[],isLive:true,isSample:false)
        XCTAssertTrue(map.annotations.isEmpty)
        XCTAssertTrue(map.overlays.isEmpty)
    }
}

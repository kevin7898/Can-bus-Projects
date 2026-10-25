import SwiftUI
import MapKit

struct RouteMap:NSViewRepresentable {
    var trips:[Trip]
    @Binding var viewport:MapViewport
    var marker:TelemetrySample? = nil
    var style:String = "standard"
    var onSelect:((Trip)->Void)? = nil
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context:Context) -> MKMapView {
        let map = MKMapView(); map.delegate = context.coordinator
        map.showsCompass = true; map.showsZoomControls = true; map.pointOfInterestFilter = .excludingAll
        map.addGestureRecognizer(NSClickGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.clicked(_:))))
        map.setRegion(region,animated:false); return map
    }
    var region:MKCoordinateRegion { MKCoordinateRegion(center:CLLocationCoordinate2D(latitude:viewport.latitude,longitude:viewport.longitude),span:MKCoordinateSpan(latitudeDelta:viewport.latitudeDelta,longitudeDelta:viewport.longitudeDelta)) }
    func updateNSView(_ map:MKMapView,context:Context) {
        context.coordinator.parent = self
        map.mapType = style=="satellite" ? .hybrid : .mutedStandard
        let signature = trips.map{$0.id.uuidString}.joined(separator:",")
        if context.coordinator.signature != signature {
            context.coordinator.signature = signature; map.removeOverlays(map.overlays)
            for trip in trips {
                // Keep gaps and impossible GPS jumps disconnected, rather than drawing invented roads.
                var segment:[CLLocationCoordinate2D] = []; var previous:TelemetrySample?
                func finish() { if segment.count>1 { map.addOverlay(MKPolyline(coordinates:segment,count:segment.count)) }; segment = [] }
                for s in trip.samples where s.hasCoordinate {
                    if let p = previous, s.timestamp.timeIntervalSince(p.timestamp)>30 || Trip.haversine(p,s)>2 { finish() }
                    segment.append(CLLocationCoordinate2D(latitude:s.latitude!,longitude:s.longitude!)); previous = s
                }
                finish()
            }
        }
        if abs(map.region.center.latitude-viewport.latitude)>0.00001 || abs(map.region.center.longitude-viewport.longitude)>0.00001 || abs(map.region.span.latitudeDelta-viewport.latitudeDelta)>0.0001 || abs(map.region.span.longitudeDelta-viewport.longitudeDelta)>0.0001 {
            context.coordinator.applying = true; map.setRegion(region,animated:false); context.coordinator.applying = false
        }
        map.removeAnnotations(map.annotations)
        if let marker = marker,marker.hasCoordinate { let a = MKPointAnnotation(); a.coordinate = CLLocationCoordinate2D(latitude:marker.latitude!,longitude:marker.longitude!); a.title = "Playback"; map.addAnnotation(a) }
    }
    final class Coordinator:NSObject,MKMapViewDelegate {
        var parent:RouteMap
        var signature = ""
        var applying = false
        init(_ parent:RouteMap) { self.parent = parent }
        func mapView(_ mapView:MKMapView,rendererFor overlay:MKOverlay) -> MKOverlayRenderer {
            let renderer = MKPolylineRenderer(overlay:overlay); renderer.strokeColor = NSColor(calibratedRed:0.4,green:0.67,blue:1,alpha:0.7); renderer.lineWidth = 3; return renderer
        }
        func mapView(_ mapView:MKMapView,regionDidChangeAnimated animated:Bool) {
            guard !applying else { return }
            var v = MapViewport(); v.latitude = mapView.region.center.latitude; v.longitude = mapView.region.center.longitude
            v.latitudeDelta = mapView.region.span.latitudeDelta; v.longitudeDelta = mapView.region.span.longitudeDelta
            DispatchQueue.main.async { [weak self] in self?.parent.viewport = v }
        }
        @objc func clicked(_ gesture:NSClickGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let location = gesture.location(in:map)
            var best:(Trip,CGFloat)?
            for trip in parent.trips {
                for sample in trip.coordinates {
                    let point = map.convert(CLLocationCoordinate2D(latitude:sample.latitude!,longitude:sample.longitude!),toPointTo:map)
                    let d = hypot(point.x-location.x,point.y-location.y)
                    if d<24 && (best==nil || d<best!.1) { best = (trip,d) }
                }
            }
            if let best = best { parent.onSelect?(best.0) }
        }
    }
    static func fitted(_ trips:[Trip]) -> MapViewport {
        let coordinates = trips.flatMap(\.coordinates)
        guard let minLat = coordinates.compactMap(\.latitude).min(),let maxLat = coordinates.compactMap(\.latitude).max(),let minLon = coordinates.compactMap(\.longitude).min(),let maxLon = coordinates.compactMap(\.longitude).max() else { return MapViewport() }
        var v = MapViewport(); v.latitude = (minLat+maxLat)/2; v.longitude = (minLon+maxLon)/2
        v.latitudeDelta = max(0.008,(maxLat-minLat)*1.25); v.longitudeDelta = max(0.012,(maxLon-minLon)*1.25); return v
    }
}

struct MapPanel:View {
    let trips:[Trip]
    @Binding var viewport:MapViewport
    var style = "standard"
    var height:CGFloat = 350
    var marker:TelemetrySample? = nil
    var onSelect:((Trip)->Void)? = nil
    var body:some View {
        VStack(spacing:0) {
            ZStack {
            RouteMap(trips:trips,viewport:$viewport,marker:marker,style:style,onSelect:onSelect)
            if trips.flatMap(\.coordinates).isEmpty {
                Text("No recorded GPS coordinates in this selection").font(.system(size:12)).padding(10).background(Theme.panel.opacity(0.95)).clipShape(RoundedRectangle(cornerRadius:6)).frame(maxWidth:.infinity,maxHeight:.infinity)
            }
            }.frame(height:max(1,height-38))
            HStack { Label("Recorded GPS traces",systemImage:"point.topleft.down.curvedto.point.bottomright.up"); Spacer(); Button("Fit recordings") { viewport = RouteMap.fitted(trips) } }.font(.system(size:10)).padding(.horizontal,10).frame(height:38).background(Theme.background.opacity(0.86))
        }.frame(height:height).clipped()
    }
}

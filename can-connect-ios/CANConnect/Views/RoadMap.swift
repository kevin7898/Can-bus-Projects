import SwiftUI
import MapKit

struct RoadFeature: Decodable { var kind: String; var name: String; var major: Bool; var lines: [[[Double]]] }
enum RoadAtlas {
    static let features: [RoadFeature] = {
        guard let url = Bundle.main.url(forResource:"NanaimoMap", withExtension:"json"), let data = try? Data(contentsOf:url) else { return [] }
        return (try? JSONDecoder().decode([RoadFeature].self, from:data)) ?? []
    }()
    static let highlighted = ["Departure Bay Rd","Brechin Rd","Terminal Ave","Terminal Ave N","Bowen Rd","Island Hwy N","Nanaimo Parkway"]
}
struct RoadMap: View {
    var route: [RoutePoint] = []
    var sample = true
    var body: some View {
        Canvas { context, size in
            func point(_ coordinate: [Double]) -> CGPoint { CGPoint(x:(coordinate[0] + 124.045) / 0.14 * size.width, y:(49.235 - coordinate[1]) / 0.105 * size.height) }
            for feature in RoadAtlas.features {
                for line in feature.lines where line.count > 1 {
                    var path = Path(); path.move(to:point(line[0])); for c in line.dropFirst() { path.addLine(to:point(c)) }
                    if feature.kind != "roads" { path.closeSubpath(); context.fill(path, with:.color(Color(hex:feature.kind == "water" ? 0x101b2a : 0x1b2c2e))) }
                    else { let driven = sample && RoadAtlas.highlighted.contains(feature.name)
                        context.stroke(path, with:.color(driven ? Palette.blue.opacity(0.85) : Color(hex:feature.major ? 0x4c5e72 : 0x344252)), style:StrokeStyle(lineWidth:driven ? 2.4 : (feature.major ? 1.2 : 0.65), lineCap:.round, lineJoin:.round))
                    }
                }
            }
            context.draw(Text("NANAIMO").font(.system(size:11, weight:.medium)).foregroundColor(Palette.muted), at:CGPoint(x:size.width * 0.64, y:size.height * 0.73))
            context.draw(Text("Bowen Rd").font(.system(size:9)).foregroundColor(Palette.muted), at:CGPoint(x:size.width * 0.4, y:size.height * 0.54))
        }.background(Color(hex:0x17202a)).clipShape(RoundedRectangle(cornerRadius:14))
        .overlay(alignment:.bottomLeading) { Text("City of Nanaimo · sample road coverage").font(.system(size:8)).foregroundStyle(Palette.muted).padding(9).background(Palette.background.opacity(0.75), in:RoundedRectangle(cornerRadius:5)).padding(7) }
        .accessibilityLabel("Nanaimo road map with sample driven corridors highlighted in blue")
    }
}
struct NativeRouteMap: UIViewRepresentable {
    var route: [RoutePoint]
    func makeUIView(context: Context) -> MKMapView {
        let view = MKMapView(); view.overrideUserInterfaceStyle = .dark; view.delegate = context.coordinator
        view.showsCompass = true; view.pointOfInterestFilter = .excludingAll
        let coords = route.map { CLLocationCoordinate2D(latitude:$0.latitude, longitude:$0.longitude) }
        if coords.count > 1 {
            let line = MKPolyline(coordinates:coords, count:coords.count); view.addOverlay(line)
            view.setVisibleMapRect(line.boundingMapRect, edgePadding:UIEdgeInsets(top:45,left:35,bottom:45,right:35), animated:false)
        } else if let coordinate = coords.first {
            view.setRegion(MKCoordinateRegion(center:coordinate, latitudinalMeters:1500, longitudinalMeters:1500), animated:false)
        } else { view.setRegion(MKCoordinateRegion(center:CLLocationCoordinate2D(latitude:49.185, longitude:-123.96), latitudinalMeters:10000, longitudinalMeters:10000), animated:false) }
        return view
    }
    func updateUIView(_ uiView: MKMapView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay:overlay) }
            let renderer = MKPolylineRenderer(polyline:line); renderer.strokeColor = UIColor(red:88/255,green:167/255,blue:1,alpha:1); renderer.lineWidth = 4; return renderer
        }
    }
}

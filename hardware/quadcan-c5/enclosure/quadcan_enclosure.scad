// QuadCAN-C5 enclosure - two-part box (base + lid), print in PETG or ASA (PLA softens in a hot car).
// Board coordinates match gen/gen_pcb.py: origin = board top-left, +x right, +y down (toward the SD slot).
// Render: openscad -D 'part="base"' -o base.stl quadcan_enclosure.scad   (part = base | lid | both)

part = "both";

BW = 110; BH = 85; BT = 1.6;        // board
gap = 0.6;                          // board-to-wall clearance
wall = 2.2; floor_t = 2.0; lid_t = 2.0;
stand = 6.0;                        // standoff height (CR1220 holder sits under the board)
above = 15.0;                       // tallest part above the board: 47 uF cap (12 mm) + margin
IW = BW + 2 * gap; IH = BH + 2 * gap;
base_h = floor_t + stand + BT + above;
holes = [[3.5, 3.5], [106.5, 3.5], [106.5, 81.5], [58, 50]];

// board (x, y) -> box XY (y flipped so the SD slot faces -Y)
function P(x, y) = [wall + gap + x, wall + gap + (BH - y)];
z_pcb_top = floor_t + stand + BT;

module rounded_box(size, r) {
    hull() for (x = [r, size[0] - r], y = [r, size[1] - r]) translate([x, y, 0]) cylinder(r = r, h = size[2], $fn = 32);
}

module base() {
    difference() {
        rounded_box([IW + 2 * wall, IH + 2 * wall, base_h], 3);
        translate([wall, wall, floor_t]) cube([IW, IH, base_h]);
        // LEFT wall: Micro-Fit harness connector (board y 29..57), 11 mm tall
        translate([-1, P(0, 57.5)[1], z_pcb_top - 0.5]) cube([wall + 2, 29, 11]);
        // TOP edge (board y = 0 -> box +Y wall): USB-C at board x 50
        translate([P(45.0, 0)[0], IH + wall - 1, z_pcb_top - 0.3]) cube([10, wall + 2, 4.2]);
        // BOTTOM edge (board y = 85 -> box -Y wall): microSD slot at board x 62..78
        translate([P(62.5, 0)[0], -1, z_pcb_top - 0.6]) cube([15, wall + 2, 2.6]);
        // RIGHT wall: SMA bulkhead for the GPS antenna (u.FL -> SMA pigtail), board y 70
        translate([IW + wall - 1, P(0, 70)[1], z_pcb_top + 6]) rotate([0, 90, 0]) cylinder(d = 6.6, h = wall + 2, $fn = 32);
        // vent slots near the 5 V buck (board x 30..50, y 60..80)
        for (i = [0:4]) translate([P(30 + i * 4, 0)[0], -1, floor_t + 3]) cube([2, wall + 2, 8]);
    }
    // standoffs with M3 self-tap holes
    for (h = holes) translate([P(h[0], h[1])[0], P(h[0], h[1])[1], 0]) difference() {
        cylinder(d = 6.5, h = floor_t + stand, $fn = 32);
        translate([0, 0, 1]) cylinder(d = 2.6, h = 20, $fn = 24);
    }
    // lid screw bosses in the corners
    for (c = [[wall + 3, wall + 3], [IW + wall - 3, wall + 3], [wall + 3, IH + wall - 3], [IW + wall - 3, IH + wall - 3]])
        translate([c[0], c[1], 0]) difference() {
            cylinder(d = 6, h = base_h, $fn = 32);
            translate([0, 0, base_h - 10]) cylinder(d = 2.6, h = 11, $fn = 24);
        }
}

module lid() {
    difference() {
        union() {
            rounded_box([IW + 2 * wall, IH + 2 * wall, lid_t], 3);
            translate([wall + 0.3, wall + 0.3, -2]) difference() {   // locating lip
                cube([IW - 0.6, IH - 0.6, 2]);
                translate([1.2, 1.2, -1]) cube([IW - 3, IH - 3, 4]);
            }
        }
        for (c = [[wall + 3, wall + 3], [IW + wall - 3, wall + 3], [wall + 3, IH + wall - 3], [IW + wall - 3, IH + wall - 3]])
            translate([c[0], c[1], -3]) cylinder(d = 3.4, h = 10, $fn = 24);
        // light-pipe holes: RX LEDs (CAN4..CAN1), STAT/SD/LINK, GPS fix
        for (n = [0:3]) translate([P(39.5, 14.5 + 10 * n)[0], P(39.5, 14.5 + 10 * n)[1], -3]) cylinder(d = 2.2, h = 10, $fn = 16);
        for (y = [20, 22.5, 25]) translate([P(100.5, y)[0], P(100.5, y)[1], -3]) cylinder(d = 2.2, h = 10, $fn = 16);
        translate([P(98, 82.5)[0], P(98, 82.5)[1], -3]) cylinder(d = 2.2, h = 10, $fn = 16);
        // MARK button access (press with a finger / pen)
        translate([P(105, 30.5)[0], P(105, 30.5)[1], -3]) cylinder(d = 7, h = 10, $fn = 32);
        // jumper window over the TERM / TX_EN headers (board x 18..44, y 12..52)
        translate([P(18, 52)[0], P(18, 52)[1], -3]) cube([26, 40, 10]);
        // label recess
        translate([P(60, 75)[0], P(60, 75)[1], lid_t - 0.6]) linear_extrude(1) text("QuadCAN", size = 6, halign = "center");
    }
}

if (part == "base" || part == "both") base();
if (part == "lid") lid();
if (part == "both") translate([0, 0, base_h + 8]) lid();

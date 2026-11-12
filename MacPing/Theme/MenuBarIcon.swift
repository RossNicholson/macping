import AppKit

/// The menu bar icon: a ball sending out waves, as a template image so it
/// follows the menu bar's colour. With hosts down the waves turn into an
/// exclamation mark beside it.
enum MenuBarIcon {
    static func image(alert: Bool) -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let ball = NSBezierPath(ovalIn: NSRect(x: 2, y: 5.5, width: 8.5, height: 8.5))
            ball.lineWidth = 1.8
            ball.stroke()

            if alert {
                NSBezierPath(roundedRect: NSRect(x: 14.2, y: 2, width: 2.4, height: 7.6), xRadius: 1.2, yRadius: 1.2).fill()
                NSBezierPath(ovalIn: NSRect(x: 14.1, y: 11, width: 2.6, height: 2.6)).fill()
            } else {
                for radius in [4.0, 7.5] {
                    let wave = NSBezierPath()
                    wave.appendArc(withCenter: NSPoint(x: 9.5, y: 7), radius: radius,
                                   startAngle: -80, endAngle: 0, clockwise: false)
                    wave.lineWidth = 1.6
                    wave.lineCapStyle = .round
                    wave.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = alert ? "MacPing: a host is down" : "MacPing"
        return image
    }
}

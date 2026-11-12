import SwiftUI

/// MacPing's mascot: a ping-pong ball with a face, bouncing off a paddle and
/// sending out waves. Drawn in the rubber-hose style of the other apps'
/// mascots: thick ink outlines, pastel fills, big eyes. `bounce` lifts the
/// ball, which the window animates while monitors are running.
struct Mascot: View {
    enum Mood { case happy, worried }

    var mood: Mood = .happy
    var size: CGFloat = 72
    var disc: Color? = AppColors.mint
    /// Points the ball rises, in a 100-point drawing
    var bounce: Double = 0
    var waves = true

    private static let ink = Color(hex: 0x232428)
    private static let ball = Color(hex: 0xFBF6E9)
    private static let ballShade = Color(hex: 0xEFE6CF)
    private static let paddle = Color(hex: 0xEE9C86)      // coral
    private static let rubber = Color(hex: 0xD9806A)
    private static let handle = Color(hex: 0xC3C7F6)      // periwinkle
    private static let blush = Color(hex: 0xF6C3B4)

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 100
            context.scaleBy(x: scale, y: scale)
            draw(in: &context)
        }
        .frame(width: size, height: size)
        .background { if let disc { Circle().fill(disc) } }
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext) {
        let ink = Self.ink
        let outline = StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)

        // The paddle, tilted behind the ball at the bottom left
        var paddle = context
        paddle.translateBy(x: 30, y: 66)
        paddle.rotate(by: .degrees(-38))
        var grip = Path(roundedRect: CGRect(x: -4, y: 12, width: 8, height: 18), cornerRadius: 3.5)
        paddle.fill(grip, with: .color(Self.handle))
        paddle.stroke(grip, with: .color(ink), style: outline)
        grip = Path(ellipseIn: CGRect(x: -15, y: -17, width: 30, height: 32))
        paddle.fill(grip, with: .color(Self.paddle))
        paddle.drawLayer { layer in
            layer.clip(to: grip)
            layer.fill(Path(ellipseIn: CGRect(x: 2, y: -20, width: 20, height: 38)), with: .color(Self.rubber))
        }
        paddle.stroke(grip, with: .color(ink), style: outline)

        // Waves off to the top right
        if waves {
            for radius in [9.0, 14.5] {
                var wave = Path()
                wave.addArc(center: CGPoint(x: 68, y: 30 - bounce), radius: radius,
                            startAngle: .degrees(-70), endAngle: .degrees(-5), clockwise: false)
                context.stroke(wave, with: .color(ink.opacity(radius > 10 ? 0.45 : 0.8)),
                               style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            }
        }

        // The ball
        var ball = context
        ball.translateBy(x: 54, y: 48 - bounce)
        let body = Path(ellipseIn: CGRect(x: -22, y: -22, width: 44, height: 44))
        ball.fill(body, with: .color(Self.ball))
        ball.drawLayer { layer in
            layer.clip(to: body)
            layer.fill(Path(ellipseIn: CGRect(x: -6, y: 2, width: 40, height: 34)), with: .color(Self.ballShade))
        }
        // A shine
        ball.stroke(Path { path in
            path.addArc(center: .zero, radius: 15.5, startAngle: .degrees(200), endAngle: .degrees(240), clockwise: false)
        }, with: .color(.white), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        ball.stroke(body, with: .color(ink), style: outline)

        // Face
        for x in [-10.5, 2.5] {
            let eye = Path(ellipseIn: CGRect(x: x, y: -8, width: 8, height: 10.5))
            ball.fill(eye, with: .color(.white))
            ball.stroke(eye, with: .color(ink), lineWidth: 2)
            switch mood {
            case .happy:
                ball.fill(Path(ellipseIn: CGRect(x: x + 2.3, y: -4.8, width: 4.8, height: 6.4)), with: .color(ink))
                ball.fill(Path(ellipseIn: CGRect(x: x + 3.2, y: -4.1, width: 1.8, height: 1.8)), with: .color(.white))
            case .worried:
                ball.fill(Path(ellipseIn: CGRect(x: x + 2.7, y: -3.8, width: 3, height: 3.6)), with: .color(ink))
            }
        }
        if mood == .worried {
            // Brows up in the middle
            for (x, direction) in [(-10.5, 1.0), (2.5, -1.0)] {
                var brow = Path()
                brow.move(to: CGPoint(x: x + (direction > 0 ? 0 : 8), y: -12))
                brow.addLine(to: CGPoint(x: x + (direction > 0 ? 8 : 0), y: -14.5))
                ball.stroke(brow, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        for x in [-16.0, 9.0] {
            ball.fill(Path(ellipseIn: CGRect(x: x, y: 4.5, width: 7, height: 3.6)), with: .color(Self.blush))
        }
        var mouth = Path()
        switch mood {
        case .happy:
            mouth.move(to: CGPoint(x: -5.5, y: 7))
            mouth.addQuadCurve(to: CGPoint(x: 4.5, y: 7), control: CGPoint(x: -0.5, y: 13))
        case .worried:
            mouth.move(to: CGPoint(x: -4.5, y: 11))
            mouth.addQuadCurve(to: CGPoint(x: 3.5, y: 11), control: CGPoint(x: -0.5, y: 7))
        }
        ball.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }
}

/// The ball bouncing while monitors run
struct BouncingMascot: View {
    var running: Bool
    var mood: Mascot.Mood = .happy
    var size: CGFloat = PanelMetrics.mascot
    var disc: Color? = AppColors.mint

    var body: some View {
        if running {
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Mascot(mood: mood, size: size, disc: disc, bounce: abs(sin(t * 2.4)) * 7)
            }
        } else {
            Mascot(mood: mood, size: size, disc: disc)
        }
    }
}

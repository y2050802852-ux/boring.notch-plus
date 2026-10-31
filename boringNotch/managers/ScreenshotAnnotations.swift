//
//  ScreenshotAnnotations.swift
//  boringNotch
//
//  Annotation tools for the frozen-screenshot overlay: freehand pen,
//  rectangle, ellipse, line and arrow strokes drawn on top of the selection,
//  composited into the final PNG on confirm.
//

import AppKit
import SwiftUI

// MARK: - Model

enum AnnotationTool: String, CaseIterable, Identifiable {
    case none, pen, rectangle, ellipse, line, arrow

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .none: return "cursorarrow"
        case .pen: return "pencil.tip"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        }
    }

    var helpKey: String {
        switch self {
        case .none: return "Move selection"
        case .pen: return "Pen"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .line: return "Line"
        case .arrow: return "Arrow"
        }
    }
}

enum AnnotationColor: String, CaseIterable, Identifiable {
    case red, yellow, green, blue, white, black

    var id: String { rawValue }

    var nsColor: NSColor {
        switch self {
        case .red: return .systemRed
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .white: return .white
        case .black: return .black
        }
    }

    var swiftColor: Color { Color(nsColor: nsColor) }

    var cgColor: CGColor {
        nsColor.usingColorSpace(.sRGB)?.cgColor ?? NSColor.black.cgColor
    }
}

/// One drawn annotation. Points are in selection-local coordinates
/// (top-left origin) so strokes follow the selection when it moves.
struct AnnotationStroke: Identifiable {
    let id = UUID()
    let tool: AnnotationTool
    let color: AnnotationColor
    var points: [CGPoint]

    /// SwiftUI path for the given offset (strokes are stored selection-local).
    func path(offset: CGPoint) -> Path {
        var path = Path()
        switch tool {
        case .none:
            break
        case .pen:
            guard let first = points.first else { break }
            path.move(to: first + offset)
            for point in points.dropFirst() {
                path.addLine(to: point + offset)
            }
        case .rectangle:
            guard let rect = rectFromPoints() else { break }
            path.addRect(rect.offsetBy(dx: offset.x, dy: offset.y))
        case .ellipse:
            guard let rect = rectFromPoints() else { break }
            path.addEllipse(in: rect.offsetBy(dx: offset.x, dy: offset.y))
        case .line:
            guard points.count >= 2 else { break }
            path.move(to: points[0] + offset)
            path.addLine(to: points[1] + offset)
        case .arrow:
            guard points.count >= 2 else { break }
            let from = points[0] + offset
            let to = points[1] + offset
            path.move(to: from)
            path.addLine(to: to)
            for head in Self.arrowHeadPoints(from: from, to: to) {
                path.move(to: to)
                path.addLine(to: head)
            }
        }
        return path
    }

    private func rectFromPoints() -> CGRect? {
        guard points.count >= 2 else { return nil }
        return CGRect(
            x: min(points[0].x, points[1].x),
            y: min(points[0].y, points[1].y),
            width: abs(points[1].x - points[0].x),
            height: abs(points[1].y - points[0].y))
    }

    private static func arrowHeadPoints(from: CGPoint, to: CGPoint, length: CGFloat = 14) -> [CGPoint] {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let spread = CGFloat.pi / 7
        return [
            CGPoint(
                x: to.x - length * cos(angle - spread),
                y: to.y - length * sin(angle - spread)),
            CGPoint(
                x: to.x - length * cos(angle + spread),
                y: to.y - length * sin(angle + spread)),
        ]
    }
}

private extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
}

// MARK: - Canvas (live rendering)

/// Renders committed and in-progress strokes across the whole overlay.
struct AnnotationCanvasView: View {
    @ObservedObject var manager: ScreenshotManager

    var body: some View {
        Canvas { context, _ in
            for stroke in manager.strokes {
                let path = stroke.path(offset: manager.rect.origin)
                if stroke.points.count < 2, let single = stroke.points.first {
                    let dot = CGRect(
                        x: manager.rect.origin.x + single.x - 1.5,
                        y: manager.rect.origin.y + single.y - 1.5,
                        width: 3, height: 3)
                    context.fill(Path(ellipseIn: dot), with: .color(stroke.color.swiftColor))
                } else {
                    context.stroke(
                        path,
                        with: .color(stroke.color.swiftColor),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Toolbar

struct AnnotationToolbarView: View {
    @ObservedObject var manager: ScreenshotManager

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AnnotationTool.allCases) { tool in
                toolButton(tool)
            }

            Divider()
                .frame(height: 18)

            ForEach(AnnotationColor.allCases) { color in
                colorButton(color)
            }

            Divider()
                .frame(height: 18)

            toolbarButton(icon: "arrow.uturn.backward", help: "Undo") {
                manager.undoAnnotation()
            }
            .disabled(manager.strokes.isEmpty)

            toolbarButton(icon: "trash", help: "Clear") {
                manager.clearAnnotations()
            }
            .disabled(manager.strokes.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.82)))
        .position(manager.toolbarPosition(for: manager.rect))
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        let active = manager.activeTool == tool
        return toolbarButton(icon: tool.symbolName, help: tool.helpKey) {
            withAnimation(.easeOut(duration: 0.1)) {
                manager.activeTool = active ? .none : tool
            }
        }
        .foregroundStyle(active ? Color.white : Color.gray)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(active ? 0.18 : 0))
        )
    }

    private func colorButton(_ color: AnnotationColor) -> some View {
        let active = manager.activeColor == color
        return Button {
            manager.activeColor = color
        } label: {
            Circle()
                .fill(color.swiftColor)
                .frame(width: 14, height: 14)
                .overlay(
                    Circle().strokeBorder(
                        active ? Color.white : Color.white.opacity(0.25),
                        lineWidth: active ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
        .help(Text(LocalizedStringKey("Color")))
    }

    private func toolbarButton(
        icon: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.gray)
        .help(Text(LocalizedStringKey(help)))
    }
}

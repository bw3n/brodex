import AppKit
import SwiftUI

struct ExpandedPanelView: View {
    @Bindable var viewModel: NotchBroViewModel
    let onCloseBubble: () -> Void
    let onLayoutChange: () -> Void
    private let shellAnimation = Animation.spring(response: 0.34, dampingFraction: 0.84)

    var body: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                shellBackground
                shellContent
            }
            .frame(width: viewModel.windowWidth, height: viewModel.windowHeight, alignment: .top)
            .contentShape(Rectangle())
            .clipShape(currentShellShape)
            .scaleEffect(viewModel.hoverPreviewVisible ? 1.15 : 1.0, anchor: .top)
            .shadow(
                color: .black.opacity((viewModel.panelVisible || viewModel.closedDropPreviewVisible) ? 0.30 : 0.0),
                radius: (viewModel.panelVisible || viewModel.closedDropPreviewVisible) ? 12 : 0,
                y: (viewModel.panelVisible || viewModel.closedDropPreviewVisible) ? 4 : 0
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(shellAnimation, value: viewModel.shellState)
        .animation(shellAnimation, value: viewModel.dropInteractionState)
        .onAppear {
            onLayoutChange()
        }
        .onChange(of: viewModel.windowWidth) { _, _ in
            onLayoutChange()
        }
        .onChange(of: viewModel.windowHeight) { _, _ in
            onLayoutChange()
        }
    }

    private var currentShellShape: AttachedNotchShape {
        AttachedNotchShape(
            topShoulderRadius: shellTopShoulderRadius,
            topShoulderDepth: shellTopShoulderDepth,
            bottomCornerRadius: shellBottomCornerRadius
        )
    }

    @ViewBuilder
    private var shellContent: some View {
        if viewModel.panelVisible {
            terminalPanel
        } else if viewModel.closedDropPreviewVisible {
            closedDropPreview
        }
    }

    private var terminalPanel: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 40)

            terminalSurface
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var terminalSurface: some View {
        TerminalViewport(
            terminalSession: viewModel.terminalSession,
            onFileDropTargetChanged: { isTargeted in
                viewModel.updateOpenDropInteraction(isTargeted)
            },
            onFileDrop: { urls in
                viewModel.acceptDroppedFileURLs(urls)
            }
        )
        .frame(height: viewModel.terminalViewportMaxHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.02, green: 0.02, blue: 0.025).opacity(0.98))
        )
        .overlay {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        viewModel.openDropPreviewVisible
                            ? Color(red: 0.31, green: 0.86, blue: 0.66).opacity(0.95)
                            : Color.white.opacity(0.14),
                        style: StrokeStyle(
                            lineWidth: viewModel.openDropPreviewVisible ? 2 : 1
                        )
                    )

                if viewModel.openDropPreviewVisible {
                    Text("Drop to insert file paths")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.84, green: 0.98, blue: 0.92))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.72))
                        )
                        .padding(.top, 14)
                        .padding(.trailing, 14)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var closedDropPreview: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 38)

            VStack(spacing: 14) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color(red: 0.69, green: 0.97, blue: 0.83))

                Text("Drop files here")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Brodex will insert quoted paths into the prompt without running them.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 250)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.05, green: 0.08, blue: 0.08).opacity(0.96))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        Color(red: 0.38, green: 0.95, blue: 0.74).opacity(0.92),
                        style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])
                    )
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var shellBackground: some View {
        currentShellShape
            .fill(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.985),
                        Color(red: 0.025, green: 0.025, blue: 0.028).opacity(0.985)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                ZStack {
                    currentShellShape
                        .stroke(Color.white.opacity(viewModel.panelVisible ? 0.08 : 0.05), lineWidth: 1)

                    LinearGradient(
                        colors: [
                            .white.opacity(0.025),
                            .clear,
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(currentShellShape)
                }
            }
    }

    private var shellTopShoulderRadius: CGFloat {
        if viewModel.closedDropPreviewVisible {
            return 19
        }

        switch viewModel.shellState {
        case .hidden, .hover:
            return 18
        case .open:
            return 19
        }
    }

    private var shellTopShoulderDepth: CGFloat {
        if viewModel.closedDropPreviewVisible {
            return 19
        }

        switch viewModel.shellState {
        case .hidden, .hover:
            return 16
        case .open:
            return 19
        }
    }

    private var shellBottomCornerRadius: CGFloat {
        if viewModel.closedDropPreviewVisible {
            return 24
        }

        switch viewModel.shellState {
        case .hidden, .hover:
            return 14
        case .open:
            return 24
        }
    }
}

private struct TerminalViewport: NSViewRepresentable {
    let terminalSession: TerminalSessionController
    let onFileDropTargetChanged: (Bool) -> Void
    let onFileDrop: ([URL]) -> Void

    func makeNSView(context: Context) -> TerminalHostContainer {
        let container = TerminalHostContainer()
        container.onFileDropTargetChanged = onFileDropTargetChanged
        container.onFileDrop = onFileDrop
        container.attach(terminalSession.terminalView)
        return container
    }

    func updateNSView(_ nsView: TerminalHostContainer, context: Context) {
        nsView.onFileDropTargetChanged = onFileDropTargetChanged
        nsView.onFileDrop = onFileDrop
        nsView.attach(terminalSession.terminalView)
    }
}

private final class TerminalHostContainer: NSView {
    var onFileDropTargetChanged: ((Bool) -> Void)?
    var onFileDrop: (([URL]) -> Void)?

    private var isFileDropTargeted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    func attach(_ terminalView: NSView) {
        if terminalView.superview !== self {
            terminalView.removeFromSuperview()
            terminalView.frame = bounds
            terminalView.autoresizingMask = [.width, .height]
            addSubview(terminalView)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        subviews.first?.frame = bounds
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateFileDropState(with: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateFileDropState(with: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setFileDropTargeted(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !FileDropPasteboardReader.fileURLs(from: sender.draggingPasteboard).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = FileDropPasteboardReader.fileURLs(from: sender.draggingPasteboard)
        setFileDropTargeted(false)

        guard !urls.isEmpty else { return false }
        onFileDrop?(urls)
        return true
    }

    private func updateFileDropState(with draggingInfo: NSDraggingInfo) -> NSDragOperation {
        let urls = FileDropPasteboardReader.fileURLs(from: draggingInfo.draggingPasteboard)
        let targeted = !urls.isEmpty
        setFileDropTargeted(targeted)
        return targeted ? .copy : []
    }

    private func setFileDropTargeted(_ targeted: Bool) {
        guard targeted != isFileDropTargeted else { return }
        isFileDropTargeted = targeted
        onFileDropTargetChanged?(targeted)
    }
}

private struct AttachedNotchShape: Shape {
    var topShoulderRadius: CGFloat
    var topShoulderDepth: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { .init(.init(topShoulderRadius, topShoulderDepth), bottomCornerRadius) }
        set {
            topShoulderRadius = newValue.first.first
            topShoulderDepth = newValue.first.second
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let compactNotch = rect.height <= 48
        if compactNotch {
            let topCornerRadius = min(6, rect.width / 2, rect.height / 2)
            let bottomCornerRadius = min(14, rect.width / 2, rect.height / 2)

            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(
                    x: rect.minX + topCornerRadius,
                    y: rect.minY + topCornerRadius
                ),
                control: CGPoint(
                    x: rect.minX + topCornerRadius,
                    y: rect.minY
                )
            )
            path.addLine(
                to: CGPoint(
                    x: rect.minX + topCornerRadius,
                    y: rect.maxY - bottomCornerRadius
                )
            )
            path.addQuadCurve(
                to: CGPoint(
                    x: rect.minX + topCornerRadius + bottomCornerRadius,
                    y: rect.maxY
                ),
                control: CGPoint(
                    x: rect.minX + topCornerRadius,
                    y: rect.maxY
                )
            )
            path.addLine(
                to: CGPoint(
                    x: rect.maxX - topCornerRadius - bottomCornerRadius,
                    y: rect.maxY
                )
            )
            path.addQuadCurve(
                to: CGPoint(
                    x: rect.maxX - topCornerRadius,
                    y: rect.maxY - bottomCornerRadius
                ),
                control: CGPoint(
                    x: rect.maxX - topCornerRadius,
                    y: rect.maxY
                )
            )
            path.addLine(
                to: CGPoint(
                    x: rect.maxX - topCornerRadius,
                    y: rect.minY + topCornerRadius
                )
            )
            path.addQuadCurve(
                to: CGPoint(
                    x: rect.maxX,
                    y: rect.minY
                ),
                control: CGPoint(
                    x: rect.maxX - topCornerRadius,
                    y: rect.minY
                )
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.closeSubpath()
            return path
        }

        let topCornerRadius = min(topShoulderRadius, rect.width / 2, rect.height / 2)
        let bottomRadius = min(bottomCornerRadius, rect.width / 2, rect.height / 2)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.minY + topCornerRadius
            ),
            control: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.minY
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.maxY - bottomRadius
            )
        )
        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topCornerRadius + bottomRadius,
                y: rect.maxY
            ),
            control: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.maxY
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.maxX - topCornerRadius - bottomRadius,
                y: rect.maxY
            )
        )
        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.maxY - bottomRadius
            ),
            control: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.maxY
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.minY + topCornerRadius
            )
        )
        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX,
                y: rect.minY
            ),
            control: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.minY
            )
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()

        return path
    }
}

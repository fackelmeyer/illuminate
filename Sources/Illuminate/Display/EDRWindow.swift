import AppKit
import Metal
import QuartzCore
import os

/// A borderless, click-through window whose only content is a `CAMetalLayer`
/// cleared to a single colour with EDR enabled.
///
/// Two roles:
/// - `.overlay`: covers the whole screen and multiplies everything beneath by the clear colour.
/// - `.trigger`: a 1×1 point under the rounded display corner whose only job is to keep
///   EDR headroom granted, so a scaled gamma table is not clipped at 1.0.
///
/// Windows are created once and kept for the app's lifetime. Repeatedly closing and
/// re-creating Metal-backed windows has crashed other XDR tools (`EXC_BAD_ACCESS`),
/// so suspension toggles visibility and the EDR flag instead.
final class EDRWindow: NSWindow {
    enum Role {
        case overlay
        case trigger
    }

    let role: Role
    private let surface: EDRSurfaceView

    init?(role: Role, screen: NSScreen) {
        guard let surface = EDRSurfaceView(multiply: role == .overlay) else { return nil }
        self.role = role
        self.surface = surface
        super.init(contentRect: Self.frame(for: role, on: screen), styleMask: .borderless, backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        canHide = false
        animationBehavior = .none
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        switch role {
        case .overlay:
            // Shielding level keeps the overlay above full-screen spaces and the menu bar.
            // No `sharingType = .none` here: an excluded multiply window still multiplies
            // the captured image against black, so screenshots would come out black.
            level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        case .trigger:
            level = .screenSaver
            // Keep the trigger pixel out of screenshots and screen shares.
            sharingType = .none
        }
        // Otherwise VoiceOver, share pickers and window lists see an "untitled window".
        setAccessibilityElement(false)
        setAccessibilityRole(.unknown)

        surface.frame = NSRect(origin: .zero, size: frame.size)
        surface.autoresizingMask = [.width, .height]
        contentView = surface
        switch role {
        case .overlay: surface.color = .neutral
        case .trigger: surface.color = .trigger
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Re-anchors the window after a resolution or arrangement change.
    func reposition(on screen: NSScreen) {
        setFrame(Self.frame(for: role, on: screen), display: false)
    }

    /// Multiplier applied to everything beneath an overlay. Ignored for triggers.
    func setGain(_ gain: Double) {
        guard role == .overlay else { return }
        surface.color = .gray(gain)
    }

    private(set) var isActive = false

    /// Shows the window and requests EDR, or hides it and releases EDR.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        surface.isEDREnabled = active
        if active {
            // Fade in only once a frame is on screen, so the unmultiplied clear
            // colour never flashes across the display.
            alphaValue = 0
            orderFrontRegardless()
            surface.onFirstFramePresented = { [weak self] in
                guard let self, self.isActive else { return }
                self.alphaValue = 1
            }
            surface.isRendering = true
        } else {
            surface.isRendering = false
            orderOut(nil)
        }
    }

    private static func frame(for role: Role, on screen: NSScreen) -> NSRect {
        switch role {
        case .overlay:
            return screen.frame
        case .trigger:
            // AppKit's origin is bottom-left; the top-left pixel hides under the rounded corner.
            return NSRect(x: screen.frame.minX, y: screen.frame.maxY - 1, width: 1, height: 1)
        }
    }
}

/// Clears a 1×1 drawable to a solid extended-range colour. The compositor stretches it
/// over the layer, so GPU cost is negligible whatever the screen size.
final class EDRSurfaceView: NSView {
    struct Color: Equatable {
        var red, green, blue, alpha: Double

        /// Multiply by 1: no visible change.
        static let neutral = gray(1)
        /// Premultiplied 1.6 at 1 % opacity. A fully transparent drawable may be skipped by
        /// the compositor on some macOS versions, which would drop the EDR request.
        static let trigger = Color(red: 0.016, green: 0.016, blue: 0.016, alpha: 0.01)

        static func gray(_ value: Double) -> Color {
            Color(red: value, green: value, blue: value, alpha: 1)
        }
    }

    /// Present at ~5 fps for the window's whole life. About a second after the last
    /// present, WindowServer promotes an idle window to direct scan-out and drops its
    /// compositing filter, which would show the raw clear colour instead of multiplying.
    private static let keepAliveInterval: TimeInterval = 0.2
    /// `nextDrawable()` blocks the main thread once every drawable is in flight.
    private static let maximumFramesInFlight = 2
    /// If the first frame's completion never arrives, show the window anyway.
    private static let firstFrameFallback: TimeInterval = 0.25

    private let metalLayer = CAMetalLayer()
    private let commandQueue: any MTLCommandQueue
    private var keepAlive: Timer?
    private var framesInFlight = 0

    /// Called once on the main actor after the next started rendering session's first frame.
    var onFirstFramePresented: (() -> Void)?

    var color = Color.neutral {
        didSet { if color != oldValue { render() } }
    }

    var isEDREnabled: Bool {
        get { metalLayer.wantsExtendedDynamicRangeContent }
        set { metalLayer.wantsExtendedDynamicRangeContent = newValue }
    }

    var isRendering = false {
        didSet {
            guard isRendering != oldValue else { return }
            keepAlive?.invalidate()
            keepAlive = nil
            guard isRendering else { return }
            render()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.firstFrameFallback) { [weak self] in
                self?.firstFramePresented()
            }
            let timer = Timer(timeInterval: Self.keepAliveInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.render() }
            }
            timer.tolerance = Self.keepAliveInterval / 2
            RunLoop.main.add(timer, forMode: .common)
            keepAlive = timer
        }
    }

    init?(multiply: Bool) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            Log.display.error("No Metal device available")
            return nil
        }
        commandQueue = queue
        super.init(frame: .zero)

        metalLayer.device = device
        metalLayer.pixelFormat = .rgba16Float
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        metalLayer.wantsExtendedDynamicRangeContent = false
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = false
        metalLayer.drawableSize = CGSize(width: 1, height: 1)
        metalLayer.contentsGravity = .resize
        metalLayer.maximumDrawableCount = 2
        if multiply {
            // WindowServer multiplies everything beneath this layer by its colour.
            metalLayer.compositingFilter = "multiply"
        }
        // Layer-hosting: AppKit leaves the layer's contents alone.
        layer = metalLayer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func firstFramePresented() {
        let callback = onFirstFramePresented
        onFirstFramePresented = nil
        callback?()
    }

    private func render() {
        guard framesInFlight < Self.maximumFramesInFlight,
              let drawable = metalLayer.nextDrawable(),
              let buffer = commandQueue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        buffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        buffer.present(drawable)
        framesInFlight += 1
        // Metal calls this on an internal queue; hop back before touching view state.
        buffer.addCompletedHandler { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.framesInFlight -= 1
                self.firstFramePresented()
            }
        }
        buffer.commit()
    }
}

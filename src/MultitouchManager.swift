import Cocoa
import Foundation

public protocol MultitouchManagerDelegate: AnyObject {
    func didDetectFourFingerTap()
}

public class MultitouchManager {
    public weak var delegate: MultitouchManagerDelegate?
    public var isEnabled: Bool = true
    public var fingerTapMode: GestureFingerMode = .fourFingers

    private func matchesFingerCount(_ count: Int) -> Bool {
        switch fingerTapMode {
        case .fourFingers:
            return count == 4
        case .threeFingers:
            return count == 3
        case .threeOrFour:
            return count == 3 || count == 4
        case .disabled:
            return false
        }
    }

    private var handle: UnsafeMutableRawPointer?
    private var registeredDevices: [UnsafeMutableRawPointer] = []
    private var globalMouseMonitor: Any?

    private struct TouchPoint {
        var x: Float
        var y: Float
    }

    private struct MTPoint {
        var x: Float
        var y: Float
    }

    private struct MTTouch {
        var frame: Int32
        var timestamp: Double
        var identifier: Int32
        var state: Int32
        var fingerId: Int32
        var handId: Int32
        var normalizedPosition: MTPoint
        var size: Float
        var zero1: Int32
        var angle: Float
        var majorAxis: Float
        var minorAxis: Float
        var unknown: MTPoint
        var zero2: Int32
        var zero3: Float
        var density: Float
    }

    private typealias MTContactCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Int32, Double, Int32) -> Int32
    private typealias MTDeviceCreateListFunc = @convention(c) () -> Unmanaged<CFArray>?
    private typealias MTRegisterContactFrameCallbackFunc = @convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void
    private typealias MTUnregisterContactFrameCallbackFunc = @convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void
    private typealias MTDeviceStartFunc = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias MTDeviceStopFunc = @convention(c) (UnsafeMutableRawPointer) -> Void
    private typealias MTDeviceIsRunningFunc = @convention(c) (UnsafeMutableRawPointer) -> DarwinBoolean

    private var isTracking: Bool = false
    private var touchStartTime: Double = 0
    private var maxTouchesInGesture: Int = 0
    private var startPositions: [Int32: TouchPoint] = [:]
    private var maxMovement: Float = 0
    private var lastTriggerTime: Double = 0

    fileprivate static weak var activeInstance: MultitouchManager?

    public init() {}

    public func startMonitoring() {
        guard handle == nil else { return }

        // Dynamically load private MultitouchSupport.framework
        guard let lib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW) else {
            print("⚠️ MultitouchSupport framework not available on this macOS system.")
            return
        }
        self.handle = lib
        MultitouchManager.activeInstance = self

        guard let createListSym = dlsym(lib, "MTDeviceCreateList"),
              let regSym = dlsym(lib, "MTRegisterContactFrameCallback"),
              let startSym = dlsym(lib, "MTDeviceStart") else {
            print("⚠️ MultitouchSupport symbols not found.")
            return
        }

        let createList = unsafeBitCast(createListSym, to: MTDeviceCreateListFunc.self)
        let registerCallback = unsafeBitCast(regSym, to: MTRegisterContactFrameCallbackFunc.self)
        let deviceStart = unsafeBitCast(startSym, to: MTDeviceStartFunc.self)

        guard let deviceList = createList()?.takeRetainedValue() as? [AnyObject] else { return }

        let callback: MTContactCallback = { device, rawTouches, numTouches, timestamp, frame in
            MultitouchManager.activeInstance?.processFrame(rawTouches: rawTouches, numTouches: numTouches, timestamp: timestamp)
            return 0
        }

        for devObj in deviceList {
            let devRef = Unmanaged.passUnretained(devObj).toOpaque()
            registerCallback(devRef, callback)
            deviceStart(devRef, 0)
            registeredDevices.append(devRef)
        }

        // Global mouse down monitor: also detect physical clicks when fingers are down
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self = self, self.isEnabled else { return }
            if self.isTracking && self.matchesFingerCount(self.maxTouchesInGesture) && self.maxMovement < 0.08 {
                self.triggerFourFingerAction()
            }
        }
    }

    private func processFrame(rawTouches: UnsafeRawPointer?, numTouches: Int32, timestamp: Double) {
        guard isEnabled else { return }

        if numTouches > 0 {
            if !isTracking {
                isTracking = true
                touchStartTime = timestamp
                maxTouchesInGesture = Int(numTouches)
                startPositions.removeAll()
                maxMovement = 0

                if let raw = rawTouches {
                    let touchPtr = raw.assumingMemoryBound(to: MTTouch.self)
                    for i in 0..<Int(numTouches) {
                        let t = touchPtr[i]
                        startPositions[t.identifier] = TouchPoint(x: t.normalizedPosition.x, y: t.normalizedPosition.y)
                    }
                }
            } else {
                maxTouchesInGesture = max(maxTouchesInGesture, Int(numTouches))
                if let raw = rawTouches {
                    let touchPtr = raw.assumingMemoryBound(to: MTTouch.self)
                    for i in 0..<Int(numTouches) {
                        let t = touchPtr[i]
                        if let start = startPositions[t.identifier] {
                            let dx = t.normalizedPosition.x - start.x
                            let dy = t.normalizedPosition.y - start.y
                            let dist = sqrt(dx*dx + dy*dy)
                            if dist > maxMovement {
                                maxMovement = dist
                            }
                        } else {
                            startPositions[t.identifier] = TouchPoint(x: t.normalizedPosition.x, y: t.normalizedPosition.y)
                        }
                    }
                }
            }
        } else {
            // Touch released (all fingers lifted)
            if isTracking {
                isTracking = false
                let duration = timestamp - touchStartTime

                // Multitouch tap qualification:
                // 1. Peak finger count matches user-configured mode (3, 4, or 3-or-4)
                // 2. Tap duration is brief (between 40ms and 500ms)
                // 3. Movement is minimal (< 0.08 normalized coordinates, differentiating tap from swipe)
                if matchesFingerCount(maxTouchesInGesture) && duration >= 0.04 && duration <= 0.50 && maxMovement < 0.08 {
                    triggerFourFingerAction()
                }

                startPositions.removeAll()
                maxTouchesInGesture = 0
                maxMovement = 0
            }
        }
    }

    public func triggerFourFingerAction() {
        let now = Date().timeIntervalSince1970
        guard (now - lastTriggerTime) > 0.8 else { return }
        lastTriggerTime = now
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didDetectFourFingerTap()
        }
    }

    public func stopMonitoring() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }

        if let lib = handle,
           let stopSym = dlsym(lib, "MTDeviceStop"),
           let isRunningSym = dlsym(lib, "MTDeviceIsRunning") {
            let deviceStop = unsafeBitCast(stopSym, to: MTDeviceStopFunc.self)
            let isRunning = unsafeBitCast(isRunningSym, to: MTDeviceIsRunningFunc.self)

            for dev in registeredDevices {
                if isRunning(dev).boolValue {
                    deviceStop(dev)
                }
            }
        }
        registeredDevices.removeAll()
    }

    deinit {
        stopMonitoring()
    }
}

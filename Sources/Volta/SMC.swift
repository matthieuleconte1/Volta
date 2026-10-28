import Foundation
import IOKit

/// Minimal read-only client for the System Management Controller.
/// On Apple Silicon it exposes live power sensors (system, battery, CPU, backlight…).
final class SMC {
    static let shared = SMC()

    private struct KeyDataVer { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
    private struct PLimitData { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    // Explicit padding: Swift would otherwise pack the next fields into the tail padding.
    private struct KeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0; var pad: (UInt8, UInt8, UInt8) = (0, 0, 0) }
    private typealias Bytes32 = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    private struct Param {
        var key: UInt32 = 0
        var vers = KeyDataVer()
        var pLimit = PLimitData()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes32 = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static let cmdReadBytes: UInt8 = 5
    private static let cmdReadKeyInfo: UInt8 = 9

    private var conn: io_connect_t = 0
    private var infoCache: [UInt32: KeyInfo?] = [:]
    private let lock = NSLock()

    private init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return nil }
    }

    deinit { IOServiceClose(conn) }

    private func call(_ input: inout Param) -> Bool {
        var output = Param()
        var size = MemoryLayout<Param>.stride
        let kr = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<Param>.stride, &output, &size)
        input = output
        return kr == KERN_SUCCESS && output.result == 0
    }

    private static func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
    private static func string(_ v: UInt32) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((v >> $0) & 0xff) }, encoding: .ascii) ?? ""
    }

    private func info(for key: UInt32) -> KeyInfo? {
        if let cached = infoCache[key] { return cached }
        var p = Param()
        p.key = key
        p.data8 = Self.cmdReadKeyInfo
        let info: KeyInfo? = call(&p) ? p.keyInfo : nil
        infoCache[key] = info
        return info
    }

    func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        lock.lock(); defer { lock.unlock() }
        let k = Self.fourCC(key)
        guard let info = info(for: k), info.dataSize > 0 else { return nil }
        var p = Param()
        p.key = k
        p.keyInfo = info
        p.data8 = Self.cmdReadBytes
        guard call(&p) else { return nil }
        let bytes = withUnsafeBytes(of: p.bytes) { Array($0.prefix(Int(min(info.dataSize, 32)))) }
        return (Self.string(info.dataType), bytes)
    }

    /// Reads a numeric key, whatever its SMC encoding.
    func number(_ key: String) -> Double? {
        guard let (type, b) = read(key) else { return nil }
        #if arch(arm64)
        let littleEndian = true
        #else
        let littleEndian = false
        #endif
        func uint(_ n: Int) -> UInt64? {
            guard b.count >= n else { return nil }
            let slice = littleEndian ? Array(b.prefix(n).reversed()) : Array(b.prefix(n))
            return slice.reduce(0) { $0 << 8 | UInt64($1) }
        }
        switch type {
        case "flt ":
            guard b.count >= 4 else { return nil }
            let v = Double(b.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
            return v.isFinite ? v : nil
        case "ui8 ": return uint(1).map { Double($0) }
        case "ui16": return uint(2).map { Double($0) }
        case "ui32": return uint(4).map { Double($0) }
        case "si8 ": return uint(1).map { Double(Int8(bitPattern: UInt8($0))) }
        case "si16": return uint(2).map { Double(Int16(bitPattern: UInt16($0))) }
        case "si32": return uint(4).map { Double(Int32(bitPattern: UInt32($0))) }
        case "sp78": // big-endian signed fixed point 7.8 (Intel)
            guard b.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256
        case "fpe2":
            guard b.count >= 2 else { return nil }
            return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4
        default: return nil
        }
    }
}

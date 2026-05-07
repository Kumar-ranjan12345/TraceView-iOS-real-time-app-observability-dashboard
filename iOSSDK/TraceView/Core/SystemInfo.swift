import UIKit
import SystemConfiguration

// ─── SystemInfo ───────────────────────────────────────────────────────────────
// Static helpers for device/system metrics.

struct SystemInfo {

    // ── Memory ────────────────────────────────────────────────────────────────
    struct MemoryInfo { let appUsed, total, used, free: Double }

    static func memoryInfo() -> MemoryInfo {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let appUsed: Double = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        } == KERN_SUCCESS ? Double(taskInfo.resident_size) / 1_048_576 : 0

        let totalRAM = Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576

        var vmStats = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let freeRAM: Double = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
            }
        } == KERN_SUCCESS ? Double(vmStats.free_count) * Double(vm_page_size) / 1_048_576 : 0

        return MemoryInfo(appUsed: appUsed, total: totalRAM, used: totalRAM - freeRAM, free: freeRAM)
    }

    // ── CPU ───────────────────────────────────────────────────────────────────
    static func cpuUsage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let threads = threadList else { return 0 }
        var total = 0.0
        let infoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = infoCount
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            if result == KERN_SUCCESS && info.flags & TH_FLAGS_IDLE == 0 {
                total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
            }
        }
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadList)),
                      vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.size))
        return total
    }

    // ── Thread Count ──────────────────────────────────────────────────────────
    static func threadCount() -> Int {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS else { return 0 }
        if let list = threadList {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: list)),
                          vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.size))
        }
        return Int(threadCount)
    }

    // ── Disk ──────────────────────────────────────────────────────────────────
    struct DiskInfo { let total, free, used: Double }

    static func diskInfo() -> DiskInfo {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        let total = (attrs?[.systemSize] as? NSNumber)?.doubleValue ?? 0
        let free  = (attrs?[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
        return DiskInfo(total: total/1_073_741_824, free: free/1_073_741_824, used: (total-free)/1_073_741_824)
    }

    // ── Network Type ──────────────────────────────────────────────────────────
    static func networkType() -> String {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)
        guard let reachability = withUnsafePointer(to: &zeroAddress, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        }) else { return "unknown" }
        var flags = SCNetworkReachabilityFlags()
        SCNetworkReachabilityGetFlags(reachability, &flags)
        if !flags.contains(.reachable) { return "offline" }
        if flags.contains(.isWWAN) { return "cellular" }
        return "wifi"
    }

    // ── Battery ───────────────────────────────────────────────────────────────
    static func batteryStateString(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .charging: return "charging"
        case .full:     return "full"
        case .unplugged: return "unplugged"
        default:        return "unknown"
        }
    }

    // ── Thermal ───────────────────────────────────────────────────────────────
    static func thermalStateString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        default:        return "unknown"
        }
    }
}

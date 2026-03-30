import Foundation
import Darwin

nonisolated struct MemoryInfo: Sendable {
    let totalBytes: UInt64
    let appBytes: UInt64
    let freeBytes: UInt64

    var otherBytes: UInt64 {
        let used = appBytes + freeBytes
        return used < totalBytes ? totalBytes - used : 0
    }

    static func format(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        } else {
            let mb = Int(Double(bytes) / 1_048_576)
            return "\(mb) MB"
        }
    }
}

actor MemoryMonitor {
    private var timer: Task<Void, Never>?

    func start(interval: Duration = .seconds(5), onUpdate: @escaping @Sendable (MemoryInfo) -> Void) {
        timer?.cancel()
        // Immediate first read
        if let info = Self.read() { onUpdate(info) }

        timer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if let info = Self.read() { onUpdate(info) }
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    nonisolated static func read() -> MemoryInfo? {
        let total = ProcessInfo.processInfo.physicalMemory

        // App physical footprint via task_vm_info (includes Metal/GPU unified memory)
        var vmInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &vmInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        let appBytes: UInt64 = (kr == KERN_SUCCESS) ? UInt64(vmInfo.phys_footprint) : 0

        // System free memory via host_statistics64
        var vmStats = vm_statistics64_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let vmKr = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &vmCount)
            }
        }

        let pageSize = UInt64(getpagesize())
        let freeBytes: UInt64
        if vmKr == KERN_SUCCESS {
            freeBytes = (UInt64(vmStats.free_count) + UInt64(vmStats.inactive_count)) * pageSize
        } else {
            freeBytes = 0
        }

        return MemoryInfo(totalBytes: total, appBytes: appBytes, freeBytes: freeBytes)
    }
}

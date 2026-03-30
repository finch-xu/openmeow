import Foundation

#if SHERPA_ONNX_AVAILABLE
/// Returns a C string pointer valid only for the duration of the current expression.
/// Safe ONLY when passed directly as a function argument (e.g. `someFunc(toCPointer(s))`).
/// Do NOT store the result in a struct field — use CStringScope instead.
nonisolated func toCPointer(_ s: String) -> UnsafePointer<Int8>! {
    (s as NSString).utf8String
}

/// Accumulates strdup'd C strings so they stay alive until the scope is deallocated.
/// Use this when multiple C string pointers must remain valid across a block of code
/// (e.g. populating a C config struct before passing it to a C API).
nonisolated final class CStringScope {
    private var allocated: [UnsafeMutablePointer<CChar>] = []

    func cString(_ s: String) -> UnsafePointer<CChar>! {
        guard let ptr = strdup(s) else { return nil }
        allocated.append(ptr)
        return UnsafePointer(ptr)
    }

    deinit {
        for ptr in allocated { free(ptr) }
    }
}
#endif

nonisolated func resolveModelPath(_ base: String, _ relative: String?) -> String {
    guard let relative else { return "" }
    return (base as NSString).appendingPathComponent(relative)
}

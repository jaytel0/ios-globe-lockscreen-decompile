import Foundation

/// Bulletproof diagnostics: append to a file inside the app container so the
/// host can read it with `simctl get_app_container`.
enum DebugLog {
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("touch.log")
    }()
    private static let q = DispatchQueue(label: "debuglog")

    static func write(_ line: String) {
        q.async {
            let s = line + "\n"
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(Data(s.utf8)); try? h.close()
            } else {
                try? Data(s.utf8).write(to: url)
            }
        }
    }
    static func reset() { try? FileManager.default.removeItem(at: url) }
}

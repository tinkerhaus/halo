import Darwin

/// A cheap, shell-free view of the process table (via `sysctl`), used to answer
/// "is a process named X running inside the frontmost app?" — e.g. is `claude`
/// running under the front terminal, to pick a dynamic profile.
///
/// Note: a process's kernel name (`p_comm`) is unreliable for this — Claude Code,
/// for instance, sets its `p_comm` to its *version* ("2.1.160") and only carries
/// "claude" in its argv. So we match the command name from **argv[0]** (read per
/// candidate via `KERN_PROCARGS2`), falling back to `p_comm` for normal programs.
enum ProcessTree {
    /// True if `rootPID`, or any descendant, is invoked as `name` (argv[0]'s
    /// basename) or has `name` in its kernel `p_comm` (case-insensitive).
    static func containsDescendant(named name: String, under rootPID: pid_t) -> Bool {
        guard !name.isEmpty, let procs = snapshot() else { return false }
        let needle = name.lowercased()

        var childrenOf: [pid_t: [pid_t]] = [:]
        var commOf: [pid_t: String] = [:]
        for p in procs {
            childrenOf[p.ppid, default: []].append(p.pid)
            commOf[p.pid] = p.comm.lowercased()
        }

        var stack = childrenOf[rootPID] ?? []        // descendants only (not the terminal itself)
        var seen = Set<pid_t>()
        while let pid = stack.popLast() {
            guard seen.insert(pid).inserted else { continue }
            if commOf[pid]?.contains(needle) == true { return true }                 // cheap (already have it)
            if let cmd = commandName(of: pid), cmd.lowercased().contains(needle) { return true }  // the real signal
            if let kids = childrenOf[pid] { stack.append(contentsOf: kids) }
        }
        return false
    }

    /// (pid, ppid, comm) for every process, or nil if the table can't be read.
    /// Retries on ENOMEM — the table can grow between the size query and the fetch
    /// on a busy machine, so we over-allocate and pass the *real* buffer capacity.
    private static func snapshot() -> [(pid: pid_t, ppid: pid_t, comm: String)]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        let stride = MemoryLayout<kinfo_proc>.stride

        for _ in 0..<6 {
            var needed = 0
            guard sysctl(&mib, 4, nil, &needed, nil, 0) == 0, needed > 0 else { return nil }

            let capacity = needed / stride + 32                       // generous slack for churn
            var buffer = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
            var length = capacity * stride                            // tell sysctl the FULL capacity
            let rc = buffer.withUnsafeMutableBytes { raw in
                sysctl(&mib, 4, raw.baseAddress, &length, nil, 0)
            }
            if rc != 0 {
                if errno == ENOMEM { continue }                       // grew again → retry
                return nil
            }

            let count = length / stride
            var out: [(pid_t, pid_t, String)] = []
            out.reserveCapacity(count)
            for i in 0..<count {
                var p = buffer[i]
                let comm = withUnsafeBytes(of: &p.kp_proc.p_comm) { raw -> String in
                    let bytes = raw.bindMemory(to: UInt8.self)
                    return String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
                }
                out.append((p.kp_proc.p_pid, p.kp_eproc.e_ppid, comm))
            }
            return out
        }
        return nil
    }

    /// The basename of `pid`'s argv[0] (how it was invoked, e.g. "claude"), or nil.
    /// Reads `KERN_PROCARGS2`, which is allowed for the user's own processes.
    private static func commandName(of pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return nil }

        // Layout: [argc:Int32][exec_path\0][padding \0…][argv[0]\0][argv[1]\0]…[env…]
        var i = MemoryLayout<Int32>.size
        while i < size, buf[i] != 0 { i += 1 }       // skip exec_path
        while i < size, buf[i] == 0 { i += 1 }       // skip padding nulls
        let start = i
        while i < size, buf[i] != 0 { i += 1 }       // argv[0]
        guard i > start else { return nil }
        let argv0 = String(decoding: buf[start..<i], as: UTF8.self)
        return argv0.split(separator: "/").last.map(String.init) ?? argv0   // basename, in case it's a path
    }
}

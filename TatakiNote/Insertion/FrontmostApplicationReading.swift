import AppKit

/// いま前面にあるアプリの読み取り。
protocol FrontmostApplicationReading {
    var frontmostProcessIdentifier: pid_t? { get }
}

struct WorkspaceFrontmostApplication: FrontmostApplicationReading {
    var frontmostProcessIdentifier: pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
}

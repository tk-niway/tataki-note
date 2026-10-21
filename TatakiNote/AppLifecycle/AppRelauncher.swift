import Foundation

/// 今のプロセスが終わるのを待ってから、指定のアプリを開く。
enum AppRelauncher {
    /// 今のプロセスの終了を待ってアプリを開く、シェルのコマンドと引数を返す。
    static func relaunchCommand(appPath: String, processIdentifier: Int32) -> [String] {
        [
            "/bin/sh",
            "-c",
            "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"",
            "sh",
            String(processIdentifier),
            appPath,
        ]
    }

    /// 今のプロセスが終わった後に `appURL` を開く処理を起こす。待たずに戻る。
    static func relaunch(at appURL: URL) throws {
        let command = relaunchCommand(appPath: appURL.path, processIdentifier: ProcessInfo.processInfo.processIdentifier)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        try process.run()
    }
}

import ArgumentParser
import Foundation
import BrainmergeCore

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "doctor", abstract: "Check Claude.app, the brain, every identity and every memory link.")
    @Flag var json = false

    func run() throws {
        let findings = Context().doctor.run()
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(findings), as: UTF8.self))
        } else {
            for f in findings {
                let mark = switch f.level { case .ok: "ok  "; case .warning: "warn"; case .error: "FAIL" }
                print("\(mark)  \(f.title): \(f.detail)")
            }
        }
        if findings.hasErrors { throw ExitCode(1) }
    }
}

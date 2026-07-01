//
//  RunFormModelTests.swift
//  berthTests
//
//  The `container run …` argv is both the previewed command and the executed one,
//  so it is the highest-value pure target. Table-driven over the flag/env/port
//  matrix and the quoting rules.
//

import Testing
@testable import berth

struct RunFormModelTests {

    @Test func defaultArgv() {
        let m = RunFormModel()
        m.image = "nginx"
        #expect(m.argv == ["run", "-d", "--arch", "arm64", "-c", "2", "-m", "1G", "nginx"])
    }

    @Test func fullArgv() {
        let m = RunFormModel()
        m.image = "nginx"
        m.name = "web"
        m.remove = true
        m.readOnly = true
        m.rosetta = true
        m.cpus = 4
        m.memoryGB = 2
        var e = RunFormModel.EnvVar(); e.key = "FOO"; e.value = "bar"
        m.env = [e]
        var p1 = RunFormModel.PortMap(); p1.host = "8080"; p1.container = "80"
        var p2 = RunFormModel.PortMap(); p2.host = "53"; p2.container = "53"; p2.udp = true
        m.ports = [p1, p2]

        #expect(m.argv == [
            "run", "-d", "--rm", "--read-only", "--rosetta",
            "--name", "web", "--arch", "arm64",
            "-c", "4", "-m", "2G",
            "-e", "FOO=bar",
            "-p", "8080:80", "-p", "53:53/udp",
            "nginx",
        ])
    }

    @Test func emptyEnvKeyDropped() {
        let m = RunFormModel()
        m.image = "nginx"
        var empty = RunFormModel.EnvVar(); empty.key = ""; empty.value = "x"
        var ok = RunFormModel.EnvVar(); ok.key = "A"; ok.value = "b"
        m.env = [empty, ok]
        #expect(m.argv.contains("A=b"))
        #expect(!m.argv.contains("=x"))
    }

    @Test func incompletePortDropped() {
        let m = RunFormModel()
        m.image = "nginx"
        var noHost = RunFormModel.PortMap(); noHost.host = ""; noHost.container = "80"
        var noContainer = RunFormModel.PortMap(); noContainer.host = "8080"; noContainer.container = ""
        m.ports = [noHost, noContainer]
        #expect(!m.argv.contains("-p"))
    }

    @Test func emptyArchOmitsFlag() {
        let m = RunFormModel()
        m.image = "nginx"
        m.arch = ""
        #expect(!m.argv.contains("--arch"))
    }

    @Test func emptyImageOmitsTrailingArg() {
        let m = RunFormModel()
        m.image = ""
        #expect(m.argv == ["run", "-d", "--arch", "arm64", "-c", "2", "-m", "1G"])
    }

    @Test func commandPreviewQuotesSpaces() {
        let m = RunFormModel()
        m.image = "nginx"
        m.name = "my app"
        #expect(m.commandPreview.hasPrefix("container run -d"))
        #expect(m.commandPreview.contains("--name \"my app\""))
    }

    @Test func canRun() {
        let m = RunFormModel()
        #expect(m.canRun == false)          // empty image
        m.image = "   "
        #expect(m.canRun == false)          // whitespace only
        m.image = "alpine"
        #expect(m.canRun == true)
        m.busy = true
        #expect(m.canRun == false)          // busy
    }
}

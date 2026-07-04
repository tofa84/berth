//
//  BuildFormModelTests.swift
//  berthTests
//
//  Layer-A: the previewed `container build …` argv is mapped 1:1 into the
//  BuildRequest, and validation runs against injected FS probes (hermetic).
//

import Testing
@testable import berth

struct BuildFormModelTests {

    @Test func defaultArgv() {
        let m = BuildFormModel()
        m.contextDir = "/ctx"
        m.tag = "app:latest"
        #expect(m.argv == ["build", "-t", "app:latest", "--platform", "linux/arm64", "/ctx"])
    }

    @Test func fullArgv() {
        let m = BuildFormModel()
        m.contextDir = "/ctx"
        m.tag = "app:1.0"
        m.dockerfileOverride = "/ctx/Dockerfile.prod"
        var arg = BuildFormModel.KV(); arg.key = "VER"; arg.value = "1"
        m.buildArgs = [arg]
        var label = BuildFormModel.KV(); label.key = "team"; label.value = "infra"
        m.labels = [label]
        m.target = "runtime"
        m.platformARM64 = true
        m.platformAMD64 = true
        m.noCache = true
        m.pull = true
        #expect(m.argv == [
            "build", "-t", "app:1.0",
            "--build-arg", "VER=1",
            "--label", "team=infra",
            "--target", "runtime",
            "--platform", "linux/arm64", "--platform", "linux/amd64",
            "--no-cache", "--pull",
            "-f", "/ctx/Dockerfile.prod",
            "/ctx",
        ])
    }

    @Test func emptyKeyRowsAreDropped() {
        let m = BuildFormModel()
        m.contextDir = "/ctx"
        m.tag = "t"
        m.buildArgs = [BuildFormModel.KV(), { var k = BuildFormModel.KV(); k.key = "A"; k.value = "B"; return k }()]
        #expect(m.argv == ["build", "-t", "t", "--build-arg", "A=B", "--platform", "linux/arm64", "/ctx"])
    }

    @Test func dockerfilePathDefaultAndOverride() {
        let m = BuildFormModel()
        m.contextDir = "/ctx"
        #expect(m.dockerfilePath == "/ctx/Dockerfile")
        m.dockerfileOverride = "/other/Dockerfile.dev"
        #expect(m.dockerfilePath == "/other/Dockerfile.dev")
    }

    @Test func commandPreviewMatchesArgv() {
        let m = BuildFormModel()
        m.contextDir = "/ctx"
        m.tag = "app:latest"
        #expect(m.commandPreview == "container build -t app:latest --platform linux/arm64 /ctx")
    }

    @Test func validationPassesWhenComplete() {
        let m = BuildFormModel(fileExists: { _ in true }, fileSize: { _ in 10 })
        m.contextDir = "/ctx"
        m.tag = "app:latest"
        #expect(m.validationError == nil)
        #expect(m.canBuild)
    }

    @Test func validationNoContext() {
        let m = BuildFormModel(fileExists: { _ in true }, fileSize: { _ in 10 })
        #expect(m.validationError == "Choose a build context folder.")
        #expect(!m.canBuild)
    }

    @Test func validationMissingContextFolder() {
        let m = BuildFormModel(fileExists: { $0 != "/ctx" }, fileSize: { _ in 10 })
        m.contextDir = "/ctx"
        m.tag = "t"
        #expect(m.validationError == "Context folder does not exist.")
    }

    @Test func validationMissingDockerfile() {
        let m = BuildFormModel(fileExists: { $0 == "/ctx" }, fileSize: { _ in 10 })
        m.contextDir = "/ctx"
        m.tag = "t"
        #expect(m.validationError == "Dockerfile not found at /ctx/Dockerfile.")
    }

    @Test func validationDockerfileTooLarge() {
        let m = BuildFormModel(fileExists: { _ in true }, fileSize: { _ in BuildRequest.maxDockerfileBytes })
        m.contextDir = "/ctx"
        m.tag = "t"
        #expect(m.validationError?.contains("too large") == true)
    }

    @Test func validationNoTag() {
        let m = BuildFormModel(fileExists: { _ in true }, fileSize: { _ in 10 })
        m.contextDir = "/ctx"
        #expect(m.validationError == "Enter an image tag.")
    }

    @Test func validationNoPlatform() {
        let m = BuildFormModel(fileExists: { _ in true }, fileSize: { _ in 10 })
        m.contextDir = "/ctx"
        m.tag = "t"
        m.platformARM64 = false
        m.platformAMD64 = false
        #expect(m.validationError == "Select at least one platform.")
    }

    @Test func requestMapping() {
        let m = BuildFormModel(fileExists: { _ in true }, fileSize: { _ in nil })
        m.contextDir = "/ctx"
        m.tag = "app:latest"
        var arg = BuildFormModel.KV(); arg.key = "K"; arg.value = "V"
        m.buildArgs = [arg, BuildFormModel.KV()]  // second (empty) is filtered
        m.platformAMD64 = true
        let request = m.request()
        #expect(request.contextDir == "/ctx")
        #expect(request.dockerfilePath == "/ctx/Dockerfile")
        #expect(request.tags == ["app:latest"])
        #expect(request.buildArgs == ["K=V"])
        #expect(request.platforms == ["linux/arm64", "linux/amd64"])
    }

    @Test func fillRoundTripsFromRequest() {
        let request = BuildRequest(
            contextDir: "/ctx", dockerfilePath: "/ctx/Dockerfile.prod",
            tags: ["app:2.0"], buildArgs: ["A=B"], labels: ["x=y"],
            target: "final", platforms: ["linux/amd64"], noCache: true, pull: true)
        let m = BuildFormModel()
        m.fill(from: request)
        #expect(m.contextDir == "/ctx")
        #expect(m.dockerfileOverride == "/ctx/Dockerfile.prod")
        #expect(m.tag == "app:2.0")
        #expect(m.buildArgs.first?.key == "A")
        #expect(m.buildArgs.first?.value == "B")
        #expect(m.target == "final")
        #expect(m.platformARM64 == false)
        #expect(m.platformAMD64 == true)
        #expect(m.noCache)
        #expect(m.pull)
    }
}

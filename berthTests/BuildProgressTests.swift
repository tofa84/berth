//
//  BuildProgressTests.swift
//  berthTests
//
//  Layer-A tests for the BuildKit plain-progress parser + step folder. Fixtures
//  are the real M0 PoC transcript, so the grammar stays locked to what the shim
//  actually emits.
//

import Testing
@testable import berth

struct BuildProgressParserTests {
    typealias Line = BuildProgressParser.Line

    @Test func vertexTitleLine() {
        #expect(BuildProgressParser.classify("#5 [linux/arm64 1/3] RUN echo hi")
            == .vertex(id: 5, text: "[linux/arm64 1/3] RUN echo hi"))
    }

    @Test func internalAndResolverVertices() {
        #expect(BuildProgressParser.classify("#2 [internal] load build definition from Dockerfile")
            == .vertex(id: 2, text: "[internal] load build definition from Dockerfile"))
        #expect(BuildProgressParser.classify("#1 [resolver] fetching image...docker.io/library/alpine:latest")
            == .vertex(id: 1, text: "[resolver] fetching image...docker.io/library/alpine:latest"))
    }

    @Test func doneWithDuration() {
        #expect(BuildProgressParser.classify("#4 DONE 0.2s") == .done(id: 4, seconds: 0.2))
        #expect(BuildProgressParser.classify("#6 DONE 12.5s") == .done(id: 6, seconds: 12.5))
    }

    @Test func doneWithoutDuration() {
        #expect(BuildProgressParser.classify("#4 DONE") == .done(id: 4, seconds: nil))
    }

    @Test func cached() {
        #expect(BuildProgressParser.classify("#4 CACHED") == .cached(id: 4))
    }

    @Test func errorLine() {
        #expect(BuildProgressParser.classify(#"#6 ERROR: process "/bin/sh -c false" did not complete successfully: exit code: 1"#)
            == .error(id: 6, message: #"process "/bin/sh -c false" did not complete successfully: exit code: 1"#))
    }

    @Test func canceled() {
        #expect(BuildProgressParser.classify("#3 CANCELED") == .canceled(id: 3))
    }

    @Test func byteProgressDetailIsVertexLine() {
        // A status/detail line for a vertex — not a title, the folder decides.
        #expect(BuildProgressParser.classify("#4 sha256:5de5 4.18MB / 4.18MB 0.1s done")
            == .vertex(id: 4, text: "sha256:5de5 4.18MB / 4.18MB 0.1s done"))
    }

    @Test func processLogDetailIsVertexLine() {
        #expect(BuildProgressParser.classify("#5 0.035 hello-from-berth")
            == .vertex(id: 5, text: "0.035 hello-from-berth"))
    }

    @Test func nonHashLinesArePlain() {
        #expect(BuildProgressParser.classify("------") == .plain("------"))
        #expect(BuildProgressParser.classify(" > [linux/arm64 2/3] RUN false:") == .plain(" > [linux/arm64 2/3] RUN false:"))
        #expect(BuildProgressParser.classify("") == .plain(""))
        #expect(BuildProgressParser.classify("#notanumber") == .plain("#notanumber"))
    }

    @Test func ansiIsStripped() {
        #expect(BuildProgressParser.classify("\u{1B}[2K#5 DONE 0.0s") == .done(id: 5, seconds: 0.0))
        #expect(BuildProgressParser.strippingANSI("\u{1B}[1mhi\u{1B}[0m\r") == "hi")
    }
}

struct BuildStepFolderTests {
    // The M0 success transcript (verbatim), minus the trailing summary lines.
    static let successTranscript = """
    #1 [resolver] fetching image...docker.io/library/alpine:latest
    #1 DONE 0.0s
    #2 [internal] load build definition from Dockerfile
    #2 transferring dockerfile: 89B done
    #2 DONE 0.0s
    #3 [internal] load .dockerignore
    #3 transferring context: 2B done
    #3 DONE 0.0s
    #4 oci-layout://docker.io/library/alpine:latest@sha256:28bd5f
    #4 resolve docker.io/library/alpine:latest@sha256:28bd5f 0.1s done
    #4 sha256:5de5 4.18MB / 4.18MB 0.1s done
    #4 extracting sha256:5de5 0.1s done
    #4 DONE 0.2s
    #5 [linux/arm64 1/3] RUN echo hello-from-berth
    #5 0.035 hello-from-berth
    #5 DONE 0.0s
    #6 [linux/arm64 2/3] RUN date
    #6 0.022 Fri Jul  3 20:42:16 UTC 2026
    #6 DONE 0.0s
    #7 exporting to oci image format
    #7 exporting layers 0.0s done
    #7 sending tarball 0.0s done
    #7 DONE 0.0s
    """

    @Test func foldsSuccessTranscript() {
        var folder = BuildStepFolder()
        for line in Self.successTranscript.split(separator: "\n", omittingEmptySubsequences: false) {
            folder.ingest(String(line))
        }
        #expect(folder.steps.count == 7)
        #expect(folder.steps.map(\.id) == [1, 2, 3, 4, 5, 6, 7])
        // All terminal states resolved to done.
        #expect(folder.steps.allSatisfy {
            if case .done = $0.state { return true } else { return false }
        })
        // Titles are the first line seen for each id.
        #expect(folder.steps[4].title == "[linux/arm64 1/3] RUN echo hello-from-berth")
        #expect(folder.steps[3].state == .done(seconds: 0.2))
        // The RUN echo output landed as a detail line on step #5.
        #expect(folder.steps[4].detail.contains("0.035 hello-from-berth"))
        // Step #2 kept its transferring detail.
        #expect(folder.steps[1].detail.contains("transferring dockerfile: 89B done"))
    }

    @Test func foldsFailureWithErrorAndExcerpt() {
        let failure = """
        #5 [linux/arm64 1/3] RUN echo about-to-fail
        #5 0.039 about-to-fail
        #5 DONE 0.0s
        #6 [linux/arm64 2/3] RUN false
        #6 ERROR: process "/bin/sh -c false" did not complete successfully: exit code: 1
        ------
         > [linux/arm64 2/3] RUN false:
        ------
        """
        var folder = BuildStepFolder()
        for line in failure.split(separator: "\n", omittingEmptySubsequences: false) {
            folder.ingest(String(line))
        }
        #expect(folder.steps.count == 2)
        #expect(folder.steps[0].state == .done(seconds: 0.0))
        if case .error(let message) = folder.steps[1].state {
            #expect(message.contains("exit code: 1"))
        } else {
            Issue.record("step #6 should be in error state, was \(folder.steps[1].state)")
        }
        // The error excerpt was captured as trailing text (trimmed of the leading space).
        #expect(folder.trailing.contains("> [linux/arm64 2/3] RUN false:"))
    }

    @Test func cachedStep() {
        var folder = BuildStepFolder()
        folder.ingest("#4 oci-layout://docker.io/library/alpine:latest")
        folder.ingest("#4 CACHED")
        #expect(folder.steps.count == 1)
        #expect(folder.steps[0].state == .cached)
    }

    @Test func blankLinesAreIgnored() {
        var folder = BuildStepFolder()
        folder.ingest("")
        folder.ingest("   ")
        #expect(folder.isEmpty)
    }

    @Test func detailIsCappedAtFifty() {
        var folder = BuildStepFolder()
        folder.ingest("#1 [internal] noisy step")
        for i in 0..<100 { folder.ingest("#1 line \(i)") }
        #expect(folder.steps[0].detail.count == 50)
        // Cap keeps the most recent lines.
        #expect(folder.steps[0].detail.last == "line 99")
    }
}

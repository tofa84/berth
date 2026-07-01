//
//  LayerCommandTests.swift
//  berthTests
//
//  `ImageLayerInfo.parse(command:)` splits a layer's CREATED BY line into
//  instruction / body / "# buildkit" comment for the Layers tab. Instructions
//  match case-sensitively (shell "run foo" is not an instruction), and only
//  the literal BuildKit suffix counts as a comment — shell bodies contain `#`.
//

import Testing
@testable import berth

struct LayerCommandTests {

    @Test func splitsInstructionAndBody() {
        let p = ImageLayerInfo.parse(command: "ENV PATH=/usr/share/grafana/bin:/usr/local/sbin")
        #expect(p.instruction == "ENV")
        #expect(p.body == "PATH=/usr/share/grafana/bin:/usr/local/sbin")
        #expect(p.comment == nil)
    }

    @Test func splitsTrailingBuildkitComment() {
        let p = ImageLayerInfo.parse(command: "RUN |2 GF_UID=472 /bin/sh -c apk add --no-cache bash # buildkit")
        #expect(p.instruction == "RUN")
        #expect(p.body == "|2 GF_UID=472 /bin/sh -c apk add --no-cache bash")
        #expect(p.comment == "# buildkit")
    }

    @Test func lowercaseShellWordIsNotAnInstruction() {
        let p = ImageLayerInfo.parse(command: "run() { echo hi; }")
        #expect(p.instruction == nil)
        #expect(p.body == "run() { echo hi; }")
    }

    @Test func hashInsideBodyIsNotAComment() {
        let p = ImageLayerInfo.parse(command: "RUN apk info -vv | sort # sorted output")
        #expect(p.instruction == "RUN")
        #expect(p.body == "apk info -vv | sort # sorted output")
        #expect(p.comment == nil)
    }

    @Test func buildkitNeedsSeparation() {
        // No space before the marker → part of the body, not a comment.
        let p = ImageLayerInfo.parse(command: "RUN echo x# buildkit")
        #expect(p.comment == nil)
        #expect(p.body == "echo x# buildkit")
    }

    @Test func bareCommandWithoutInstruction() {
        let p = ImageLayerInfo.parse(command: "—")
        #expect(p.instruction == nil)
        #expect(p.body == "—")
        #expect(p.comment == nil)
    }

    @Test func instructionAloneWithComment() {
        let p = ImageLayerInfo.parse(command: "RUN # buildkit")
        #expect(p.instruction == "RUN")
        #expect(p.body == "")
        #expect(p.comment == "# buildkit")
    }

    @Test func singleWordIsBodyNotInstruction() {
        // A lone uppercase word with nothing else is left as the body — there
        // is nothing to visually separate it from.
        let p = ImageLayerInfo.parse(command: "RUN")
        #expect(p.instruction == nil)
        #expect(p.body == "RUN")
    }

    @Test func composesWithCleanLayerCommand() {
        // End-to-end through the fixture path: the `/bin/sh -c #(nop)` strip
        // runs first, then the parts split.
        let img = Fixtures.image(layers: [
            Fixtures.LayerSpec(createdBy: "/bin/sh -c #(nop)  ENV LANG=C.UTF-8"),
        ])
        let parts = img.variantInfos.first?.layers.first?.commandParts
        #expect(parts?.instruction == "ENV")
        #expect(parts?.body == "LANG=C.UTF-8")
        #expect(parts?.comment == nil)
    }
}

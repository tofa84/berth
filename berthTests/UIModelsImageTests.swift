//
//  UIModelsImageTests.swift
//  berthTests
//
//  Pure `ImageResource` accessors from UIModels.swift — reference parsing, digest
//  shortening, platform de-duplication, and layer-command cleanup.
//

import Testing
@testable import berth

struct UIModelsImageTests {

    @Test func repositoryAndTagWithTag() {
        let img = Fixtures.image(name: "docker.io/library/alpine:latest")
        #expect(img.repository == "docker.io/library/alpine")
        #expect(img.tag == "latest")
    }

    @Test func tagIsNoneForDigestReference() {
        let img = Fixtures.image(name: "docker.io/library/alpine@sha256:abc123")
        #expect(img.repository == "docker.io/library/alpine")
        #expect(img.tag == "<none>")
    }

    @Test func hostPortColonIsNotATag() {
        let img = Fixtures.image(name: "localhost:5000/foo")
        #expect(img.repository == "localhost:5000/foo")
        #expect(img.tag == "latest")
    }

    @Test func bareNameDefaultsToLatest() {
        let img = Fixtures.image(name: "alpine")
        #expect(img.repository == "alpine")
        #expect(img.tag == "latest")
    }

    @Test func shortAndFullDigest() {
        let d = "sha256:deadbeefcafebabe1234567890abcdef"
        let img = Fixtures.image(variants: [Fixtures.VariantSpec(digest: d)])
        #expect(img.fullDigest == d)
        #expect(img.shortDigest == "deadbeefcafe")   // "sha256:" stripped, first 12
    }

    @Test func platformsTextDropsUnknownAndDedupes() {
        let img = Fixtures.image(variants: [
            Fixtures.VariantSpec(os: "linux", arch: "arm64", variant: "v8"),
            Fixtures.VariantSpec(os: "linux", arch: "arm64", variant: "v7"),   // same os/arch → deduped
            Fixtures.VariantSpec(os: "unknown", arch: "unknown", variant: nil),
        ])
        #expect(img.platformsText == "linux/arm64")
    }

    @Test func totalSizeAndMultiArch() {
        let img = Fixtures.image(variants: [
            Fixtures.VariantSpec(arch: "arm64", size: 100),
            Fixtures.VariantSpec(arch: "amd64", size: 250),
        ])
        #expect(img.totalSize == 350)
        #expect(img.isMultiArch == true)
    }

    @Test func cleanLayerCommandStripsShellPrefix() {
        let img = Fixtures.image(layers: [
            Fixtures.LayerSpec(createdBy: "/bin/sh -c #(nop)  CMD [\"nginx\"]"),
        ])
        let command = img.variantInfos.first?.layers.first?.command
        #expect(command == "CMD [\"nginx\"]")
    }
}

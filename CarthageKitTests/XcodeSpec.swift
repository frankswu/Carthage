//
//  XcodeSpec.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-11.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import LlamaKit
import Nimble
import Quick
import ReactiveCocoa

class XcodeSpec: QuickSpec {
	override func spec() {
		let directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("ReactiveCocoaLayout", withExtension: nil)!
		let workspaceURL = directoryURL.URLByAppendingPathComponent("ReactiveCocoaLayout.xcworkspace")
		let buildFolderURL = directoryURL.URLByAppendingPathComponent(CarthageBinariesFolderName)

		let stdoutHandle = NSFileHandle.fileHandleWithStandardOutput()
		let stdoutSink = SinkOf<NSData> { data in
			stdoutHandle.writeData(data)
		}

		beforeEach {
			NSFileManager.defaultManager().removeItemAtURL(buildFolderURL, error: nil)
			return ()
		}

		it("should build for all platforms") {
			let dependencies = [
				ProjectIdentifier.GitHub(GitHubRepository(owner: "github", name: "Archimedes")),
				ProjectIdentifier.GitHub(GitHubRepository(owner: "ReactiveCocoa", name: "ReactiveCocoa")),
			]

			for project in dependencies {
				let (outputSignal, schemeSignals) = buildDependencyProject(project, directoryURL, withConfiguration: "Debug")
				let outputDisposable = outputSignal.observe(stdoutSink)

				let result = schemeSignals
					.concat(identity)
					.on(disposed: {
						outputDisposable.dispose()
					})
					.wait()

				expect(result.error()).to(beNil())
			}

			let (outputSignal, schemeSignals) = buildInDirectory(directoryURL, withConfiguration: "Debug")
			let outputDisposable = outputSignal.observe(stdoutSink)

			let result = schemeSignals
				.concat(identity)
				.wait()

			expect(result.error()).to(beNil())

			// Verify that the build products exist at the top level.
			var projectNames = dependencies.map { project in project.name }
			projectNames.append("ReactiveCocoaLayout")

			for dependency in projectNames {
				let macPath = buildFolderURL.URLByAppendingPathComponent("Mac/\(dependency).framework").path!
				let iOSPath = buildFolderURL.URLByAppendingPathComponent("iOS/\(dependency).framework").path!

				var isDirectory: ObjCBool = false
				expect(NSFileManager.defaultManager().fileExistsAtPath(macPath, isDirectory: &isDirectory)).to(beTruthy())
				expect(isDirectory).to(beTruthy())

				expect(NSFileManager.defaultManager().fileExistsAtPath(iOSPath, isDirectory: &isDirectory)).to(beTruthy())
				expect(isDirectory).to(beTruthy())
			}

			// Verify that the iOS framework is a universal binary for device
			// and simulator.
			let output = launchTask(TaskDescription(launchPath: "/usr/bin/otool", arguments: [ "-fv", buildFolderURL.URLByAppendingPathComponent("iOS/ReactiveCocoaLayout.framework/ReactiveCocoaLayout").path! ]))
				.map { NSString(data: $0, encoding: NSStringEncoding(NSUTF8StringEncoding))! }
				.first()
				.value()!

			expect(output).to(contain("architecture i386"))
			expect(output).to(contain("architecture armv7"))
			expect(output).to(contain("architecture arm64"))
		}

		it("should locate the workspace") {
			let result = locateProjectsInDirectory(directoryURL).first()
			expect(result.error()).to(beNil())

			let locator = result.value()!
			expect(locator).to(equal(ProjectLocator.Workspace(workspaceURL)))
		}

		it("should locate the project from the parent directory") {
			let result = locateProjectsInDirectory(directoryURL.URLByDeletingLastPathComponent!).first()
			expect(result.error()).to(beNil())

			let locator = result.value()!
			expect(locator).to(equal(ProjectLocator.Workspace(workspaceURL)))
		}

		it("should not locate the project from a directory not containing it") {
			let result = locateProjectsInDirectory(directoryURL.URLByAppendingPathComponent("ReactiveCocoaLayout")).first()
			expect(result.value()).to(beNil())
		}
	}
}

//
//  JITCompiler.swift
//  Compiler
//
//  Created by James Froggatt on 04.08.2017.
//  Copyright © 2017 James Froggatt. All rights reserved.
//

import Foundation
import LLVM

public class JITCompiler {
	public let module: Module
	public init(for module: Module) {
		self.module = module
	}
	
	private func makeJIT() throws -> JIT {
		return try JIT(module: module, machine: try TargetMachine())
	}
	
	@discardableResult public func runMain() throws -> IRValue {
		return try runFunction(named: "main")
	}
	@discardableResult public func runFunction(named name: String, params: () = ()) throws -> IRValue {
		return try makeJIT().runFunction(module.function(named: "main")!, args: [])
	}
	
	public func produceVoidFunction(named name: String) throws -> () -> () {
		typealias FunctionPointer = @convention(c) () -> ()
		let functionAddress = try makeJIT().addressOfFunction(name: name)
		let function = unsafeBitCast(functionAddress, to: FunctionPointer.self)
		return function
	}
}

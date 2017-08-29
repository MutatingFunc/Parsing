//
//  PrefixMatchables.swift
//  Parsing
//
//  Created by James Froggatt on 11.08.2017.
//  Copyright © 2017 James Froggatt. All rights reserved.
//

import Foundation

public protocol PrefixMatchable {
	func matchPrefix(_ str: Substring) -> String.Index?
}
public extension PrefixMatchable {
	func parse(from str: inout Substring) -> Substring? {
		guard let matchEnd = self.matchPrefix(str) else {return nil}
		assert((str.startIndex ... str.endIndex).contains(matchEnd))
		defer {
			let original = str
			str = str.suffix(from: matchEnd)
			assert(original[str.startIndex ..< str.endIndex] == str) //Substring should still point to original String
		}
		return str[..<matchEnd]
	}
	var parser: Parser<Substring> {return Parser(self.parse)}
	var ignore: Parser<()> {return self.parser => {_ in ()}}
}
public protocol ManyPrefixMatchable: PrefixMatchable {
	func matchManyPrefix(_ str: Substring) -> String.Index?
}

extension String {
	func matchPrefix(_ str: Substring, regEx: Bool, caseSensitive: Bool) -> String.Index? {
		var options: String.CompareOptions = [.anchored]
		if regEx {options.insert(.regularExpression)}
		if !caseSensitive {options.insert(.caseInsensitive)}
		guard let range = str.range(of: self, options: options) else {return nil}
		assert(range.lowerBound.encodedOffset == 0, "bug where Substring.range result begins at 0, not .startIndex appears to be fixed")
		//assert(range.lowerBound == str.startIndex, "anchored search should only match prefix)
		return str.index(str.startIndex, offsetBy: range.upperBound.encodedOffset)
	}
}
extension String: PrefixMatchable {
	public func matchPrefix(_ str: Substring) -> String.Index? {
		return matchPrefix(str, regEx: false, caseSensitive: true)
	}
}
public struct CaseInsensitiveString: PrefixMatchable {
	public var string: String
	public func matchPrefix(_ str: Substring) -> String.Index? {
		return string.matchPrefix(str, regEx: false, caseSensitive: false)
	}
}

public struct RegEx: PrefixMatchable {
	public var string: String
	public func matchPrefix(_ str: Substring) -> String.Index? {
		return string.matchPrefix(str, regEx: true, caseSensitive: true)
	}
}
extension String {
	public var regEx: RegEx {return RegEx(string: self)}
}
public struct CaseInsensitiveRegEx: PrefixMatchable {
	public var string: String
	public func matchPrefix(_ str: Substring) -> String.Index? {
		return string.matchPrefix(str, regEx: true, caseSensitive: false)
	}
}

prefix operator ~
public prefix func ~(str: String) -> CaseInsensitiveString {return .init(string: str)}
public prefix func ~(regEx: RegEx) -> CaseInsensitiveRegEx {return .init(string: regEx.string)}


public struct MatchableCharSet: ManyPrefixMatchable {
	public var chars: CharacterSet
	public func matchPrefix(_ str: Substring) -> String.Index? {
		let str = str.unicodeScalars.prefix(1)
		if let matchIndex = str.index(where: chars.contains) {
			assert(matchIndex == str.startIndex, "only compares with 1 unicodeScalar")
			return str.index(after: str.startIndex)
		}
		return nil
	}
	public func matchManyPrefix(_ str: Substring) -> String.Index? {
		let str = str.unicodeScalars
		let matchEnd = str.index(where: chars.inverted.contains) ?? str.endIndex
		if matchEnd == str.startIndex {return nil}
		return matchEnd
	}
}
prefix operator /
public prefix func /(chars: CharacterSet) -> MatchableCharSet {return .init(chars: chars)}
prefix operator ¬/
public prefix func ¬/(chars: CharacterSet) -> MatchableCharSet {return .init(chars: chars.inverted)}
prefix operator ¬
public prefix func ¬(prefix: MatchableCharSet) -> MatchableCharSet {return .init(chars: prefix.chars.inverted)}


public struct MatchOptional: PrefixMatchable {
	var prefix: PrefixMatchable
	public func matchPrefix(_ str: Substring) -> String.Index? {
		return prefix.matchPrefix(str) ?? str.startIndex
	}
	public func matchManyPrefix(_ str: Substring) -> String.Index? {
		return self.matchPrefix(str)
	}
}
public postfix func .?(prefix: PrefixMatchable) -> MatchOptional {return MatchOptional(prefix: prefix)}

public struct MatchMany: ManyPrefixMatchable {
	var prefix: PrefixMatchable
	public func matchPrefix(_ str: Substring) -> String.Index? {
		if let prefix = prefix as? ManyPrefixMatchable {
			return prefix.matchManyPrefix(str)
		}
		var endIndex: String.Index?
		while let matchEnd = prefix.matchPrefix(str) {endIndex = matchEnd}
		return endIndex
	}
	public func matchManyPrefix(_ str: Substring) -> String.Index? {
		return self.matchPrefix(str)
	}
}
public postfix func +(prefix: PrefixMatchable) -> MatchMany {return MatchMany(prefix: prefix)}

public postfix func *(prefix: PrefixMatchable) -> MatchOptional {return MatchOptional(prefix: MatchMany(prefix: prefix))}

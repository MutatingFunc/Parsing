//
//  PrefixMatchables.swift
//  Parsing
//
//  Created by James Froggatt on 11.08.2017.
//  Copyright © 2017 James Froggatt. All rights reserved.
//

import Foundation

public protocol PrefixMatchable: CustomStringConvertible {
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

public struct MatchableString: PrefixMatchable {
	public var literal: String, caseSensitive: Bool
	public func matchPrefix(_ str: Substring) -> String.Index? {
		var options: String.CompareOptions = [.anchored]
		if !caseSensitive {options.insert(.caseInsensitive)}
		guard let range = str.range(of: literal, options: options) else {return nil}
		assert(range.lowerBound.encodedOffset == 0, "bug where Substring.range result begins at 0, not .startIndex appears to be fixed")
		//assert(range.lowerBound == str.startIndex, "anchored search should only match prefix)
		return str.index(str.startIndex, offsetBy: range.upperBound.encodedOffset)
	}
	public var description: String {
		return (caseSensitive ? "^" : "~^") + "\"\(literal.description)\""
	}
}
prefix operator ^
public prefix func ^(str: String) -> MatchableString {return MatchableString(literal: str, caseSensitive: true)}
prefix operator ~^
public prefix func ~^(str: String) -> MatchableString {return MatchableString(literal: str, caseSensitive: false)}


public struct RegEx: PrefixMatchable {
	public var regEx: String, caseSensitive: Bool
	public func matchPrefix(_ str: Substring) -> String.Index? {
		var options: String.CompareOptions = [.anchored, .regularExpression]
		if !caseSensitive {options.insert(.caseInsensitive)}
		guard let range = str.range(of: regEx, options: options) else {return nil}
		assert(range.lowerBound.encodedOffset == 0, "bug where Substring.range result begins at 0, not .startIndex appears to be fixed")
		//assert(range.lowerBound == str.startIndex, "anchored search should only match prefix)
		return str.index(str.startIndex, offsetBy: range.upperBound.encodedOffset)
	}
	public var description: String {
		return (caseSensitive ? "/" : "~/") + "\"\(regEx)\""
	}
}
prefix operator /
public prefix func /(str: String) -> RegEx {return RegEx(regEx: str, caseSensitive: true)}
prefix operator ~/
public prefix func ~/(str: String) -> RegEx {return RegEx(regEx: str, caseSensitive: false)}


public struct MatchableChars: ManyPrefixMatchable {
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
	public var description: String {
		return "/\"\(chars.description)\""
	}
}
public prefix func /(chars: CharacterSet) -> MatchableChars {return MatchableChars(chars: chars)}
prefix operator ¬/
public prefix func ¬/(chars: CharacterSet) -> MatchableChars {return MatchableChars(chars: chars.inverted)}
prefix operator ¬
public prefix func ¬(prefix: MatchableChars) -> MatchableChars {return MatchableChars(chars: prefix.chars.inverted)}


public struct MatchOptional: PrefixMatchable {
	var prefix: PrefixMatchable
	public func matchPrefix(_ str: Substring) -> String.Index? {
		if let prefix = prefix as? MatchOptional {
			return prefix.matchPrefix(str)
		}
		if let matchEnd = prefix.matchPrefix(str) {
			return matchEnd
		}
		return str.startIndex
	}
	public func matchManyPrefix(_ str: Substring) -> String.Index? {
		return self.matchPrefix(str)
	}
	public var description: String {
		return "(" + prefix.description + ")+"
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
	public var description: String {
		return "(" + prefix.description + ")+"
	}
}
public postfix func +(prefix: PrefixMatchable) -> MatchMany {return MatchMany(prefix: prefix)}

public postfix func *(prefix: PrefixMatchable) -> MatchOptional {return MatchOptional(prefix: MatchMany(prefix: prefix))}

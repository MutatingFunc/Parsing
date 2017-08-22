//
//  PrefixMatchables.swift
//  Parsing
//
//  Created by James Froggatt on 11.08.2017.
//  Copyright © 2017 James Froggatt. All rights reserved.
//

import Foundation

public protocol PrefixMatchable: CustomStringConvertible {
	var matchMany: Bool {get mutating set}
	func matchPrefix(_ str: Substring) -> Range<String.Index>?
}
public extension PrefixMatchable {
	func take(from str: Substring) -> (matched: Substring, rest: Substring)? {
		guard let match = self.matchPrefix(str) else {return nil}
		assert(match.lowerBound == str.startIndex)
		return (matched: str[match], rest: str[match.upperBound...])
	}
}

public struct MatchableString: PrefixMatchable {
	public var literal: String, caseSensitive: Bool, matchMany: Bool
	public func matchPrefix(_ str: Substring) -> Range<String.Index>? {
		var options: String.CompareOptions = [.anchored]
		if !caseSensitive {options.insert(.caseInsensitive)}
		let range = str.range(of: literal, options: options)
		assert(range.map{$0.lowerBound.encodedOffset == 0} ?? true, "fix for Substring.range result beginning at 0, not .startIndex is no longer needed")
		return range.map{str.startIndex ..< str.index(str.startIndex, offsetBy: $0.upperBound.encodedOffset)}
	}
	public var description: String {
		return "~^" + literal.description
	}
}
prefix operator ^
public prefix func ^(str: String) -> MatchableString {return MatchableString(literal: str, caseSensitive: true, matchMany: false)}
prefix operator ~^
public prefix func ~^(str: String) -> MatchableString {return MatchableString(literal: str, caseSensitive: false, matchMany: false)}


public struct RegEx: PrefixMatchable {
	public var regEx: String, caseSensitive: Bool, matchMany: Bool
	public func matchPrefix(_ str: Substring) -> Range<String.Index>? {
		var options: String.CompareOptions = [.anchored, .regularExpression]
		if !caseSensitive {options.insert(.caseInsensitive)}
		let range = str.range(of: regEx, options: options)
		assert(range.map{$0.lowerBound.encodedOffset == 0} ?? true, "fix for Substring.range result beginning at 0, not .startIndex is no longer needed")
		return range.map{str.startIndex ..< str.index(str.startIndex, offsetBy: $0.upperBound.encodedOffset)}
	}
	public var description: String {
		return (caseSensitive ? "/" : "~/") + "\"" + regEx + "\""
	}
}
prefix operator /
public prefix func /(str: String) -> RegEx {return RegEx(regEx: str, caseSensitive: true, matchMany: false)}
prefix operator ~/
public prefix func ~/(str: String) -> RegEx {return RegEx(regEx: str, caseSensitive: false, matchMany: false)}


public struct MatchableChars: PrefixMatchable {
	public var chars: CharacterSet, matchMany: Bool
	public func matchPrefix(_ str: Substring) -> Range<String.Index>? {
		let str = matchMany ? str.unicodeScalars : str.prefix(1).unicodeScalars
		let range = str.startIndex ..< (str.index(where: chars.inverted.contains) ?? str.endIndex)
		return range.isEmpty ? nil : range
	}
	public var description: String {
		return chars.description
	}
}
public prefix func /(chars: CharacterSet) -> MatchableChars {return MatchableChars(chars: chars, matchMany: false)}
prefix operator ¬/
public prefix func ¬/(chars: CharacterSet) -> MatchableChars {return MatchableChars(chars: chars.inverted, matchMany: false)}
prefix operator ¬
public prefix func ¬(prefix: MatchableChars) -> MatchableChars {return MatchableChars(chars: prefix.chars.inverted, matchMany: false)}
public postfix func +(prefix: MatchableChars) -> PrefixMatchable {
	var prefix = prefix
	prefix.matchMany = true
	return prefix
}

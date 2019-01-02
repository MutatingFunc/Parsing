//
//  Parser.swift
//  Kaleidoscope
//
//  Created by James Froggatt on 08.08.2017.
//  Copyright © 2017 James Froggatt. All rights reserved.
//

private var whitespaceParser: Parser<()>? = nil
private func skipWhitespace(_ str: inout Substring) {whitespaceParser?.parse(&str)}
public struct Parser<Token> {
	public var parse: (inout Substring) -> Token?
	public init(_ parse: @escaping (inout Substring) -> Token?) {
		self.parse = parse
	}
	public func skippingLeadingWhitespace() -> Parser {
		return Parser {substr in
			skipWhitespace(&substr)
			return self.parse(&substr)
		}
	}
	public func skippingTrailingWhitespace() -> Parser {
		return Parser {substr in
			defer {skipWhitespace(&substr)}
			return self.parse(&substr)
		}
	}
	
	public func withWhitespaceOverride(_ whitespace: Parser<()>?) -> Parser {
		return Parser {substr in
			let oldValue = whitespaceParser
			whitespaceParser = whitespace
			defer {whitespaceParser = oldValue}
			return self.parse(&substr)
		}
	}
	
	public func tryParse(_ str: String) throws -> Token {
		let startTime = CFAbsoluteTimeGetCurrent()
		defer {print("\n\nTime to parse: \(CFAbsoluteTimeGetCurrent() - startTime)\n\n")}
		
		var rest = Substring(str)
		if let result = self.parse(&rest) {
			return result
		}
		
		assert((str.startIndex ... str.endIndex).contains(rest.startIndex), "resulting substring should not begin past end of file")
		assert(str[rest.startIndex ..< rest.endIndex] == rest, "substring should still correspond to the original string")
		var lineNum = 1, linePos = 0
		for (charIndex, char) in zip(str.indices, str) {
			if charIndex == rest.startIndex {
				let error = ParserError.failed(rest: rest, line: lineNum, position: linePos)
				print("Error: " + error.localizedDescription)
				throw error
			}
			if char == "\n" {
				lineNum += 1
				linePos = 0
			} else {
				linePos += 1
			}
		}
		preconditionFailure("Unreachable if above assertion is true")
	}
}

public enum ParserError: LocalizedError {
	case failed(rest: Substring, line: Int, position: Int)
	public var localizedDescription: String {
		switch self {
		case let .failed(rest, line, index): return "Line \(line) position \(index)\n\nRemaining input:\n\(rest)"
		}
	}
}

precedencegroup ParsingPrecedence {
	lowerThan: DefaultPrecedence, LogicalDisjunctionPrecedence
	higherThan: TernaryPrecedence, WhitespacePrecedence
}
infix operator =>: ParsingPrecedence
public func =><Token>(prefix: PrefixMatchable, token: @escaping (Substring) -> Token) -> Parser<Token> {
	return Parser(prefix.parse) => token
}
public func =><Token>(prefix: PrefixMatchable, token: Token) -> Parser<Token> {
	return Parser {substr in
		prefix.parse(from: &substr) != nil ? token : nil
	}
}
public func =><Token, AST>(parser: Parser<Token>, transform: @escaping (Token) -> AST) -> Parser<AST> {
	return Parser {substr in
		parser.parse(&substr).map(transform)
	}
}

precedencegroup WhitespacePrecedence {}
infix operator ~~: WhitespacePrecedence
public func ~~<Token>(parser: Parser<Token>, whitespace: Parser<()>) -> Parser<Token> {
	return parser.withWhitespaceOverride(whitespace)
}

prefix operator ..
public prefix func ..<Token>(parser: Parser<Token>) -> Parser<Token> {
	return parser.skippingLeadingWhitespace()
}
postfix operator ..
public postfix func ..<Token>(parser: Parser<Token>) -> Parser<Token> {
	return parser.skippingTrailingWhitespace()
}
infix operator -: AdditionPrecedence
public func -<TokenA, TokenB>(lhs: Parser<TokenA>, rhs: Parser<TokenB>) -> Parser<(TokenA, TokenB)> {
	return Parser {substr in
		if let token1 = lhs.parse(&substr), let token2 = rhs.parse(&substr) {
			return (token1, token2)
		}
		return nil
	}
}

infix operator --: AdditionPrecedence
public func --<TokenA, TokenB>(lhs: Parser<TokenA>, rhs: Parser<TokenB>) -> Parser<(TokenA, TokenB)> {
	return lhs.. - rhs
}

prefix operator |
public prefix func |<Matchable: PrefixMatchable>(_ tokens: [Matchable]) -> Parser<Matchable> {
	return Parser {substr in
		let original = substr
		for token in tokens {
			if token.parse(from: &substr) != nil {return token}
			substr = original
		}
		return nil
	}
}
public func |<Token>(lhs: Parser<Token>, rhs: Parser<Token>) -> Parser<Token> {
	return Parser {substr in
		let original = substr
		if let token = lhs.parse(&substr) {return token}
		substr = original
		if let token = rhs.parse(&substr) {return token}
		substr = original
		return nil
	}
}

postfix operator .?
public postfix func .?<Token>(parser: Parser<Token>) -> Parser<Token?> {
	return Parser {substr in
		let original = substr
		if let token = parser.parse(&substr) {return Optional(token)}
		substr = original
		return Optional(nil)
	}
}

postfix operator +
public postfix func +<Token>(parser: Parser<Token>) -> Parser<[Token]> {
	return Parser {substr in
		guard let first = parser.parse(&substr) else {return nil}
		var tokens = [first]
		var rest = substr
		while let nextToken = parser.parse(&substr) {
			tokens.append(nextToken)
			rest = substr
		}
		substr = rest
		return tokens
	}
}
postfix operator ..+
public postfix func ..+<Token>(parser: Parser<Token>) -> Parser<[Token]> {
	return (parser..)+
}

postfix operator *
public postfix func *<Token>(parser: Parser<Token>) -> Parser<[Token]> {
	return Parser {substr in
		var tokens: [Token] = []
		var rest = substr
		while let nextToken = parser.parse(&substr) {
			tokens.append(nextToken)
			rest = substr
		}
		substr = rest
		return tokens
	}
}
postfix operator ..*
public postfix func ..*<Token>(parser: Parser<Token>) -> Parser<[Token]> {
	return (parser..)*
}

//allows for closure recursion
public func recursive<Token>(_ makeThis: (Parser<Token>) -> Parser<Token>) -> Parser<Token> {
	var this: Parser<Token>!
	this = makeThis(Parser {str in this.parse(&str)})
	return this
}
/*
let intParser = RegEx(string: "[0-9]") => {(str: Substring) in Double(str)!}
let opParser = "-" => ()
let exprParser: Parser<Double> = recursive {this in
	(intParser -- opParser -- this => {a, op, b in a - b})
		| intParser
}

var str = "5-2" as Substring
exprParser.parse(&str)
str
*/


//required due to lack of variadics

public func -<TokenA, TokenB, TokenZ>(lhs: Parser<(TokenA, TokenB)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenZ)> {
	return lhs - rhs => {($0.0.0, $0.0.1, $0.1)}
}
public func -<TokenA, TokenB, TokenC, TokenZ>(lhs: Parser<((TokenA, TokenB), TokenC)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenZ)> {
	return lhs - rhs => {($0.0.0.0, $0.0.0.1, $0.0.1, $0.1)}
}
public func -<TokenA, TokenB, TokenC, TokenD, TokenZ>(lhs: Parser<(((TokenA, TokenB), TokenC), TokenD)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenD, TokenZ)> {
	return lhs - rhs => {($0.0.0.0.0, $0.0.0.0.1, $0.0.0.1, $0.0.1, $0.1)}
}
public func -<TokenA, TokenB, TokenC, TokenD, TokenE, TokenZ>(lhs: Parser<((((TokenA, TokenB), TokenC), TokenD), TokenE)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenD, TokenE, TokenZ)> {
	return lhs - rhs => {($0.0.0.0.0.0, $0.0.0.0.0.1, $0.0.0.0.1, $0.0.0.1, $0.0.1, $0.1)}
}
public func -<TokenA, TokenB, TokenC, TokenD, TokenE, TokenF, TokenZ>(lhs: Parser<(((((TokenA, TokenB), TokenC), TokenD), TokenE), TokenF)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenD, TokenE, TokenF, TokenZ)> {
	return lhs - rhs => {($0.0.0.0.0.0.0, $0.0.0.0.0.0.1, $0.0.0.0.0.1, $0.0.0.0.1, $0.0.0.1, $0.0.1, $0.1)}
}
public func -<TokenA, TokenB, TokenC, TokenD, TokenE, TokenF, TokenG, TokenZ>(lhs: Parser<((((((TokenA, TokenB), TokenC), TokenD), TokenE), TokenF), TokenG)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenD, TokenE, TokenF, TokenG, TokenZ)> {
	return lhs - rhs => {($0.0.0.0.0.0.0.0, $0.0.0.0.0.0.0.1, $0.0.0.0.0.0.1, $0.0.0.0.0.1, $0.0.0.0.1, $0.0.0.1, $0.0.1, $0.1)}
}

public func --<TokenA, TokenB, TokenZ>(lhs: Parser<(TokenA, TokenB)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenZ)> {
	return lhs -- rhs => {($0.0.0, $0.0.1, $0.1)}
}
public func --<TokenA, TokenB, TokenC, TokenZ>(lhs: Parser<((TokenA, TokenB), TokenC)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenZ)> {
	return lhs -- rhs => {($0.0.0.0, $0.0.0.1, $0.0.1, $0.1)}
}
public func --<TokenA, TokenB, TokenC, TokenD, TokenZ>(lhs: Parser<(((TokenA, TokenB), TokenC), TokenD)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenD, TokenZ)> {
	return lhs -- rhs => {($0.0.0.0.0, $0.0.0.0.1, $0.0.0.1, $0.0.1, $0.1)}
}
public func --<TokenA, TokenB, TokenC, TokenD, TokenE, TokenZ>(lhs: Parser<((((TokenA, TokenB), TokenC), TokenD), TokenE)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenD, TokenE, TokenZ)> {
	return lhs -- rhs => {($0.0.0.0.0.0, $0.0.0.0.0.1, $0.0.0.0.1, $0.0.0.1, $0.0.1, $0.1)}
}
public func --<TokenA, TokenB, TokenC, TokenD, TokenE, TokenF, TokenZ>(lhs: Parser<(((((TokenA, TokenB), TokenC), TokenD), TokenE), TokenF)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenD, TokenE, TokenF, TokenZ)> {
	return lhs -- rhs => {($0.0.0.0.0.0.0, $0.0.0.0.0.0.1, $0.0.0.0.0.1, $0.0.0.0.1, $0.0.0.1, $0.0.1, $0.1)}
}
public func --<TokenA, TokenB, TokenC, TokenD, TokenE, TokenF, TokenG, TokenZ>(lhs: Parser<((((((TokenA, TokenB), TokenC), TokenD), TokenE), TokenF), TokenG)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenD, TokenE, TokenF, TokenG, TokenZ)> {
	return lhs -- rhs => {($0.0.0.0.0.0.0.0, $0.0.0.0.0.0.0.1, $0.0.0.0.0.0.1, $0.0.0.0.0.1, $0.0.0.0.1, $0.0.0.1, $0.0.1, $0.1)}
}

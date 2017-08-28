//
//  Parser.swift
//  Kaleidoscope
//
//  Created by James Froggatt on 08.08.2017.
//  Copyright © 2017 James Froggatt. All rights reserved.
//

private var whitespaceParser: Parser<()>? = nil
public struct Parser<Token> {
	public var parse: (inout Substring) -> Token?
	public init(_ parse: @escaping (inout Substring) -> Token?) {
		self.parse = parse
	}
	public func skippingWhitespace() -> Parser {
		return Parser {substr in
			while whitespaceParser?.parse(&substr) != nil {}
			return self.parse(&substr)
		}
	}
	
	public func withWhitespace(_ whitespace: Parser<()>?) -> Parser {
		return Parser {substr in
			let oldValue = whitespaceParser
			whitespaceParser = whitespace
			defer {whitespaceParser = oldValue}
			return self.parse(&substr)
		}
	}
	
	public func parseToEnd(_ file: String) throws -> Token {
		let startTime = CFAbsoluteTimeGetCurrent()
		defer {print("\n\nTime to parse: \(CFAbsoluteTimeGetCurrent() - startTime)\n\n")}
		
		let parser = self → (/"$").parser ~> {ast, _ in ast}
		var rest = Substring(file)
		if let result = parser.parse(&rest) {
			return result
		}
		
		for (lineNum, line) in zip(1..., file.split(separator: "\n")) {
			for (linePos, charIndex) in zip(0..., line.characters.indices) {
				if charIndex == rest.startIndex {
					throw ParserError.failed(rest: rest, line: lineNum, position: linePos)
				}
			}
		}
		throw ParserError.failed(rest: rest, line: 1, position: 0)
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
	lowerThan: AdditionPrecedence
	higherThan: WhitespacePrecedence
}
infix operator ~>: ParsingPrecedence
public func ~><Token>(prefix: PrefixMatchable, token: @escaping (Substring) -> Token) -> Parser<Token> {
	return prefix.parser ~> token
}
public func ~><Token>(prefix: PrefixMatchable, token: Token) -> Parser<Token> {
	return Parser {substr in
		prefix.parse(from: &substr) != nil ? token : nil
	}
}
public func ~><Token, AST>(parser: Parser<Token>, transform: @escaping (Token) -> AST) -> Parser<AST> {
	return Parser {substr in
		parser.parse(&substr).map(transform)
	}
}

precedencegroup WhitespacePrecedence {}
infix operator --: WhitespacePrecedence
public func --<Token>(parser: Parser<Token>, whitespace: Parser<()>) -> Parser<Token> {
	return parser.withWhitespace(whitespace)
}

prefix operator -
public prefix func -<Token>(parser: Parser<Token>) -> Parser<Token> {
	return parser.skippingWhitespace()
}
infix operator →: AdditionPrecedence
public func →<TokenA, TokenB>(lhs: Parser<TokenA>, rhs: Parser<TokenB>) -> Parser<(TokenA, TokenB)> {
	return Parser {substr in
		if let token1 = lhs.parse(&substr), let token2 = rhs.parse(&substr) {
			return (token1, token2)
		}
		return nil
	}
}

infix operator -→: AdditionPrecedence
public func -→<TokenA, TokenB>(lhs: Parser<TokenA>, rhs: Parser<TokenB>) -> Parser<(TokenA, TokenB)> {
	return lhs → -rhs
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
postfix operator -+
public postfix func -+<Token>(parser: Parser<Token>) -> Parser<[Token]> {
	return Parser {substr in
		guard let first = parser.parse(&substr) else {return nil}
		var tokens = [first]
		var rest = substr
		let parser = parser.skippingWhitespace()
		while let nextToken = parser.parse(&substr) {
			tokens.append(nextToken)
			rest = substr
		}
		substr = rest
		return tokens
	}
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
postfix operator -*
public postfix func -*<Token>(parser: Parser<Token>) -> Parser<[Token]> {
	return Parser {substr in
		var tokens: [Token] = []
		var rest = substr
		if let first = parser.parse(&substr) {
			tokens.append(first)
			rest = substr
			let parser = parser.skippingWhitespace()
			while let nextToken = parser.parse(&substr) {
				tokens.append(nextToken)
				rest = substr
			}
		}
		substr = rest
		return tokens
	}
}


//required due to lack of variadics

public func →<TokenA, TokenB, TokenZ>(lhs: Parser<(TokenA, TokenB)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenZ)> {
	return lhs → rhs ~> {($0.0.0, $0.0.1, $0.1)}
}
public func →<TokenA, TokenB, TokenC, TokenZ>(lhs: Parser<((TokenA, TokenB), TokenC)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenZ)> {
	return lhs → rhs ~> {($0.0.0.0, $0.0.0.1, $0.0.1, $0.1)}
}
public func →<TokenA, TokenB, TokenC, TokenD, TokenZ>(lhs: Parser<(((TokenA, TokenB), TokenC), TokenD)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenD, TokenZ)> {
	return lhs → rhs ~> {($0.0.0.0.0, $0.0.0.0.1, $0.0.0.1, $0.0.1, $0.1)}
}
public func →<TokenA, TokenB, TokenC, TokenD, TokenE, TokenZ>(lhs: Parser<((((TokenA, TokenB), TokenC), TokenD), TokenE)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenD, TokenE, TokenZ)> {
	return lhs → rhs ~> {($0.0.0.0.0.0, $0.0.0.0.0.1, $0.0.0.0.1, $0.0.0.1, $0.0.1, $0.1)}
}

public func -→<TokenA, TokenB, TokenZ>(lhs: Parser<(TokenA, TokenB)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenZ)> {
	return lhs -→ rhs ~> {($0.0.0, $0.0.1, $0.1)}
}
public func -→<TokenA, TokenB, TokenC, TokenZ>(lhs: Parser<((TokenA, TokenB), TokenC)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenZ)> {
	return lhs -→ rhs ~> {($0.0.0.0, $0.0.0.1, $0.0.1, $0.1)}
}
public func -→<TokenA, TokenB, TokenC, TokenD, TokenZ>(lhs: Parser<(((TokenA, TokenB), TokenC), TokenD)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenD, TokenZ)> {
	return lhs -→ rhs ~> {($0.0.0.0.0, $0.0.0.0.1, $0.0.0.1, $0.0.1, $0.1)}
}
public func -→<TokenA, TokenB, TokenC, TokenD, TokenE, TokenZ>(lhs: Parser<((((TokenA, TokenB), TokenC), TokenD), TokenE)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenD, TokenE, TokenZ)> {
	return lhs -→ rhs ~> {($0.0.0.0.0.0, $0.0.0.0.0.1, $0.0.0.0.1, $0.0.0.1, $0.0.1, $0.1)}
}

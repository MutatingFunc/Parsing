//
//  Parser.swift
//  Kaleidoscope
//
//  Created by James Froggatt on 08.08.2017.
//  Copyright © 2017 James Froggatt. All rights reserved.
//

private var whitespaceParser: Parser<()>? = nil
public struct Parser<Token> {
	public var prefix: [PrefixMatchable], ws: [PrefixMatchable], parse: (Substring) -> ParserResult<Token>
	public init(prefix: [PrefixMatchable], ws: [PrefixMatchable], parse: @escaping (Substring) -> ParserResult<Token>) {
		self.prefix = prefix; self.ws = ws; self.parse = parse
	}
	public static func applyingIgnoreRules(prefix: [PrefixMatchable], ws: [PrefixMatchable], parse: @escaping (Substring) -> ParserResult<Token>) -> Parser {
		return Parser(prefix: prefix, ws: ws) {
			var substr = $0
			while case .parsed(_, let rest)? = whitespaceParser?.parse(substr) {substr = rest}
			return parse(substr)
		}
	}
	public static func applyingIgnoreRules(_ parser: Parser) -> Parser {
		return Parser.applyingIgnoreRules(prefix: parser.prefix, ws: parser.ws, parse: parser.parse)
	}
	
	public func ignoring(prefix parser: Parser<()>?) -> Parser {
		let parser = parser?.ignoring(prefix: nil)
		return Parser(prefix: self.prefix, ws: parser?.prefix ?? []) {[parse] in
			let oldValue = whitespaceParser
			whitespaceParser = parser
			defer {whitespaceParser = oldValue}
			return parse($0)
		}
	}
	public func map<Result>(_ transform: @escaping (Token) -> Result) -> Parser<Result> {
		let parse = self.parse
		return .init(prefix: self.prefix, ws: self.ws, parse: {parse($0).map(transform)})
	}
	
	public func parseToEnd(_ file: String) throws -> Token {
		let startTime = CFAbsoluteTimeGetCurrent()
		defer {print("\n\nTime to parse: \(CFAbsoluteTimeGetCurrent() - startTime)\n\n")}
		let parser = self → (/"$" ~> ())
		switch parser.parse(Substring(file)) {
		case .parsed((let token, _), _): return token
		case .failed(let rest):
			var line = 1, position: Int = 0
			if file.startIndex != rest.startIndex {
				let indexIterator = sequence(first: file.startIndex) {prev in
					let next = file.index(after: prev)
					return next == rest.startIndex ? nil : next
				}
				for index in indexIterator {
					if file[index] == "\n" {line += 1; position = 0}
					else {position += 1}
				}
			}
			let error = ParserError.failed(expected: parser.prefix, ws: parser.ws, got: rest, line: line, position: position)
			print("Error: " + error.localizedDescription)
			throw error
		}
	}
}
public enum ParserResult<Token> {
	case parsed(Token, rest: Substring)
	case failed(got: Substring)
	
	public func map<Result>(_ transform: (Token) -> Result) -> ParserResult<Result> {
		switch self {
		case .parsed(let token, let rest): return .parsed(transform(token), rest: rest)
		case .failed(let rest): return .failed(got: rest)
		}
	}
}

public enum ParserError: LocalizedError {
	case failed(expected: [PrefixMatchable], ws: [PrefixMatchable], got: Substring, line: Int, position: Int)
	public var localizedDescription: String {
		switch self {
		case let .failed(matchables, whitespace, rest, line, index):
			let wsMessage = whitespace.isEmpty ? "With no whitespace permitted" : "Or any whitespace: \(whitespace)"
			return "Line \(line) position \(index)\n\nTop level expects one of: \(matchables),\n\(wsMessage)\n\nRemaining input:\n\(rest)"
		}
	}
}

precedencegroup ParsingPrecedence {
	lowerThan: AdditionPrecedence
	higherThan: WhitespacePrecedence
}
postfix operator ~>
public postfix func ~>(prefix: PrefixMatchable) -> Parser<Substring> {
	return Parser(prefix: [prefix], ws: []) {
		guard let (matched, rest) = prefix.take(from: $0) else {return .failed(got: $0)}
		return .parsed(matched, rest: rest)
	}
}
infix operator ~>: ParsingPrecedence
public func ~><Token>(prefix: PrefixMatchable, token: @escaping (Substring) -> Token) -> Parser<Token> {
	return Parser(prefix: [prefix], ws: []) {
		guard let (matched, rest) = prefix.take(from: $0) else {return .failed(got: $0)}
		return .parsed(token(matched), rest: rest)
	}
}
public func ~><Token>(prefix: PrefixMatchable, token: Token) -> Parser<Token> {
	return Parser(prefix: [prefix], ws: []) {
		guard let (_, rest) = prefix.take(from: $0) else {return .failed(got: $0)}
		return .parsed(token, rest: rest)
	}
}
public func ~><Token, AST>(parser: Parser<Token>, transform: @escaping (Token) -> AST) -> Parser<AST> {
	return parser.map(transform)
}

precedencegroup WhitespacePrecedence {}
infix operator --: WhitespacePrecedence
public func --<Token>(parser: Parser<Token>, whitespace: Parser<()>) -> Parser<Token> {
	return parser.ignoring(prefix: whitespace)
}

prefix operator -
public prefix func -<Token>(parser: Parser<Token>) -> Parser<Token> {
	return Parser.applyingIgnoreRules(parser)
}
infix operator →: AdditionPrecedence
public func →(lhs: Parser<()>, rhs: PrefixMatchable) -> Parser<()> {
	return lhs → (rhs ~> ()) ~> {_ in ()}
}
public func →<TokenA, TokenB>(lhs: Parser<TokenA>, rhs: Parser<TokenB>) -> Parser<(TokenA, TokenB)> {
	return Parser(prefix: lhs.prefix, ws: lhs.ws) {
		switch lhs.parse($0) {
		case .failed(let rest): return .failed(got: rest)
		case .parsed(let token1, let substr):
			switch rhs.parse(substr) {
			case .failed(let rest): return .failed(got: rest)
			case .parsed(let token2, let rest): return .parsed((token1, token2), rest: rest)
			}
		}
	}
}
public func →<TokenA, TokenB>(lhs: @escaping () -> Parser<TokenA>, rhs: Parser<TokenB>) -> Parser<(TokenA, TokenB)> {
	return Parser(prefix: [], ws: []) {(lhs() → rhs).parse($0)} //can't get prefix without resolving
}
public func →<TokenA, TokenB>(lhs: Parser<TokenA>, rhs: @escaping () -> Parser<TokenB>) -> Parser<(TokenA, TokenB)> {
	return Parser(prefix: lhs.prefix, ws: lhs.ws) {(lhs → rhs()).parse($0)}
}
public func →<TokenA, TokenB>(lhs: @escaping () -> Parser<TokenA>, rhs: @escaping () -> Parser<TokenB>) -> Parser<(TokenA, TokenB)> {
	return Parser(prefix: [], ws: []) {(lhs() → rhs()).parse($0)}
}

infix operator -→: AdditionPrecedence
public func -→<TokenA, TokenB>(lhs: Parser<TokenA>, rhs: Parser<TokenB>) -> Parser<(TokenA, TokenB)> {
	return lhs → -rhs
}
public func -→<TokenA, TokenB>(lhs: @escaping () -> Parser<TokenA>, rhs: Parser<TokenB>) -> Parser<(TokenA, TokenB)> {
	return Parser(prefix: [], ws: []) {(lhs() -→ rhs).parse($0)} //can't get prefix without resolving
}
public func -→<TokenA, TokenB>(lhs: Parser<TokenA>, rhs: @escaping () -> Parser<TokenB>) -> Parser<(TokenA, TokenB)> {
	return Parser(prefix: lhs.prefix, ws: lhs.ws) {(lhs -→ rhs()).parse($0)}
}
public func -→<TokenA, TokenB>(lhs: @escaping () -> Parser<TokenA>, rhs: @escaping () -> Parser<TokenB>) -> Parser<(TokenA, TokenB)> {
	return Parser(prefix: [], ws: []) {(lhs() -→ rhs()).parse($0)} //can't get prefix without resolving
}

public func |<Token>(lhs: Parser<Token>, rhs: Parser<Token>) -> Parser<Token> {
	return Parser(prefix: lhs.prefix + rhs.prefix, ws: lhs.ws + rhs.ws) {
		switch lhs.parse($0) {
		case .parsed(let token1, let rest): return .parsed(token1, rest: rest)
		case .failed(_):
			switch rhs.parse($0) {
			case .parsed(let token2, let rest): return .parsed(token2, rest: rest)
			case .failed(let rest): return .failed(got: rest)
			}
		}
	}
}

postfix operator .?
public postfix func .?<Token>(parser: Parser<Token>) -> Parser<Token?> {
	return Parser(prefix: parser.prefix, ws: parser.ws) {
		if case let .parsed(token, rest) = parser.parse($0) {return .parsed(token, rest: rest)}
		else {return .parsed(nil, rest: $0)}
	}
}
postfix operator *
public postfix func *<Token>(parser: Parser<Token>) -> Parser<[Token]> {
	return Parser(prefix: parser.prefix, ws: parser.ws) {
		var str = $0, tokens: [Token] = []
		while case let .parsed(token, rest) = parser.parse(str) {
			str = rest
			tokens.append(token)
		}
		return .parsed(tokens, rest: str)
	}
}
postfix operator -*
public postfix func -*<Token>(parser: Parser<Token>) -> Parser<[Token]> {
	return Parser(prefix: parser.prefix, ws: parser.ws) {
		var str = $0, tokens: [Token] = []
		while case let .parsed(token, rest) = parser.parse(str) {
			str = rest
			tokens.append(token)
			while case .parsed(_, let rest)? = whitespaceParser?.parse(str) {str = rest}
		}
		return .parsed(tokens, rest: str)
	}
}

postfix operator +
public postfix func +<Token>(parser: Parser<Token>) -> Parser<[Token]> {
	return parser → parser* ~> {first, rest in [first] + rest}
}
postfix operator -+
public postfix func -+<Token>(parser: Parser<Token>) -> Parser<[Token]> {
	return parser -→ parser-* ~> {first, rest in [first] + rest}
}


//required due to lack of variadics

public func →<TokenA, TokenB, TokenZ>(lhs: Parser<(TokenA, TokenB)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenZ)> {
	return lhs → rhs ~> {($0.0.0, $0.0.1, $0.1)}
}
public func →<TokenA, TokenB, TokenZ>(lhs: Parser<(TokenA, TokenB)>, rhs: @escaping () -> Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenZ)> {
	return lhs → rhs ~> {($0.0.0, $0.0.1, $0.1)}
}
public func →<TokenA, TokenB, TokenC, TokenZ>(lhs: Parser<((TokenA, TokenB), TokenC)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenZ)> {
	return lhs → rhs ~> {($0.0.0.0, $0.0.0.1, $0.0.1, $0.1)}
}
public func →<TokenA, TokenB, TokenC, TokenZ>(lhs: Parser<((TokenA, TokenB), TokenC)>, rhs: @escaping () -> Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenZ)> {
	return lhs → rhs ~> {($0.0.0.0, $0.0.0.1, $0.0.1, $0.1)}
}
public func →<TokenA, TokenB, TokenC, TokenD, TokenZ>(lhs: Parser<(((TokenA, TokenB), TokenC), TokenD)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenD, TokenZ)> {
	return lhs → rhs ~> {($0.0.0.0.0, $0.0.0.0.1, $0.0.0.1, $0.0.1, $0.1)}
}
public func →<TokenA, TokenB, TokenC, TokenD, TokenZ>(lhs: Parser<(((TokenA, TokenB), TokenC), TokenD)>, rhs: @escaping () -> Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenD, TokenZ)> {
	return lhs → rhs ~> {($0.0.0.0.0, $0.0.0.0.1, $0.0.0.1, $0.0.1, $0.1)}
}
public func →<TokenA, TokenB, TokenC, TokenD, TokenE, TokenZ>(lhs: Parser<((((TokenA, TokenB), TokenC), TokenD), TokenE)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenD, TokenE, TokenZ)> {
	return lhs → rhs ~> {($0.0.0.0.0.0, $0.0.0.0.0.1, $0.0.0.0.1, $0.0.0.1, $0.0.1, $0.1)}
}
public func →<TokenA, TokenB, TokenC, TokenD, TokenE, TokenZ>(lhs: Parser<((((TokenA, TokenB), TokenC), TokenD), TokenE)>, rhs: @escaping () -> Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenD, TokenE, TokenZ)> {
	return lhs → rhs ~> {($0.0.0.0.0.0, $0.0.0.0.0.1, $0.0.0.0.1, $0.0.0.1, $0.0.1, $0.1)}
}

public func -→<TokenA, TokenB, TokenZ>(lhs: Parser<(TokenA, TokenB)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenZ)> {
	return lhs -→ rhs ~> {($0.0.0, $0.0.1, $0.1)}
}
public func -→<TokenA, TokenB, TokenZ>(lhs: Parser<(TokenA, TokenB)>, rhs: @escaping () -> Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenZ)> {
	return lhs -→ rhs ~> {($0.0.0, $0.0.1, $0.1)}
}
public func -→<TokenA, TokenB, TokenC, TokenZ>(lhs: Parser<((TokenA, TokenB), TokenC)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenZ)> {
	return lhs -→ rhs ~> {($0.0.0.0, $0.0.0.1, $0.0.1, $0.1)}
}
public func -→<TokenA, TokenB, TokenC, TokenZ>(lhs: Parser<((TokenA, TokenB), TokenC)>, rhs: @escaping () -> Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenZ)> {
	return lhs -→ rhs ~> {($0.0.0.0, $0.0.0.1, $0.0.1, $0.1)}
}
public func -→<TokenA, TokenB, TokenC, TokenD, TokenZ>(lhs: Parser<(((TokenA, TokenB), TokenC), TokenD)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenD, TokenZ)> {
	return lhs -→ rhs ~> {($0.0.0.0.0, $0.0.0.0.1, $0.0.0.1, $0.0.1, $0.1)}
}
public func -→<TokenA, TokenB, TokenC, TokenD, TokenZ>(lhs: Parser<(((TokenA, TokenB), TokenC), TokenD)>, rhs: @escaping () -> Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenD, TokenZ)> {
	return lhs -→ rhs ~> {($0.0.0.0.0, $0.0.0.0.1, $0.0.0.1, $0.0.1, $0.1)}
}
public func -→<TokenA, TokenB, TokenC, TokenD, TokenE, TokenZ>(lhs: Parser<((((TokenA, TokenB), TokenC), TokenD), TokenE)>, rhs: Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenD, TokenE, TokenZ)> {
	return lhs -→ rhs ~> {($0.0.0.0.0.0, $0.0.0.0.0.1, $0.0.0.0.1, $0.0.0.1, $0.0.1, $0.1)}
}
public func -→<TokenA, TokenB, TokenC, TokenD, TokenE, TokenZ>(lhs: Parser<((((TokenA, TokenB), TokenC), TokenD), TokenE)>, rhs: @escaping () -> Parser<TokenZ>) -> Parser<(TokenA, TokenB, TokenC, TokenD, TokenE, TokenZ)> {
	return lhs -→ rhs ~> {($0.0.0.0.0.0, $0.0.0.0.0.1, $0.0.0.0.1, $0.0.0.1, $0.0.1, $0.1)}
}

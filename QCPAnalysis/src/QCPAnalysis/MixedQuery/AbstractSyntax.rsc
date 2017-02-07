module QCPAnalysis::MixedQuery::AbstractSyntax

public data Literal = string(str strVal)
				    | number(str numVal)
				    | hex(str hexVal)
				    | bit(str bitVal)
				    | boolean(str boolVal)
				    | null(str nullVal)
				    | literalHole();


public data Identifier = identifier(str identifierVal)
					   | identifierHole();
					   
public data SelectExpr = columnName(Identifier id)
					   | wildCard();

public data Expr = orExpr(Expr left, Expr right)
				 | xorExpr(Expr left, Expr right)
				 | andExpr(Expr left, Expr right)
				 | notExpr(Expr negated)
				 | booleanExprWithExpected(BooleanPrimary boolean, str expected)
				 | booleanExpr(BooleanPrimary boolean);

public data BooleanPrimary = nullTest(BooleanPrimary boolean, str mode)
						   | spaceShip(BooleanPrimary left, Predicate right)
						   | comparison(BooleanPrimary left, str operator, Predicate right)
						   | comparisonWithSubQuery(BooleanPrimary left, str operator, str mode, SubQuery subquery)
						   | predicate(Predicate pred);
						   
public data Predicate = predSubQuery(BitExpr left, str mode, SubQuery subquery)
					  | predExprList(BitExpr left, str mode, list[Expr] exprs)
					  | predBetween(BitExpr left, str mode, BitExpr lowerBounds, Predicate upperBounds)
					  | predSoundsLike(BitExpr left, BitExpr right)
					  | predLike(BitExpr left, str mode, SimpleExpr right, OptionalEscape escape)
					  | predRegex(BitExpr left, str mode, BitExpr right)
					  | bitExpr(BitExpr expr);

public data OptionalEscape = escapeExpr(SimpleExpr escape)
						   | noEscape();

public data BitExpr = bitOr(BitExpr left, BitExpr right)
			   | bitAnd(BitExpr left, BitExpr right)
			   | bitXor(BitExpr left, BitExpr right)
			   | bitShiftLeft(BitExpr left, BitExpr	right)
			   | bitShiftRight(BitExpr left, BitExpr right)
			   | addition(BitExpr left, BitExpr right)
			   | subtraction(BitExpr left, BitExpr right)
			   | multiplication(BitExpr left, BitExpr right)
			   | division(BitExpr left, BitExpr right)
			   | intDivision(BitExpr left, BitExpr right)
			   | modulo(BitExpr left, BitExpr right)
			   | simple(SimpleExpr expr);

		 			
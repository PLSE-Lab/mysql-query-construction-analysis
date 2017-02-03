module QCPAnalysis::MixedQuery::AbstractSyntax

public data Literal = string(str strVal)
				    | number(str numVal)
				    | hex(str hexVal)
				    | bit(str bitVal)
				    | boolean(str boolVal)
				    | null(str nullVal);


public data Identifier = identifier(str identifierVal);


		 			
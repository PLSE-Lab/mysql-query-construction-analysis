module QCPAnalysis::MixedQuery::ConcreteSyntax

extend lang::std::Layout;


syntax Name = name: [a-zA-Z0-9_.]+
			  | hole: "Ø";
			  
syntax Param = param: [a-zA-Z0-9_.]+
			  | hole: "Ø";

start syntax Query
	= selectQuery: "SELECT" Name From Join Where Boolean;

syntax From
	= from: "FROM" Name;
	
syntax Join
	= inner: "INNER JOIN" Name "ON" Name "=" Name
	| left: "LEFT JOIN" Name "ON" Name "=" Name
	| right: "RIGHT JOIN" Name "ON" Name "=" Name
	| full: "FULL JOIN" Name "ON" Name "=" Name
	> noJoin : "";


syntax Where
	= where: "WHERE" Name "=" Param
	> noWhere: "";

syntax Boolean
	= and: "AND" Name "=" Param Boolean
	| or: "OR" Name "=" Param Boolean
	| not: "NOT" Name "=" Param Boolean
	> noBoolean: "";


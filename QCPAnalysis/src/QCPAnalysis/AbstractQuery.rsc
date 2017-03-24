module QCPAnalysis::AbstractQuery

import lang::php::ast::AbstractSyntax;

import QCPAnalysis::ParseSQL::AbstractSyntax;

/*
 * QCP1: a) param to mysql_query is a literal string
 * 		 b) param to mysql_query is a variable containing a literal string
 * QCP2  a) param to mysql_query is built using cascading .= assignments
 * QCP3: a) param to mysql_query is a variable that can take on multiple possible literal queries distributed
 		    over control flow
 		 b) param to mysql query is a variable that can take on multiple possible QCP4 queries distributed over
 		    control flow
 * QCP4: a) param to mysql_query is a concatenation of literals and php variables, function calls, etc.
 		 b) param to mysql_query is an encapsed string made up of literals and php variables, function calls, etc.
 		 c) param to mysql_query is a variable containing 1) or 2)
 * QCP5: param to mysql_query comes from a function, method, or static method parameter
 */
 

public data Query = QCP1a(loc callloc, str sql, SQLQuery parsed)
				  | QCP1b(loc callloc, str sql, SQLQuery parsed)
				  | QCP2(loc callloc, str mixedQuery, SQLQuery parsed)
				  | QCP3a(loc callloc, list[str] staticqueries)
				  | QCP3b(loc callloc, rel[str, SQLQuery] mixedAndParsed)
				  | QCP4a(loc callloc, str mixedQuery, SQLQuery parsed)
				  | QCP4b(loc callloc, str mixedQuery, SQLQuery parsed)
				  | QCP4c(loc callloc, str mixedQuery, SQLQuery parsed)
				  | QCP5(loc callloc, str functionOrMethodName, list[Query] paramQueries)
				  | unclassified(loc callloc, int errorCode);
				  // ERROR CODES:
				  // 0: no patterns matched the query (normal case for unclassified query)
				  // 1: classification failed due to there not being enough actual parameters
				  // 2: classification failed due to infinite recursion in QCP5 classification

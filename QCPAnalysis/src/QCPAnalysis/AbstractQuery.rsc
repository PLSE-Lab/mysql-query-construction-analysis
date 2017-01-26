module QCPAnalysis::AbstractQuery

import lang::php::ast::AbstractSyntax;

/*
 * QCP1: a) param to mysql_query is a literal string
 * 		 b) param to mysql_query is a variable containing a literal string
 * QCP2: param to mysql_query is built using cascading .= assignments
 * QCP3: a) param to mysql_query is a variable that can take on multiple possible literal queries distributed
 		    over control flow
 		 b) param to mysql query is a variable that can take on multiple possible QCP4 queries distributed over
 		    control flow
 * QCP4: a) param to mysql_query is a concatenation of literals and php variables, function calls, etc.
 		 b) param to mysql_query is an encapsed string made up of literals and php variables, function calls, etc.
 		 c) param to mysql_query is a variable containing 1) or 2)
 * QCP5: param to mysql_query comes from a function, method, or static method parameter
 */
 
// TODO: modify QCP2 and QCP4 to have a list of Expr corresponding to the dynamic holes in the query
public data Query = QCP1a(loc callloc, str sql)
				  | QCP1b(loc callloc, str sql)
				  | QCP2(loc callloc, str mixedQuery)
				  | QCP3a(loc callloc, list[str] staticqueries)
				  | QCP3b(loc callloc, list[str] mixedqueries)
				  | QCP4a(loc callloc, str mixedQuery)
				  | QCP4b(loc callloc, str mixedQuery)
				  | QCP4c(loc callloc, str mixedQuery)
				  | QCP5(loc callloc, loc paramTo)
				  | unclassified(loc callloc);
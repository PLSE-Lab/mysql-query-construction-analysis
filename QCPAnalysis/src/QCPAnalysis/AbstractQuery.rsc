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
 
public data Query = QCP1a(loc callloc, str sql)
				  | QCP1b(loc callloc, str sql)
				  | QCP2(loc callloc, list[QuerySnippet] assignments)
				  | QCP3a(loc callloc, list[str] staticqueries)
				  | QCP3b(loc callloc, list[list[QuerySnippet]] queries)
				  | QCP4a(loc callloc, list[QuerySnippet] parts)
				  | QCP4b(loc callloc, list[QuerySnippet] parts)
				  | QCP4c(loc callloc, list[QuerySnippet] parts)
				  | QCP5(loc callloc, loc paramTo)
				  | unclassified(loc callloc);

public data QuerySnippet = staticsnippet(str sql)
					  | dynamicParams(DynamicParams params) // dynamic snippet used as a parameter
					  | dynamicName(DynamicName name) // dynamic snippet provides database, table, or column name
					  | dynamicsnippet(Expr expr); // truly dynamic, i.e. query structure depends on a variable


// DynamicParams and DynamicName are just placeholders for something better in the future					
public data DynamicParams = whereParam(str attribute, Expr equals)
						 | andParam(str attribute, Expr equals)
						 | orParam(str attribute, Expr equals)
						 | notParam(str attribute, Expr equals)
						 | setParam(rel[str, Expr] pairs)
						 | valuesParam(list[Expr] values);
						 
public data DynamicName = databaseName(Expr name)
						| tableName(Expr name)
						| columnName(Expr name);
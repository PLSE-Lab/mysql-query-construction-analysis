module QCPAnalysis::AbstractQuery

import lang::php::ast::AbstractSyntax;

/*
 * QCP1: param to mysql_query is a literal string or a variable containing a literal string
 * QCP2: param to mysql_query is built using cascading .= assignments
 * QCP3: param to mysql_query is a variable that can can take on multiple possible queries 
 * 		 distributed over control flow
 * QCP4: 1) param to mysql_query is a concatenation of literals and php variables, function calls, etc.
 		 2) param to mysql_query is an encapsed string made up of literals and php variables, function calls, etc.
 		 3) param to mysql_query is a variable containing 1) or 2)
 * QCP5: param to mysql_query comes from a function, method, or static method parameter
 */
public data Query = QCP1(loc callloc, str sql)
				  | QCP2(loc callloc, list[QuerySnippet] assignments)
				  | QCP3(loc callloc, set[Query] queries)
				  | QCP4(loc callloc, list[QuerySnippet] parts)
				  | QCP5(loc callloc, loc paramTo)
				  | unclassified(loc callloc);

public data QuerySnippet = staticsnippet(str sql)
					  | dynamicParams(DynamicParams params)
					  | dynamicName(DynamicName name)
					  | dynamicsnippet(Expr expr); // truly dynamic, i.e. query structure depends on a variable

						
public data DynamicParams = whereParam(str attribute, Expr equals)
						 | andParam(str attribute, Expr equals)
						 | orParam(str attribute, Expr equals)
						 | notParam(str attribute, Expr equals)
						 | setParam(rel[str, Expr] pairs)
						 | valuesParam(list[Expr] values);
						 
public data DynamicName = databaseName(str name)
						| tableName(str name)
						| columnName(str name);
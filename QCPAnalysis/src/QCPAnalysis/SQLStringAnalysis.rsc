/*
 * The purpose of this module is to analyze all mysql_query calls in the system
 * and figure out which parts of the SQL String are static and which come from
 * dynamic sources.
 * After initial creation of SQLString data structures for each call, each dynamic
 * Snippet will be analyzed in the CFGs and pattern flags will be set for that SQLString
 * structure based on defined query construction patterns
 *
 * Pattern classification:
 *
 * allstatic: mysql_query parameter is static SQL with no functions, variables, etc.
 * 
 */
 
 // TODO: add pattern recognizers
 // TODO: add code that will reference the CFGs for each dynamicsnippet
 // TODO: Add flags that indicate whether a particular pattern occurred in the building of a SQLString
module QCPAnalysis::SQLStringAnalysis

import QCPAnalysis::QCPCorpus;
import QCPAnalysis::QueryGroups;

import lang::php::util::Corpus;
import lang::php::ast::AbstractSyntax;

import List;
import Map;
import IO;

loc cfgloc = |project://QCPAnalysis/cfgs/binary|;

// represents a SQL string (parameter to a mysql_query call)
data SQLString = sqlstring(loc callloc, list[SQLSnippet] snippets, bool allstatic);

// represents a part of a SQL string (parameter to a mysql_query call)
data SQLSnippet = staticsnippet(str staticpart)
				| dynamicsnippet(Expr dynamicpart);

public list[SQLString] buildSQLStrings() = [s | call <- getMSQCorpusList(), s := buildSQLString(call)];
			
// build SQL strings based on cases from Rucareanu thesis. At this point, the only analysis that has been performed
// is looking at the parameter directly. All dynamic snippets will be further analyzed through the CFGs
public SQLString buildSQLString(c:call(name(name("mysql_query")), params)){
	switch(params){
		case [actualParameter(scalar(string(s)), _)]: return sqlstring(c@at, [staticsnippet(s)], true);
		case [actualParameter(scalar(string(s)), _), _]: return sqlstring(c@at, [staticsnippet(s)], true);
		case [actualParameter(e:scalar(encapsed(_)),_)]: return sqlstring(c@at, buildQG2Snippets(e), false);
		case [actualParameter(e:scalar(encapsed(_)), _),_]: return sqlstring(c@at, buildQG2Snippets(e), false);
		case [actualParameter(e:binaryOperation(left,right,concat()),_)]: return sqlstring(c@at, buildQG2Snippets(e), false);
		case [actualParameter(e:binaryOperation(left,right,concat()),_), _]: return sqlstring(c@at, buildQG2Snippets(e), false);
		case [actualParameter(v:var(name(name(_))), _)] : return sqlstring(c@at, [dynamicsnippet(v)], false);
		case [actualParameter(v:var(name(name(_))), _), _] : return sqlstring(c@at, [dynamicsnippet(v)], false);
		case [actualParameter(v:fetchArrayDim(var(name(name(_))),_),_)] : return sqlstring(c@at, [dynamicsnippet(v)], false);
		case [actualParameter(v:fetchArrayDim(var(name(name(_))),_),_),_] : return sqlstring(c@at, [dynamicsnippet(v)], false);
		default: throw "unhandled case";
	}
}

// returns snippets for the more complicated case of static sql concatenated with php variables, functions, etc.
private list[SQLSnippet] buildQG2Snippets(Expr e){
	if(scalar(string(s)) := e) return [staticsnippet(s)];
	else if(scalar(encapsed(parts)) := e) return buildQG2Snippets(parts);
	else if(binaryOperation(left, right, concat()) := e) return buildQG2Snippets(left) + buildQG2Snippets(right);
	else return [dynamicsnippet(e)];
}
private list[SQLSnippet] buildQG2Snippets(list[Expr] parts){
	snippets = [];
	for(p <- parts){
		snippets += buildQG2Snippets(p);
	}
	return snippets;
}

// analyzes all dynamicsnippets by referencing the CFGs
public void analyzeDynamicSnippets(){
	// to be implemented
}
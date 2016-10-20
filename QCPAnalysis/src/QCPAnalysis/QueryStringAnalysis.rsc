/*
 * The purpose of this module is to analyze all mysql_query calls in the system
 * and figure out which parts of the Query String are static and which come from
 * dynamic sources.
 * After initial creation of QueryString data structures for each call, each dynamic
 * Snippet will be analyzed in the CFGs and pattern flags will be set for that QueryString
 * structure based on defined query construction patterns
 */
 
 // TODO: add pattern recognizers
 // TODO: add code that will reference the CFGs for each dynamicsnippet
 // TODO: Add flags that indicate whether a particular pattern occurred in the building of a QueryString
module QCPAnalysis::QueryStringAnalysis

import QCPAnalysis::QCPCorpus;
import QCPAnalysis::QueryGroups;

import lang::php::util::Corpus;
import lang::php::util::Utils;
import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::analysis::NamePaths;
import lang::php::analysis::cfg::BuildCFG;
import lang::php::analysis::cfg::CFG;
import lang::php::analysis::cfg::Util;

import Set;
import Map;
import IO;
import ValueIO;

loc cfglocb = |project://QCPAnalysis/cfgs/binary|;
loc cfglocp = |project://QCPAnalysis/cfgs/plain|;

// See the Wiki of this GitHub Repository for more detailed information on pattern classifications
 
// represents a Query string (parameter to a mysql_query call)
data QueryString = querystring(loc callloc, list[QuerySnippet] snippets, int querygroup, int querypattern);

// represents a part of a SQL query
data QuerySnippet = staticsnippet(str staticpart)
				| dynamicsnippet(Expr dynamicpart);
				
// builds query string structures for all mysql_query calls in the corpus
public set[QueryString] buildQueryStrings() = {s | call <- getMSQCorpusList(), s := buildQueryString(call)};

// builds a QueryString based on the Query Groups. At this point, the only analysis that has been performed
// is looking at the parameter directly. All dynamic snippets will be further analyzed through the CFGs
public QueryString buildQueryString(c:call(name(name("mysql_query")), params)){
	switch(params){
		case [actualParameter(scalar(string(s)), _)]: return querystring(c@at, [staticsnippet(s)], 1, 1);
		case [actualParameter(scalar(string(s)), _), _]: return querystring(c@at, [staticsnippet(s)], 1, 1);
		case [actualParameter(e:scalar(encapsed(_)),_)]: return querystring(c@at, buildQG2Snippets(e), 2, 0);
		case [actualParameter(e:scalar(encapsed(_)), _),_]: return querystring(c@at, buildQG2Snippets(e), 2, 0);
		case [actualParameter(e:binaryOperation(left,right,concat()),_)]: return querystring(c@at, buildQG2Snippets(e), 2, 0);
		case [actualParameter(e:binaryOperation(left,right,concat()),_), _]: return querystring(c@at, buildQG2Snippets(e), 2, 0);
		case [actualParameter(v:var(name(name(_))), _)] : return querystring(c@at, [dynamicsnippet(v)], 3, 0);
		case [actualParameter(v:var(name(name(_))), _), _] : return querystring(c@at, [dynamicsnippet(v)], 3, 0);
		case [actualParameter(v:fetchArrayDim(var(name(name(_))),_),_)] : return querystring(c@at, [dynamicsnippet(v)], 4, 0);
		case [actualParameter(v:fetchArrayDim(var(name(name(_))),_),_),_] : return querystring(c@at, [dynamicsnippet(v)], 4, 0);
		default: throw "unhandled case";
	}
}

// returns snippets for the more complicated case of static sql concatenated with php variables, functions, etc.
private list[QuerySnippet] buildQG2Snippets(Expr e){
	if(scalar(string(s)) := e) return [staticsnippet(s)];
	else if(scalar(encapsed(parts)) := e) return buildQG2Snippets(parts);
	else if(binaryOperation(left, right, concat()) := e) return buildQG2Snippets(left) + buildQG2Snippets(right);
	else return [dynamicsnippet(e)];
}
private list[QuerySnippet] buildQG2Snippets(list[Expr] parts){
	snippets = [];
	for(p <- parts){
		snippets += buildQG2Snippets(p);
	}
	return snippets;
}

public void writeCFGsAndQueryStrings(){
	Corpus corpus = getCorpus();
	for(p <- corpus, v := corpus[p]){
		int id = 0;
		pt = loadBinary(p,v);
		for(l <- pt.files, scr := pt.files[l]){
			querystrings = {q | /c:call(name(name("mysql_query")),_) := scr, q := buildQueryString(c)};
			if(size(querystrings) != 0){
				cfgs = buildCFGs(scr);
				map[CFG, set[QueryString]] cfgsAndQueryStrings = (cfg : {} | np <- cfgs, cfg := cfgs[np]);
				for(qs <- querystrings){
					cfgsAndQueryStrings[findContainingCFG(scr, cfgs, qs.callloc)] += qs;
				}
				iprintToFile(cfglocp + "/<p>_<v>/<id>", cfgsAndQueryStrings);
				writeBinaryValueFile(cfglocb + "<p>_<v>/<id>", cfgsAndQueryStrings);
				id += 1;
			}
		}
	}
}


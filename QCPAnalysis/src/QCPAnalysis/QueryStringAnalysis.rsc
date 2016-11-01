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
import lang::php::analysis::includes::IncludesInfo;
import lang::php::analysis::evaluators::Simplify;
import lang::php::analysis::includes::QuickResolve;

import Set;
import Map;
import IO;
import ValueIO;
import List;

loc cfglocb = |project://QCPAnalysis/cfgs/binary|;
loc cfglocp = |project://QCPAnalysis/cfgs/plain|;

// See the Wiki of this GitHub Repository for more detailed information on pattern classifications
 
// represents a Query string (parameter to a mysql_query call)
data QueryString = querystring(loc callloc, list[QuerySnippet] snippets, PatternFlags flags);

// represents a part of a SQL query
data QuerySnippet = staticsnippet(str staticpart)
				| dynamicsnippet(Expr dynamicpart);

// collection of boolean flags for each construction pattern
data PatternFlags = flags(bool unclassified, bool qcp1, bool qcp2, bool qcp3, bool qcp4, bool qcp5);
		
// builds query string structures for all mysql_query calls in the corpus
public set[QueryString] buildQueryStrings() = {s | call <- getMSQCorpusList(), s := buildQueryString(call)};

// builds a QueryString based on the Query Groups. At this point, the only analysis that has been performed
// is looking at the parameter directly. All dynamic snippets will be further analyzed through the CFGs
public QueryString buildQueryString(c:call(name(name("mysql_query")), params)){
	switch(params){
		case [actualParameter(scalar(string(s)), _)]: return querystring(c@at, [staticsnippet(s)], flags(false, true, false, false, false, false));
		case [actualParameter(scalar(string(s)), _), _]: return querystring(c@at, [staticsnippet(s)], flags(false, true, false, false, false, false));
		case [actualParameter(e:scalar(encapsed(_)),_)]: return querystring(c@at, buildQG2Snippets(e),flags(true, false, false, false, false, false));
		case [actualParameter(e:scalar(encapsed(_)), _),_]: return querystring(c@at, buildQG2Snippets(e), flags(true, false, false, false, false, false));
		case [actualParameter(e:binaryOperation(left,right,concat()),_)]: return querystring(c@at, buildQG2Snippets(e), flags(true, false, false, false, false, false));
		case [actualParameter(e:binaryOperation(left,right,concat()),_), _]: return querystring(c@at, buildQG2Snippets(e), flags(true, false, false, false, false, false));
		case [actualParameter(v:var(name(name(_))), _)] : return querystring(c@at, [dynamicsnippet(v)], flags(true, false, false, false, false, false));
		case [actualParameter(v:var(name(name(_))), _), _] : return querystring(c@at, [dynamicsnippet(v)], flags(true, false, false, false, false, false));
		case [actualParameter(v:fetchArrayDim(var(name(name(_))),_),_)] : return querystring(c@at, [dynamicsnippet(v)], flags(true, false, false, false, false, false));
		case [actualParameter(v:fetchArrayDim(var(name(name(_))),_),_),_] : return querystring(c@at, [dynamicsnippet(v)], flags(true, false, false, false, false, false));
		default: throw "unhandled case";
	}
}

@doc{Run the simplifier on the parameters being passed to this function}
private Expr simplifyParams(Expr c:call(NameOrExpr funName, list[ActualParameter] parameters), loc baseLoc, IncludesInfo iinfo) {
	list[ActualParameter] simplifiedParameters = [];
	for (p:actualParameter(Expr expr, bool byRef) <- parameters) {
		simplifiedParameters += p[expr=simplifyExpr(replaceConstants(expr,iinfo), baseLoc)];
	}
	return c[parameters=simplifiedParameters];
}

@doc{Build query string structures for all mysql_query calls in the corpus, simplifying the parameters to each call before building each structure}
public set[QueryString] buildAndSimplifyQueryStrings() {
	Corpus corpus = getCorpus();
	set[QueryString] res = { };

	for (p <- corpus, v := corpus[p]){
		pt = loadBinary(p,v);
		if (!(pt has baseLoc)) {
			println("WARNING: Cannot simplify system <p> at version <v>, rep has no base location");
			res = res + { buildQueryString(c) | /c:call(name(name("mysql_query")),_) := pt };
		} else {
			IncludesInfo iinfo = loadIncludesInfo(p, v);
			res = res + { buildQueryString(simplifyParams(c, pt.baseLoc, iinfo)) | /c:call(name(name("mysql_query")),_) := pt };
		}
	}

	return res;	
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

// builds and classifies all query strings based on the Query Construction Patterns in the wiki
public set[QueryString] buildAndClassifyQueryStrings(){
	Corpus corpus = getCorpus();
	set[QueryString] corpusres = {};
	for(p <- corpus, v := corpus[p]){
		pt = loadBinary(p,v);
		if (!pt has baseLoc) {
			println("Skipping system <p>, version <v>, no base loc included");
			continue;
		}
		IncludesInfo iinfo = loadIncludesInfo(p, v);
		callsOfInterest = [ c | /c:call(name(name("mysql_query")),[actualParameter(var(name(name(_))),false),_*]) := pt ];
		println("Calls in system <p>, version <v> (total = <size(callsOfInterest)>):");
		neededCFGs = ( l : buildCFGs(pt.files[l], buildBasicBlocks=false) | l <- { c@at.top | c <- callsOfInterest } );
		set[QueryString] sysres = {};
		for(c <- callsOfInterest){
			QueryString qs =  buildQueryString(simplifyParams(c, pt.baseLoc, iinfo));
			// case of a variable parameter
			if(call(_,[actualParameter(var(name(name(queryVar))),_),_*]) := c){
			
				bool assignsScalarToQueryVar(CFGNode cn) {
					if (exprNode(assign(var(name(name(queryVar))),queryExpr),_) := cn) {
						simplifiedQueryExpr = simplifyExpr(replaceConstants(queryExpr,iinfo), pt.baseLoc);
						if (scalar(string(_)) := simplifiedQueryExpr) {
							return true;
						}
					}
					return false;
				}
			
				// If we have a non-literal assignment to the query var, then we stop looking, that "spoils" any
				// literal assignment we could find above, e.g., $x = goodValue, $x .= badValue. 
				bool assignsNonScalarToQueryVar(CFGNode cn) {
					if (exprNode(assign(var(name(name(queryVar))),queryExpr),_) := cn) {
						simplifiedQueryExpr = simplifyExpr(replaceConstants(queryExpr,iinfo), pt.baseLoc);
						if (scalar(string(_)) !:= simplifiedQueryExpr) {
							return true;
						}
					} else if (exprNode(assignWOp(var(name(name(queryVar))),queryExpr,_),_) := cn) {
						return true;
					}
					return false;			
				}
			
				Expr getAssignedScalar(CFGNode cn) {
					if (exprNode(assign(var(name(name(queryVar))),queryExpr),_) := cn) {
						simplifiedQueryExpr = simplifyExpr(replaceConstants(queryExpr,iinfo), pt.baseLoc);
						if (ss:scalar(string(_)) := simplifiedQueryExpr) {
							return ss;
						}
					}	
					throw "gather should only be called when pred returns true";
				}
			
				containingScript = pt.files[c@at.top];
				containingCFG = findContainingCFG(containingScript, neededCFGs[c@at.top], c@at);
				callNode = findNodeForExpr(containingCFG, c);
				gr = gatherOnAllReachingPaths(cfgAsGraph(containingCFG), callNode, assignsScalarToQueryVar, assignsNonScalarToQueryVar, getAssignedScalar);
							
				// QCP2 recognizer (case where a single string literal is assigned to the query variable)
				if(gr.trueOnAllPaths && size(gr.results) == 1){
					qs.flags.unclassified = false;
					qs.flags.qcp2 = true;
					println("QCP2 occurrence found at <c@at>");
				}
				// TODO: write recognizers for the other Query Construction Patterns
			}
			sysres += qs;
		}
		corpusres = corpusres + sysres;
	}
	return corpusres;
}

public void findReachableQueryStrings() {
	Corpus corpus = getCorpus();
	for (p <- corpus, v := corpus[p]) {
		pt = loadBinary(p, v);
		if (!pt has baseLoc) {
			println("Skipping system <p>, version <v>, no base loc included");
			continue;
		}
		callsOfInterest = [ c | /c:call(name(name("mysql_query")),[actualParameter(var(name(name(_))),false),_*]) := pt ];
		println("Calls in system <p>, version <v> (total = <size(callsOfInterest)>):");
		neededCFGs = ( l : buildCFGs(pt.files[l], buildBasicBlocks=false) | l <- { c@at.top | c <- callsOfInterest } );
		IncludesInfo iinfo = loadIncludesInfo(p, v);
		for (c:call(_,[actualParameter(var(name(name(queryVar))),_),_*]) <- callsOfInterest) {
			containingScript = pt.files[c@at.top];
			containingCFG = findContainingCFG(containingScript, neededCFGs[c@at.top], c@at);
			callNode = findNodeForExpr(containingCFG, c);
			// NOTE: It would be better to have a reaching definitions analysis for this. Since that is still under
			// development, we instead simulate this for common cases.
			
			// If we have a standard literal assignment to the query var, then we can use the assigned value
			// TODO: This does not handle cascades of .= assignments.
			bool assignsScalarToQueryVar(CFGNode cn) {
				if (exprNode(assign(var(name(name(queryVar))),queryExpr),_) := cn) {
					simplifiedQueryExpr = simplifyExpr(replaceConstants(queryExpr,iinfo), pt.baseLoc);
					if (scalar(string(_)) := simplifiedQueryExpr) {
						return true;
					}
				}
				return false;
			}
			
			// If we have a non-literal assignment to the query var, then we stop looking, that "spoils" any
			// literal assignment we could find above, e.g., $x = goodValue, $x .= badValue. 
			bool assignsNonScalarToQueryVar(CFGNode cn) {
				if (exprNode(assign(var(name(name(queryVar))),queryExpr),_) := cn) {
					simplifiedQueryExpr = simplifyExpr(replaceConstants(queryExpr,iinfo), pt.baseLoc);
					if (scalar(string(_)) !:= simplifiedQueryExpr) {
						return true;
					}
				} else if (exprNode(assignWOp(var(name(name(queryVar))),queryExpr,_),_) := cn) {
					return true;
				}
				return false;			
			}
			
			Expr getAssignedScalar(CFGNode cn) {
				if (exprNode(assign(var(name(name(queryVar))),queryExpr),_) := cn) {
					simplifiedQueryExpr = simplifyExpr(replaceConstants(queryExpr,iinfo), pt.baseLoc);
					if (ss:scalar(string(_)) := simplifiedQueryExpr) {
						return ss;
					}
				}
				throw "gather should only be called when pred returns true";
			}
			
			gr = gatherOnAllReachingPaths(cfgAsGraph(containingCFG), callNode, assignsScalarToQueryVar, assignsNonScalarToQueryVar, getAssignedScalar);
			if (gr.trueOnAllPaths) {
				println("For call at location <c@at>, found <size(gr.results)> literal assignments into the query variable");
			//} else {
			//	println("For call at location <c@at>, no assignment of a string literal to the query var was found on at least one reaching path");
			}
		} 
	}
	println(x);
}
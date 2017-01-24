module QCPAnalysis::ParseQueries

import QCPAnalysis::AbstractQuery;
import QCPAnalysis::QCPCorpus;

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
// along with AbstractQuery.rsc, will replace QueryStringAnalysis, QueryGroups, and QCP4SubcaseAnalysis

public void printCounts(){
	queryMap = buildQueriesCorpus();
	for(sys <- queryMap, queries := queryMap[sys]){
		println("counts for <sys>");
		println("QCP1a: <size({q | q <- queries, QCP1a(_,_) := q})>");
		println("QCP1b: <size({q | q <- queries, QCP1b(_,_) := q})>");
		println("QCP2: <size({q | q <- queries, QCP2(_,_) := q})>");
		println("QCP3a: <size({q | q <- queries, QCP3a(_,_) := q})>");
		println("QCP3b: <size({q | q <- queries, QCP3b(_,_) := q})>");
		println("QCP4a: <size({q | q <- queries, QCP4a(_,_) := q})>");
		println("QCP4b: <size({q | q <- queries, QCP4b(_,_) := q})>");
		println("QCP4c: <size({q | q <- queries, QCP4c(_,_) := q})>");
		println("QCP5: <size({q | q <- queries, QCP5(_,_) := q})>");
		println("unclassified: <size({q | q <- queries, unclassified(_) := q})>");
	}
}

public map[str, list[Query]] buildQueriesCorpus(){
	Corpus corpus = getCorpus();
	res = ();
	for(p <- corpus, v := corpus[p]){
		pt = loadBinary(p,v);
		if (!pt has baseLoc) {
			println("Skipping system <p>, version <v>, no base loc included");
			continue;
		}
		IncludesInfo iinfo = loadIncludesInfo(p, v);
		calls = [ c | /c:call(name(name("mysql_query")),_) := pt ];
		simplified = [s | c <- calls, s := simplifyParams(c, pt.baseLoc, iinfo)];
		println("Calls in system <p>, version <v> (total = <size(calls)>):");
		neededCFGs = ( l : buildCFGs(pt.files[l], buildBasicBlocks=false) | l <- { c@at.top | c <- calls } );
		queries = buildQueriesSystem(pt, simplified, iinfo, neededCFGs);
		res += ("<p>_<v>" : queries);
	}
	return res;
}

public list[Query] buildQueriesSystem(System pt, list[Expr] calls, IncludesInfo iinfo, map[loc, map[NamePath,CFG]] cfgs){
	res = [];
	classifiedCalls = [];
	
	// build Query structures for the easy cases
	easy = buildEasyQueries(calls);
	res += easy.queries;
	classifiedCalls += easy.classified;
	
	// build Query structures for QCP2
	qcp2 = buildQCP2Queries(calls - classifiedCalls);
	res += qcp2.queries;
	classifiedCalls += qcp2.classified;
	
	// build Query structures for variable cases
	varQueries = buildVariableQueries(pt, calls, iinfo, cfgs);
	res += varQueries.queries;
	classifiedCalls += varQueries.classified;
	
	// build Query structures for unknown cases
	unknowns = buildUnknownQueries(calls - classifiedCalls);
	res += unknowns.queries;
	classifiedCalls += unknowns.classified;
	
	// make sure all calls were characterized
	if(size(calls) != size(classifiedCalls)) 
		throw "not all calls were classified";
		
	return res;
}

@doc{builds Query structures for cases where we can classifty the query just by looking at the parameter (QCP1a,  QCP4a, or QCPb)}
public tuple[list[Query] queries, list[Expr] classified] buildEasyQueries(list[Expr] calls){
	res = [];
	classifiedCalls = [];
	for(c:call(name(name("mysql_query")), params) <- calls){
		if(actualParameter(scalar(string(s)),false) := head(params)){
			res += QCP1a(c@at, s);
			classifiedCalls += c;
		}
		// check for QCP4a (encapsed string)
		else if(actualParameter(scalar(encapsed(parts)), false) := head(params)){
			res += QCP4a(c@at, buildMixedSnippets(parts));
			classifiedCalls += c;
		}
		
		// check for QCP4b (concatenation)
		else if(actualParameter(b:binaryOperation(left, right, concat()), false) := head(params)){
			res += QCP4b(c@at, buildMixedSnippets(b));
			classifiedCalls += c;
		}
		else{
			continue;
		}	
	}
	return <res, classifiedCalls>;
}

@doc{builds Query Structures for cases found by the QCP2 checker}
public tuple[list[Query] queries, list[Expr] classified] buildQCP2Queries(list[Expr] calls){
	// TO BE IMPLEMENTED
	return <[],[]>;
}

@doc{builds Query Structures for other cases where the param to mysql_query is a variable}
public tuple[list[Query] queries, list[Expr] classified] buildVariableQueries(System pt, list[Expr] calls, IncludesInfo iinfo, map[loc, map[NamePath, CFG]] cfgs){
	// TO BE IMPLEMENTED
	return <[],[]>;
}

@doc{builds queries that we arent able to classify yet}
public tuple[list[Query] queries, list[Expr] classified] buildUnknownQueries(list[Expr] calls){
	res = [];
	classifiedCalls = [];
	for(c:call(name(name("mysql_query")), params) <- calls){
		res += unclassified(c@at);
		classifiedCalls += c;
	}
	return <res, classifiedCalls>;
}

// placeholder, will be replaced with code that classifies dynamic snippets based on what role they play in the query
@doc{builds Query structures for QCP2 and QCP4 where there is a mixture of static and dynamic query parts}
private list[QuerySnippet] buildMixedSnippets(Expr e){
	if(scalar(string(s)) := e) return [staticsnippet(s)];
	else if(scalar(encapsed(parts)) := e) return buildMixedSnippets(parts);
	else if(binaryOperation(left, right, concat()) := e) return buildMixedSnippets(left) + buildMixedSnippets(right);
	else return [dynamicsnippet(e)];
}
private list[QuerySnippet] buildMixedSnippets(list[Expr] parts){
	snippets = [];
	for(p <- parts){
		snippets += buildMixedSnippets(p);
	}
	return snippets;
}
			
@doc{Run the simplifier on the parameters being passed to this function}
private Expr simplifyParams(Expr c:call(NameOrExpr funName, list[ActualParameter] parameters), loc baseLoc, IncludesInfo iinfo) {
	list[ActualParameter] simplifiedParameters = [];
	for (p:actualParameter(Expr expr, bool byRef) <- parameters) {
		simplifiedParameters += p[expr=simplifyExpr(replaceConstants(expr,iinfo), baseLoc)];
	}
	return c[parameters=simplifiedParameters];
}


data ConcatBuilder = concatBuilder(str varName, list[Expr] queryParts, loc startsAt, Expr queryExpr, loc usedAt);

@doc {checks for QCP2 occurrences (cascading .= assignments)}
public rel[str system, str version, ConcatBuilder occurrence] concatAssignments() {
	rel[str system, str version, ConcatBuilder occurrence] res = { };
	corpus = getCorpus();

	cfgsForScripts = ( );
	
	for (systemName <- corpus, systemVersion := corpus[systemName]) {
		theSystem = loadBinary(systemName, systemVersion);
		
		for (scriptLoc <- theSystem.files) {
			Script scr = theSystem.files[scriptLoc];
			
			// Find calls to mysql_query in this script that use a variable to store the query. We want to
			// check to see which queries formed using concatenations reach this query.
			queryCalls = { < queryCall, varName, queryCall@at > | 
				/queryCall:call(name(name("mysql_query")), [actualParameter(var(name(name(varName))),_),*_]) := scr };
			
			for ( varName <- queryCalls<1>) {
				// Are there assignments with following appends into the query variable?
				for ( /[_*,exprstmt(firstPart:assign(var(name(name(varName))),firstQueryPart)),*after] := scr ) {
					queryParts = [ firstQueryPart ];
					for (possibleConcat <- after) {
						if (exprstmt(assignWOp(var(name(name(varName))),queryPart,concat())) := possibleConcat) {
							queryParts = queryParts + queryPart;
						} else {
							break;
						}
					}
					if (size(queryParts) > 1) {
						//println("Found a concat query starting at <firstPart@at> with <size(queryParts)> parts, for variable <varName>");
						if (scriptLoc notin cfgsForScripts) {
							cfgsForScripts[scriptLoc] = buildCFGs(scr, buildBasicBlocks=false);
						}
						scriptCFGs = cfgsForScripts[scriptLoc];
						neededCFG = findContainingCFG(scr, scriptCFGs, queryParts[-1]@at);
						neededCFGAsGraph = cfgAsGraph(neededCFG);
						startNode = findNodeForExpr(neededCFG, queryParts[-1]@at);
						
						// Now, make sure the query is actually reachable
						// bool(CFGNode cn) pred, bool(CFGNode cn) stop, &T (CFGNode cn) gather
						bool foundQueryCall(CFGNode cn) {
							if (exprNode(call(name(name("mysql_query")), [actualParameter(var(name(name(varName))),_),*_]),_) := cn) {
								return true;
							} else {
								return false;
							}
						}
						tuple[Expr,loc] collectQueryCall(CFGNode cn) {
							if (exprNode(exprToCollect:call(name(name("mysql_query")), [actualParameter(var(name(name(varName))),_),*_]),_) := cn) {
								return < exprToCollect, exprToCollect@at >;
							} else {
								throw "Given unexpected node: <cn>";
							}
						}
						bool foundAnotherAssignment(CFGNode cn) {
							if (exprNode(potential:assign(var(name(name(varName))),_),_) := cn && potential@at != firstPart@at) {
								return true;
							} else {
								return false;
							}
						}
						allUsingQueries = findAllReachedUntil(neededCFGAsGraph, startNode, foundQueryCall, foundAnotherAssignment, collectQueryCall);
						res = res + { < systemName, systemVersion, concatBuilder(varName, queryParts, firstPart@at, queryCallExpr, queryCallLoc) > | < queryCallExpr, queryCallLoc > <- allUsingQueries };
					}
				}
			}
		}
	}

	return res;
}
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

public map[str, map[str, int]] countsBySystem(){
	queryMap = buildQueriesCorpus();
	res = ();
	for(sys <- queryMap, queries := queryMap[sys]){
		counts = ("total" : size(queries),
				  "QCP1a" : size([q | q <- queries, QCP1a(_,_) := q]),
				  "QCP1b" : size([q | q <- queries, QCP1b(_,_) := q]), 
				  "QCP2" : size([q | q <- queries, QCP2(_,_) := q]),
				  "QCP3a" : size([q | q <- queries, QCP3a(_,_) := q]),
				  "QCP3b" : size([q | q <- queries, QCP3b(_,_) := q]),
				  "QCP4a" : size([q | q <- queries, QCP4a(_,_) := q]),
				  "QCP4b" : size([q | q <- queries, QCP4b(_,_) := q]),
				  "QCP4c" : size([q | q <- queries, QCP4c(_,_) := q]),
				  "QCP5" : size([q | q <- queries, QCP5(_,_) := q]),
				  "unclassified" : size([q | q <- queries, unclassified(_) := q])
		);
		res += (sys : counts);
	}
	return res;
}

public map[str, int] countsByPattern(){
	sysCounts = countsBySystem();
	res = (
		"total" : 0,
		"QCP1a" : 0,
		"QCP1b" : 0,
		"QCP2" : 0,
		"QCP3a" : 0,
		"QCP3b" : 0,
		"QCP4a" : 0,
		"QCP4b" : 0,
		"QCP4c" : 0,
		"QCP5" : 0,
		"unclassified" : 0
	);
	for(sys <- sysCounts, counts := sysCounts[sys]){
		res["total"] += counts["total"];
		res["QCP1a"] += counts["QCP1a"];
		res["QCP1b"] += counts["QCP1b"];
		res["QCP2"] += counts["QCP2"];
		res["QCP3a"] += counts["QCP3a"];
		res["QCP3b"] += counts["QCP3b"];
		res["QCP4a"] += counts["QCP4a"];
		res["QCP4b"] += counts["QCP4b"];
		res["QCP4c"] += counts["QCP4c"];
		res["QCP5"] += counts["QCP5"];
		res["unclassified"] += counts["unclassified"];
	}
	return res;
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
	
	// get calls already found by the concat assignment checker
	ca = concatAssignments()[pt.name, pt.version];
	
	for(c:call(name(name("mysql_query")), params) <- calls){
	
		// check if this call was already found by the QCP2 checker
		if(c@at in [a.usedAt | a <- ca]){
			queryParts = getOneFrom([a.queryParts | a <- ca, c@at == a.usedAt]);
			res += QCP2(c@at, buildMixedSnippets(queryParts));
			continue;
		}
		
		//check for easy cases QCP1a, QCP4a, and QCP4b
		query = buildEasyCaseQuery(c);
		if(unclassified(_) !:= query){
			res += query;
			continue;	
		}
		
		// check for QCP1b and QCP3a
		query = buildLiteralVariableQuery(pt, c, iinfo, cfgs);
		if(unclassified(_) !:= query){
			res += query;
			continue;	
		}
		
		// check for QCP4a and QCP3b
		query = buildMixedVariableQuery(pt, c, iinfo, cfgs);
		if(unclassified(_) !:= query){
			res += query;
			continue;	
		}
		
		// check for QCP5
		query = buildQCP5Query(pt, c, iinfo, cfgs);
		if(unclassified(_) !:= query){
			res += query;
			continue;	
		}
		
		// nothing classified this query, add it as an unclassified query
		res += unclassified(c@at);
	}
	return res;
}

@doc{builds a Query structure for easy case (QCP1a,  QCP4a, or QCPb), if the query matches these cases. Otherwise, returns an unclassified query}
public Query buildEasyCaseQuery(Expr c){

	if(call(name(name("mysql_query")), params) := c){
		if(actualParameter(scalar(string(s)),false) := head(params)){
			return QCP1a(c@at, s);
		}
		// check for QCP4a (encapsed string)
		else if(actualParameter(scalar(encapsed(parts)), false) := head(params)){
			return QCP4a(c@at, buildMixedSnippets(parts));
		}
		
		// check for QCP4b (concatenation)
		else if(actualParameter(b:binaryOperation(left, right, concat()), false) := head(params)){
			return QCP4b(c@at, buildMixedSnippets(b));
		}
		else{
			return unclassified(c@at);
		}
	}
	else{
		throw "error: buildEasyCase should only be called on calls to mysql_query";
	}
}

@doc{builds Query Structures for QCP1b or QCP3a if the query matches these cases. Otherwise, returns an unclassified query}
public Query buildLiteralVariableQuery(System pt, Expr c, IncludesInfo iinfo, map[loc, map[NamePath, CFG]] cfgs){
	if(call(_,[actualParameter(var(name(name(queryVar))),false),_*]) := c){
	
		containingScript = pt.files[c@at.top];
		containingCFG = findContainingCFG(containingScript, cfgs[c@at.top], c@at);
		callNode = findNodeForExpr(containingCFG, c);
			
		// If we have a standard literal assignment to the query var, then we can use the assigned value
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
			
		literalGR = gatherOnAllReachingPaths(cfgAsGraph(containingCFG), callNode, assignsScalarToQueryVar, assignsNonScalarToQueryVar, getAssignedScalar);
		if(literalGR.trueOnAllPaths){
			// QCP1b (single literal assignment into the query variable)
			if(size(literalGR.results) == 1){
				return QCP1b(c@at, getOneFrom(literalGR.results).scalarVal.strVal);
			}
				
			// QCP3a (literal assignments distributed over control flow)
			if(size(literalGR.results) > 1){
				return  QCP3a(c@at, [r.scalarVal.strVal | r <- literalGR.results]);
			}
		}
	}
	return unclassified(c@at);
}
@doc{builds a Query Structue for QCP4c or QCP3b if the query matches these cases. Otherwise, returns an unclassified query}
public Query buildMixedVariableQuery(System pt, Expr c, IncludesInfo iinfo, map[loc, map[NamePath, CFG]] cfgs){

	if(call(_,[actualParameter(var(name(name(queryVar))),false),_*]) := c){
		containingScript = pt.files[c@at.top];
		containingCFG = findContainingCFG(containingScript, cfgs[c@at.top], c@at);
		callNode = findNodeForExpr(containingCFG, c);
		bool assignsConcatOrEncapsedToQueryVar(CFGNode cn){
			if (exprNode(assign(var(name(name(queryVar))),queryExpr),_) := cn) {
				simplifiedQueryExpr = simplifyExpr(replaceConstants(queryExpr,iinfo), pt.baseLoc);
				if (scalar(encapsed(_)) := simplifiedQueryExpr || binaryOperation(left,right,concat()) := simplifiedQueryExpr) {
					return true;
				}
			} 
			return false;			
		}
				
		bool notAssignsConcatOrEncapsedToQueryVar(CFGNode cn) {
			if (exprNode(assign(var(name(name(queryVar))),queryExpr),_) := cn) {
				simplifiedQueryExpr = simplifyExpr(replaceConstants(queryExpr,iinfo), pt.baseLoc);
				if (scalar(encapsed(_)) := simplifiedQueryExpr || binaryOperation(left,right,concat()) := simplifiedQueryExpr) {
					return false;
				} else {
					return true;
				}
			} 
			return false;				
		}
		
		Expr getAssignedConcatOrEncapsed(CFGNode cn){
			if (exprNode(assign(var(name(name(queryVar))),queryExpr),_) := cn) {
				simplifiedQueryExpr = simplifyExpr(replaceConstants(queryExpr,iinfo), pt.baseLoc);
				if (e:scalar(encapsed(_)) := simplifiedQueryExpr) {
					return e;
				}
				else if(e:binaryOperation(left, right, concat()) := simplifiedQueryExpr){
					return e;
				}
			}	
			throw "gather should only be called when pred returns true";
		}
		
		concatOrEncapsedGR = gatherOnAllReachingPaths(cfgAsGraph(containingCFG), callNode, 
			assignsConcatOrEncapsedToQueryVar, notAssignsConcatOrEncapsedToQueryVar, getAssignedConcatOrEncapsed);
		
		if(concatOrEncapsedGR.trueOnAllPaths){
			// QCP4c check (QCP4a or QCP4b query assigned to a variable)
			if(size(concatOrEncapsedGR.results) == 1){
				return  QCP4c(c@at, buildMixedSnippets(toList(concatOrEncapsedGR.results)));
			}
			
			// QCP3b check (QCP4 queries distributed over control flow)
			if(size(concatOrEncapsedGR.results) > 1){
				queries = [];
				for(r <- concatOrEncapsedGR.results){
					queries += [buildMixedSnippets(r)];
				}
				return QCP3b(c@at, queries);
			}
		}
	}
	return unclassified(c@at);
}

@doc{builds a query if it is classified as QCP5, otherwise returns an unclassified query}
public Query buildQCP5Query(System pt, Expr c, IncludesInfo iinfo, map[loc, map[NamePath, CFG]] cfgs){
	// TO BE IMPLEMENTED
	return unclassified(c@at);
}

// placeholder, will be replaced with code that classifies dynamic snippets based on what role they play in the query
@doc{builds Query Snippets for QCP2 and QCP4 where there is a mixture of static and dynamic query parts}
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
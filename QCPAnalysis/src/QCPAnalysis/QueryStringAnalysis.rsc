/*
 * The purpose of this module is to analyze all mysql_query calls in the system
 * and figure out which parts of the Query String are static and which come from
 * dynamic sources.
 * After initial creation of QueryString data structures for each call, each dynamic
 * Snippet will be analyzed in the CFGs and pattern flags will be set for that QueryString
 * structure based on defined query construction patterns
 */
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
data PatternFlags = flags(bool unclassified, bool qcp1, bool qcp2, bool qcp3a, bool qcp3b, bool qcp4);
		
// builds query string structures for all mysql_query calls in the corpus without classifying them
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
		default: throw "unhandled case encountered when building query string";
	}
}

// used for rebuilding a string with a variable parameter where we know that 
// the variable contains either a string literal, a encapsed string, or the result of a concat operation
public QueryString replaceVar(QueryString qs, Expr e){
	switch(e){
		case scalar(string(s)) : return querystring(qs.callloc, [staticsnippet(s)], qs.flags);
		case e:binaryOperation(_,_,concat()) : return querystring(qs.callloc, buildQG2Snippets(e), qs.flags);
		case e:scalar(encapsed(_)) : return querystring(qs.callloc, buildQG2Snippets(e), qs.flags);
		default: throw "unhandled case encountered when replacing query variable";
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

public void reportQCPCounts(){
	qs = buildAndClassifyQueryStrings();
	println("Number of QCP1 cases: <size({q | q <- qs, q.flags.qcp1 == true})>");
	println("Number of QCP2 cases: <size({q | q <- qs, q.flags.qcp2 == true})>");
	println("Number of QCP3a cases: <size({q | q <- qs, q.flags.qcp3a == true})>");
	println("Number of QCP3b cases: <size({q | q <- qs, q.flags.qcp3b == true})>");
	println("Number of QCP4 cases: <size({q | q <- qs, q.flags.qcp4 == true})>");
	println("Number of unclassified cases: <size({q | q <- qs, q.flags.unclassified == true})>");
}

public set[QueryString] getQCP(int id){
	qs = buildAndClassifyQueryStrings();
	switch(id){
		case 0 : return {q | q <- qs, q.flags.unclassified == true};
		case 1 : return {q | q <- qs, q.flags.qcp1 == true};
		case 2 : return {q | q <- qs, q.flags.qcp2 == true};
		case 3 : return {q | q <- qs, q.flags.qcp3a == true || q.flags.qcp3b == true};
		case 4 : return {q | q <- qs, q.flags.qcp4 == true};
		default: throw "Value must be between 0 and 4";
	}
}
public set[loc] getQCPLocs(int id) = {q.callloc | q <- getQCP(id)};

// builds and classifies all query strings based on the Query Construction Patterns in the wiki
public set[QueryString] buildAndClassifyQueryStrings(){
	Corpus corpus = getCorpus();
	set[QueryString] corpusres = {};
	// get all QCP2 occurrences (cascading assignments)
	cascadingLocs = {c.usedAt | c <- concatAssignments()<2>};
	for(p <- corpus, v := corpus[p]){
		pt = loadBinary(p,v);
		if (!pt has baseLoc) {
			println("Skipping system <p>, version <v>, no base loc included");
			continue;
		}
		IncludesInfo iinfo = loadIncludesInfo(p, v);
		calls = [ c | /c:call(name(name("mysql_query")),_) := pt ];
		println("Calls in system <p>, version <v> (total = <size(calls)>):");
		neededCFGs = ( l : buildCFGs(pt.files[l], buildBasicBlocks=false) | l <- { c@at.top | c <- calls } );
		set[QueryString] sysres = {};
		for(c <- calls){
			QueryString qs =  buildQueryString(simplifyParams(c, pt.baseLoc, iinfo));
			
			// case of a variable parameter
			if(call(_,[actualParameter(var(name(name(queryVar))),false),_*]) := c){
			
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
				
				// case where the variable is assigned a query string that is a concatenation or interpolation of string literals
				// and PHP variables, function calls, etc.
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
				
				
				Expr getAssignedScalar(CFGNode cn) {
					if (exprNode(assign(var(name(name(queryVar))),queryExpr),_) := cn) {
						simplifiedQueryExpr = simplifyExpr(replaceConstants(queryExpr,iinfo), pt.baseLoc);
						if (ss:scalar(string(_)) := simplifiedQueryExpr) {
							return ss;
						}
					}	
					throw "gather should only be called when pred returns true";
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
			
				containingScript = pt.files[qs.callloc.top];
				containingCFG = findContainingCFG(containingScript, neededCFGs[qs.callloc.top], qs.callloc);
				callNode = findNodeForExpr(containingCFG, c);
				literalGR = gatherOnAllReachingPaths(cfgAsGraph(containingCFG), callNode, assignsScalarToQueryVar, assignsNonScalarToQueryVar, getAssignedScalar);
				concatOrEncapsedGR = gatherOnAllReachingPaths(cfgAsGraph(containingCFG), callNode, 
					assignsConcatOrEncapsedToQueryVar, notAssignsConcatOrEncapsedToQueryVar, getAssignedConcatOrEncapsed);
				
				// check if this query string is already found by the cascading assignment checker
				if(qs.callloc in cascadingLocs){
					qs.flags.unclassified = false;
					qs.flags.qcp2 = true;
				}
						
				else if(literalGR.trueOnAllPaths){
					// QCP1 recognizer (case where a string literal is assigned to the query variable)
					if(size(literalGR.results) == 1){
						qs.flags.unclassified = false;
						qs.flags.qcp1 = true;
						// we know that a literal string goes into this query string, so replace the variable with that string
						qs = replaceVar(qs, getOneFrom(literalGR.results));
					}
					
					// QCP3A: multiple possible literal assignments distributed over control flow structures
					else if(size(literalGR.results) > 1){
						qs.flags.unclassified = false;
						qs.flags.qcp3a = true;
					}
				}
				
				else if(concatOrEncapsedGR.trueOnAllPaths){
					// QCP4 recognizer (variable is assigned query string that contains literals and php variables, functions, etc encapsed or concatenated)
					if(size(concatOrEncapsedGR.results) == 1){
						qs.flags.unclassified = false;
						qs.flags.qcp4 = true;
						//we know that an encapsed string or concat operation result goes into this query string, so replace the variable with that Expr
						qs = replaceVar(qs, getOneFrom(concatOrEncapsedGR.results));
					}
					
					//QCP3B: multiple possible QCP4 occurrences distributed over control flow structures
					else if(size(concatOrEncapsedGR.results) > 1){
						qs.flags.unclassified = false;
						qs.flags.qcp3b = true;
					}
				}		
			}
			
			// QCP4 recognizer where the parameter is literals and php variables, function calls, etc concatenated or encapsed
			else if(call(_,[actualParameter(scalar(encapsed(_)),false),_*]) := c
				|| call(_,[actualParameter(binaryOperation(left, right, concat()),false),_*]) := c){
				qs.flags.unclassified = false;
				qs.flags.qcp4 = true;
			}
			else{
				println("unclassified query found at <qs.callloc>");
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
}

data ConcatBuilder = concatBuilder(str varName, list[Expr] queryParts, loc startsAt, Expr queryExpr, loc usedAt);

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
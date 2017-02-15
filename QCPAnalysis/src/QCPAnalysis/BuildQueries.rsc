module QCPAnalysis::BuildQueries

import QCPAnalysis::AbstractQuery;
import QCPAnalysis::QCPCorpus;

import QCPAnalysis::MixedQuery::AbstractSyntax;
import QCPAnalysis::MixedQuery::LoadQuery;

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
import Exception;
import String;

public map[str, list[Query]] buildQueriesCorpus(){
	Corpus corpus = getCorpus();
	res = ();
	ca = concatAssignments();
	for(p <- corpus, v := corpus[p]){
		pt = loadBinary(p,v);
		if (!pt has baseLoc) {
			println("Skipping system <p>, version <v>, no base loc included");
			continue;
		}
		sysCA = ca[p, v];
		IncludesInfo iinfo = loadIncludesInfo(p, v);
		calls = [ c | /c:call(name(name("mysql_query")),_) := pt ];
		simplified = [s | c <- calls, s := simplifyParams(c, pt.baseLoc, iinfo)];
		println("Calls in system <p>, version <v> (total = <size(calls)>):");
		neededCFGs = ( l : buildCFGs(pt.files[l], buildBasicBlocks=false) | l <- { c@at.top | c <- calls } );
		queries = buildQueriesSystem(pt, simplified, iinfo, neededCFGs, sysCA);
		res += ("<p>_<v>" : queries);
	}
	return res;
}

public list[Query] buildQueriesSystem(System pt, list[Expr] calls, IncludesInfo iinfo, map[loc, map[NamePath,CFG]] cfgs, set[ConcatBuilder] ca){
	res = [];

	for(c:call(name(name("mysql_query")), params) <- calls){
	
		// check if this call was already found by the QCP2a checker
		if(c@at in [a.usedAt | a <- ca]){
			queryParts = getOneFrom([a.queryParts | a <- ca, c@at == a.usedAt]);
			mixed = buildMixedSnippets(queryParts);
			SQLQuery parsed;
			try parsed = load(mixed);
			catch: parsed = error();
			res += QCP2a(c@at, mixed, parsed);
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
			mixed = buildMixedSnippets(parts);
			SQLQuery parsed;
			try parsed = load(mixed);
			catch: parsed = error();
			return QCP4a(c@at, mixed, parsed);
		}
		
		// check for QCP4b (concatenation)
		else if(actualParameter(b:binaryOperation(left, right, concat()), false) := head(params)){
			mixed = buildMixedSnippets(b);
			SQLQuery parsed;
			try parsed = load(mixed);
			catch: parsed = error();
			return QCP4b(c@at, mixed, parsed);
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
				mixed = buildMixedSnippets(toList(concatOrEncapsedGR.results));
				SQLQuery parsed;
				try parsed = load(mixed);
				catch: parsed = error();
				return  QCP4c(c@at, mixed, parsed);
			}
			
			// QCP3b check (QCP4 queries distributed over control flow)
			if(size(concatOrEncapsedGR.results) > 1){
				queries = {};
					for(r <- concatOrEncapsedGR.results){
					mixed = buildMixedSnippets(toList(concatOrEncapsedGR.results));
					SQLQuery parsed;
					try parsed = load(mixed);
					catch: parsed = error();
					queries += <mixed, parsed>;
				}
				return QCP3b(c@at, queries);
			}
		}
	}
	return unclassified(c@at);
}

@doc{builds a query if it is classified as QCP5, otherwise returns an unclassified query}
public Query buildQCP5Query(System pt, Expr c, IncludesInfo iinfo, map[loc, map[NamePath, CFG]] cfgs){

	if(call(_,[actualParameter(var(name(name(queryVar))),false),_*]) := c){
	
		containingScript = pt.files[c@at.top];
		containingCFG = findContainingCFG(containingScript, cfgs[c@at.top], c@at);
		callNode = findNodeForExpr(containingCFG, c);
		entryNode = getEntryNode(containingCFG);
		
		if(functionEntry(functionName) := entryNode){
			//find the function in the script matching the entryNode and see if queryVar is in its parameters
			containingFunction = getOneFrom({s | s <- containingScript.body, function(functionName, _,_,_) := s});
			paramNames = {p.paramName | p <- containingFunction.params};
			if(queryVar in paramNames){
				return QCP5(c@at, containingFunction@at);
			}
		}
		
		if(methodEntry(className, methodName) := entryNode){
			// find the method in the script matching the entryNode and see if queryVar is in its parameters
			containingClass = getOneFrom({cl | /Stmt cl <- containingScript.body, classDef(class(className,_,_,_,_)) := cl});
			containingMethod = getOneFrom({m | m <- containingClass.classDef.members, method(methodName,_,_,_,_) := m});
			paramNames = {p.paramName | p <- containingMethod.params};
			if(queryVar in paramNames){				
				return QCP5(c@at, containingMethod@at);
			}
		}
	}
	return unclassified(c@at);
}

@doc{builds Query Snippets for QCP2a and QCP4 where there is a mixture of static and dynamic query parts}
private str buildMixedSnippets(Expr e){
	if(scalar(string(s)) := e){
		res = replaceAll(s,"\n", "");
		res = replaceAll(res, "\r", "");
		return res;
	}
	else if(scalar(encapsed(parts)) := e) return buildMixedSnippets(parts);
	else if(binaryOperation(left, right, concat()) := e) return buildMixedSnippets(left) + buildMixedSnippets(right);
	else return "Ø";//symbol for dynamic query part
}
private str buildMixedSnippets(list[Expr] parts){
	res = "";
	for(p <- parts){
		res += buildMixedSnippets(p);
	}
	return res;
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

@doc {checks for QCP2a occurrences (cascading .= assignments)}
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
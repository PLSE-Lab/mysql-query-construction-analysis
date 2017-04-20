module QCPAnalysis::BuildQueries

import QCPAnalysis::AbstractQuery;
import QCPAnalysis::QCPCorpus;
import QCPAnalysis::ParseSQL::AbstractSyntax;
import QCPAnalysis::ParseSQL::RunSQLParser;
import QCPAnalysis::ParseSQL::LoadQuery;
import QCPAnalysis::FunctionQueries;
import QCPAnalysis::QCPSystemInfo;
import QCPAnalysis::Utils;

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
import lang::php::analysis::callgraph::SimpleCG;

import Set;
import Map;
import IO;
import ValueIO;
import List;
import Exception;
import String;
import Relation;

private int holeID = 0;

data ConcatBuilder = concatBuilder(str varName, list[Expr] queryParts, loc startsAt, Expr queryExpr, loc usedAt);

public map[str, list[Query]] buildQueriesCorpus(str functionName = "mysql_query"){
	Corpus corpus = getCorpus();
	res = ();
	for(p <- corpus, v := corpus[p]){
		res["<p>_<v>"] = buildQueriesSystem(p, v, functionName = functionName, seenBefore = { });
	}
	return res;
}

public list[Query] buildQueriesSystem(str p, str v, str functionName = "mysql_query", set[str] seenBefore = { }) {
	qcpi = readQCPSystemInfo(p,v);
	if (!qcpi.sys has baseLoc) {
		println("Skipping system <p>, version <v>, no base loc included");
		return [ ];
	}

	calls = qcpi.functionCalls[_,functionName];
	ca = concatAssignments(qcpi, functionName);

	return buildQueriesSystem(qcpi, calls, ca, functionName = functionName, seenBefore = seenBefore); 
}

public list[Query] buildQueriesSystem(QCPSystemInfo qcpi, set[Expr] calls, set[ConcatBuilder] ca, str functionName = "mysql_query", set[str] seenBefore = { }, int index = 0) {
	simplified = [s | c <- calls, s := simplifyParams(c, qcpi.sys.baseLoc, qcpi.iinfo)];
	println("Calls to <functionName> in system <qcpi.sys.name>, version <qcpi.sys.version> (total = <size(calls)>):");
	
	res = [];
	for(c <- calls){
		// check if this call was already found by the QCP2 checker
		if(c@at in [a.usedAt | a <- ca]){
			queryParts = getOneFrom([a.queryParts | a <- ca, c@at == a.usedAt]);
			mixed = "";
			for(qp <- queryParts){
				mixed += buildMixedSnippets(qp);
			}
			holeID = 0;
			res += QCP2(c@at, mixed, unknownQuery());
			continue;
		}
		
		//check for easy cases QCP1a, QCP4a, and QCP4b
		query = buildEasyCaseQuery(c, index);
		if(!(query is unclassified)){
			res += query;
			continue;	
		}
		
		// check for QCP1b and QCP3a
		query = buildLiteralVariableQuery(qcpi, c, index);
		if(!(query is unclassified)){
			res += query;
			continue;	
		}
		
		// check for QCP4a and QCP3b
		query = buildMixedVariableQuery(qcpi, c, index);
		if(!(query is unclassified)){
			res += query;
			continue;	
		}
		
		// restrict QCP5 analysis to only calls to mysql_query to prevent chaining of QCP5 classifications (for now)
		//if(functionName := "mysql_query"){
			query = buildQCP5Query(qcpi, ca, c, index, functionName, seenBefore);
		//}
		
		if(!(query is unclassified)){
			res += query;
			continue;	
		}
		
		// query remained unclassified after all classifications, add it as unclassified
		res += query;
	}
	return res;
}

@doc{builds a Query structure for easy case (QCP1a,  QCP4a, or QCPb), if the query matches these cases. Otherwise, returns an unclassified query}
public Query buildEasyCaseQuery(Expr c, int index){
	if (! (index < size(c.parameters)) ) {
		println("Index not available for call at location <c@at>");
		return unclassified(c@at, 1);
	}
	if(actualParameter(scalar(string(s)),false) := c.parameters[index]){
		SQLQuery parsed;
		sql = replaceAll(replaceAll(s, "\n", " "), "\t", " ");
		try parsed = runParser(sql);
		catch: parsed = parseError();
		return QCP1a(c@at, sql, parsed);
	}
	// check for QCP4a (encapsed string)
	else if(actualParameter(s:scalar(encapsed(parts)), false) := c.parameters[index]){
		mixed = replaceAll(replaceAll(buildMixedSnippets(s), "\n", " "), "\t", " ");
		holeID = 0;
		SQLQuery parsed;
		try parsed = runParser(mixed);
		catch: parsed = parseError();
		return QCP4a(c@at, mixed, parsed);
	}
		
	// check for QCP4b (concatenation)
	else if(actualParameter(b:binaryOperation(left, right, concat()), false) := c.parameters[index]){
		mixed = replaceAll(replaceAll(buildMixedSnippets(b), "\n", " "), "\t", " ");
		holeID = 0;
		SQLQuery parsed;
		try parsed = runParser(mixed);
		catch: parsed = parseError();
		return QCP4b(c@at, mixed, parsed);
	}
	else{
		return unclassified(c@at,0);
	}
}

@doc{builds Query Structures for QCP1b or QCP3a if the query matches these cases. Otherwise, returns an unclassified query}
public Query buildLiteralVariableQuery(QCPSystemInfo qcpi, Expr c, int index){
	if (! (index < size(c.parameters)) ) {
		println("Index not available for call at location <c@at>");
		return unclassified(c@at,1);
	}

	if(actualParameter(var(name(name(queryVar))),false) := c.parameters[index]){
	
		containingScript = qcpi.sys.files[c@at.top];
		containingCFG = findContainingCFG(containingScript, qcpi.systemCFGs[c@at.top], c@at);
		callNode = findNodeForExpr(containingCFG, c);
			
		// If we have a standard literal assignment to the query var, then we can use the assigned value
		bool assignsScalarToQueryVar(CFGNode cn) {
			if (exprNode(assign(var(name(name(queryVar))),queryExpr),_) := cn) {
				simplifiedQueryExpr = simplifyExpr(replaceConstants(queryExpr,qcpi.iinfo), qcpi.sys.baseLoc);
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
				simplifiedQueryExpr = simplifyExpr(replaceConstants(queryExpr,qcpi.iinfo), qcpi.sys.baseLoc);
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
				simplifiedQueryExpr = simplifyExpr(replaceConstants(queryExpr,qcpi.iinfo), qcpi.sys.baseLoc);
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
				s = getOneFrom(literalGR.results).scalarVal.strVal;
				SQLQuery parsed;
				sql = replaceAll(replaceAll(s, "\n", " "), "\t", " ");
				try parsed = runParser(sql);
				catch: parsed = parseError();
				return QCP1b(c@at, sql, parsed);
			}
				
			// QCP3a (literal assignments distributed over control flow)
			if(size(literalGR.results) > 1){
				return  QCP3a(c@at, [r.scalarVal.strVal | r <- literalGR.results]);
			}
		}
	}
	return unclassified(c@at,0);
}

@doc{builds a Query Structue for QCP4c or QCP3b if the query matches these cases. Otherwise, returns an unclassified query}
public Query buildMixedVariableQuery(QCPSystemInfo qcpi, Expr c, int index){
	if (! (index < size(c.parameters)) ) {
		println("Index not available for call at location <c@at>");
		return unclassified(c@at,1);
	}

	if(actualParameter(var(name(name(queryVar))),false) := c.parameters[index]){
		containingScript = qcpi.sys.files[c@at.top];
		containingCFG = findContainingCFG(containingScript, qcpi.systemCFGs[c@at.top], c@at);
		callNode = findNodeForExpr(containingCFG, c);
		bool assignsConcatOrEncapsedToQueryVar(CFGNode cn){
			if (exprNode(assign(var(name(name(queryVar))),queryExpr),_) := cn) {
				simplifiedQueryExpr = simplifyExpr(replaceConstants(queryExpr,qcpi.iinfo), qcpi.sys.baseLoc);
				if (scalar(encapsed(_)) := simplifiedQueryExpr || binaryOperation(left,right,concat()) := simplifiedQueryExpr) {
					return true;
				}
			} 
			return false;			
		}
				
		bool notAssignsConcatOrEncapsedToQueryVar(CFGNode cn) {
			if (exprNode(assign(var(name(name(queryVar))),queryExpr),_) := cn) {
				simplifiedQueryExpr = simplifyExpr(replaceConstants(queryExpr,qcpi.iinfo), qcpi.sys.baseLoc);
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
				simplifiedQueryExpr = simplifyExpr(replaceConstants(queryExpr,qcpi.iinfo), qcpi.sys.baseLoc);
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
				mixed = replaceAll(replaceAll(buildMixedSnippets(getOneFrom(concatOrEncapsedGR.results)), "\n", " "), "\t", " ");
				holeID = 0;
				SQLQuery parsed;
				try parsed = runParser(mixed);
				catch: parsed = parseError();;
				return QCP4c(c@at, mixed, parsed);
			}
			
			// QCP3b check (QCP4 queries distributed over control flow)
			if(size(concatOrEncapsedGR.results) > 1){
				queries = {};
				for(r <- concatOrEncapsedGR.results){
					mixed = buildMixedSnippets(r);
					try parsed = runParser(mixed);
					catch: parsed = parseError();;
					queries += <mixed, parsed>;
					holeID = 0;
				}
				return QCP3b(c@at, queries);
			}
		}
	}
	return unclassified(c@at,0);
}

@doc{builds Query Snippets for QCP2 and QCP4 where there is a mixture of static and dynamic query parts}
private str buildMixedSnippets(Expr e){
	res = "";
	if(scalar(string(s)) := e){
		res = res + s;
	}
	else if(scalar(encapsed(parts)) := e){
		for(p <- parts){
			res += buildMixedSnippets(p);
		}
	}
	else if(binaryOperation(left, right, concat()) := e){
		res = res + buildMixedSnippets(left) + buildMixedSnippets(right);
	}
	else{
		res = res + " ?<holeID> ";//symbol for dynamic query part
		holeID = holeID + 1;
	}
	
	res = replaceAll(res,"\n", "");
	res = replaceAll(res, "\r", "");
	return res;
}

@doc {checks for QCP2 occurrences (cascading .= assignments) for functionName across the entire corpus}
public rel[str system, str version, ConcatBuilder occurrence] concatAssignments(str functionName) {
	rel[str system, str version, ConcatBuilder occurrence] res = { };
	corpus = getCorpus();
	for (systemName <- corpus, systemVersion := corpus[systemName]) {
		res = res + concatAssignments(systemName, systemVersion, functionName);
	}
	return res;
}

@doc {checks for QCP2 occurrences (cascading .= assignments) for functionName across the given system based on the provided name and version}
public rel[str system, str version, ConcatBuilder occurrence] concatAssignments(str systemName, str systemVersion, str functionName) {
	qcpi = readQCPSystemInfo(p,v);
	return { < systemName, systemVersion > } join concatAssignments(qcpi, functionName);
}

@doc {checks for QCP2 occurrences (cascading .= assignments) for functionName across the entire system}
public set[ConcatBuilder] concatAssignments(QCPSystemInfo qcpi, str functionName) {
	set[ConcatBuilder] res = { };
	
	for (scriptLoc <- qcpi.sys.files) {
		Script scr = qcpi.sys.files[scriptLoc];
		
		// Find calls to mysql_query in this script that use a variable to store the query. We want to
		// check to see which queries formed using concatenations reach this query.
		queryCalls = { < queryCall, varName, queryCall@at > | 
			/queryCall:call(name(name(functionName)), [actualParameter(var(name(name(varName))),_),*_]) := scr };
		
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
					scriptCFGs = qcpi.systemCFGs[scriptLoc];
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
					res = res + { concatBuilder(varName, queryParts, firstPart@at, queryCallExpr, queryCallLoc) | < queryCallExpr, queryCallLoc > <- allUsingQueries };
				}
			}
		}
	}
	
	return res;
}

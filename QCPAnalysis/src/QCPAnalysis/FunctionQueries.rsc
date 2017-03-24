module QCPAnalysis::FunctionQueries

import QCPAnalysis::AbstractQuery;
import QCPAnalysis::QCPCorpus;
import QCPAnalysis::BuildQueries;
import QCPAnalysis::QCPSystemInfo;

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
import List;
import IO;

@doc{builds a query if it is classified as QCP5, otherwise returns an unclassified query}
public Query buildQCP5Query(QCPSystemInfo qcpi, set[ConcatBuilder] ca, Expr c, int index, str functionName, set[str] seenBefore) {
	if (! (index < size(c.parameters)) ) {
		println("Index not available for call at location <c@at>");
		return unclassified(c@at);
	}
	
	if (functionName in seenBefore) {
		return unclassified(c@at);
	}

	seenBefore = seenBefore + functionName;
	
	if(actualParameter(var(name(name(queryVar))),false) := c.parameters[index]){	
	
		containingScript = qcpi.sys.files[c@at.top];
		containingCFG = findContainingCFG(containingScript, qcpi.systemCFGs[c@at.top], c@at);
		callNode = findNodeForExpr(containingCFG, c);
		entryNode = getEntryNode(containingCFG);

		if (entryNode is functionEntry) {
			// Find the function in the script that contains the call
			// TODO: Should we extract defs into info as well?
			containingFunction = getOneFrom({s | /s:function(fn,_,_,_) := qcpi.sys, fn == entryNode.functionName, c@at < s@at});
			paramNames = [p.paramName | p <- containingFunction.params];
			if(queryVar in paramNames){
				// record index in case function has multiple params (we are only interested in the query param for now)
				int newIndex = indexOf(paramNames, queryVar);
				println("Call at <c@at>, in function at <containingFunction@at>, parameter <newIndex>, name <queryVar>");
				paramQueries = buildParamQueries(qcpi, ca, entryNode.functionName, containingFunction@at, newIndex, seenBefore);
				return QCP5(c@at, entryNode.functionName, paramQueries);
			}			
		}		
		
		if(methodEntry(className, methodName,_) := entryNode){
			// find the method in the script matching the entryNode and see if queryVar is in its parameters
			containingClass = getOneFrom({cl | /Stmt cl <- containingScript.body, classDef(class(className,_,_,_,_)) := cl});
			containingMethod = getOneFrom({m | m <- containingClass.classDef.members, method(methodName,_,_,_,_) := m});
			paramNames = [p.paramName | p <- containingMethod.params];
			if(queryVar in paramNames){
				// record index in case method has multiple params (we are only interested in the query param for now)
				int newIndex = indexOf(paramNames, queryVar);
				paramQueries = buildParamQueries(qcpi, ca, className, methodName, containingMethod@at, newIndex, seenBefore);
				return QCP5(c@at, methodName, paramQueries);
				//return QCP5(c@at, methodName, []);
			}
		}
	}
	return unclassified(c@at);
}

@doc{performs our query modeling function on calls to a particular function as if it were a call to mysql_query (as in cases of QCP5)}
public list[Query] buildParamQueries(QCPSystemInfo qcpi, set[ConcatBuilder] ca, str functionName, loc functionLoc, int index, set[str] seenBefore) {
	// get all calls to this function
	callingLocs = qcpi.cg[functionTarget(functionName,functionLoc)];
	functionCalls = qcpi.functionCalls[callingLocs, functionName];
	
	// run our query modeling function on the query parameters to the calls
	return buildQueriesSystem(qcpi, functionCalls, ca, functionName = functionName, index = index, seenBefore = seenBefore);
}

public list[Query] buildParamQueries(QCPSystemInfo qcpi, set[ConcatBuilder] ca, str className, str methodName, loc methodLoc, int index, set[str] seenBefore) {
	// get all calls to this method
	callingLocs = qcpi.cg[methodTarget(className,methodName,methodLoc)];
	methodCalls = qcpi.methodCalls[callingLocs, methodName];
	
	// run our query modeling function on the query parameters to the calls
	return buildQueriesSystem(qcpi, methodCalls, ca, functionName = methodName, index = index, seenBefore = seenBefore);
}
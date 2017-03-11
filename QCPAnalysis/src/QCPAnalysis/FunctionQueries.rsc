module QCPAnalysis::FunctionQueries

import QCPAnalysis::AbstractQuery;
import QCPAnalysis::QCPCorpus;
import QCPAnalysis::BuildQueries;

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
public Query buildQCP5Query(System pt, set[ConcatBuilder] ca,  map[loc, map[NamePath, CFG]] cfgs, Expr c, int index){

	if(actualParameter(var(name(name(queryVar))),false):= c.parameters[index]){
	
		containingScript = pt.files[c@at.top];
		containingCFG = findContainingCFG(containingScript, cfgs[c@at.top], c@at);
		callNode = findNodeForExpr(containingCFG, c);
		entryNode = getEntryNode(containingCFG);
		
		if(functionEntry(functionName) := entryNode){
			//find the function in the script matching the entryNode and see if queryVar is in its parameters
			containingFunction = getOneFrom({s | s <- containingScript.body, function(functionName, _,_,_) := s});
			paramNames = [p.paramName | p <- containingFunction.params];
			if(queryVar in paramNames){
				// record index in case function has multiple params (we are only interested in the query param for now)
				int newIndex = indexOf(paramNames, queryVar);
				paramQueries = buildParamQueries(pt, ca, functionName, containingFunction@at, newIndex);
				return QCP5(c@at, functionName, paramQueries);
			}
		}
		
		if(methodEntry(className, methodName) := entryNode){
			// find the method in the script matching the entryNode and see if queryVar is in its parameters
			containingClass = getOneFrom({cl | /Stmt cl <- containingScript.body, classDef(class(className,_,_,_,_)) := cl});
			containingMethod = getOneFrom({m | m <- containingClass.classDef.members, method(methodName,_,_,_,_) := m});
			paramNames = [p.paramName | p <- containingMethod.params];
			if(queryVar in paramNames){
				// record index in case method has multiple params (we are only interested in the query param for now)
				int newIndex = indexOf(paramNames, queryVar);
				paramQueries = buildParamQueries(pt, ca, className, methodName, containingMethod@at, newIndex);
				return QCP5(c@at, methodName, paramQueries);
			}
		}
	}
	return unclassified(c@at);
}

@doc{performs our query modeling function on calls to a particular function as if it were a call to mysql_query (as in cases of QCP5)}
public list[Query] buildParamQueries(System pt, set[ConcatBuilder] ca, str functionName, loc functionLoc, int index){
	cg = computeSystemCallGraph(pt);
	// get all calls to this function
	functionCalls = [c | /c:call(name(name(functionName)),_) := cg, functionCallee(functionName,functionLoc) in c@callees];
	// run our query modeling function on the query parameters to the calls
	return buildQueriesSystem(pt, functionCalls, ca, functionName = functionName, index = index);
}

public list[Query] buildParamQueries(System pt, set[ConcatBuilder] ca, str className, str methodName, loc methodLoc, int index){
	/*cg = computeSystemCallGraph(pt);
	methodCalls = [mc | /mc:methodCall(_,name(name(methodName)),_) := cg,methodCallee(className,methodName,methodLoc) in mc@callees];
	return buildQueriesSystem(pt, methodCalls, ca, functionName = methodName, index = index);
	
	
	The above code has a bug where every method is processed rather than just relevant ones...
	*/
	return [];
}
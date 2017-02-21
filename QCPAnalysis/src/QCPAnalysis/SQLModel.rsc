module QCPAnalysis::SQLModel

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::analysis::cfg::CFG;
import lang::php::analysis::cfg::BuildCFG;
import lang::php::analysis::cfg::Util;
import lang::php::analysis::cfg::FlowEdge;

import Set;
import IO;
import Relation;

// TODO: Currently, this focuses just on function calls. We need to also add
// support for method calls to pick up calls to new APIs, such as the PDO
// libraries.

public rel[loc callLoc, CFG graph] cfgsWithCalls(System s, set[str] functionNames = {}, set[str] methodNames = {}) {
	rel[loc callLoc, CFG graph] res = { };
	for (l <- s.files) {
		cfgsForFile = buildCFGs(s.files[l], buildBasicBlocks=false);
		
		// Find the relevant function calls
		res = res + { < cn@at, cfgsForFile[np] > | np <- cfgsForFile, n:exprNode(cn:call(name(name(fname)),_), _) <- cfgsForFile[np].nodes, fname in functionNames };
	}
	return res;
}

public Expr queryParameter(exprNode(call(name(name("mysql_query")),[actualParameter(Expr e,_),_*]),_)) = e;
public default Expr queryParameter(CFGNode n) { throw "Unexpected parameter <n>"; }

public CFG reduceCFG(CFG inputGraph, loc callLoc) {
	// First, find the node representing the call
	possibleMatches = { n | n:exprNode(cn:call(_,_),_) <- inputGraph.nodes, cn@at == callLoc };
	
	// If we have more than one, this is a problem -- we should only have one,
	// so this would be a bug
	if (size(possibleMatches) > 1) {
		throw "Error, should have at most one match for node at <callLoc>, instead have <size(possibleMatches)>";
	} else if (size(possibleMatches) == 0) {
		println("WARNING: No matches found in CFG for call at location <callLoc>");
		return inputGraph;
	}
	
	startNode = getOneFrom(possibleMatches);
	
	cfgGraph = invert(cfgAsGraph(inputGraph));
	reachableNodes = (cfgGraph*)[startNode];
	cfgGraph = { < gn1, gn2 > | < gn1, gn2 > <- cfgGraph, gn1 in reachableNodes, gn2 in reachableNodes };
	
	// TODO: Now, starting at the call node, see what names are used; then we can
	// reason backwards to see how those are made
	queryVars = { vn | /var(name(name(vn))) := queryParameter(startNode) };
	
	println("Starting with <size(queryVars)> variables");
	set[CFGNode] assignments = { };
	
	solve(queryVars, assignments) {
		directAssignments = { an | an:exprNode(assign(var(name(name(vn))),_),_) <- reachableNodes, vn in queryVars };
		println("Found <size(directAssignments)> assignments");
		assignments = assignments + directAssignments;
		queryVars = queryVars + { vn | /var(name(name(vn))) := assignments };
		println("Expanded to <size(queryVars)> variables");
	}
	
	inputGraph.nodes = reachableNodes;
	inputGraph.edges = { e | e <- inputGraph.edges, e.from in reachableNodes || e.to in reachableNodes };
	
	return inputGraph;
}
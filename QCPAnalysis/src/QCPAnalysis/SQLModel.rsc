module QCPAnalysis::SQLModel

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::analysis::cfg::CFG;
import lang::php::analysis::cfg::BuildCFG;
import lang::php::analysis::cfg::Util;
import lang::php::analysis::cfg::FlowEdge;
import lang::php::analysis::cfg::Label;
import lang::php::util::Utils;
import lang::php::analysis::usedef::UseDef;
import lang::php::analysis::slicing::BasicSlicer;

import QCPAnalysis::Utils;
import QCPAnalysis::QCPSystemInfo;

import Set;
import IO;
import Relation;
import List;
import Map;

// TODO: Currently, this focuses just on function calls. We need to also add
// support for method calls to pick up calls to new APIs, such as the PDO
// libraries.

data SQLModel = sqlModel(rel[SQLModelNode, SQLModelNode] modelGraph, SQLModelNode topNode);

data SQLModelNode
	= literalNode(str literalFragment, Lab l)
	| nameUseNode(Name name, Lab l)
	| nameDefNode(Name name, DefExpr definingExpr, Lab l)
	| dynamicNode(list[SQLModel] fragments, Lab l)
	| conditionNode(Expr cond, SQLModel trueBranch, SQLModel falseBranch, Lab l)
	| emptyNode(Lab l)
	| computedNode(Expr e, Lab l)
	;

public rel[loc callLoc, CFG graph] cfgsWithCalls(System s, set[str] functionNames = {}, set[str] methodNames = {}) {
	rel[loc callLoc, CFG graph] res = { };
	for (l <- s.files) {
		cfgsForFile = buildCFGs(s.files[l], buildBasicBlocks=false);
		
		// Find the relevant function calls
		res = res + { < cn@at, cfgsForFile[np] > | np <- cfgsForFile, n:exprNode(cn:call(name(name(fname)),_), _) <- cfgsForFile[np].nodes, fname in functionNames };
	}
	return res;
}

//public rel[Name, SQLModelNode] cfgNode2ModelNode(exprNode(Expr e, Lab l)) = expr2ModelNode(e,l);
//public rel[Name, SQLModelNode] cfgNode2ModelNode(stmtNode(Stmt s, Lab l)) = stmt2ModelNode(s,l);
//
//public rel[Name, SQLModelNode] cfgNode2ModelNode(functionEntry(_,_)) = { };
//public rel[Name, SQLModelNode] cfgNode2ModelNode(functionExit(_,_)) = { };
//public rel[Name, SQLModelNode] cfgNode2ModelNode(methodEntry(_,_,_)) = { };
//public rel[Name, SQLModelNode] cfgNode2ModelNode(methodExit(_,_,_)) = { };
//public rel[Name, SQLModelNode] cfgNode2ModelNode(scriptEntry(_)) = { };
//public rel[Name, SQLModelNode] cfgNode2ModelNode(scriptExit(_)) = { };
//
//public default rel[Name, SQLModelNode] cfgNode2ModelNode(CFGNode n) {
//	throw "Unhandled CFG node in cfgNode2ModelNode: <n>";
//}

//public rel[Name, SQLModelNode] expr2ModelNode(var(name(name(str s))), Lab l) = { < varName(s), nameUseNode(varName(s), l) > };
//public rel[Name, SQLModelNode] expr2ModelNode(assign(var(name(name(str s))), Expr e), Lab l) = { < varName(s), nameDefNode(varName(s), e, l) > };
//public default rel[Name, SQLModelNode] expr2ModelNode(Expr e, Lab l) = { < computedName(e), computedNode(e,l) > };
//
//public default rel[Name, SQLModelNode] expr2StmtNode(Stmt s, Lab l) = { };

//public Expr queryParameter(call(name(name("mysql_query")),[actualParameter(Expr e,_),_*])) = e;
public Expr queryParameter(exprNode(call(name(name("mysql_query")),[actualParameter(Expr e,_),_*]),_)) = e;
public default Expr queryParameter(CFGNode n) { throw "Unexpected parameter <n>"; }

public Expr getQueryExpr(call(name(name("mysql_query")),[actualParameter(Expr e,_),*_])) = e;
public default Expr getQueryExpr(Expr e) { throw "Unhandled query expression <e>"; }
 
//public list[SQLModelNode] buildQueryFragments(Lab l, scalar(string(str s))) = [ literalNode(s, l) ];
//public list[SQLModelNode] buildQueryFragments(Lab l, var(name(name(str s)))) = [ nameNode(s, l) ];
//public list[SQLModelNode] buildQueryFragments(Lab l, fetchArrayDim(var(name(name(str s))),_)) = [ nameNode(s, l) ];
//public list[SQLModelNode] buildQueryFragments(Lab l, binaryOperation(Expr lft, Expr rt, concat())) = buildQueryFragments(lft, l) + buildQueryFragments(rt, l);
//public list[SQLModelNode] buildQueryFragments(Lab l, scalar(encapsed(list[Expr] pieces))) = [ *buildQueryFragments(p, l) | p <- pieces ];
//public list[SQLModelNode] buildQueryFragments(Lab l, Expr e) = [ computedNode(e, l) ];

public SQLModelNode getNodeRep(exprNode(call(name(name(fn)),[actualParameter(scalar(string(str s)),_),_*]), Lab l)) = literalNode(s,l);
public SQLModelNode getNodeRep(exprNode(call(name(name(fn)),[actualParameter(Expr e,_),_*]), Lab l)) = computedNode(e,l) when scalar(string(_)) !:= e;
public default SQLModelNode getNodeRep(CFGNode n) { throw "Unexpected node: <n>"; }

public SQLModel buildModel(QCPSystemInfo qcpi, loc callLoc, set[str] functions = { "mysql_query" }) {
	inputSystem = qcpi.sys;
	baseLoc = inputSystem.baseLoc;
	inputCFG = findContainingCFG(inputSystem.files[callLoc.top], qcpi.systemCFGs[callLoc.top], callLoc);
	iinfo = qcpi.iinfo;
	inputNode = findNodeForExpr(inputCFG, callLoc);

	d = definitions(inputCFG);
	u = uses(inputCFG, d);
	slicedCFG = basicSlice(inputCFG, inputNode, u[inputNode.l]<0>);
	nodesForLabels = ( n.l : n | n <- inputCFG.nodes );
	
	firstNode = getNodeRep(inputNode);
	rel[SQLModelNode, SQLModelNode] modelGraph = { < firstNode, nameUseNode(usedName, definedAt) > | < usedName, definedAt > <- u[inputNode.l] };
	solve(modelGraph) {
		modelGraph = modelGraph +
			{ < nameUseNode(usedName, definedAt1), nameDefNode(definedName, definingExpr, definedAt2) > | nameUseNode(usedName, definedAt1) <- modelGraph<1>, < definedName, definingExpr, definedAt2 > <- d[definedAt1] } +
			{ < nameDefNode(definedName, definingExpr, definedAt1), nameUseNode(usedName, definedAt2) > | nameDefNode(definedName, definingExpr, definedAt1) <- modelGraph<0>, < usedName, definedAt2 > <- u[definedAt1] }; 
	}

	println("Computed model graph is size <size(modelGraph)>");
	
	return sqlModel(modelGraph, firstNode);
}

data SQLPiece = staticPiece(str literal) | dynamicPiece();
alias SQLYield = list[SQLPiece];

public set[SQLYield] yields(SQLModel m) {
	if (literalNode(fragment) := m) {
		return { [ staticPiece(fragment) ] };
	}
}

public void testcode() {
	pt = loadBinary("Schoolmate", "1.5.4");
	literalQueryLoc = |home:///PHPAnalysis/systems/Schoolmate/schoolmate_1.5.4/EditClass.php|(956,57,<29,0>,<29,0>);
	qloc = |home:///PHPAnalysis/systems/Schoolmate/schoolmate_1.5.4/DeleteFunctions.php|(5364,87,<165,0>,<165,0>);
	locInWhile = |home:///PHPAnalysis/systems/Schoolmate/schoolmate_1.5.4/ManageGrades.php|(7737,98,<213,0>,<213,0>);
	locInIf = |home:///PHPAnalysis/systems/Schoolmate/schoolmate_1.5.4/Registration.php|(860,115,<22,0>,<22,0>);
	cfgs = cfgsWithCalls(pt,functionNames={"mysql_query"});
}
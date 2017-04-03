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

import Set;
import IO;
import Relation;

// TODO: Currently, this focuses just on function calls. We need to also add
// support for method calls to pick up calls to new APIs, such as the PDO
// libraries.

data SQLModel = sqlModel();

public rel[loc callLoc, CFG graph] cfgsWithCalls(System s, set[str] functionNames = {}, set[str] methodNames = {}) {
	rel[loc callLoc, CFG graph] res = { };
	for (l <- s.files) {
		cfgsForFile = buildCFGs(s.files[l], buildBasicBlocks=false);
		
		// Find the relevant function calls
		res = res + { < cn@at, cfgsForFile[np] > | np <- cfgsForFile, n:exprNode(cn:call(name(name(fname)),_), _) <- cfgsForFile[np].nodes, fname in functionNames };
	}
	return res;
}

//public Expr queryParameter(call(name(name("mysql_query")),[actualParameter(Expr e,_),_*])) = e;
public Expr queryParameter(exprNode(call(name(name("mysql_query")),[actualParameter(Expr e,_),_*]),_)) = e;
public default Expr queryParameter(CFGNode n) { throw "Unexpected parameter <n>"; }


public SQLModel buildModel(CFG inputCFG, loc callLoc) {
	inputNode = getNodeForExpr(inputCFG, callLoc);
	d = definitions(inputCFG);
	u = uses(inputCFG, d);
	
	slicedCFG = basicSlice(inputCFG, inputNode, u[inputNode.l]<0>);
	
	return sqlModel();
}

public void testcode() {
	pt = loadBinary("Schoolmate", "1.5.4");
	qloc = |home:///PHPAnalysis/systems/Schoolmate/schoolmate_1.5.4/DeleteFunctions.php|(5364,87,<165,0>,<165,0>);
	locInWhile = |home:///PHPAnalysis/systems/Schoolmate/schoolmate_1.5.4/ManageGrades.php|(7737,98,<213,0>,<213,0>);
	locInIf = |home:///PHPAnalysis/systems/Schoolmate/schoolmate_1.5.4/Registration.php|(860,115,<22,0>,<22,0>);
	cfgs = cfgsWithCalls(pt,functionNames={"mysql_query"});
}
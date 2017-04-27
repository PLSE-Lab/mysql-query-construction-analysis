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
import lang::php::analysis::evaluators::Simplify;
import lang::php::analysis::includes::QuickResolve;

import QCPAnalysis::Utils;
import QCPAnalysis::QCPSystemInfo;

import Set;
import IO;
import Relation;
import List;
import Map;
import analysis::graphs::Graph;

// TODO: Currently, this focuses just on function calls. We need to also add
// support for method calls to pick up calls to new APIs, such as the PDO
// libraries.

// Fragment can be
// 1) literal
// 2) name
// 3) dynamic
// 4) list of fragments
// 5) concat
data QueryFragment
	= literalFragment(str literalFragment)
	| nameFragment(Name name)
	| dynamicFragment(Expr fragmentExpr)
	| compositeFragment(list[QueryFragment] fragments)
	| concatFragment(QueryFragment left, QueryFragment right)
	| unknownFragment()
	;

data SQLModel = sqlModel(rel[Lab, QueryFragment, Lab, QueryFragment] fragmentRel, QueryFragment startFragment);

@doc{Turn a specific expression into a possibly-nested query fragment.}
public QueryFragment expr2qf(Expr ex, QCPSystemInfo qcpi, bool simplify=true) {
	QueryFragment expr2qfAux(Expr e) {
		if (simplify) {
			e = simplifyExpr(replaceConstants(e,qcpi.iinfo), qcpi.sys.baseLoc);
		}
		
		switch(e) {
			case scalar(string(s)) :
				return literalFragment(s);
				
			case scalar(encapsed(parts)) : {
				return compositeFragment([expr2qfAux(part) | part <- parts ]);
			}
			
			case binaryOperation(left, right, concat()) :
				return concatFragment(expr2qfAux(left), expr2qfAux(right));
				
			case assignWOp(left, right, concat()) :
				return concatFragment(expr2qfAux(left), expr2qfAux(right));
			
			case var(name(name(vn))) :
				return nameFragment(varName(vn));
			
			case fetchArrayDim(var(name(name(vn))),_) :
				return nameFragment(varName(vn));
				
			case var(expr(Expr e)) :
				return nameFragment(computedName(e));
			
			case fetchArrayDim(var(expr(Expr e)),_) :
				return nameFragment(computedName(e));
			
			case propertyFetch(target, name(name(vn))) :
				return nameFragment(propertyName(target, vn));
				
			case propertyFetch(target, Expr e) :
				return nameFragment(computedPropertyName(target, e));
			
			case staticPropertyFetch(name(name(target)), name(name(vn))) :
				return nameFragment(staticPopertyName(target, vn));
				
			case staticPropertyFetch(name(name(target)), Expr e) :
				return nameFragment(computedStaticPopertyName(target, e));
			
			case staticPropertyFetch(expr(Expr target), name(name(vn))) :
				return nameFragment(computedStaticPopertyName(target, vn));
				
			case staticPropertyFetch(expr(Expr target), Expr e) :
				return nameFragment(computedStaticPopertyName(target, e));
		
			default:
				return dynamicFragment(e);
		}
	}
	
	return expr2qfAux(ex);
}

public rel[Lab, QueryFragment, Lab, QueryFragment] expandFragment(Lab l, QueryFragment qf, Uses u, Defs d, QCPSystemInfo qcpi) {
	rel[Lab, QueryFragment, Lab, QueryFragment] res = { };
	
	// TODO: Do we want all names in the fragment, or just leaf node names?
	set[Name] usedNames = { n | /nameFragment(Name n) := qf };
	println("Found <size(usedNames)> names in fragment");
	
	for (n <- usedNames, ul <- u[l, n], < de, dl > <- d[ul, n]) {
		if (de is defExpr) {
			newFragment = expr2qf(de.e, qcpi);
			res = res + < l, qf, dl, newFragment >;
		} else {
			res = res + < l, qf, dl, unknownFragment() >;
		}
	}
	
	return res;
} 
public rel[loc callLoc, CFG graph] cfgsWithCalls(System s, set[str] functionNames = {}, set[str] methodNames = {}) {
	rel[loc callLoc, CFG graph] res = { };
	for (l <- s.files) {
		cfgsForFile = buildCFGs(s.files[l], buildBasicBlocks=false);
		
		// Find the relevant function calls
		res = res + { < cn@at, cfgsForFile[np] > | np <- cfgsForFile, n:exprNode(cn:call(name(name(fname)),_), _) <- cfgsForFile[np].nodes, fname in functionNames };
	}
	return res;
}

public Expr getQueryExpr(call(name(name("mysql_query")),[actualParameter(Expr e,_),*_])) = e;
public default Expr getQueryExpr(Expr e) { throw "Unhandled query expression <e>"; }
 
public Expr queryParameter(exprNode(Expr e,_)) = getQueryExpr(e);
public default Expr queryParameter(CFGNode n) { throw "Unexpected parameter <n>"; }
 
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
	
	queryExp = queryParameter(inputNode);
	startingFragment = expr2qf(queryExp, qcpi);
	rel[Lab, QueryFragment, Lab, QueryFragment] res = { };
	solve(res) {
		for ( < l, f > <- (res<2,3> + < inputNode.l, startingFragment>) ) {
			res = res + expandFragment(l, f, u, d, qcpi);
		} 
	}
	
	return sqlModel(res, startingFragment);
}

public QueryFragment testFragments(str exprText) {
	QCPSystemInfo qcpi = readQCPSystemInfo("Schoolmate","1.5.4");
	inputExpr = parsePHPExpression(exprText);
	return expr2qf(inputExpr, qcpi);
}

//data SQLPiece = staticPiece(str literal) | dynamicPiece();
//alias SQLYield = list[SQLPiece];
//
//public set[SQLYield] yields(SQLModel m) {
//	if (literalNode(fragment) := m) {
//		return { [ staticPiece(fragment) ] };
//	}
//}

public void testcode() {
	pt = loadBinary("Schoolmate", "1.5.4");
	literalQueryLoc = |home:///PHPAnalysis/systems/Schoolmate/schoolmate_1.5.4/EditClass.php|(956,57,<29,0>,<29,0>);
	qloc = |home:///PHPAnalysis/systems/Schoolmate/schoolmate_1.5.4/DeleteFunctions.php|(5364,87,<165,0>,<165,0>);
	locInWhile = |home:///PHPAnalysis/systems/Schoolmate/schoolmate_1.5.4/ManageGrades.php|(7737,98,<213,0>,<213,0>);
	locInIf = |home:///PHPAnalysis/systems/Schoolmate/schoolmate_1.5.4/Registration.php|(860,115,<22,0>,<22,0>);
	cfgs = cfgsWithCalls(pt,functionNames={"mysql_query"});
}
module src::lang::php::analysis::sql::Utils

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::analysis::cfg::CFG;
import lang::php::analysis::includes::IncludesInfo;
import lang::php::analysis::evaluators::Simplify;
import lang::php::analysis::includes::QuickResolve;

@doc{Run the simplifier on the parameters being passed to this function}
public Expr simplifyParams(Expr c:call(NameOrExpr funName, list[ActualParameter] parameters), loc baseLoc, IncludesInfo iinfo) {
	list[ActualParameter] simplifiedParameters = [];
	for (p:actualParameter(Expr expr, bool byRef, bool isPacked) <- parameters) {
		simplifiedParameters += p[expr=simplifyExpr(replaceConstants(expr,iinfo), baseLoc)];
	}
	return c[parameters=simplifiedParameters];
}

@doc{Run the simplifier on the parameters being passed to this method}
public Expr simplifyParams(Expr c:methodCall(_,NameOrExpr methodName, list[ActualParameter] parameters), loc baseLoc, IncludesInfo iinfo) {
	list[ActualParameter] simplifiedParameters = [];
	for (p:actualParameter(Expr expr, bool byRef, bool isPacked) <- parameters) {
		simplifiedParameters += p[expr=simplifyExpr(replaceConstants(expr,iinfo), baseLoc)];
	}
	return c[parameters=simplifiedParameters];
}
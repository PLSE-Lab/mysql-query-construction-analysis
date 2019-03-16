module lang::php::analysis::sql::Utils

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::analysis::cfg::CFG;
import lang::php::analysis::includes::IncludesInfo;
import lang::php::analysis::evaluators::Simplify;
import lang::php::analysis::includes::QuickResolve;
import lang::php::util::Utils;

import IO;

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

private loc sqlCorpusLoc = |file:///Users/mhills/PHPAnalysis/sql-corpus|;

public loc getCorpusLoc() {
	return sqlCorpusLoc;
}

public set[str] getSQLSystems() {
	return { l.file | l <- sqlCorpusLoc.ls, isDirectory(l) };
}

public System loadSQLSystem(str systemName) {
	return loadBinary(systemName, "current");
}

alias CallRel = rel[str systemName, str callName, Expr callExpr, loc at];

public CallRel getSystemCalls(System pt) {
	if (! (pt has name)) {
		throw "Should only use named systems";
	}
	
	return { < pt.name, cn, c, c@at > | /c:call(name(name(str cn)),_) := pt, /mysql/ := cn };
}
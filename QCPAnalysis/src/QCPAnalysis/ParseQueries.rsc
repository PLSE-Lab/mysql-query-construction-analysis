module QCPAnalysis::ParseQueries

import QCPAnalysis::AbstractQuery;
import QCPAnalysis::QCPCorpus;

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

// functionality for parsing queries into
// abstract representation of their construction


public map[str, list[Query]] parseQueriesCorpus(){
	Corpus corpus = getCorpus();
	res = ();
	for(p <- corpus, v := corpus[p]){
		pt = loadBinary(p,v);
		if (!pt has baseLoc) {
			println("Skipping system <p>, version <v>, no base loc included");
			continue;
		}
		IncludesInfo iinfo = loadIncludesInfo(p, v);
		calls = [ c | /c:call(name(name("mysql_query")),_) := pt ];
		simplified = [s | c <- calls, s := simplifyParams(c, pt.baseLoc, iinfo)];
		println("Calls in system <p>, version <v> (total = <size(calls)>):");
		neededCFGs = ( l : buildCFGs(pt.files[l], buildBasicBlocks=false) | l <- { c@at.top | c <- calls } );
		queries = parseQueriesSystem(pt, calls, iinfo, neededCFGs);
		res += ("<p>_<v>" : queries);
	}
	return res;
}


private list[Query] parseQueriesSystem(System pt, list[Expr] simplified, IncludesInfo iinfo, map[loc, map[NamePath,CFG]] neededCFGs){
	res = [];
	for(c:call(name(name("mysql_query")), params) <- simplified){
	
		// check for QCP1a (parameter is a literal)
		if(actualParameter(scalar(string(s)), _) := head(params)){
			res += QCP1(c@at, s);
		}
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
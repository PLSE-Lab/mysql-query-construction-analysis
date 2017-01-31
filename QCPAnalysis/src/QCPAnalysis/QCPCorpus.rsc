module QCPAnalysis::QCPCorpus

import lang::php::util::Corpus;
import lang::php::util::Utils;
import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::analysis::cfg::CFG;
import lang::php::analysis::cfg::BuildCFG;
import lang::php::analysis::includes::IncludesInfo;

import Node;
import ValueIO;
import Map;

private Corpus originalCorpus = (
	"faqforge" 		: "1.3.2",
	"geccBBlite" 	: "0.1",
	"Schoolmate" 	: "1.5.4",
	"WebChess" 		: "0.9.0"
	);
	
private Corpus newCorpus = (
	"firesoftboard" : "2.0.5",
	"MyPHPSchool"	: "0.3.1",
	"OMS"			: "1.0.1",
	"OpenClinic" 	: "0.8.2",
	"UseBB"			: "1.0.16",
	"web2project"	: "3.3",
	// 2017 additions below
	"inoERP" 		: "0.5.1",
	"PHPFusion"		: "7.02.07"
	);

public str getSensibleName("faqforge") = "FAQ Forge";
public str getSensibleName("firesoftboard") = "Fire-Soft-Board";
public default str getSensibleName(str p) = p;

private Corpus corpus = originalCorpus + newCorpus;


public Corpus getOriginalCorpus() = originalCorpus();
public Corpus getNewCorpus() = newCorpus();
public Corpus getCorpus() = corpus;

public void buildCorpus() {
	for (p <- corpus, v := corpus[p]) {
		buildBinaries(p,v);
	}
}

public void buildCorpusItem(str p, str v){
	if(p in corpus, v := corpus[p]){
		buildBinaries(p,v);
	}
	else
		throw "invalid corpus item or version";
}

public void buildCorpusInfo() {
	for (p <- corpus, v := corpus[p]) {
		buildCorpusInfo(p,v);
	}
}

public void buildCorpusInfo(str p, str v) {
	pt = loadBinary(p,v);
	buildIncludesInfo(pt);
}

public rel[str exprType, loc useLoc] exprTypesAndLocsInCorpus() {
	rel[str exprType, loc useLoc] res = { };
	for (p <- corpus, v := corpus[p]) {
		pt = loadBinary(p,v);
		
		// Get all the calls to mysql_query
		queriesRel = { < c, c@at > | /c:call(name(name("mysql_query")),_) := pt };
		
		// Extract out all the parameters
		params = { pi | c <- queriesRel<0>, pi <- c.parameters };
		
		// Find all the expression node names used in any of the parameters
		res = res + { < getName(e), e@at > | /Expr e := params };
	}
	return res;
}

public set[str] exprTypesInCorpus() = exprTypesAndLocsInCorpus()<0>;

public set[loc] locsExprType(str t) = exprTypesAndLocsInCorpus()[t];
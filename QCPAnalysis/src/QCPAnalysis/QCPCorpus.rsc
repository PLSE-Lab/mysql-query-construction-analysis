module QCPAnalysis::QCPCorpus

import lang::php::util::Corpus;
import lang::php::util::Utils;
import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::analysis::cfg::CFG;
import lang::php::analysis::cfg::BuildCFG;
import lang::php::analysis::includes::IncludesInfo;
import lang::php::analysis::signatures::Extract;
import lang::php::analysis::signatures::Summaries;

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
	"PHPFusion"		: "7.02.07",
	"LinPHA"		: "1.3.4",
	"Timeclock"		: "1.04",
	"PHPAgenda" 	: "2.2.12",
	"AddressBook"   : "8.2.5.2",
	"OcoMon"		: "2.0RC6"
	);

private map[str,int] systemNumbers = (
	"AddressBook" : 1,
	"faqforge" : 2,
	"firesoftboard" : 3,
	"geccBBlite" : 4,
	"inoERP" : 5,
	"LinPHA" : 6,
	"MyPHPSchool" : 7,
	"OcoMon" : 8,
	"OMS" : 9,
	"OpenClinic" : 10,
	"PHPAgenda" : 11,
	"PHPFusion" : 12,
	"Schoolmate" : 13,
	"Timeclock" : 14,
	"UseBB" : 15,
	"web2project" : 16,
	"WebChess" : 17
);

public map[str,int] getSystemsWithNumbers() = systemNumbers;

public map[int,str] getNumbersWithSystems() = invertUnique(systemNumbers);

public str getSystemForNumber(int n) {
	numbersAndSystems = getNumbersWithSystems();
	if (n in numbersAndSystems) {
		return numbersAndSystems[n];
	}
	return "There is no system with id <n>"; 
}

public System loadSystemForNumber(int n) {
	systemByNumber = invertUnique(systemNumbers);
	if (n in systemByNumber) {
		return loadBinary(systemByNumber[n], (originalCorpus+newCorpus)[systemByNumber[n]]);
	}
	throw "No system with number <n> exists";
}

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
	buildIncludesInfo(pt, forceBuild=true);
}

public void buildSummaries(){
	map[PageType,loc] pagePaths = getAllLibraryPages();
	extractSummaries(pagePaths);
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
module lang::php::analysis::sql::QCPCorpus

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
import IO;

private Corpus originalCorpus = (
	"faqforge" 		: "1.3.2",
	"geccBBlite" 	: "0.1",
	"Schoolmate" 	: "1.5.4",
	"WebChess" 		: "0.9.0"
	);
	
private Corpus corpus2017 = (
	"firesoftboard" : "2.0.5",
	"MyPHPSchool"	: "0.3.1",
	"OMS"			: "1.0.1",
	"OpenClinic" 	: "0.8.2",
	"UseBB"			: "1.0.16",
	"web2project"	: "3.3",
	"inoERP" 		: "0.5.1",
	"PHPFusion"		: "7.02.07",
	"LinPHA"		: "1.3.4",
	"Timeclock"		: "1.04",
	"PHPAgenda" 	: "2.2.12",
	"AddressBook"   : "8.2.5.2",
	"OcoMon"		: "2.0RC6"
	);
	
private Corpus corpus2018 = (
	"cpg" : "1.5.46",
	"mantisbt" : "2.10.0",
	"SugarCE" : "6.5.26",
	"orangehrm" : "4.0",
	"SchoolERP" : "1.0"
);

private lrel[str repoName, str fullName, int fileCount, int lineCount] top20 = [ 
	< "php-src", "php/php-src", 290, 18620 >,
	< "CodeIgniter", "bcit-ci/CodeIgniter", 280, 35597 >,
	< "WordPress", "WordPress/WordPress", 995, 232799 >,
	< "piwik", "piwik/piwik", 2581, 252161 >,
	< "opencart", "opencart/opencart", 2666, 227647 >,
	< "typecho", "typecho/typecho", 204, 23524 >,
	< "joomla-cms", "joomla/joomla-cms", 3690, 410378 >,
	< "PrestaShop", "PrestaShop/PrestaShop", 3027, 262360 >,
	< "adminer", "vrana/adminer", 144, 25367 >,
	< "phpspider", "owner888/phpspider", 30, 13875 >,
	< "KODExplorer", "kalcaddle/KODExplorer", 125, 58257 >,
	< "FrameworkBenchmarks", "TechEmpower/FrameworkBenchmarks", 274, 7765 >,
	< "moodle", "moodle/moodle", 10048, 1423013 >,
	< "Search-Replace-DB", "interconnectit/Search-Replace-DB", 6, 3113 >,
	< "PHP-MySQLi-Database-Class", "joshcam/PHP-MySQLi-Database-Class", 8, 2509 >,
	< "Bonfire", "ci-bonfire/Bonfire", 810, 94638 >,
	< "phpbb", "phpbb/phpbb", 1584, 286184 >,
	< "charisma", "usmanhalalit/charisma", 47, 8815 >,
	< "php-crud-api", "mevdschee/php-crud-api", 78, 10268 >,
	< "thinkphp", "top-think/thinkphp", 319, 51134 >
];

public list[str] getTop20Systems() = top20<0>;

public list[str] getTop20Repos() = top20<1>;

public lrel[str repoName, str fullName, int fileCount, int lineCount] getTop20Rel() = top20;

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
	"WebChess" : 17,
	"cpg" : 18,
	"mantisbt" : 19,
	"SugarCE" : 20,
	"orangehrm" : 21,
	"SchoolERP" : 22
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
		return loadBinary(systemByNumber[n], (originalCorpus+corpus2017+corpus2018)[systemByNumber[n]]);
	}
	throw "No system with number <n> exists";
}

public str getSensibleName("faqforge") = "FAQ Forge";
public str getSensibleName("firesoftboard") = "Fire-Soft-Board";
public default str getSensibleName(str p) = p;

private Corpus corpus = originalCorpus + corpus2017 + corpus2018;

public Corpus getOriginalCorpus() = originalCorpus;
public Corpus getCorpus2017() = corpus2017;
public Corpus getCorpus2018 = corpus2018;
public Corpus getCorpus() = getSQLSystemsAsCorpus(); //corpus;

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

public void buildCorpusInfo(bool forceBuild=true) {
	for (p <- corpus, v := corpus[p]) {
		buildCorpusInfo(p,v);
	}
}

public void buildCorpusInfo(str p, str v, bool forceBuild=true) {
	pt = loadBinary(p,v);
	buildIncludesInfo(pt, forceBuild=forceBuild);
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

private loc sqlCorpusLoc = |home:///PHPAnalysis/sql-corpus|;

public loc getSQLCorpusRoot() {
	return sqlCorpusLoc;
}

public set[str] defaultExcludes ={ "dolibarr", "mybb", "php-webshells", "php-malware-finder", "webshell"};

public set[str] getSQLSystems(set[str] excludes = defaultExcludes) {
	return { l.file | l <- sqlCorpusLoc.ls, isDirectory(l), l.file notin excludes };
}

public Corpus getSQLSystemsAsCorpus(set[str] excludes = defaultExcludes) {
	return ( s : "current" | s <- getSQLSystems(excludes=excludes) );
}

public set[loc] getSQLCorpus(set[str] excludes = defaultExcludes) {
	return { l | l <- sqlCorpusLoc.ls, isDirectory(l), l.file notin excludes };
}

public void buildSQLSystems(bool overwrite=true) {
	for (l <- getSQLCorpus()) {
		buildCurrent(l,overwrite=overwrite);
	}
}

public void buildSQLSystemsIncludes(bool forceBuild=true) {
	for (l <- getSQLCorpus()) {
		buildCorpusInfo(l.file,"current",forceBuild=forceBuild);
	}
}


public System loadSQLSystem(str systemName) {
	return loadBinary(systemName, "current");
}

/* The purpose of this module is to provide functions that
 * output results of analyzing query construction patterns
 */

module lang::php::analysis::sql::WriteResults

import lang::php::analysis::sql::QCPCorpus;
import lang::php::analysis::sql::SQLAnalysis;
import lang::php::analysis::sql::SQLModel;
import lang::php::analysis::sql::ModelAnalysis;

import lang::php::ast::AbstractSyntax;
import lang::php::util::Corpus;
import lang::php::util::Utils;
import lang::php::stats::SLOC;

import IO;
import ValueIO;
import List;
import String;
import Set;
import Map;
import util::Math;

loc tables = |project://QCPAnalysis/results/tables/|;
loc examples = |project://QCPAnalysis/results/examples/|;

/**
	getExample finds a random example (from either a specific system, or the whole corpus) for a 
	specified pattern and if one exists,
	1) generates a dot graph for the model of this example
	2) generates a latex figure for the yields, query strings, and SQL ASTs for the example
	3) returns the location of the example
*/
public loc getExample(str qcp, int exampleNum = 0){
	models = groupSQLModelsCorpus();
	return getExample(qcp, models, exampleNum);
}

public loc getExample(str qcp, str p, str v, int exampleNum = 0){
	models = groupSQLModels(p, v);
	return getExample(qcp, models, exampleNum);
}

private loc getExample(str qcp, map[str, SQLModelRel] models, int exampleNum){
	try 
		matches = models[qcp];
	catch : 
		throw "there are no models matching pattern: <qcp>";
	
	return writeExample(qcp, matches, exampleNum);
}

/**
	getPartialExample finds a QCP2 query in the corpus that is a partial statement (query text hole)
*/
public loc getPartialExample(int exampleNum = 0){
	models = groupSQLModelsCorpus()[qcp2];
	matches = {};
	for(m <- models){
		if(sameType(partial(t)) := m.info && t != "unknown"){
			matches += m;
		}
	}
	return writeExample(qcp2, matches, exampleNum);
}

/**
	getExamples finds numExamples random examples (from either a specific system, or the whole corpus) for a 
	specified pattern. and for each example:
		1) generates a dot graph for the model of this example
		2) generates a latex figure for the yields, query strings, and SQL ASTs for the example
		3) returns the location of the example
	if the number of existing examples < than numExamples, it returns the number of existing examples
*/

public set[loc] getExamples(int numExamples, str qcp, int exampleNum = 0){
	models = groupSQLModelsCorpus();
	return getExamples(qcp, models, exampleNum);
}

public set[loc] getExamples(int numExamples, str qcp, str p, str v, int exampleNum = 0){
	models = groupSQLModels(p, v);
	return getExamples(numExamples, qcp, models, exampleNum);
}

public set[loc] getExamples(int numExamples, str qcp, map[str, SQLModelRel] models, int exampleNum){
	try 
		matches = models[qcp];
	catch : 
		throw "there are no models matching pattern: <qcp>";
		
	res = {};
	for(i <- [0..numExamples]){
		if(size(matches) == 0){
			println("Only <i> models matching \"<qcp>\" could be found");
			break;
		}
		else{
			model = takeOneFrom(matches);
			res += writeExample(qcp, matches, exampleNum + i);
		}
	}
	return res;
}

private loc writeExample(str qcp, SQLModelRel matches, int exampleNum){
	exampleLoc = examples + "/<qcp>/<exampleNum>/";
	model = getOneFrom(matches);
	pattern = getOneFrom(invert(QCPs)[qcp]);
	pluralYield = size(model.yieldsRel<0>) > 1 ? "s" : "";
	pluralString = size(model.yieldsRel<1>) > 1 ? "s" : "";
	pluralAST = size(model.yieldsRel<2>) > 1 ? "s" : "";
	
	str latex = 
		"\\begin{figure*}
		'\\begin{enumerate}
		'\\item\\begin{lstlisting}
		'<for(y <- model.yieldsRel<0>){><y>\n<}>
		'\\end{lstlisting}
		'
		'\\item\\begin{lstlisting}
		'<for(y <- model.yieldsRel<1>){><y>\n<}>
		'\\end{lstlisting}
		'
		'\\item\\begin{lstlisting}
		'<for(y <- model.yieldsRel<2>){><y>\n<}>
		'\\end{lstlisting}
		'
		'\\end{enumerate}
		'\\caption{<toUpperCase(pattern)>: Yield<pluralYield>, Query String<pluralString>, and AST<pluralAST>.}
		'\\label{fig:<pattern>_<exampleNum>_yields}
		'\\end{figure*}
		";
	
	iprintToFile(exampleLoc + "model.txt", model.model);
	writeFile(exampleLoc + "<pattern>_<exampleNum>.tex", latex);
	renderSQLModelAsDot(model.model, exampleLoc + "<pattern>_<exampleNum>.dot");
	
	return model.location;
}

public lrel[str, real] qcpPercentages(Corpus corpus = getCorpus()){
	percentages = (qcp : 0.0 | qcp <- invert(QCPs));
	patternCounts = countPatternsInCorpus(corpus = corpus);
	total = (0 | it + e | qcp <- patternCounts, int e := patternCounts[qcp]);
	
	for(qcp <- percentages){
		if(qcp in patternCounts){
			percentages[qcp] += patternCounts[qcp];
			percentages[qcp] /= total;
		}
	}
	
	invMap = invert(percentages);
	sorted = sort(domain(invMap));
	return [<pattern, percent> | percent <- sorted, pattern <- {invertUnique(QCPs)[qcp] | qcp <- invMap[percent]}];
}

public lrel[str, real] fragmentCategoryPercentages(Corpus corpus = getCorpus()){
	fc = fcToAbbreviatedMap(totalFCForCorpus(corpus = corpus));
	percentages = (c : 0.0 | c <- fc);
	total = (0 | it + e | c <- fc, e := fc[c]);
	
	for(p <- percentages){
		percentages[p] += fc[p];
		percentages[p] /= total;
	}
	
	invMap = invert(percentages);
	sorted = sort(domain(invMap));
	return [<f, p> | p <- sorted, f <- invMap[p]];
}

public lrel[str, real] queryTypePercentages(Corpus corpus = getCorpus()){
	typeCounts = ("select" : 0, "insert" : 0, "update" : 0, "delete" : 0, "partial" : 0, "other" : 0);
	counts = extractClauseCounts(getModelsCorpus(corpus = corpus));
	for(t <- typeCounts){
		typeCounts[t] = counts[t]["total queries"];
	}
	total = (0 | it + e | t <- typeCounts, e := typeCounts[t]);
	
	invMap = invert(typeCounts);
	sorted = sort(domain(invMap));
	return [<t, toReal(p) / total> | p <- sorted, t <- invMap[p]];
}

public map[str, lrel[str, real]] clausePercentages(Corpus corpus = getCorpus()){
	sortedTypes = ["select", "insert", "update", "delete"];
	counts = extractClauseCounts(getModelsCorpus(corpus = corpus));
	percentages = (t : [] | t <- sortedTypes);
	for(t <- sortedTypes){
		for(clause <- counts[t]){
			if(clause == "total queries"){
				continue;
			}
			percentages[t] += <clause, toReal(counts[t][clause]) / counts[t]["total queries"]>;
		}
		percentages[t] = sort(percentages[t], bool(tuple[str, real] t1, tuple[str, real] t2) { return t1[1] < t2[1];});
	}
	
	return percentages;
}

public str queryTypeCountsAsLatexTable(bool captionOnTop = false, bool tablestar = false){
	Corpus corpus = getCorpus();
	pForSort = [ < toUpperCase(p), p > | p <- corpus ];
	pForSort = sort(pForSort, bool(tuple[str,str] t1, tuple[str,str] t2) { return t1[0] < t2[0]; });
	sortedTypes = ["select", "insert", "update", "delete", "partial", "other"];
	totals = <0, 0, 0, 0, 0, 0>;
	
	str getLine(str p, v){
		counts = extractClauseCounts(getModels(p, v));
		res = "<getSensibleName(p)>";
		int i = 0;
		for(t <- sortedTypes){
			count = counts[t]["total queries"];
			res += "& \\numprint{<count>}";
			totals[i] += count;
			i += 1;	
		}
		return res;
	}
	
	str getTotalLine(){
		res = "\\textbf{totals}";
		int i = 0;
		for(t <- sortedTypes){
			res +=  "& \\numprint{<totals[i]>}";
			i += 1;
		}
		return res;
	}
	
		str res =
		"\\npaddmissingzero
		'\\npfourdigitsep
		'\\begin{table<if(tablestar){>*<}>}
		'\\centering
		'<if(captionOnTop){>\\caption{The Corpus.\\label{tbl:php-corpus}}<}>
		'\\ra{1.2}
		'\\begin{tabularx}{\\columnwidth}{Xrrrrrrrr} \\toprule
		'System & SELECT & INSERT & UPDATE & DELETE & PARTIAL & OTHER\\\\ \\midrule
		'<for(<_,p> <- pForSort, v := corpus[p]){><getLine(p, v)> \\\\
		'<}>\\midrule
		'<getTotalLine()> \\\\
		'\\bottomrule
		'\\end{tabularx}
		'\\\\
		'\\vspace{2ex}
		'<if(!captionOnTop){>\\caption{Query Type Counts by System.\\label{tbl:query-type-counts}}<}>
		'\\end{table<if(tablestar){>*<}>}
		'\\npfourdigitnosep
		'\\npnoaddmissingzero
		";
		
	writeFile(tables + "queryTypeCounts.tex", res);
	return res;
}

public str clauseCountsAsLatexTable(bool captionOnTop = false, bool tablestar = false){
	counts = extractClauseCounts(getModelsCorpus());
	sortedTypes  = ["select", "insert", "update", "delete"];
	sortedSelect = ["select", "from", "where", "groupBy", "having", "orderBy", "limit", "joins", "total queries"];
	sortedInsert = ["into", "values", "setOps", "select", "onDuplicateSetOps", "total queries"];
	sortedUpdate = ["tables", "setOps", "where", "orderBy", "limit", "total queries"];
	sortedDelete = ["from", "using", "where", "orderBy", "limit", "total queries"];
	
	str getInnerClauseNameTable(list[str] clauses){
		res = "\\begin{tabular}{l}";
		for(c <- clauses){
			res = res + "<c>\\\\";
		}
		res = res + "\\end{tabular}";
		return res;
	}
	
	str getInnerClauseCountsTable(list[str] clauses, str queryType){
		clauseCounts = counts[queryType];
		res = "\\begin{tabular}{l}";
		for(c <- clauses){
			res = res + "\\numprint{<clauseCounts[c]>}\\\\";
		}
		res = res + "\\end{tabular}";
		return res;
	}
	
	str getLine(str queryType){
		res = "<queryType>";
		clauses = [];
		
		switch(queryType){
			case "select" : clauses = sortedSelect;
			case "insert" : clauses = sortedInsert;
			case "update" : clauses = sortedUpdate;
			case "delete" : clauses = sortedDelete;
		}
		
		res = res + "& <getInnerClauseNameTable(clauses)> & <getInnerClauseCountsTable(clauses, queryType)>";
		
		return res;
	}
	
	str res =
		"\\npaddmissingzero
		'\\npfourdigitsep
		'\\begin{table<if(tablestar){>*<}>}
		'\\centering
		'<if(captionOnTop){>\\caption{The Corpus.\\label{tbl:php-corpus}}<}>
		'\\ra{1.2}
		'\\begin{tabularx}{\\columnwidth}{Xlll} \\toprule
		'Query Type & Clauses & Counts \\\\ \\midrule
		'<for(t <- sortedTypes){><getLine(t)>\\\\ \\midrule
		'<}>
		'\\bottomrule
		'\\end{tabularx}
		'\\\\
		'\\vspace{2ex}
		'<if(!captionOnTop){>\\caption{Clause Counts for each Query Type.\\label{tbl:clause-counts}}<}>
		'\\end{table<if(tablestar){>*<}>}
		'\\npfourdigitnosep
		'\\npnoaddmissingzero
		";
		
	writeFile(tables + "clauseCounts.tex", res);
	return res;
}

public str qcp3bYieldComparisonAsLatexTable(bool captionOnTop = false, bool tablestar = false){
	models = groupSQLModelsCorpus()[qcp3b];
	counts = extractClauseComparison(models);
	sortedTypes  = ["select", "insert", "update", "delete"];
	sortedSelect = ["select", "from", "where", "groupBy", "having", "orderBy", "limit", "joins"];
	sortedInsert = ["into", "values", "setOps", "select", "onDuplicateSetOps"];
	sortedUpdate = ["tables", "setOps", "where", "orderBy", "limit"];
	sortedDelete = ["from", "using", "where", "orderBy", "limit"];
	
	str getInnerClauseNameTable(list[str] clauses){
		res = "\\begin{tabular}{l}";
		for(c <- clauses){
			res = res + "<c>\\\\";
		}
		res = res + "\\end{tabular}";
		return res;
	}
	
	str getInnerClauseComparisonCountTables(list[str] clauses, str queryType){
		clauseMap = counts[queryType];
		sameTable = "\\begin{tabular}{l}";
		someTable = "\\begin{tabular}{l}";
		differentTable = "\\begin{tabular}{l}";
		noneTable = "\\begin{tabular}{l}";
		
		for(c <- clauses){
			sameTable = sameTable + "<clauseMap[c].same>\\\\";
			someTable = someTable + "<clauseMap[c].some>\\\\";
			differentTable = differentTable + "<clauseMap[c].different>\\\\";
			noneTable = noneTable + "<clauseMap[c].none>\\\\";
		}
		
		sameTable = sameTable + "\\end{tabular}";
		someTable = someTable + "\\end{tabular}";;
		differentTable = differentTable + "\\end{tabular}";
		noneTable = noneTable + "\\end{tabular}";
		
		return "<sameTable> & <differentTable> & <someTable> & <noneTable>";
	}
	
	str getLine(str queryType){
		res = "<queryType>";
		clauses = [];
		
		switch(queryType){
			case "select" : clauses = sortedSelect;
			case "insert" : clauses = sortedInsert;
			case "update" : clauses = sortedUpdate;
			case "delete" : clauses = sortedDelete;
		}
		
		res = res + "& <getInnerClauseNameTable(clauses)> & <getInnerClauseComparisonCountTables(clauses, queryType)>";
		
		return res;
	}
	
	str res =
		"\\npaddmissingzero
		'\\npfourdigitsep
		'\\begin{table<if(tablestar){>*<}>}
		'\\centering
		'<if(captionOnTop){>\\caption{The Corpus.\\label{tbl:php-corpus}}<}>
		'\\ra{1.2}
		'\\begin{tabularx}{\\columnwidth}{Xllllll} \\toprule
		'Query Type & Clauses & Same & Different & Some & None\\\\ \\midrule
		'<for(t <- sortedTypes){><getLine(t)>\\\\ \\midrule
		'<}>
		'\\bottomrule
		'\\end{tabularx}
		'\\\\
		'\\vspace{2ex}
		'<if(!captionOnTop){>\\caption{Clause Comparison Counts for Pattern QCP3b.\\label{tbl:clause-comparison-counts}}<}>
		'\\end{table<if(tablestar){>*<}>}
		'\\npfourdigitnosep
		'\\npnoaddmissingzero
		";
		
	writeFile(tables + "qcp3bClauseComparison.tex", res);
	return res; 
	
	
}

public str qcpCountsAsLatexTable(bool captionOnTop = false, bool tablestar = false){
	Corpus corpus = getCorpus();
	counts = groupPatternCountsBySystem();
	totals = counts[<"total", "0.0">];
	delete(counts, "total");//total should be printed last
	
	pForSort = [ < toUpperCase(p), p > | p <- corpus ];
	pForSort = sort(pForSort, bool(tuple[str,str] t1, tuple[str,str] t2) { return t1[0] < t2[0]; });
	sortedQ = [qcp0, qcp1, qcp2, qcp3a, qcp3b, qcp3c, qcp4, otherType, parseError, unknown];
	
	str getLine(str p, str v){
		sysCounts = counts[<p, v>];
		res = "<getSensibleName(p)> & <v>";
		for(qcp <- sortedQ){
			res +=  "& \\numprint{<(qcp in sysCounts) ? sysCounts[qcp] : 0>}";
		}
		return res;
	}
	
	str getTotalLine(){
		res = "\\textbf{totals} & -";
		for(qcp <- sortedQ){
			res +=  "& \\numprint{<(qcp in totals) ? totals[qcp] : 0>}";
		}
		return res;
	}
	
	str res =
		"\\npaddmissingzero
		'\\npfourdigitsep
		'\\begin{table<if(tablestar){>*<}>}
		'\\centering
		'<if(captionOnTop){>\\caption{The Corpus.\\label{tbl:php-corpus}}<}>
		'\\ra{1.2}
		'\\begin{tabularx}{\\columnwidth}{Xrrrrrrrrrrr} \\toprule
		'System & Version & 0 & 1 & 2 & 3a & 3b & 3c & 4 & O & P & U \\\\ \\midrule
		'<for(<_,p> <- pForSort, v := corpus[p]){><getLine(p,v)> \\\\
		'<}>\\midrule
		'<getTotalLine()> \\\\
		'\\bottomrule
		'\\end{tabularx}
		'\\\\
		'\\vspace{2ex}
		'\\footnotesize
		' Counts for each QCP in each System. QCP names are abbreviated. Numbered patterns
		' are replaced by their number. O stands for other query type. P stands for parse error.
		' U stands for models that match no patterns.
		'<if(!captionOnTop){>\\caption{QCP Counts by System.\\label{tbl:qcp-counts}}<}>
		'\\end{table<if(tablestar){>*<}>}
		'\\npfourdigitnosep
		'\\npnoaddmissingzero
		";
		
	writeFile(tables + "qcpCounts.tex", res);
	return res;
}

public str fragmentCategoriesAsLatexTable(bool captionOnTop=false, bool tablestar = false){
	categoriesMap = sumFCMap(computeForCorpus());
	totals = fcToAbbreviatedMap(totalFCForCorpus());
	
	pForSort = [ < toUpperCase(p), p > | p <- getCorpus() ];
	pForSort = sort(pForSort, bool(tuple[str,str] t1, tuple[str,str] t2) { return t1[0] < t2[0]; });
	
	cForSort = ["L", "LV", "LP", "LC", "GV", "GP", "GC", "PN", "PP", "PC", "C"];
	
	str getLine(str p){
		fc = fcToAbbreviatedMap(categoriesMap[p]);
		res = "<getSensibleName(p)>";
		for(category <- cForSort, counts := fc[category]){
			res += "& <counts>";
		}
		return res; 
	}
	
	str getTotalLine(){
		res = "\\textbf{total}";
		for(category <- cForSort, counts := totals[category]){
			res += "& <counts>";
		}
		return res; 
	}
	
	str res =
		"\\npaddmissingzero
		'\\npfourdigitsep
		'\\begin{table<if(tablestar){>*<}>}
		'\\centering
		'<if(captionOnTop){>\\caption{The Corpus.\\label{tbl:php-corpus}}<}>
		'\\ra{1.2}
		'\\begin{tabularx}{\\columnwidth}{Xrrrrrrrrrrrr} \\toprule
		'System <for(c <- cForSort){> & <c> <}> \\\\ \\midrule
		'<for(<_,p> <- pForSort){><getLine(p)> \\\\
		'<}>\\midrule
		'<getTotalLine()> \\\\
		'\\bottomrule
		'\\end{tabularx}
		'\\\\
		'\\vspace{2ex}
		'\\footnotesize
		' Counts of each Fragment Category in the corpus. The table headings for each fragment category have the following
		' abbreviations: L for literals, LV for local variables, LP for properties of local variables, LC for computed local names, 
		' GV for global variables, GP for properties of global variables, GC for computed global names, PN for parameters,
		' PP for properties of parameters, PC for computed property names and C for computed fragments that are not names
		'<if(!captionOnTop){>\\caption{Fragment Category Counts by System.\\label{tbl:fragment-category-counts}}<}>
		'\\end{table<if(tablestar){>*<}>}
		'\\npfourdigitnosep
		'\\npnoaddmissingzero
		";
		
	writeFile(tables + "fragmentCategories.tex", res);
	return res;
}

public str corpusAsLatexTable(bool captionOnTop=false, bool tablestar = false) {
	Corpus corpus = getCorpus();
	corpusCounts = getSortedCountsCaseInsensitive();
	pForSort = [ < toUpperCase(p), p > | p <- corpus ];
	pForSort = sort(pForSort, bool(tuple[str,str] t1, tuple[str,str] t2) { return t1[0] < t2[0]; });
	totalSystems = size(corpus);
	totalFiles = ( 0 | it + fc | < p, v, _, fc > <- corpusCounts, p in corpus, v == corpus[p] );
	totalSLOC = ( 0 | it + lc | < p, v, lc, _ > <- corpusCounts, p in corpus, v == corpus[p] );
	 
	str getLine(str p, str v) = "<getSensibleName(p)> & <v> & \\numprint{<getOneFrom(corpusCounts[p,v]<1>)>} & \\numprint{<getOneFrom(corpusCounts[p,v]<0>)>}";
	str res =
		"\\npaddmissingzero
		'\\npfourdigitsep
		'\\begin{table<if(tablestar){>*<}>}
		'\\centering
		'<if(captionOnTop){>\\caption{The Corpus.\\label{tbl:php-corpus}}<}>
		'\\ra{1.2}
		'\\begin{tabularx}{\\columnwidth}{Xrrr} \\toprule
		'System & Version & File Count & SLOC \\\\ \\midrule
		'<for(<_,p> <- pForSort, v := corpus[p]){><getLine(p,v)> \\\\
		'<}>
		'\\bottomrule
		'\\end{tabularx}
		'\\\\
		'\\vspace{2ex}
		'\\footnotesize
		'The File Count includes files with either 
		'a .php or an .inc extension, while SLOC includes source lines from these files.
		'In total, there are <totalSystems>
		'systems consisting of \\numprint{<totalFiles>} files with \\numprint{<totalSLOC>} total lines of source. 
		'\\normalsize
		'<if(!captionOnTop){>\\caption{The Corpus.\\label{tbl:php-corpus}}<}>
		'\\end{table<if(tablestar){>*<}>}
		'\\npfourdigitnosep
		'\\npnoaddmissingzero
		";
	return res;
}

public int totalCorpusFiles() {
	Corpus corpus = getCorpus();
	corpusCounts = { < p, v, lc, fc > | < p, v, lc, fc > <- getSortedCounts(), p in corpus<0>, v := corpus[p] };
	corpusFileCounts = corpusCounts<3>;
	return ( 0 | it + fc | fc <- corpusFileCounts );
}

public int totalCorpusLines() {
	Corpus corpus = getCorpus();
	corpusCounts = { < p, v, lc, fc > | < p, v, lc, fc > <- getSortedCounts(), p in corpus<0>, v := corpus[p] };
	corpusLineCounts = corpusCounts<2>;
	return ( 0 | it + fc | fc <- corpusLineCounts );
}
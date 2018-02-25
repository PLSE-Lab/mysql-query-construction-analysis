/* The purpose of this module is to provide functions that
 * output results of analyzing query construction patterns
 */

module QCPAnalysis::WriteResults

import QCPAnalysis::QCPCorpus;
import QCPAnalysis::SQLAnalysis;
import QCPAnalysis::SQLModel;

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
	models = groupSQLModelsCorups();
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
		'\\caption{<toUpperCase(pattern)>: Yield<pluralYield>, Query String<pluralString>, and AST<pluralAST>}
		'\\label{fig:<pattern>_<exampleNum>_yields}
		'\\end{figure*}
		";
	
	iprintToFile(exampleLoc + "model.txt", model.model);
	writeFile(exampleLoc + "<pattern>_<exampleNum>.tex", latex);
	renderSQLModelAsDot(model.model, exampleLoc + "<pattern>_<exampleNum>.dot");
	
	return model.location;
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
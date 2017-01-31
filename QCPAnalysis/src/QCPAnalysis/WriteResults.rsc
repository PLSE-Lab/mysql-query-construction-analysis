/* The purpose of this module is to provide functions that
 * output results of analyzing query construction patterns
 */

module QCPAnalysis::WriteResults

import QCPAnalysis::QCPCorpus;
import QCPAnalysis::BuildQueries;
import QCPAnalysis::AnalyzeQueries;

import lang::php::ast::AbstractSyntax;
import lang::php::util::Corpus;
import lang::php::util::Utils;

import IO;
import ValueIO;
import List;
import String;
import Set;

loc tables = |project://QCPAnalysis/results/tables/|;

public void writeTables(){
	writeFile(tables + "qcpCounts.tex", qcpCountsAsLatexTable());
	writeFile(tables + "qcpCountsBySystem.tex", qcpCountsBySystemAsLatexTable());
}

public str qcpCountsAsLatexTable(){
	str getLine(str pattern, int count) = "<pattern> & <count>";
	str res =
	"\\npaddmissingzero
	'\\npfourdigitsep
	'\\begin{table}
	'\\centering
	'\\caption{Counts of Each Query Construction Pattern\\label{tbl:qcp-counts}}
	'\\ra{1.2}
	'\\begin{tabularx}{\\columnwidth}{Xrrr} \\toprule
	'Query Construction Pattern & Number of Occurrences\\\\ \\midrule
	'<for(<p,c> <- getQCPCounts(true)){><getLine(p,c)> \\\\
	'<}>
	'\\bottomrule
	'\\end{tabularx}
	'\\end{table}
	'\\npfourdigitnosep
	'\\npnoaddmissingzero
	";
	return res;
}

public str qcpCountsBySystemAsLatexTable(){
	Corpus corpus = getCorpus();
	patterns = ["QCP1", "QCP2", "QCP3", "QCP4", "QCP5", "unclassified"];
	str getLine(str p, str v){
		line = "<p>_<v>";
		for(pattern <- patterns){
			line = line + " & <size(getQCPSystem(p,v,pattern))> ";
		}
		return line;
	}
	str res =
	"\\npaddmissingzero
	'\\npfourdigitsep
	'\\begin{table}
	'\\centering
	'\\caption{Counts of Each Query Construction Pattern\\label{tbl:qcp-counts}}
	'\\ra{1.2}
	'\\begin{tabularx}{\\columnwidth}{Xrrr} \\toprule
	'System & QCP1 & QCP2 & QCP3 & QCP4 & QCP5 & unclassified\\\\ \\midrule
	'<for(p <- corpus, v := corpus[p]){><getLine(p,v)> \\\\
	'<}>
	'\\bottomrule
	'\\end{tabularx}
	'\\end{table}
	'\\npfourdigitnosep
	'\\npnoaddmissingzero
	";
	return res;
}

public str corpusAsLatexTable() {
	Corpus corpus = getCorpus();
	corpusCounts = getSortedCountsCaseInsensitive();
	pForSort = [ < toUpperCase(p), p > | p <- corpus ];
	pForSort = sort(pForSort, bool(tuple[str,str] t1, tuple[str,str] t2) { return t1[0] < t2[0]; });
	
	str getLine(str p, str v) = "<getSensibleName(p)> & <v> & <getOneFrom(corpusCounts[p,v]<1>)> & <getOneFrom(corpusCounts[p,v]<0>)>";
	str res =
		"\\npaddmissingzero
		'\\npfourdigitsep
		'\\begin{table}
		'\\centering
		'\\caption{The Corpus.\\label{tbl:php-corpus}}
		'\\ra{1.2}
		'\\begin{tabularx}{\\columnwidth}{Xrrr} \\toprule
		'System & Version & File Count & SLOC \\\\ \\midrule
		'<for(<_,p> <- pForSort, v := corpus[p]){><getLine(p,v)> \\\\
		'<}>
		'\\bottomrule
		'\\end{tabularx}
		'\\end{table}
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
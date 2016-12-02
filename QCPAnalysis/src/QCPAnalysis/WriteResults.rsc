/* The purpose of this module is to provide functions that
 * output results of analyzing query construction patterns
 */

module QCPAnalysis::WriteResults

import QCPAnalysis::QCPCorpus;
import QCPAnalysis::QueryGroups;
import QCPAnalysis::QueryStringAnalysis;
import QCPAnalysis::QCP4SubcaseAnalysis;

import lang::php::ast::AbstractSyntax;
import lang::php::util::Corpus;
import lang::php::util::Utils;

import IO;
import List;
import String;
import Set;

loc tables = |project://QCPAnalysis/results/tables/|;
public void writeTables(){
	qs = getQCP("4");
	ds = getDynamicSnippets(qs);
	writeFile(tables + "qcpCounts.txt", qcpCountsAsLatexTable());
	writeFile(tables + "qcp4Types.txt", qcp4TypesAsLatexTable(ds));
	writeFile(tables + "qcp4Roles.txt", qcp4RolesAsLatexTable(qs));
}

public str qcpCountsAsLatexTable(){
	str getLine(str pattern, int count) = "<pattern> & <count>";
	str res =
	"\\npaddmissingzero
	'\\npfourdigitsep
	'\\begin{table}
	'\\centering
	'\\caption{Counts of Each Query Construction Pattern\\label{tbl:php-corpus}}
	'\\ra{1.2}
	'\\begin{tabularx}{\\columnwidth}{Xrrr} \\toprule
	'Query Construction Pattern & Number of Occurrences\\\\ \\midrule
	'<for(<p,c> <- reportQCPCounts()){><getLine(p,c)> \\\\
	'<}>
	'\\bottomrule
	'\\end{tabularx}
	'\\end{table}
	'\\npfourdigitnosep
	'\\npnoaddmissingzero
	";
	return res;
}

public str qcp4TypesAsLatexTable(list[QuerySnippet] qs){
	typeGroups = groupDynamicSnippetsByType(qs);
	str getLine(str t, int c) = "<t> & <c>";
	str res =
	"\\npaddmissingzero
	'\\npfourdigitsep
	'\\begin{table}
	'\\centering
	'\\caption{Counts of Each Type of Dynamic Query Part in QCP4 Occurrences\\label{tbl:php-qcp4-types}}
	'\\ra{1.2}
	'\\begin{tabularx}{\\columnwidth}{Xrrr} \\toprule
	'Type & Number of Occurrences\\\\ \\midrule
	'<for(p <- typeGroups, c := typeGroups[p]){><getLine(p,size(c))> \\\\
	'<}>
	'\\bottomrule
	'\\end{tabularx}
	'\\end{table}
	'\\npfourdigitnosep
	'\\npnoaddmissingzero
	";
	return res;
}

public str qcp4RolesAsLatexTable(set[QueryString] qs){
	roleGroups = groupDynamicSnippetsByRole(qs);
	str getLine(str r, int c) = "<r> & <c>";
	str res =
	"\\npaddmissingzero
	'\\npfourdigitsep
	'\\begin{table}
	'\\centering
	'\\caption{Counts of Each QCP4 Dynamic Part Grouped by Role\\label{tbl:php-qcp4-roles}}
	'\\ra{1.2}
	'\\begin{tabularx}{\\columnwidth}{Xrrr} \\toprule
	'Role & Number of Occurrences\\\\ \\midrule
	'<for(p <- roleGroups, c := roleGroups[p]){><getLine(p,size(c))> \\\\
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
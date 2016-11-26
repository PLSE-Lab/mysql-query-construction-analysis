module QCPAnalysis::QCP4SubcaseAnalysis
import QCPAnalysis::QueryStringAnalysis;

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
import List;
import Map;
import Node;
import IO;
import ValueIO;

set[str] superglobals = {"_SERVER", "_REQUEST", "_POST", "_GET", "_FILES",
	"_ENV", "_COOKIE", "_SESSION"};

// write QCP4 list to file since function takes a long time to execute
public void writeQCP4(){
	qcp4 = getQCP("4");
	writeBinaryValueFile(|project://QCPAnalysis/results/lists/qcp4|, qcp4);
}

// perform the analyses on QCP4 and print results	
public void analyzeQCP4(){
	qcp4 = readBinaryValueFile(#set[QueryString], |project://QCPAnalysis/results/lists/qcp4|);
	println("There are a total of <size(qcp4)> QCP4 calls in the corpus");
	ds = getDynamicSnippets(qcp4);
	println("There are a total of <size(ds)> dynamic query snippets in all QCP4 calls in the corpus");
	types = getQCP4DynamicSnippetTypes(ds) + "superglobal";
	println("Types of dynamic snippets: <types>");
	println("Counts for each type:\n <(n : size(d) | n <- groupDynamicSnippets(ds), d := groupDynamicSnippets(ds)[n])>");
}

private list[QuerySnippet] getDynamicSnippets(set[QueryString] qs) = [s | q <- qs, s <- q.snippets, dynamicsnippet(_) := s];
private set[str] getQCP4DynamicSnippetTypes(list[QuerySnippet] ds) = {getName(e) | d <- ds, dynamicsnippet(e) := d};
private map[str, list[QuerySnippet]] groupDynamicSnippets(list[QuerySnippet] ds){
	res = ();
	
	// group vars
	res += ("var" : [d | d <- ds, dynamicsnippet(var(name(name(n)))) := d]);
	
	// group references to superglobals
	res += ("superglobal" : [d | d <- ds, dynamicsnippet(fetchArrayDim(var(name(name(n))), _)) := d, n in superglobals]);
	
	// group fetchArrayDim
	res += ("fetchArrayDim" : [d | d <- ds, dynamicsnippet(fetchArrayDim(var(name(name(n))),_)) := d, n notin superglobals]);
	// needed case for 2-dimensional arrays
	res["fetchArrayDim"] += [d | d <- ds, dynamicsnippet(fetchArrayDim(fetchArrayDim(var(name(name(n))),_),_)) := d, n notin superglobals];
	
	// group function calls
	res += ("call" : [d | d <- ds, dynamicsnippet(call(_,_)) := d]);
	
	// group ternary
	res += ("ternary" : [d | d <- ds, dynamicsnippet(ternary(_,_,_)) := d]);
	
	return res;
}

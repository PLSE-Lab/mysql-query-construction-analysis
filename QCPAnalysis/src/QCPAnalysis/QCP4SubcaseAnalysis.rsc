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
	println("Counts for each type:\n <(n : size(d) | n <- groupDynamicSnippetsByType(ds), d := groupDynamicSnippetsByType(ds)[n])>");
	println("Counts for each role:\n <(n : size(d) | n <- groupDynamicSnippetsByRole(qcp4), d := groupDynamicSnippetsByRole(qcp4)[n])>");
}

private map[str, list[QuerySnippet]] groupDynamicSnippetsByType(list[QuerySnippet] ds){
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
	
	if(size(ds) != size(res["var"]) + size(res["superglobal"]) + size(res["fetchArrayDim"]) + size(res["call"]) + size(res["ternary"])){
		println("Warning: some dynamic snippets were not grouped. Type groupings may need additions.");
	}
	return res;
}

// groups all QCP4 occurrences based on what role their dynamic snippets take on
private map[str, list[QuerySnippet]] groupDynamicSnippetsByRole(set[QueryString] qs){
	res = ("param" : [], "name" : [], "other" : []);
	for(q <- qs){
		indexes = getDynamicSnippetIndexes(q);
		
		// returns true if this dynamic snippet is used as a parameter
		bool paramSnippet(int i){
			// get previous static snippet
			if(staticsnippet(ss) := q.snippets[i - 1]){
				// perform regex matching on the static snippet to determine if the dynamic snippet is used as a parameter
				if(/^.*WHERE\s[\w\.\`]+\s?\=\s?[^\w\.\`]*$/i := ss){
					return true;
				}
				else if(/^.*AND\s[\w\.\`]+\s?\=\s?[^\w\.\`]*$/i := ss){
					return true;
				}
				else if(/^.*OR\s[\w\.\`]+\s?\=\s?[^\w\.\`]*$/i := ss){
					return true;
				}
				else if(/^.*NOT\s[\w\.\`]+\s?\=\s?[^\w\.\`]*$/i := ss){
					return true;
				}
			}
			return false;
		}
		
		bool valuesParamSnippet(int index){
			boundaries = <-1,-1>;
			for(i <- [0..size(q.snippets)]){
				if(staticsnippet(ss1) := q.snippets[i] && /^.*VALUES\([^\)]*/i := ss1){
					boundaries[0] = i;
					break;
				}
			}
			if(boundaries[0] != -1){
				for(i <- [boundaries[0]..size(q.snippets)]){
					//find right paren
					if(staticsnippet(ss2) := q.snippets[i] && /\)$/i := ss2){
						boundaries[1] = i;
						break;
					}
				}
			}	
			if(boundaries[0] == -1 || boundaries[1] == -1){
				return false;
			}
			// values clause found, is the dynamic snippet at index inside its boundaries?
			else if(index > boundaries[0] && index < boundaries[1]){
				return true;
			}
			else{
				return false;
			}
		}
		
		// returns true if this dynamic snippet is the parameter to a SET clause
		bool setParamSnippet(int index){
			//finds the beginning of the SET clause of q, if it exists
			setBegin = -1;
			for(i <- [0..size(q.snippets)]){
				if(staticsnippet(ss) := q.snippets[i] && /^.*SET\s[\w\.\`]+\s?\=\s?[^\w\.\`]*$/i := ss){
					setBegin = i;
					break;
				}
			}
			if(setBegin != -1){
				// check for the easy case of the dynamic snippet at index being the first assignment after the SET clause
				if(index == setBegin + 1 && dynamicsnippet(_) := q.snippets[setBegin + 1]){
					return true;
				}
				// starting at the next snippet, look for <staticsnippet, dynamicsnippet> pairs of the form:
				// atributename = $dynamicsnippet
				else{
					setBegin = setBegin + 2;
					for(i <- [setBegin..size(q.snippets) - 1]){
						if(index == i + 1 && staticsnippet(s) := q.snippets[i] && /^\'?\\?\s?\,\s?[\w\.\`]+\s?\=\s?\\?\'?$/ := s){
							return true;
						}
					}
				}
			}
			return false;
		}
		
		for(i <- indexes, ds := q.snippets[i]){
			if(paramSnippet(i) || setParamSnippet(i) || valuesParamSnippet(i)){
				res["param"] += ds;
			}
			else{
				res["other"] += ds;
			}
		}
	}
	return res;
}
// gets all dynamic query snippets from each querystring in qs
private list[QuerySnippet] getDynamicSnippets(set[QueryString] qs) = [s | q <- qs, s <- q.snippets, dynamicsnippet(_) := s];

// gets the names of all the types used in dynamicsnippets
private set[str] getQCP4DynamicSnippetTypes(list[QuerySnippet] ds) = {getName(e) | d <- ds, dynamicsnippet(e) := d};

// gets the index of each dynamicsnippet in qs.snippets
private set[int] getDynamicSnippetIndexes(QueryString qs){
	res = {};
	for(i <- [0..size(qs.snippets)]){
		if(dynamicsnippet(_) := qs.snippets[i]){
			res += i;
		}
	}
	return res;
}
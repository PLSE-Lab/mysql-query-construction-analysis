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
	for(q <- groupDynamicSnippetsByRole(qcp4)["Other"]) println(q.dynamicpart@at);
}

public map[str, list[QuerySnippet]] groupDynamicSnippetsByType(list[QuerySnippet] ds){
	res = ();
	
	// group vars
	res += ("Variable" : [d | d <- ds, dynamicsnippet(var(name(name(n)))) := d]);
	
	// group references to superglobals
	res += ("Fetch Superglobal Element" : [d | d <- ds, dynamicsnippet(fetchArrayDim(var(name(name(n))), _)) := d, n in superglobals]);
	
	// group fetchArrayDim
	res += ("Fetch Array Element" : [d | d <- ds, dynamicsnippet(fetchArrayDim(var(name(name(n))),_)) := d, n notin superglobals]);
	// needed case for 2-dimensional arrays
	res["Fetch Array Element"] += [d | d <- ds, dynamicsnippet(fetchArrayDim(fetchArrayDim(var(name(name(n))),_),_)) := d, n notin superglobals];
	
	// group function calls
	res += ("Function Call" : [d | d <- ds, dynamicsnippet(call(_,_)) := d]);
	
	// group ternary
	res += ("Ternary Operator" : [d | d <- ds, dynamicsnippet(ternary(_,_,_)) := d]);
	
	if(size(ds) != size(res["Variable"]) + size(res["Fetch Superglobal Element"]) + size(res["Fetch Array Element"]) 
		+ size(res["Function Call"]) + size(res["Ternary Operator"])){
		
		println("Warning: some dynamic snippets were not grouped. Type groupings may need additions.");
	}
	return res;
}

// groups all QCP4 occurrences based on what role their dynamic snippets take on
private map[str, list[QuerySnippet]] groupDynamicSnippetsByRole(set[QueryString] qs){
	res = ("Parameter" : [], "Name" : [], "Other" : []);
	for(q <- qs){
		indexes = getDynamicSnippetIndexes(q);
		
		// returns true if this dynamic snippet is used as a parameter
		bool paramSnippet(int i){
			// get previous static snippet
			if(staticsnippet(ss) := q.snippets[i - 1]){
				// perform regex matching on the static snippet to determine if the dynamic snippet at i is used as a parameter
				if(/.*[\w\`\.]+\s*\=|(\<\>)|(\!\=)|\<|\>|(\<\=)|(\>\=)\s*\'?\\?$/i := ss){
					return true;
				}
				else if(/.*ORDER\sBY\s$/i := ss){
					return true;
				}
				else if(/.*LIMIT\s$/i := ss){
					return true;
				}
				else{
					return false;
				}
			}
			else{
				return false;
			}				
		}
		
		// check for case of arithmetic in set clause
		bool setParamArithmetic(int i){
			if(staticsnippet(ss) := q.snippets[i - 1]){
				if(/.*<word:\w+>\s?\=\s?\(<word>\s?\+|\-\s?$/i := ss){
					return true;
				}
				else{
					return false;
				}
			}
			else{
				return false;
			}
		}
		
		
		bool valuesParamSnippet(int index){
			boundaries = <-1,-1>;
			for(i <- [0..size(q.snippets)]){
				if(staticsnippet(ss1) := q.snippets[i] && /VALUES/i := ss1){
					boundaries[0] = i;
					break;
				}
			}
			if(boundaries[0] != -1){
				// assume last snippet is the end of the VALUES clause
				boundaries[1] = size(q.snippets);
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
		
		bool nameSnippet(int i){
			if(staticsnippet(ss) := q.snippets[i - 1]){
				// perform regex matching on the static snippet to determine if the dynamic snippet is used as a parameter
				if(/^.*FROM\s$/ := ss){
					return true;
				}
				else if(/^UPDATE\s$/ := ss){
					return true;
				}
				else if(/^SELECT\s$/ := ss){
					return true;
				}
				else if(/^INSERT\sINTO\s$/ := ss){
					return true;
				}
				else if(/^.*DATABASE\s$/ := ss){
					return true;
				}
				else if(/^.*EXISTS\s$/ := ss){
					return true;
				}
				else if(/^.*USE\s$/ := ss){
					return true;
				}
			}
			return false;
		}
		
		for(i <- indexes, ds := q.snippets[i]){
			if(paramSnippet(i) || setParamArithmetic(i) || valuesParamSnippet(i)){
				res["Parameter"] += ds;
			}
			else if(nameSnippet(i)){
				res["Name"] += ds;
			}
			else{
				res["Other"] += ds;
			}
		}
	}
	return res;
}
// gets all dynamic query snippets from each querystring in qs
public list[QuerySnippet] getDynamicSnippets(set[QueryString] qs) = [s | q <- qs, s <- q.snippets, dynamicsnippet(_) := s];

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
/* The purpose of this module is to count
 * the number of mysql_query calls in
 * the corpus, and to provide functions
 * useful to other modules.
 */
 // will be removed in the next commit
module QCPAnalysis::Util

import lang::php::util::Utils;
import lang::php::util::Corpus;
import lang::php::ast::System;
import lang::php::ast::AbstractSyntax;

// returns the name and version of all systems in the corpus
public set[str] getCorpusItems(){
	set[str] items = {};
	for(product <- getProducts(), version <- getVersions(product)){
		items += "<product>-<version>";
	}
	return items;
}

// returns the number of mysql_query calls in the corpus
public map[str,int] numMSQCallsCorpus(){
	set[str] items = getCorpusItems();
	map[str,int] counts = ();
	int total = 0;
	for(item <- items){
		System system = loadBinary(item);
		int count = numMSQCallsSystem(system);
		counts += (item : count);
		total += count;
	}
	counts += ("total" : total);
	return counts;
}

// returns the number of mysql_query calls in a System
private int numMSQCallsSystem(System system){
	int count = 0;
	for(location <- system.files){
		Script scr = system.files[location];
		count += numMSQCallsScript(scr);
	}
	return count;
}

// returns the number of mysql_query calls in a Script object
private int numMSQCallsScript(Script scr){
	int count = 0;
	top-down visit (scr) {
		case call(name(name("mysql_query" )), _) : {
			count += 1;
		}
	};
	return count;
}
/* the purpose of this module is to further analyze mysql_query calls
 * whose parameter is a variable (QCP3), or QCP2 calls whose parameter
 * contains variable(s) concatenated or interpolated. Information about
 * the origin of the variable and how its SQL string is built is
 * reported.
 *
 */
module QCPAnalysis::VariableAnalysis

import QCPAnalysis::QCPCorpus;
import QCPAnalysis::GeneralQCP;

import lang::php::util::Utils;
import lang::php::util::Corpus;
import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::analysis::NamePaths;
import lang::php::analysis::cfg::CFG;
import lang::php::analysis::cfg::BuildCFG;

import Set;
import Map;
import IO;
import ValueIO;

loc cfglocb = |project://QCPAnalysis/cfgs/binary|;
loc cfglocp = |project://QCPAnalysis/cfgs/plain|;

// returns the location of all scripts in the Corpus that contain mysql_query calls whose parameters contain variables.
private set[loc] scriptsWithVars(){
	Corpus corpus = getCorpus();
	set[loc] locs = {};
	for(p <- corpus, v := corpus[p]){
		pt = loadBinary(p, v);
		for(l <- pt.files, scr := pt.files[l]){
			calls = { c | /c:call(name(name("mysql_query")),_) := scr};
			vars  = { e | c <- calls, /Expr e:var(name(name(_))) := c.parameters};
			if(!isEmpty(vars))
				locs += l;
		}
	}
	return locs;
}

// builds the CFGs for all scripts with variables
public void buildCFGsSWV(){
	int id = 0;
	rel[int id, loc scriptloc, NamePath scope] cfginfo = {};
	for(scrloc <- scriptsWithVars()){
		Script scr = loadPHPFile(scrloc);
		map[NamePath,CFG] scrCFGs = buildCFGs(scr);
		
		// build global cfg
		set[loc] gcwv = globalCWV(scr);
		if(!isEmpty(gcwv)){
			NamePath gnp = globalPath();
			CFG gcfg = scrCFGs[gnp];
			cfginfo += <id, scrloc, gnp>;
			tuple[set[loc] cwv, CFG cfg] filecontents = <gcwv, gcfg>;
			writeBinaryValueFile(cfglocb + "/cfg<id>.cfg", filecontents);
			iprintToFile(cfglocp + "/cfg<id>.cfg", filecontents);
			id = id + 1;
		}
		
		// build cfgs for functions, classes, methods in script
		namepaths = getPathsAndStmtsScript(scr);
		for(<np,st> <- namepaths){
			fcmcwv = functionClassMethodCWV(st);
			if(!isEmpty(fcmcwv)){
				CFG fcmcfg = scrCFGs[np];
				cfginfo += <id, scrloc, np>;
				tuple[set[loc] cwv, CFG cfg] filecontents = <fcmcwv, fcmcfg>;
				writeBinaryValueFile(cfglocb + "/cfg<id>.cfg", filecontents);
				iprintToFile(cfglocp + "/cfg<id>.cfg", filecontents);
				id = id + 1;
			}
		}
	}
	writeBinaryValueFile(cfglocb + "/cfginfo.tuple", cfginfo);
	iprintToFile(cfglocp + "/cfginfo.tuple", cfginfo);
}

// returns the location of all global mysql_query calls whose parameter contains variable(s)
private set[loc] globalCWV(Script scr) =
	{ e@at | /c:call(name(name("mysql_query")),_) := scr, /e:var(name(name(_))) := c.parameters};

// returns the location of all mysql_query calls in a particular function/class/method
// whose parameter contains variable(s) 
private set[loc] functionClassMethodCWV(Stmt st)
	= { e@at | /c:call(name(name("mysql_query")),_) := st, /e:var(name(name(_))) := c.parameters};

// returns the NamePath and Stmt of all functions and methods in a particular script
// TODO: add support for methods
public rel[NamePath,Stmt] getPathsAndStmtsScript(Script scr){
	rel[NamePath,Stmt] ps = {};
	for (/f:function(fname,_,_,_) := scr){
		ps += <functionPath(fname), f>;
	}
	// TODO: fix unexpected type error
	/*for(/class(cname,_,_,_,mbrs) := scr, m:method(mname,_,_,_,_) <- mbrs){
		ps += <methodPath(cname, mname), m>;
	}*/
	return ps;
}

/* the purpose of this module is to build the CFGs that will be
 * used for analysis in other modules
 */
module QCPAnalysis::CFGCreation

import QCPAnalysis::QCPCorpus;
import QCPAnalysis::QueryGroups;

import lang::php::util::Utils;
import lang::php::util::Corpus;
import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::analysis::NamePaths;
import lang::php::analysis::cfg::CFG;
import lang::php::analysis::cfg::BuildCFG;

loc cfglocb = |project://QCPAnalysis/cfgs/binary|;
loc cfglocp = |project://QCPAnalysis/cfgs/plain|;

// This is in the process of being rewritten to reflect the change from NamePaths to locations

// builds the CFGs for all scripts in the corpus that contain mysql_query calls
public void buildCFGsCorpus(){
	// to be implemented
}

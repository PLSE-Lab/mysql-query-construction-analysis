/* the purpose of this module is to further analyze mysql_query calls
 * whose parameter is a variable (QCP3), or QCP2 calls whose parameter
 * contains variable(s) concatenated or interpolated. Information about
 * the origin of the variable and how its SQL string is built is
 * reported.
 *
 * Note: in method and variable naming, CWV stands for "calls with variables",
 * referring to mysql_query calls whose parameters contain variables
 */
module QCPAnalysis::VariableAnalysis

import QCPAnalysis::QCPCorpus;
import QCPAnalysis::GeneralQCP;
import QCPAnalysis::QCP2Analysis;

import lang::php::util::Utils;
import lang::php::util::Corpus;
import lang::php::ast::AbstractSyntax;
import lang::php::analysis::cfg::CFG;
import lang::php::analysis::cfg::BuildCFG;

import IO;
import Relation;

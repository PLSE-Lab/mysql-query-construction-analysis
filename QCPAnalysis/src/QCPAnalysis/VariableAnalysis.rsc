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

// returns the locations of all variables in the corpus that are paramaters to mysql_query calls
public set[loc] getQueryVarLocs() = { l | <s, l> <- exprTypesAndLocsInCorpus(), s := "var" };

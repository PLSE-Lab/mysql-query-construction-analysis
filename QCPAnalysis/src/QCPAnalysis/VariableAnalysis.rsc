/* the purpose of this module is to further analyze mysql_query calls
 * whose parameter is a variable (QCP3), or QCP2 calls whose parameter
 * contains variable(s) concatenated or interpolated. Information about
 * the origin of the variable and how its SQL string is built is
 * reported.
 */
 
// to be implemented
module QCPAnalysis::VariableAnalysis

import QCPAnalysis::QCPCorpus;
import QCPAnalysis::GeneralQCP;
import QCPAnalysis::QCP2Analysis;

import lang::php::util::Utils;
import lang::php::ast::System;
import lang::php::ast::AbstractSyntax;

// gets all mysql_query calls in the corpus that contain variables
public map[str, list[Expr]] getCallsWithVars(){
	map[str,list[Expr]] qcp2WithVars = getQCP2WithExprType("var");
	map[str,list[Expr]] qcp3 = getQCP(3);
	map[str,list[Expr]] callsWithVars = ();
	for(sys <- qcp2WithVars, qcp2 <- qcp2WithVars[sys]){
		callsWithVars += (sys : qcp2 + qcp3[sys]);
	}
	return callsWithVars;
}
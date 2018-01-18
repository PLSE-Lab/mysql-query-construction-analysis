module QCPAnalysis::ModelAnalysis

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::util::Utils;
import lang::php::util::Corpus;
import lang::php::analysis::cfg::CFG;

import QCPAnalysis::Utils;
import QCPAnalysis::QCPSystemInfo;
import QCPAnalysis::SQLModel;

import Relation;

data FragmentCategories = fcat(int literals, int localNames, int globalNames, int parameterNames, int computed);

public set[QueryFragment] flattenFragment(QueryFragment qf) {
	if (qf is compositeFragment) {
		return { qf } + { *flattenFragment(fi) | fi <- qf.fragments };
	} 
	
	if (qf is concatFragment) {
		return { qf } + flattenFragment(qf.left) + flattenFragment(qf.right);
	}
	
	return { qf };
}

public set[QueryFragment] flattenFragment(set[QueryFragment] qfs) {
	return { *flattenFragment(qf) | qf <- qfs };
}

public FragmentCategories computeFragmentCategories(SQLModel sqm, CFG cflow) {
	FragmentCategories fc = fcat(0, 0, 0, 0, 0);

	fragments = flattenFragment(sqm.fragmentRel<1> + sqm.fragmentRel<4>);
	
	// Get names for input parameters for the function or method
	parameterNames = { n.paramName | n <- cflow.nodes, n is actualProvided || n is actualNotProvided };
	
	// Get the global names
	globalNames = { gn | /global(list[Expr] exprs) := cflow.nodes, var(name(name(gn))) <- exprs };
	
	// Remove the global names from the parameter names, the global declaration would change the scope
	parameterNames -= globalNames;
	
	for (fragment <- fragments) {
		switch(fragment) {
			case literalFragment(str lf): {
				fc.literals += 1;
			}
			
			// TODO: Modify, we have names for params and global from the use/def info!
			case nameFragment(varName(n)): {
				if (n in parameterNames) {
					fc.parameterNames += 1;
				} else if (n in globalNames) {
					fc.globalNames += 1;
				} else {
					fc.localNames += 1;
				}
			}
			
			case dynamicFragment(_): {
				fc.computed += 1;
			}

			// NOTE: This should never happen if we actually had a literal since
			// that would have been simplified
			case compositeFragment(_): {
				fc.computed += 1;
			}
			
			// NOTE: This should never happen if we actually had a literal since
			// that would have been simplified
			case concatFragment(_): {
				fc.computed += 1;
			}
			
			case inputParamFragment(_): {
				fc.parameterNames += 1;
			}
			
			case globalFragment(_): {
				fc.parameterNames += 1;
			}
			
			case unknownFragment(): {
				fc.computed += 1;
			}
			
		}
	}

	return fc;
}

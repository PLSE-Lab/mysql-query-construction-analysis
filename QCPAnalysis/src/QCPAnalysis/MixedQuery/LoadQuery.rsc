module QCPAnalysis::MixedQuery::LoadQuery

import QCPAnalysis::MixedQuery::ParseQuery;  
import QCPAnalysis::MixedQuery::AbstractSyntax;         
import ParseTree;                                    

public SQLQuery load(str txt) = implode(#SQLQuery, parse(txt)); 
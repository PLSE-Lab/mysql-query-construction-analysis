module QCPAnalysis::MixedQuery::LoadQuery

import QCPAnalysis::MixedQuery::ParseQuery;  
import QCPAnalysis::MixedQuery::AbstractSyntax;         
import ParseTree;                                    

public Query load(str txt) = implode(#Query, parseQuery(txt)); 
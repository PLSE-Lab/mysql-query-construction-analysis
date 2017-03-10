module QCPAnalysis::MixedQuery::LoadQuery

import QCPAnalysis::MixedQuery::ParseQuery;  
import QCPAnalysis::MixedQuery::AbstractSyntax;         
import ParseTree;                                    

public QCPAnalysis::MixedQuery::AbstractSyntax::SQLQuery load(str txt) = implode(#QCPAnalysis::MixedQuery::AbstractSyntax::SQLQuery, parse(txt)); 
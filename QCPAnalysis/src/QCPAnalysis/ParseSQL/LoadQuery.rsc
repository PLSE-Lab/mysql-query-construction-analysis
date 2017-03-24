module QCPAnalysis::ParseSQL::LoadQuery

import QCPAnalysis::ParseSQL::ParseQuery;  
import QCPAnalysis::ParseSQL::AbstractSyntax;         
import ParseTree;                                    

public QCPAnalysis::ParseSQL::AbstractSyntax::SQLQuery load(str txt) = implode(#QCPAnalysis::ParseSQL::AbstractSyntax::SQLQuery, parse(txt)); 
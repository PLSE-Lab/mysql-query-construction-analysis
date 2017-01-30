module QCPAnalysis::MixedQuery::AbstractSyntax

public data Query = selectQuery(Name columnname, From fc, Join jc, Where wc, Boolean bc);				  
public data Name = name(str name)
				 | dynamicName();

public data Param = param(str name)
				  | dynamicParam();

public data From = from(Name tablename);

public data Join = inner(Name tablename, Name on1, Name on2)
				       | left(Name tablename, Name on1, Name on2)
				       | right(Name tablename, Name on1, Name on2)
				       | full(Name tablename, Name on1, Name on2)
				       | noJoin();

public data On = on(Name left, Name right);

public data Where = where(Name columnname, Param param)
				   | noWhere();

public data Boolean = and(Name columnname, Param param, Boolean next)
					| or(Name columnname, Param param, Boolean next)
					| not(Name columnname, Param param, Boolean next)
		 			| noBoolean();
		 			
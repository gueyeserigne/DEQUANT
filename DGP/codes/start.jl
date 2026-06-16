using Pkg

ENV["CPLEX_STUDIO_BINARIES"] = "/opt/ibm/ILOG/CPLEX_Studio_Community2212/cplex/bin/x86-64_linux/"
Pkg.add("JuMP")
Pkg.build("CPLEX")
Pkg.add("CPLEX")
Pkg.add("Cbc")

using JuMP
using Cbc
using CPLEX

m=Model(CPLEX.Optimizer)
#m=Model(Cbc.Optimizer)

@variable(m,xa>=0)
@variable(m,xb>=0)

@objective(m,Max, 4xa + 5xb)

@constraint(m,2xa+xb<=800)
@constraint(m,xa+2xb<=700)
@constraint(m,xb<=300)

status=optimize!(m)

println(status)

println(objective_value(m))
println(value(xa))
println(value(xb))
println("solve_time: ", solve_time(m))
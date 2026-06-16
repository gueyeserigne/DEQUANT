using Pkg
Pkg.add("JuMP")
Pkg.add("Ipopt")
Pkg.add("CPLEX")
Pkg.add("CSV")
Pkg.add("Plots")
using JuMP, Ipopt, CPLEX, CSV, LinearAlgebra, Plots

global n=3
global dim=2
limit_dim=2
limit_points=10
L=10.0

for n in 3:limit_points
    for dim in 2:limit_dim
        Q=zeros(n,n)
        for i in 1:n
            for j in i+1:n
                gen_Q=L.*rand(0:10)
                Q[i,j]=gen_Q
                Q[j,i]=gen_Q
            end
        end
        println("Q = ", Q)

        model= Model(Ipopt.Optimizer)
        @variable(model, x[1:n, 1:dim] >= 0)
        @variable(model, y[i=1:n,j=i+1:n]>=0)
        @variable(model, z[i=1:n,j=i+1:n]>=0)
        @objective(model, Min, sum((y[i,j]+ z[i,j] -Q[i,j]^2)^2 for i in 1:n , j in i+1:n ))
        @constraint(model, [i in 1:n, j in (i+1):n], y[i, j] == (x[i, 1] - x[j, 1])^2)
        @constraint(model, [i in 1:n, j in (i+1):n], z[i, j] == (x[i, 2] - x[j, 2])^2)

        status=optimize!(model)
        println(status)
        println("objective_value = ", objective_value(model))
        println("x = ", value.(x))
        println("y = ", value.(y))
        println("z = ", value.(z))


        open("results1.csv","a") do file
            println(file, "Q = ", Q)
            println(file, "objective_value = ", objective_value(model))
            println(file, "x = ", value.(x))
            println(file, "y = ", value.(y))
            println(file, "z = ", value.(z))
            println(file, "-----------------------------------")
        end

    end
end


using JuMP, Ipopt, CSV, LinearAlgebra

L=10.0
n=3
dim=2
limit_dim=2
limit_points=10

for n in 3:limit_points
    for dim in 2:limit_dim
        
        x_true = L.* rand(n, dim) 
        Q = zeros(n, n)
        for i in 1:n
            for j in i+1:n
                dist = norm(x_true[i, :] - x_true[j, :])
                Q[i, j] = dist
                Q[j, i] = dist
            end
        end

        model = Model(Ipopt.Optimizer)
        @variable(model, x[1:n, 1:dim] >= 0)
        @variable(model, y[i=1:n, j=i+1:n] >= 0)
        @variable(model, z[i=1:n, j=i+1:n] >= 0)

        for i in 1:n, k in 1:dim
            set_start_value(x[i, k], 10.0 * rand())
        end

        @objective(model, Min, sum((y[i,j] + z[i,j] - Q[i,j]^2)^2 for i in 1:n, j in i+1:n))
        
        @constraint(model, [i in 1:n, j in (i+1):n], y[i, j] == (x[i, 1] - x[j, 1])^2)
        @constraint(model, [i in 1:n, j in (i+1):n], z[i, j] == (x[i, 2] - x[j, 2])^2)

        optimize!(model)
        
        println("-----------------------------------")
        println("Instance n = ", n)
        #println("Status          = ", termination_status(model))
        println("Objective Value = ", objective_value(model))
        #println("Recovered x     = ", value.(x))
        #println("Z = ", value.(z))
        #println("Y = ", value.(y))
    end
end
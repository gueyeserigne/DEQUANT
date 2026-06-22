using Pkg
Pkg.add("JuMP")
Pkg.add("Ipopt")
Pkg.add("Plots")
using JuMP, Ipopt, Plots, LinearAlgebra

global n=3
global dim=2
limit_points=10
limit_dim=2
number_generation_per_instance=10
L=10.0
for n in 3:limit_points
    for dim in 2:limit_dim
        for _ in 1:number_generation_per_instance
            Q=zeros(n,n)
            for i in 1:n
                for j in i+1:n
                    gen_Q=L.*rand(0:10)
                    Q[i,j]=gen_Q
                    Q[j,i]=gen_Q
                end
            end

            println("Q = ", Q)



            model=Model(Ipopt.Optimizer)
            @variable(model, x_opt[1:n, 1:dim]>=0)
            @objective(model,Min,sum(
                (sum((x_opt[i,k]-x_opt[j,k])^2 for k in 1:dim)

                -Q[i,j])^2 for i in 1:n , j in i+1:n))

            optimize!(model)

            println("objective_value = ", objective_value(model))

            println("x = ", value.(x_opt))



            scatter!(value.(x_opt)[:,1], value.(x_opt)[:,2], label="x_opt")

            savefig("comparaison_mds1.png")
            println("Le graphique a été sauvegardé sous 'comparaison_mds1.png'")


        end
    end
end

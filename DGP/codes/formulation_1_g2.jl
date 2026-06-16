using Random
using LinearAlgebra
using Pkg
Pkg.add("Ipopt")
using JuMP
using Ipopt
Pkg.add("Plots")
using Plots


Random.seed!(2024)


global n=3
global dim=2
limit_points=10
limit_dim=2
number_generation_per_instance=10
L=10

for n in 3:limit_points
    for dim in 2:limit_dim 
        for _ in 1:number_generation_per_instance
            println("n = ", n, ", dim = ", dim)
                
            x=L*rand(n,dim)

            println("x_reel = ", x)

            Q=zeros(n,n)
            for i in 1:n
                for j in i+1:n
                    println("x_$i = ", x[i,:])
                    println("x_$j = ", x[j,:])
                    norm_value=sum((x[i,:]-x[j,:]).^2)
                    println("n_$i$j = ", norm_value)
                    Q[i,j]=norm_value
                    Q[j,i]=norm_value
                end
            end

            println("Q = ", Q)


            

            model=Model(Ipopt.Optimizer)
            @variable(model, x_opt[1:n, 1:dim]>=0)
            @objective(model,Min,sum(
                (sum((x_opt[i,k]-x_opt[j,k])^2 for k in 1:dim)

                -Q[i,j])^2 for i in 1:n , j in i+1:n))

            status=optimize!(model)
            println(status)

            println("objective_value = ", objective_value(model))

            println("x = ", value.(x_opt))


        

            p = scatter(x[:,1], x[:,2], label="x_reel")
            scatter!(value.(x_opt)[:,1], value.(x_opt)[:,2], label="x_opt")

            savefig("comparaison_mds.png")
            println("Le graphique a été sauvegardé sous 'comparaison_mds.png'")



            open("results.csv", "a") do file
                println(file,"Initial data")
                println(file, "x_reel : ", replace(string(x),";" => ","))
                println(file, "Q : ", replace(string(Q),";" => ","))
                println(file, "Results")
                println(file, "Valeur de l'objectif : ", objective_value(model))
                println(file, "Positions optimisées :")
                println(file, "x_opt = ", replace(string(value.(x_opt)),";" => ","))

                
                println(file, "\n" * "="^50 * "\n") 

            end

        end
    end
end
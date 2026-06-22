using JuMP, Ipopt, LinearAlgebra, DataFrames, Random, Printf, CSV, Statistics
using Plots, StatsPlots

Random.seed!(42)
const MOI = JuMP.MOI

# ═══════════════════════════════════════════════════════════════
#  §1  PARAMÈTRES
# ═══════════════════════════════════════════════════════════════
n_values = [4,10,30,50]
dim      = 2
c6       = 1.0
d_min    = 0.2
z_min    = d_min^2

function nb_restarts_bench(n)
    n <= 3  ? 5 :
    n <= 10 ? 5 :
    n <= 20 ? 3 : 2
end

# ═══════════════════════════════════════════════════════════════
#  §2  UTILITAIRES
# ═══════════════════════════════════════════════════════════════
function generer_init(n, dim, L; seuil=z_min)
    x = zeros(n, dim)
    for i in 1:n
        x[i, :] = L * rand(dim)
        # On teste le point i contre tous les points précédents (1 à i-1)
        j = 1
        while j < i
            if norm(x[i, :] - x[j, :]) < seuil
                # Collision détectée : on régénère le point i
                x[i, :] = L * rand(dim)
                # On redémarre la vérification pour i à partir de j=1
                j = 1
            else
                j += 1
            end
        end
    end
    return x
end

function erreur_rydberg_vraie(x_sol, Q, c6, n, dim)

    try
        val = 0.0
        for i in 1:n, j in i+1:n
            d = norm(x_sol[i,:] - x_sol[j,:])
            val += (c6 / d^6 - Q[i,j])^2
        end
        return val
    catch
        return Inf
    end
end

function rmse_dist(x, x_ref, n)
    err = 0.0
    count = 0
    for i in 1:n, j in i+1:n
        d1 = norm(x[i,:] - x[j,:])
        d2 = norm(x_ref[i,:] - x_ref[j,:])
        err += (d1 - d2)^2
        count += 1
    end
    return sqrt(err / count)
end

function rmse_dist_safe(x, x_ref, n)
    x === nothing && return Inf
    try
        return rmse_dist(x, x_ref, n)
    catch
        return Inf
    end
end

function matrix_to_csv_str(M::AbstractMatrix)
    rows = String[]
    for i in 1:size(M, 1)
        push!(rows, join(string.(M[i, :]), ","))
    end
    return join(rows, ";")
end

function csv_str_to_matrix(s::AbstractString)
    isempty(s) && return nothing
    rows = split(s, ";")
    data = [parse.(Float64, split(row, ",")) for row in rows]
    return reduce(vcat, [reshape(r, 1, :) for r in data])
end

const L_SEED = 10.0
const ALL_L_TYPES = ["L_fixe", "L_adaptatif", "L_optimal"]

function build_Q_matrix(x, c6, n)
    Q = zeros(n, n)
    for i in 1:n, j in i+1:n
        d = norm(x[i,:] - x[j,:])
        Q[i,j] = Q[j,i] = c6 / d^6
    end
    return Q
end

function L_optimal_from_Q(Q, c6, n)
    qmin = minimum(Q[i,j] for i in 1:n for j in i+1:n)
    return ((c6 / qmin)^(1/6))
end

function L_value(L_type::AbstractString, n::Int; Q=nothing, c6=1.0)
    if L_type == "L_fixe"
        return 10.0
    elseif L_type == "L_adaptatif"
        return 100.0 * sqrt(n)
    elseif L_type == "L_optimal"
        Q === nothing && error("L_optimal nécessite la matrice Q")
        return L_optimal_from_Q(Q, c6, size(Q, 1))
    else
        error("Type de L inconnu : $L_type")
    end
end

# ═══════════════════════════════════════════════════════════════
#  §2b  BRUIT MULTIPLICATIF
#  Seul ajout au code original : fonction pour bruiter Q
# ═══════════════════════════════════════════════════════════════
function ajouter_bruit(Q, theta_bruit, n)
    Q_bruit = copy(Q)
    for i in 1:n, j in i+1:n
        Q_bruit[i,j] = max(Q[i,j] * (1 + theta_bruit * randn()))
        Q_bruit[j,i] = Q_bruit[i,j]
    end
    return Q_bruit
end

# ═══════════════════════════════════════════════════════════════
#  §3  FORMULATION 1 — STANDARD
#  Positions libres dans R² (invariance par translation/rotation)
# ═══════════════════════════════════════════════════════════════
function solve_standard(n, dim, Q, c6, L, x_init)
    m = Model(Ipopt.Optimizer)
    set_optimizer_attribute(m, "print_level",        0)
    set_optimizer_attribute(m, "tol",                1e-12)
    set_optimizer_attribute(m, "max_iter",           10000)

    @variable(m, 0<=x[1:n, 1:dim]<=L)          
    for i in 1:n, d in 1:dim
        set_start_value(x[i, d], x_init[i, d])
    end

    @expression(m, d2[i=1:n, j=i+1:n],
        sum((x[i, k] - x[j, k])^2 for k in 1:dim)
    )
    for i in 1:n, j in i+1:n
        @constraint(m, d2[i, j] >= z_min)   # contrainte physique
    end
    @objective(m, Min,
        sum((c6 / d2[i, j]^3 - Q[i, j])^2 for i in 1:n for j in i+1:n)
    )

    optimize!(m)
    status = termination_status(m)
    if status in [MOI.LOCALLY_SOLVED, MOI.ALMOST_LOCALLY_SOLVED, MOI.ITERATION_LIMIT, MOI.SLOW_PROGRESS]
        return (status, objective_value(m), value.(x))
    end
end

# ═══════════════════════════════════════════════════════════════
#  §4  FORMULATION 2 — REFORMULÉE
# ═══════════════════════════════════════════════════════════════
function solve_reformulee(n, dim, Q, c6, L, x_init)
    m = Model(Ipopt.Optimizer)
    set_optimizer_attribute(m, "print_level",        0)
    set_optimizer_attribute(m, "tol",                1e-12)
    set_optimizer_attribute(m, "max_iter",           10000)

    @variable(m, 0<=x2[1:n, 1:dim]<=L)         


    @variable(m, z[i=1:n, j=(i+1):n])
    @variable(m, u[i=1:n, j=(i+1):n])
    @variable(m, w[i=1:n, j=(i+1):n])
    @variable(m, r[i=1:n, j=(i+1):n])

    for i in 1:n, d in 1:dim
        set_start_value(x2[i, d], x_init[i, d])
    end
    for i in 1:n, j in i+1:n
        d_sq = sum((x_init[i,k]-x_init[j,k])^2 for k in 1:dim)
        set_start_value(z[i,j], d_sq)
        set_start_value(u[i,j], d_sq^2)
        set_start_value(w[i,j], d_sq^3)
        set_start_value(r[i,j], c6/d_sq^3)
    end
    for i in 1:n, j in i+1:n
        @constraint(m, r[i,j] * w[i,j] == c6)
        @constraint(m, z[i,j] == sum((x2[i,k]-x2[j,k])^2 for k in 1:dim))
        @constraint(m, w[i,j] == u[i,j] * z[i,j])
        @constraint(m, u[i,j] == z[i,j]^2)
    end
    @objective(m, Min,
        sum((r[i,j]-Q[i,j])^2 for i in 1:n for j in i+1:n)
    )

    optimize!(m)
    status = termination_status(m)
    if status in [MOI.LOCALLY_SOLVED, MOI.ALMOST_LOCALLY_SOLVED, MOI.ITERATION_LIMIT, MOI.SLOW_PROGRESS]
        return (status, objective_value(m), value.(x2))
    end
end

# ═══════════════════════════════════════════════════════════════
#  §5  FORMULATION 3 — POLAIRE
# ═══════════════════════════════════════════════════════════════
function solve_polaire(n, dim, Q, c6, L, x_init)
    model = Model(Ipopt.Optimizer)
    set_optimizer_attribute(model, "print_level",        0)
    set_optimizer_attribute(model, "tol",                1e-12)
    set_optimizer_attribute(model, "max_iter",           10000)

    @variable(model, 0<=x[1:n, 1:dim]<=L)     
    @variable(model, -pi <= theta[i=1:n, j=i+1:n] <= pi)
    @variable(model, R[i=1:n, j=i+1:n] >= d_min)

    for i in 1:n, d in 1:dim
        set_start_value(x[i,d], x_init[i,d])
    end
    for i in 1:n, j in i+1:n
        dx = x_init[i,1] - x_init[j,1]
        dy = x_init[i,2] - x_init[j,2]
        set_start_value(theta[i,j], atan(dy,dx))
        set_start_value(R[i,j], norm([dx,dy]))
    end

    @variable(model, error_pair[i=1:n, j=i+1:n])
    for i in 1:n, j in i+1:n
        @constraint(model, x[i,1]-x[j,1] == R[i,j]*cos(theta[i,j]))
        @constraint(model, x[i,2]-x[j,2] == R[i,j]*sin(theta[i,j]))
        @constraint(model, R[i,j] >= z_min)
        @constraint(model, error_pair[i,j] == (c6/R[i,j]^6) - Q[i,j])
    end
    @objective(model, Min,
        sum(error_pair[i,j]^2 for i in 1:n for j in i+1:n)
    )

    optimize!(model)
    status = termination_status(model)
    if status in [MOI.LOCALLY_SOLVED, MOI.ALMOST_LOCALLY_SOLVED,MOI.ITERATION_LIMIT, MOI.SLOW_PROGRESS]
        return (status, objective_value(model), value.(x))
    end
    return nothing
end

# ═══════════════════════════════════════════════════════════════
#  §5b  FORMULATION — SUROGATE
# ═══════════════════════════════════════════════════════════════
function solve_surogate(n, dim, Q, c6, L, x_init)
    m = Model(Ipopt.Optimizer)
    set_optimizer_attribute(m, "print_level", 0)
    set_optimizer_attribute(m, "tol",                1e-12)
    set_optimizer_attribute(m, "max_iter",           10000)

    @variable(m, 0 <= x[1:n, 1:dim] <= L)
    @variable(m, r[i=1:n, j=i+1:n])
    @variable(m, w[i=1:n, j=i+1:n])
    @variable(m, z[i=1:n, j=i+1:n])
    @variable(m, mu[i=1:n, j=i+1:n])

    for i in 1:n, d in 1:dim
        set_start_value(x[i, d], x_init[i, d])
    end
    for i in 1:n, j in i+1:n
        d_sq = sum((x_init[i,k] - x_init[j,k])^2 for k in 1:dim)
        set_start_value(z[i, j], d_sq)
        set_start_value(mu[i, j], d_sq^2)
        set_start_value(w[i, j], d_sq^3)
        set_start_value(r[i, j], c6 / d_sq^3)
    end

    for i in 1:n, j in i+1:n
        @constraint(m, z[i,j] >= z_min)
    end

    @objective(m, Min, sum((r[i, j] - Q[i, j])^2 for i in 1:n, j in i+1:n))

    for i in 1:n, j in i+1:n
        @constraint(m,
            r[i,j] * w[i,j] + z[i,j] + w[i,j] + mu[i,j] - mu[i,j] * z[i,j] - z[i,j]^2
            - sum((x[i,k] - x[j,k])^2 for k in 1:dim) - c6 == 0
        )
    end

    optimize!(m)
    status = termination_status(m)
    if status in [MOI.LOCALLY_SOLVED, MOI.ALMOST_LOCALLY_SOLVED, MOI.ITERATION_LIMIT, MOI.SLOW_PROGRESS]
        return (status, objective_value(m), value.(x))
    end
    return nothing
end

# ═══════════════════════════════════════════════════════════════
#  §5c  FORMULATION — QUADRATIQUE (matrices explicites)
# ═══════════════════════════════════════════════════════════════
function solve_quadratique(n, dim, Q, c6, L, x_init)
    m = Model(Ipopt.Optimizer)
    set_optimizer_attribute(m, "print_level", 0)
    set_optimizer_attribute(m, "tol",                1e-12)
    set_optimizer_attribute(m, "max_iter",           10000)

    @variable(m, 0 <= x[1:n, 1:dim] <= L)
    @variable(m, r[i=1:n, j=i+1:n])
    @variable(m, w[i=1:n, j=i+1:n])
    @variable(m, z[i=1:n, j=i+1:n])
    @variable(m, mu[i=1:n, j=i+1:n])

    for i in 1:n, d in 1:dim
        set_start_value(x[i, d], x_init[i, d])
    end
    for i in 1:n, j in i+1:n
        d_sq = sum((x_init[i,k] - x_init[j,k])^2 for k in 1:dim)
        set_start_value(z[i, j], d_sq)
        set_start_value(mu[i, j], d_sq^2)
        set_start_value(w[i, j], d_sq^3)
        set_start_value(r[i, j], c6 / d_sq^3)
    end

    @objective(m, Min, sum((r[i, j] - Q[i, j])^2 for i in 1:n, j in i+1:n))

    for i in 1:n, j in i+1:n
        X_vec = [r[i,j], w[i,j], mu[i,j], z[i,j], x[i,1], x[i,2], x[j,1], x[j,2]]

        Q1 = zeros(8, 8); Q1[1,2] = 1; Q1[2,1] = 1
        @constraint(m, 0.5 * X_vec' * Q1 * X_vec == c6)

        Q2 = zeros(8, 8); Q2[3,4] = 1; Q2[4,3] = 1
        b2 = zeros(8); b2[2] = -1
        @constraint(m, 0.5 * X_vec' * Q2 * X_vec + b2' * X_vec == 0)

        Q3 = zeros(8, 8); Q3[4,4] = 2
        b3 = zeros(8); b3[3] = -1
        @constraint(m, 0.5 * X_vec' * Q3 * X_vec + b3' * X_vec == 0)

        Q4 = zeros(8, 8)
        Q4[5,5] = 2; Q4[6,6] = 2
        Q4[7,7] = 2; Q4[8,8] = 2
        Q4[5,7] = -2; Q4[7,5] = -2
        Q4[6,8] = -2; Q4[8,6] = -2
        b4 = zeros(8); b4[4] = -1
        @constraint(m, 0.5 * X_vec' * Q4 * X_vec + b4' * X_vec == 0)
        @constraint(m, z[i,j] >= z_min)
    end

    optimize!(m)
    status = termination_status(m)
    if status in [MOI.LOCALLY_SOLVED, MOI.ALMOST_LOCALLY_SOLVED, MOI.ITERATION_LIMIT, MOI.SLOW_PROGRESS]
        return (status, objective_value(m), value.(x))
    end
    return nothing
end

# ═══════════════════════════════════════════════════════════════
#  §6  FORMULATION 4 — MDS EXACT (solution algébrique globale)
#
#  Q_ij = c6/d_ij^6  →  d_ij = (c6/Q_ij)^(1/6)  exactement connu
#  → Positionnement par distances via double centrage + eigendecomposition
#  → Erreur Rydberg ≈ 0 garanti si Q parfait, O(n³), sans itération
# ═══════════════════════════════════════════════════════════════
function solve_mds(n, dim, Q, c6)
    # Étape 1 : distances cibles
    D = zeros(n, n)
    for i in 1:n, j in i+1:n
        d_ij = (c6 / Q[i,j])^(1/6)
        D[i,j] = d_ij;  D[j,i] = d_ij
    end

    # Étape 2 : double centrage → matrice de Gram
    D2 = D .^ 2
    H  = I - ones(n,n) / n
    B  = Symmetric(-0.5 * H * D2 * H)

    # Étape 3 : décomposition spectrale
    F      = eigen(B)
    λ      = F.values
    V      = F.vectors
    idx    = sortperm(λ, rev=true)[1:dim]
    λ_top  = max.(λ[idx], 0.0)

    # Étape 4 : positions X = V · √Λ
    X_mds = V[:, idx] * Diagonal(sqrt.(λ_top))

    # Translation pour centrer dans R² (pas d'impact sur erreur)
    for d in 1:dim
        X_mds[:, d] .-= minimum(X_mds[:, d])
    end

    return (:MDS_EXACT, X_mds)
end

# ═══════════════════════════════════════════════════════════════
#  §7  RUNNER (NLP avec multistart)
# ═══════════════════════════════════════════════════════════════
function run_formulation(solver_fn, n, dim, Q, c6, L, x_inits_shared,multistart::Bool)
    t0          = time()
    best_obj    = Inf
    best_ry     = Inf
    best_status = "ÉCHEC"
    best_x      = nothing
    n_runs      = multistart ? length(x_inits_shared) : 1
    n_used      = 0

    for k in 1:n_runs
        res = solver_fn(n, dim, Q, c6, L, x_inits_shared[k])
        n_used += 1
        if res !== nothing
            stat, obj, x_sol = res
            ry = erreur_rydberg_vraie(x_sol, Q, c6, n, dim)
            if ry < best_ry
                best_ry     = ry
                best_obj    = obj
                best_status = string(stat)
                best_x      = x_sol
            end
            best_ry < 1e-12 && break
        end
    end

    return (best_obj, best_ry, best_status, best_x, n_used, time()-t0)
end

# ═══════════════════════════════════════════════════════════════
#  §8  BOUCLE PRINCIPALE
# ═══════════════════════════════════════════════════════════════
function normalize_formulation_name(s::AbstractString)
    t = lowercase(strip(s))
    t in ("std", "standard") && return "Standard"
    t in ("reform", "reformulee", "reformulée") && return "Reformulee"
    t in ("pol", "polaire") && return "Polaire"
    t in ("surogate", "surrogate") && return "Surogate"
    t in ("quad", "quadratique") && return "Quadratique"
    t in ("mds", "mds_exact", "mdsexact") && return "MDS_Exact"
    return s
end

function run_benchmark(n_values, dim, c6; formulations::Vector{String}=["Standard", "Reformulee", "Polaire", "Surogate", "Quadratique", "MDS_Exact"], L_types::Vector{String}=ALL_L_TYPES)
    df = DataFrame(
        n            = Int[],
        L_type       = String[],
        L_val        = Float64[],
        strategy     = String[],
        formulation  = String[],
        obj_solver   = Float64[],
        obj_rydberg  = Float64[],
        rmse_dist    = Float64[],
        n_restarts   = Int[],
        time_s       = Float64[],
        status       = String[]
    )

    forms_set = Set(formulations)
    nlp_forms = Pair{String, Any}[]
    "Standard" in forms_set    && push!(nlp_forms, "Standard"    => solve_standard)
    "Reformulee" in forms_set  && push!(nlp_forms, "Reformulee"  => solve_reformulee)
    "Polaire" in forms_set     && push!(nlp_forms, "Polaire"     => solve_polaire)
    "Surogate" in forms_set    && push!(nlp_forms, "Surogate"    => solve_surogate)
    "Quadratique" in forms_set && push!(nlp_forms, "Quadratique" => solve_quadratique)
    include_mds = "MDS_Exact" in forms_set

    for n in n_values
        for L_type in L_types
            if L_type == "L_optimal"
                x_vrais = generer_init(n, dim, L_SEED)
                Q_local = build_Q_matrix(x_vrais, c6, n)
                L = L_optimal_from_Q(Q_local, c6, n)
            else
                L = L_value(L_type, n; c6=c6)
                x_vrais = generer_init(n, dim, L)
                Q_local = build_Q_matrix(x_vrais, c6, n)
            end

            println("\n" * "═"^62)
            @printf("  n=%-3d  |  %s  (L=%.4f)\n", n, L_type, L)
            println("═"^62)

            n_rs           = nb_restarts_bench(n)
            x_inits_shared = [generer_init(n, dim, L) for _ in 1:n_rs]

            x_mds = nothing
            if include_mds
                # ── MDS : un seul appel algébrique ─────────────────
                t_mds = @elapsed begin
                    _, x_mds = solve_mds(n, dim, Q_local, c6)
                end
                ry_mds = erreur_rydberg_vraie(x_mds, Q_local, c6, n, dim)
                rmse_mds = rmse_dist_safe(x_mds, x_vrais, n)
                @printf("    [%-12s] obj_rydberg=%+.3e  rmse_dist=%.4e  t=%8.5fs  [EXACT]\n",
                        "MDS_Exact", ry_mds, rmse_mds, t_mds)
                push!(df, (n, L_type, L, "exact", "MDS_Exact",
                           0.0, ry_mds, rmse_mds, 1, t_mds, "MDS_EXACT"))
            end

            # ── NLP : single et multistart ──────────────────────
            for (strategy_name, use_multistart) in [("single",     false),
                                                     ("multistart", true)]
                println("\n  ── Stratégie : $strategy_name ──")
                sols_config = Dict{String, Union{Nothing, Matrix{Float64}}}()

                for (form_name, solver_fn) in nlp_forms
                    obj_s, obj_ry, stat_s, x_sol, n_used, t_s =run_formulation(solver_fn, n, dim, Q_local, c6, L, x_inits_shared, use_multistart)
                    sols_config[form_name] = x_sol
                    rmse_s = rmse_dist_safe(x_sol, x_vrais, n)
                    @printf("    [%-12s] obj_solver=%+.3e  obj_rydberg=%+.3e  rmse_dist=%.4e  t=%6.2fs  [%s]\n",
                            form_name, obj_s, obj_ry, rmse_s, t_s,
                            stat_s[1:min(20, length(stat_s))])
                    push!(df, (n, L_type, L, strategy_name, form_name,
                               obj_s, obj_ry, rmse_s, n_used, t_s, stat_s))
                end

                if include_mds
                    println("\n    ┌── Injection croisée ──────────────────────────┐")
                    scores = Float64[]
                    all_forms = vcat(nlp_forms, [("MDS_Exact", nothing)])
                    sols_config["MDS_Exact"] = x_mds
                    for (f, _) in all_forms
                        ry = erreur_rydberg_vraie(sols_config[f], Q_local, c6, n, dim)
                        rmse_f = rmse_dist_safe(sols_config[f], x_vrais, n)
                        push!(scores, ry)
                        @printf("    │  x_sol[%-12s] → err_Rydberg = %+.3e  rmse_dist = %.4e\n", f, ry, rmse_f)
                    end
                    best_form = all_forms[argmin(scores)][1]
                    println("    │  → GAGNANT : $best_form")
                    println("    └──────────────────────────────────────────────────┘")
                end
            end
        end
    end
    return df
end

const bench_results = run_benchmark(n_values, dim, c6)

# ═══════════════════════════════════════════════════════════════
#  §9  TABLEAU FINAL
# ═══════════════════════════════════════════════════════════════
println("\n\n" * "═"^70)
println("  TABLEAU COMPARATIF FINAL — obj_rydberg (métrique universelle)")
println("═"^70)

println("─"^70)
for grp in groupby(bench_results, [:n, :L_type])
    r = grp[1,:]
    @printf("\n  n=%-3d  %s\n", r.n, r.L_type)
    min_ry = minimum(replace(grp.obj_rydberg, Inf => 1e300))
    for row in eachrow(grp)
        ry_cmp = isinf(row.obj_rydberg) ? 1e300 : row.obj_rydberg
        marker = ry_cmp == min_ry ? " ← ★" : ""
        @printf("    %-12s [%-11s]  obj_ry=%+.4e  rmse=%.4e  t=%7.4fs%s\n",
                row.formulation, row.strategy,
                row.obj_rydberg, row.rmse_dist, row.time_s, marker)
    end
end

csv_path = joinpath(@__DIR__, "benchmark_formulations_test_L_huge.csv")
CSV.write(csv_path, bench_results)
println("\n\nRésultats sauvegardés : $csv_path")
println("═"^70)

# ═══════════════════════════════════════════════════════════════
#  §10  VISUALISATION — 4 GRAPHIQUES (3 formulations NLP + MDS)
# ═══════════════════════════════════════════════════════════════
println("\nGénération des graphiques...")

COULEURS = Dict(
    "Standard"    => :steelblue,
    "Reformulee"  => :darkorange,
    "Polaire"     => :seagreen,
    "Surogate"    => :mediumpurple,
    "Quadratique" => :goldenrod,
    "MDS_Exact"   => :crimson
)
FORMS_NLP = ["Standard", "Reformulee", "Polaire", "Surogate", "Quadratique"]
FORMS_ALL = ["Standard", "Reformulee", "Polaire", "Surogate", "Quadratique", "MDS_Exact"]
LABELS_NLP = ["Standard", "Reformulée", "Polaire", "Surogate", "Quadratique"]
LABELS_ALL = ["Standard", "Reformulée", "Polaire", "Surogate", "Quadratique", "MDS Exact"]
LINE_STYLES_NLP = [:solid, :dash, :dot, :dashdot, :dashdotdot]
n_str = string.(n_values)

safe(x) = isinf(x) || isnan(x) ? NaN : x

function positive_finite_values(series_list)
    vals = Float64[]
    for series in series_list
        append!(vals, filter(x -> isfinite(x) && x > 0, series))
    end
    return vals
end

# Fonction utilitaire de recherche dans le DataFrame
function get_ry(df, n, L_type, strategy, form)
    rows = filter(r -> r.n == n && r.L_type == L_type &&
                       r.strategy == strategy && r.formulation == form,
                  eachrow(df))
    isempty(rows) ? NaN : safe(first(rows).obj_rydberg)
end

function get_time(df, n, L_type, strategy, form)
    rows = filter(r -> r.n == n && r.L_type == L_type &&
                       r.strategy == strategy && r.formulation == form,
                  eachrow(df))
    isempty(rows) ? NaN : first(rows).time_s
end

function get_rmse(df, n, L_type, strategy, form)
    rows = filter(r -> r.n == n && r.L_type == L_type &&
                       r.strategy == strategy && r.formulation == form,
                  eachrow(df))
    isempty(rows) ? NaN : safe(first(rows).rmse_dist)
end

# ─── Plot 1 : Erreur Rydberg — multistart, L fixe ───────────────────────────
series_p1 = [
    [get_ry(bench_results, n, "L_fixe", "multistart", form) for n in n_values]
    for form in FORMS_NLP
]
vals_mds = [get_ry(bench_results, n, "L_fixe", "exact", "MDS_Exact") for n in n_values]
all_p1 = positive_finite_values(vcat(series_p1, [vals_mds]))

if !isempty(all_p1)
    p1 = plot(title="Erreur Rydberg — Multistart + MDS, L fixe (L=10)",
              xlabel="n (atomes)", ylabel="Erreur Rydberg (log₁₀)",
              legend=:topleft, yscale=:log10,
              ylims=(minimum(all_p1)/10, maximum(all_p1)*10),
              xticks=(1:length(n_values), n_str),
              yminorgrid=false, size=(600,400))
else
    p1 = plot(title="Erreur Rydberg — Multistart + MDS, L fixe (L=10)",
              xlabel="n (atomes)", ylabel="Erreur Rydberg",
              legend=:topleft,
              xticks=(1:length(n_values), n_str),
              yminorgrid=false, size=(600,400))
end

for (form, lab) in zip(FORMS_NLP, LABELS_NLP)
    vals = get_ry.(Ref(bench_results), n_values, Ref("L_fixe"), Ref("multistart"), Ref(form))
    plot!(p1, 1:length(n_values), vals,
          label=lab, color=COULEURS[form],
          marker=:circle, markersize=6, linewidth=2,
          linestyle=LINE_STYLES_NLP[findfirst(==(form), FORMS_NLP)])
end

# MDS (stratégie "exact")
plot!(p1, 1:length(n_values), vals_mds,
      label="MDS Exact", color=COULEURS["MDS_Exact"],
      marker=:star5, markersize=9, linewidth=2, linestyle=:dash)

# ─── Plot 2 : Erreur Rydberg — multistart, L adaptatif ──────────────────────
series_p2 = [
    [get_ry(bench_results, n, "L_adaptatif", "multistart", form) for n in n_values]
    for form in FORMS_NLP
]
vals_mds2 = [get_ry(bench_results, n, "L_adaptatif", "exact", "MDS_Exact") for n in n_values]
all_p2 = positive_finite_values(vcat(series_p2, [vals_mds2]))

if !isempty(all_p2)
    p2 = plot(title="Erreur Rydberg — Multistart + MDS, L adaptatif (L=2√n)",
              xlabel="n (atomes)", ylabel="Erreur Rydberg (log₁₀)",
              legend=:topleft, yscale=:log10,
              ylims=(minimum(all_p2)/10, maximum(all_p2)*10),
              xticks=(1:length(n_values), n_str),
              yminorgrid=false, size=(600,400))
else
    p2 = plot(title="Erreur Rydberg — Multistart + MDS, L adaptatif (L=2√n)",
              xlabel="n (atomes)", ylabel="Erreur Rydberg",
              legend=:topleft,
              xticks=(1:length(n_values), n_str),
              yminorgrid=false, size=(600,400))
end

for (form, lab) in zip(FORMS_NLP, LABELS_NLP)
    vals = get_ry.(Ref(bench_results), n_values, Ref("L_adaptatif"), Ref("multistart"), Ref(form))
    plot!(p2, 1:length(n_values), vals,
          label=lab, color=COULEURS[form],
        marker=:square, markersize=6, linewidth=2,
        linestyle=LINE_STYLES_NLP[findfirst(==(form), FORMS_NLP)])
end
plot!(p2, 1:length(n_values), vals_mds2,
      label="MDS Exact", color=COULEURS["MDS_Exact"],
      marker=:star5, markersize=9, linewidth=2, linestyle=:dash)

annotate!(p2, 1.55, maximum(all_p2) / 1.8,
        text("Sous L adaptatif, les courbes sont presque\nsuperposées : les erreurs sont très proches.",
           8, :gray35))

# ─── Plot 2b : Erreur Rydberg — multistart, L optimal ───────────────────────
series_p2b = [
    [get_ry(bench_results, n, "L_optimal", "multistart", form) for n in n_values]
    for form in FORMS_NLP
]
vals_mds_opt = [get_ry(bench_results, n, "L_optimal", "exact", "MDS_Exact") for n in n_values]
all_p2b = positive_finite_values(vcat(series_p2b, [vals_mds_opt]))

if !isempty(all_p2b)
    p2b = plot(title="Erreur Rydberg — Multistart + MDS, L optimal (L=(c₆/max Q)^(1/6))",
               xlabel="n (atomes)", ylabel="Erreur Rydberg (log₁₀)",
               legend=:topleft, yscale=:log10,
               ylims=(minimum(all_p2b)/10, maximum(all_p2b)*10),
               xticks=(1:length(n_values), n_str),
               yminorgrid=false, size=(600,400))
else
    p2b = plot(title="Erreur Rydberg — Multistart + MDS, L optimal (L=(c₆/max Q)^(1/6))",
               xlabel="n (atomes)", ylabel="Erreur Rydberg",
               legend=:topleft,
               xticks=(1:length(n_values), n_str),
               yminorgrid=false, size=(600,400))
end

for (form, lab) in zip(FORMS_NLP, LABELS_NLP)
    vals = get_ry.(Ref(bench_results), n_values, Ref("L_optimal"), Ref("multistart"), Ref(form))
    plot!(p2b, 1:length(n_values), vals,
          label=lab, color=COULEURS[form],
          marker=:utriangle, markersize=6, linewidth=2,
          linestyle=LINE_STYLES_NLP[findfirst(==(form), FORMS_NLP)])
end
plot!(p2b, 1:length(n_values), vals_mds_opt,
      label="MDS Exact", color=COULEURS["MDS_Exact"],
      marker=:star5, markersize=9, linewidth=2, linestyle=:dash)

# ─── Plot 3 : Temps d'exécution — multistart + MDS, L fixe ─────────────────
# 4 formulations → inner=4
n_f = length(FORMS_ALL)
time_vals = [
    get_time(bench_results, n, "L_fixe",
             form == "MDS_Exact" ? "exact" : "multistart", form)
    for n in n_values for form in FORMS_ALL
]

p3 = groupedbar(
    repeat(n_str, inner=n_f),
    time_vals,
    group     = repeat(LABELS_ALL, outer=length(n_values)),
    title     = "Temps total — Multistart + MDS, L fixe",
    xlabel    = "n (atomes)",
    ylabel    = "Temps (secondes)",
    color     = reshape([COULEURS[f] for f in FORMS_ALL], 1, n_f),
    bar_width = 0.7,
    legend    = :topleft,
    size      = (600, 400)
)

# ─── Plot 4 : Gain multistart vs single — L fixe (NLP seulement) ────────────
# MDS n'a pas de notion single/multistart → exclu de ce graphique
ratio_series = Dict{String, Vector{Float64}}()
all_ratios = Float64[]
for form in FORMS_NLP
    ratios = Float64[]
    for n in n_values
        ry_s = get_ry(bench_results, n, "L_fixe", "single", form)
        ry_m = get_ry(bench_results, n, "L_fixe", "multistart", form)
        ratio = if isfinite(ry_s) && isfinite(ry_m) && ry_m > 0
            ry_s / ry_m
        elseif !isfinite(ry_s) && isfinite(ry_m)
            1e6
        else
            NaN
        end
        push!(ratios, ratio)
    end
    ratio_series[form] = ratios
    append!(all_ratios, filter(x -> isfinite(x) && x > 0, ratios))
end

if !isempty(all_ratios)
    p4 = plot(title="Gain multistart (ratio single/multi) — L fixe",
              xlabel="n (atomes)", ylabel="Ratio obj_single / obj_multi",
              legend=:topright, yscale=:log10,
              ylims=(minimum(all_ratios)/10, maximum(all_ratios)*10),
              xticks=(1:length(n_values), n_str),
              yminorgrid=false, size=(600,400))
else
    p4 = plot(title="Gain multistart (ratio single/multi) — L fixe",
              xlabel="n (atomes)", ylabel="Ratio obj_single / obj_multi",
              legend=:topright,
              xticks=(1:length(n_values), n_str),
              yminorgrid=false, size=(600,400))
end

hline!(p4, [1.0], linestyle=:dash, color=:black,
       label="ratio=1 (aucun gain)", linewidth=1)

for (form, lab) in zip(FORMS_NLP, LABELS_NLP)
    ratios = ratio_series[form]
    plot!(p4, 1:length(n_values), ratios,
          label=lab, color=COULEURS[form],
          marker=:diamond, markersize=7, linewidth=2)
end

# Note MDS sur le graphique
annotate!(p4, length(n_values)/2, 1e4,
          text("MDS toujours ≈ 0\n(pas de notion single/multi)", 8, :gray))

# ─── Assemblage final ────────────────────────────────────────────────────────
fig = plot(p1, p2, p2b, p3, p4,
           layout     = (3, 2),
           size       = (1300, 1200),
           margin     = 6Plots.mm,
           plot_title = "Benchmark — 3 formulations NLP + MDS exact")

fig_path = joinpath(@__DIR__, "benchmark_visualisation_mds_test_L_huge.png")
savefig(fig, fig_path)
println("\nGraphique sauvegardé : $fig_path")
display(fig)

function plot_rmse_multistart(df, L_type, L_label)
    series = [
        [get_rmse(df, n, L_type, "multistart", form) for n in n_values]
        for form in FORMS_NLP
    ]
    vals_mds = [get_rmse(df, n, L_type, "exact", "MDS_Exact") for n in n_values]
    all_vals = positive_finite_values(vcat(series, [vals_mds]))

    p = if !isempty(all_vals)
        plot(title="RMSE distances — Multistart + MDS, $L_label",
             xlabel="n (atomes)", ylabel="RMSE distances (log₁₀)",
             legend=:topleft, yscale=:log10,
             ylims=(minimum(all_vals)/10, maximum(all_vals)*10),
             xticks=(1:length(n_values), n_str),
             yminorgrid=false, size=(600, 400))
    else
        plot(title="RMSE distances — Multistart + MDS, $L_label",
             xlabel="n (atomes)", ylabel="RMSE distances",
             legend=:topleft,
             xticks=(1:length(n_values), n_str),
             yminorgrid=false, size=(600, 400))
    end

    for (form, lab) in zip(FORMS_NLP, LABELS_NLP)
        vals = get_rmse.(Ref(df), n_values, Ref(L_type), Ref("multistart"), Ref(form))
        plot!(p, 1:length(n_values), vals,
              label=lab, color=COULEURS[form],
              marker=:circle, markersize=6, linewidth=2,
              linestyle=LINE_STYLES_NLP[findfirst(==(form), FORMS_NLP)])
    end
    plot!(p, 1:length(n_values), vals_mds,
          label="MDS Exact", color=COULEURS["MDS_Exact"],
          marker=:star5, markersize=9, linewidth=2, linestyle=:dash)
    return p
end

fig_rmse = plot(
    plot_rmse_multistart(bench_results, "L_fixe", "L fixe"),
    plot_rmse_multistart(bench_results, "L_adaptatif", "L adaptatif"),
    plot_rmse_multistart(bench_results, "L_optimal", "L optimal"),
    layout=(3, 1), size=(700, 1100), margin=6Plots.mm,
    plot_title="RMSE distances — toutes formulations et L"
)
fig_rmse_path = joinpath(@__DIR__, "benchmark_rmse_dist.png")
savefig(fig_rmse, fig_rmse_path)
println("Graphique RMSE sauvegardé : $fig_rmse_path")
display(fig_rmse)

# ═══════════════════════════════════════════════════════════════
#  §11  BENCHMARK AVEC BRUIT
#  Seul ajout : on reboucle sur les mêmes n et formulations
#  mais avec Q bruité. x_inits régénérés pour chaque theta_bruit.
# ═══════════════════════════════════════════════════════════════
println("\n\n" * "═"^70)
println("  BENCHMARK AVEC BRUIT — robustesse des formulations")
println("═"^70)

bruit_niveaux = [0.0]

df_bruit = DataFrame(
    n           = Int[],
    L_type      = String[],
    L_val       = Float64[],
    sigma       = Float64[],
    formulation = String[],
    err_vs_vrai = Float64[],
    err_vs_bruit= Float64[],
    rmse_dist   = Float64[],
    time_s      = Float64[],
    Q           = String[],
    X           = String[],
    x_opt       = String[]
)

mds_positions = Dict{Tuple{Int,String,Float64}, Tuple{Matrix{Float64}, Matrix{Float64}}}()

nlp_forms_bruit = [
    ("Standard",    solve_standard),
    ("Reformulee",  solve_reformulee),
    ("Polaire",     solve_polaire),
    ("Surogate",    solve_surogate),
    ("Quadratique", solve_quadratique),
]

for n in n_values
    for L_type in ALL_L_TYPES
        if L_type == "L_optimal"
            x_vrais   = generer_init(n, dim, L_SEED)
            Q_parfait = build_Q_matrix(x_vrais, c6, n)
            L_bruit   = L_optimal_from_Q(Q_parfait, c6, n)
        else
            L_bruit   = L_value(L_type, n; c6=c6)
            x_vrais   = generer_init(n, dim, L_bruit)
            Q_parfait = build_Q_matrix(x_vrais, c6, n)
        end

        println("\n" * "═"^62)
        @printf("  n=%-3d  |  %s  (L=%.4f)\n", n, L_type, L_bruit)
        println("═"^62)

        for theta_bruit in bruit_niveaux
            @printf("\n  ── theta_bruit = %.0f%% ──\n", theta_bruit * 100)

            Q_bruit = ajouter_bruit(Q_parfait, theta_bruit, n)
            Q_str = matrix_to_csv_str(Q_bruit)
            X_str = matrix_to_csv_str(x_vrais)

            # x_inits régénérés pour chaque theta_bruit (pas de biais)
            n_rs           = nb_restarts_bench(n)
            x_inits_shared = [generer_init(n, dim, L_bruit) for _ in 1:n_rs]

            # MDS sur Q bruité
            t_mds = @elapsed begin
                _, x_mds = solve_mds(n, dim, Q_bruit, c6)
            end
            ev_mds = erreur_rydberg_vraie(x_mds, Q_parfait, c6, n, dim)
            eb_mds = erreur_rydberg_vraie(x_mds, Q_bruit,   c6, n, dim)
            rmse_mds = rmse_dist_safe(x_mds, x_vrais, n)
            @printf("    [%-12s] err_vrai=%+.3e  err_bruit=%+.3e  rmse_dist=%.4e  t=%.4fs\n",
                    "MDS_Exact", ev_mds, eb_mds, rmse_mds, t_mds)
            x_opt_str = matrix_to_csv_str(x_mds)
            mds_positions[(n, L_type, theta_bruit)] = (copy(x_vrais), copy(x_mds))
            push!(df_bruit, (n, L_type, L_bruit, theta_bruit, "MDS_Exact",
                             ev_mds, eb_mds, rmse_mds, t_mds, Q_str, X_str, x_opt_str))

            # NLP multistart sur Q bruité 
            for (form_name, solver_fn) in nlp_forms_bruit
                ry_bruit, stat_s, x_sol, t_s =
                    begin
                        t0 = time()
                        br = Inf; bs = "ÉCHEC"; bx = nothing
                        for k in 1:n_rs
                            res = solver_fn(n, dim, Q_bruit, c6, L_bruit, x_inits_shared[k])
                            if res !== nothing
                                stat, obj, xs = res
                                ry = erreur_rydberg_vraie(xs, Q_bruit, c6, n, dim)
                                if ry < br; br = ry; bs = string(stat); bx = xs; end
                                br < 1e-12 && break
                            end
                        end
                        (br, bs, bx, time()-t0)
                    end
                ry_vrai = erreur_rydberg_vraie(x_sol, Q_parfait, c6, n, dim)
                rmse_s = rmse_dist_safe(x_sol, x_vrais, n)
                @printf("    [%-12s] err_vrai=%+.3e  err_bruit=%+.3e  rmse_dist=%.4e  t=%.2fs  [%s]\n",
                        form_name, ry_vrai, ry_bruit, rmse_s, t_s,
                        stat_s[1:min(20, length(stat_s))])
                push!(df_bruit, (n, L_type, L_bruit, theta_bruit, form_name,
                                 ry_vrai, ry_bruit, rmse_s, t_s, Q_str, X_str, ""))
            end
        end
    end
end

# Tableau bruit final
println("\n\n" * "═"^70)
println("  IMPACT DU BRUIT — err_vs_Qvrai (qualité de reconstruction)")
println("═"^70)
for grp in groupby(df_bruit, [:n, :L_type, :sigma])
    r = grp[1,:]
    @printf("\n  n=%-3d  %s  theta_bruit=%.0f%%\n", r.n, r.L_type, r.sigma * 100)
    min_ry = minimum(replace(grp.err_vs_vrai, Inf => 1e300))
    for row in eachrow(grp)
        ry_cmp = isinf(row.err_vs_vrai) ? 1e300 : row.err_vs_vrai
        marker = ry_cmp == min_ry ? " ← ★ MEILLEUR" : ""
        @printf("    %-12s  err_vrai=%+.4e  rmse=%.4e%s\n",
                row.formulation, row.err_vs_vrai, row.rmse_dist, marker)
    end
end

csv_bruit = joinpath(@__DIR__, "benchmark_bruit_test.csv")
CSV.write(csv_bruit, df_bruit)
println("\n\nRésultats bruit sauvegardés : $csv_bruit")
println("═"^70)

# ═══════════════════════════════════════════════════════════════
#  §12  VISUALISATION DU BRUIT
#  Deux métriques : err_vs_vrai et err_vs_bruit
#  Chaque figure compare L_fixe, L_adaptatif et L_optimal.
# ═══════════════════════════════════════════════════════════════
println("\nGénération des graphiques de bruit...")

function get_bruit_metric(df, n, L_type, sigma, form, metric::Symbol)
    rows = filter(r -> r.n == n && r.L_type == L_type &&
                       r.sigma == sigma && r.formulation == form,
                  eachrow(df))
    isempty(rows) ? NaN : safe(getproperty(first(rows), metric))
end

function plot_bruit_grid(df, metric::Symbol, metric_label::String)
    subplots = Any[]
    for n in n_values
        for L_type in ALL_L_TYPES
            series_list = [
                [get_bruit_metric(df, n, L_type, sigma, form, metric) for sigma in bruit_niveaux]
                for form in FORMS_ALL
            ]
            vals_pos = positive_finite_values(series_list)

            p = if !isempty(vals_pos)
                plot(title="n=$n — $L_type — $metric_label",
                     xlabel="σ bruit", ylabel=metric_label,
                     yscale=:log10,
                     ylims=(minimum(vals_pos) / 10, maximum(vals_pos) * 10),
                     xticks=(bruit_niveaux, string.(bruit_niveaux)),
                     legend=:topright, yminorgrid=false, size=(600, 380))
            else
                plot(title="n=$n — $L_type — $metric_label",
                     xlabel="σ bruit", ylabel=metric_label,
                     xticks=(bruit_niveaux, string.(bruit_niveaux)),
                     legend=:topright, yminorgrid=false, size=(600, 380))
            end

            for (form, lab) in zip(FORMS_ALL, LABELS_ALL)
                vals = [get_bruit_metric(df, n, L_type, sigma, form, metric) for sigma in bruit_niveaux]
                plot!(p, bruit_niveaux, vals,
                      label=lab, color=COULEURS[form],
                      marker=(form == "MDS_Exact" ? :star5 : :circle),
                      markersize=(form == "MDS_Exact" ? 8 : 6),
                      linewidth=2,
                      linestyle=(form == "MDS_Exact" ? :dash : LINE_STYLES_NLP[findfirst(==(form), FORMS_NLP)]))
            end

            push!(subplots, p)
        end
    end

    n_sub = length(subplots)
    n_cols = (n_sub % 2 == 0) ? 2 : 1
    n_rows = cld(n_sub, n_cols)

    return plot(subplots..., layout=(n_rows, n_cols),
                size=(1300, 500 * n_rows),
                margin=6Plots.mm,
                plot_title="Benchmark bruit — $metric_label")
end

fig_bruit_vrai = plot_bruit_grid(df_bruit, :err_vs_vrai, "Erreur vs Q vrai")
fig_bruit_bruit = plot_bruit_grid(df_bruit, :err_vs_bruit, "Erreur vs Q bruité")
fig_bruit_rmse = plot_bruit_grid(df_bruit, :rmse_dist, "RMSE distances")

path_bruit_vrai = joinpath(@__DIR__, "benchmark_bruit_vs_vrai.png")
path_bruit_bruit = joinpath(@__DIR__, "benchmark_bruit_vs_bruit.png")
path_bruit_rmse = joinpath(@__DIR__, "benchmark_bruit_rmse.png")

savefig(fig_bruit_vrai, path_bruit_vrai)
savefig(fig_bruit_bruit, path_bruit_bruit)
savefig(fig_bruit_rmse, path_bruit_rmse)

println("Graphique bruit sauvegardé : $path_bruit_vrai")
println("Graphique bruit sauvegardé : $path_bruit_bruit")
println("Graphique bruit sauvegardé : $path_bruit_rmse")
display(fig_bruit_vrai)
display(fig_bruit_bruit)
display(fig_bruit_rmse)

# ═══════════════════════════════════════════════════════════════
#  §13  VISUALISATION DES POSITIONS — MDS Exact vs X vrai
#  Un sous-graphe par (n, L_type) pour toutes les valeurs de n
# ═══════════════════════════════════════════════════════════════
println("\nGénération des graphiques MDS Exact (X vrai vs x_opt)...")

function align_to_reference(X_ref::Matrix{Float64}, X_est::Matrix{Float64})
    μ_ref = vec(mean(X_ref, dims=1))
    μ_est = vec(mean(X_est, dims=1))

    Xr = X_ref .- reshape(μ_ref, 1, :)
    Xe = X_est .- reshape(μ_est, 1, :)

    M = transpose(Xe) * Xr
    F = svd(M)
    R = F.U * F.Vt

    if det(R) < 0
        S = Matrix{Float64}(I, size(R, 1), size(R, 2))
        S[end, end] = -1.0
        R = F.U * S * F.Vt
    end

    Xa = Xe * R
    Xa .+= reshape(μ_ref, 1, :)
    return Xa
end

function plot_mds_positions_grid(positions::Dict, sigma::Float64)
    subplots = Any[]
    for n in n_values
        for L_type in ALL_L_TYPES
            key = (n, L_type, sigma)
            if !haskey(positions, key)
                continue
            end
            x_vrai, x_mds = positions[key]
            x_mds_aligne = align_to_reference(x_vrai, x_mds)

            p = scatter(x_vrai[:, 1], x_vrai[:, 2],
                        label="X vrai",
                        color=:black,
                        marker=:diamond,
                        markersize=7,
                        markerstrokewidth=0,
                        xlabel="x", ylabel="y",
                        title="n=$n — $L_type",
                        legend=:topright,
                        aspect_ratio=:equal,
                        size=(520, 420))

            scatter!(p, x_mds_aligne[:, 1], x_mds_aligne[:, 2],
                     label="MDS Exact (x_opt)",
                     color=COULEURS["MDS_Exact"],
                     marker=:star5,
                     markersize=8,
                     markerstrokewidth=0)

            for i in 1:n
                annotate!(p, x_vrai[i, 1], x_vrai[i, 2], text(string(i), 7, :black))
            end

            push!(subplots, p)
        end
    end

    n_sub = length(subplots)
    n_cols = min(3, n_sub)
    n_rows = cld(n_sub, n_cols)

    return plot(subplots...,
                layout=(n_rows, n_cols),
                size=(520 * n_cols, 420 * n_rows),
                margin=6Plots.mm,
                plot_title="MDS Exact — positions X vrai vs x_opt (σ=$(sigma))")
end

sigma_plot = first(bruit_niveaux)
fig_mds_positions = plot_mds_positions_grid(mds_positions, sigma_plot)

path_mds_positions = joinpath(@__DIR__, "benchmark_positions_mds_exact.png")
savefig(fig_mds_positions, path_mds_positions)
println("Graphique positions MDS Exact sauvegardé : $path_mds_positions")
display(fig_mds_positions)

# ═══════════════════════════════════════════════════════════════
#  §14  FONCTION START() — LANCEUR CONFIGURÉ
# ═══════════════════════════════════════════════════════════════
function start(;
    n_vals::Vector{Int} = [3, 10],
    formulations::Vector{String} = ["Standard", "Reformulee", "Polaire", "Surogate", "Quadratique", "MDS"],
    L_types::Vector{String} = ALL_L_TYPES,
    noise_levels::Vector{Float64} = [0.0, 0.01, 0.05, 0.10, 0.20, 0.30],
    vis_n::Int = maximum(n_vals),
    vis_L::String = "L_adaptatif",
    vis_sigma::Float64 = 0.10,
    verbose::Bool = true
)
    """
    Lance le benchmark complet avec configuration flexible.

    # Paramètres
    - n_vals: tailles de problèmes à tester
    - formulations: liste de formulations ("Standard", "Reformulee", "Polaire", "Surogate", "Quadratique", "MDS")
    - L_types: configurations de L ("L_fixe", "L_adaptatif", "L_optimal")
    - noise_levels: niveaux de bruit à tester
    - vis_n: taille pour visualisation des positions
    - vis_L: type de L pour visualisation
    - vis_sigma: niveau de bruit pour visualisation
    - verbose: affiche les détails

    # Exemples
    start()  # tous les defaults
    start(n_vals=[2,3], formulations=["MDS", "Polaire"])
    start(formulations=["Standard", "Polaire"])
    """

    canonical_forms = unique(normalize_formulation_name.(formulations))
    canonical_forms = filter(f -> f in ["Standard", "Reformulee", "Polaire", "Surogate", "Quadratique", "MDS_Exact"], canonical_forms)

    verbose && println("\n" * "═"^70)
    verbose && println("  BENCHMARK CONFIGURÉ")
    verbose && println("═"^70)
    verbose && @printf("  n: %s\n", n_vals)
    verbose && @printf("  Formulations: %s\n", join(canonical_forms, ", "))
    verbose && @printf("  L: %s\n", join(L_types, ", "))
    verbose && @printf("  Niveaux de bruit: %s\n", join(string.(noise_levels), ", "))
    verbose && println("═"^70 * "\n")

    if isempty(canonical_forms)
        error("Aucune formulation valide. Utiliser Standard/std, Reformulee/reform, Polaire/pol, Surogate/surogate, Quadratique/quad, MDS/mds.")
    end

    df = run_benchmark(n_vals, dim, c6; formulations=canonical_forms, L_types=L_types)
    
    if verbose
        @printf("\n  Résultats calculés: %d lignes\n", nrow(df))
        for grp in groupby(df, [:formulation])
            f = first(grp).formulation
            @printf("  - %s : %d lignes\n", f, nrow(grp))
        end
    end

    return df
end

# ─── LANCER LE BENCHMARK ───────────────────────────────────────
# Configuration par défaut
if abspath(PROGRAM_FILE) == @__FILE__
    #start(n_vals=[3,10,20,50,100], formulations=["std", "reform", "pol", "mds"], L_types=ALL_L_TYPES, noise_levels=[0.0, 0.10, 0.20, 0.30])
    start(n_vals=[1000], formulations=["mds"], L_types=ALL_L_TYPES, noise_levels=[0.99])

end

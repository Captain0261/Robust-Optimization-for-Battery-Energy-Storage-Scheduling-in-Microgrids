using JuMP, Gurobi, CSV, DataFrames

cluster_id = 4  # Choose cluster 1/2/3/4

function solve_robust_models()
    T = 24
    max_iter = 100
    epsilon = 1e-4

    E_max = 2000 #kWh
    P_cmax = E_max / 2
    P_dmax = E_max / 2

    eta_char = 0.95
    eta_dis = 0.95

    Soc_min = 0.1 * E_max
    Soc_max = 0.95 * E_max

    # P_load and Price_DA
    demand_and_price = CSV.read("demand_and_price.csv", DataFrame)
    Price_DA = demand_and_price[!, :Price_DA]
    P_load = demand_and_price[!, :Demand]

    # Price_RT
    Price_RT_buy = 1.3 * Price_DA
    Price_RT_sell = 0.7 * Price_DA

    Big_M = 5 * Price_RT_buy

    # P_re
    re_energy = CSV.read("Robust_Parameters.csv", DataFrame)

    P_PV = Symbol("P_bar_PV_Cluster$cluster_id")
    P_Wind = Symbol("P_bar_Wind_Cluster$cluster_id")
    Delta_PV = Symbol("Delta_P_PV_Cluster$cluster_id")
    Delta_Wind = Symbol("Delta_P_Wind_Cluster$cluster_id")

    P_re_PV = re_energy[!, P_PV]
    P_re_Wind = re_energy[!, P_Wind]
    P_re = P_re_PV + P_re_Wind

    Delta_P_PV = re_energy[!, Delta_PV]
    Delta_P_Wind = re_energy[!, Delta_Wind]
    Delta_P_re = Delta_P_PV + Delta_P_Wind

    for Gamma in 0:24
        println("\n" * "*"^50)
        println("Starting Optimization for Gamma = $Gamma")
        println("*"^50)

        UB = Inf
        LB = -Inf
        gap = Inf
        k = 1
        worst_xi = []

        P_RT_buy = Dict()
        P_RT_sell = Dict()

        mp = Model(Gurobi.Optimizer)
        set_silent(mp)

        @variable(mp, P_DA[1:T] >= 0)
        @variable(mp, 0 <= P_char[1:T] <= P_cmax)
        @variable(mp, 0 <= P_dis[1:T] <= P_dmax)

        @variable(mp, u_char[1:T], Bin)
        @variable(mp, u_dis[1:T], Bin)

        @variable(mp, Soc_min <= Soc[0:T] <= Soc_max)
        @variable(mp, alpha >= 0)

        P_RT_buy[1] = @variable(mp, [1:T], lower_bound = 0, base_name = "P_RT_buy_1")
        P_RT_sell[1] = @variable(mp, [1:T], lower_bound = 0, base_name = "P_RT_sell_1")

        @objective(mp, Min, sum(Price_DA[t] * P_DA[t] for t in 1:T) + alpha)

        @constraint(mp, [t=1:T], u_char[t] + u_dis[t] <= 1)
        @constraint(mp, [t=1:T], P_char[t] <= P_cmax * u_char[t])
        @constraint(mp, [t=1:T], P_dis[t] <= P_dmax * u_dis[t])

        @constraint(mp, initial_Soc, Soc[0] == Soc_min)
        @constraint(mp, final_Soc, Soc[T] == Soc_min)

        @constraint(mp, alpha >= sum(Price_RT_buy[t] * P_RT_buy[1][t] -
                                     Price_RT_sell[t] * P_RT_sell[1][t] for t in 1:T))

        @constraint(mp, [t=1:T], P_DA[t] + P_dis[t] - P_char[t] ==
                                 P_load[t] - P_re[t] - P_RT_buy[1][t] + P_RT_sell[1][t])

        @constraint(mp, [t=1:T], Soc[t] == Soc[t-1] + eta_char * P_char[t] - P_dis[t] / eta_dis)

        log_filename = "C&CG_Iteration_Cluster$(cluster_id)_Gamma_$(Gamma).txt"
        open(log_filename, "w") do io
            redirect_stdout(io) do
                print("\nStart Column and Constraint Generation Algorithm for Gamma = $Gamma")

                while gap > epsilon && k <= max_iter
                    optimize!(mp)

                    LB = max(LB, objective_value(mp))

                    P_DA_star = value.(P_DA)
                    P_dis_star = value.(P_dis)
                    P_char_star = value.(P_char)

                    results = DataFrame(
                        Hour=1:T,
                        P_DA=[round(value(P_DA[t]), digits=3) for t in 1:T],
                        P_char=[round(value(P_char[t]), digits=3) for t in 1:T],
                        P_dis=[round(value(P_dis[t]), digits=3) for t in 1:T],
                        SOC=[round(value(Soc[t]), digits=3) for t in 1:T],
                        RT_buy=[round(value(P_RT_buy[k][t]), digits=3) for t in 1:T],
                        RT_sell=[round(value(P_RT_sell[k][t]), digits=3) for t in 1:T]
                    )

                    println("\n" * "="^80)
                    println("Iteration $k: Master Problem Dispatch")
                    println("="^80)
                    println(results)
                    println("="^80 * "\n")

                    sp = Model(Gurobi.Optimizer)
                    set_silent(sp)

                    @variable(sp, xi[1:T], Bin)
                    @constraint(sp, uncertain_set, sum(xi[t] for t in 1:T) <= Gamma)

                    @variable(sp, Price_RT_sell[t] <= pi[t=1:T] <= Price_RT_buy[t])
                    @variable(sp, omega[t=1:T])

                    @constraint(sp, [t=1:T], omega[t] >= - Big_M[t] * xi[t])
                    @constraint(sp, [t=1:T], omega[t] <= Big_M[t] * xi[t])
                    @constraint(sp, [t=1:T], omega[t] >= pi[t] - Big_M[t] * (1 - xi[t]))
                    @constraint(sp, [t=1:T], omega[t] <= pi[t] + Big_M[t] * (1 - xi[t]))

                    @objective(sp, Max,
                        sum(pi[t] * (P_load[t] - P_re[t] - P_DA_star[t] - P_dis_star[t] +
                                     P_char_star[t]) + omega[t] * Delta_P_re[t] for t in 1:T))

                    optimize!(sp)

                    DA_cost = sum(Price_DA[t] * P_DA_star[t] for t in 1:T)
                    UB = min(UB, objective_value(sp) + DA_cost)
                    gap = abs(UB - LB) / abs(LB)

                    print("Iteration $k: LB: $LB, UB: $UB, Gap: $gap")

                    xi_star = value.(xi)
                    push!(worst_xi, xi_star)

                    if gap > epsilon
                        k = k + 1
                        P_RT_buy[k] = @variable(mp, [1:T], lower_bound = 0, base_name="P_RT_buy_$k")
                        P_RT_sell[k] = @variable(mp, [1:T], lower_bound = 0, base_name="P_RT_sell_$k")

                        @constraint(mp, alpha >= sum(Price_RT_buy[t] * P_RT_buy[k][t] -
                                                     Price_RT_sell[t] * P_RT_sell[k][t] for t in 1:T))

                        @constraint(mp, [t=1:T], P_DA[t] + P_dis[t] - P_char[t] ==
                                                 P_load[t] - P_RT_buy[k][t] + P_RT_sell[k][t] -
                                                 P_re[t] + xi_star[t] * Delta_P_re[t])
                    end
                end
                print("\nDone! Iterated $k times for Gamma = $Gamma")
            end
        end

        final_results = DataFrame(
            Hour=1:T,
            P_DA=[round(value(P_DA[t]), digits=3) for t in 1:T],
            P_char=[round(value(P_char[t]), digits=3) for t in 1:T],
            P_dis=[round(value(P_dis[t]), digits=3) for t in 1:T],
            SOC=[round(value(Soc[t]), digits=3) for t in 1:T],
            RT_buy=[round(value(P_RT_buy[k][t]), digits=3) for t in 1:T],
            RT_sell=[round(value(P_RT_sell[k][t]), digits=3) for t in 1:T]
        )

        CSV.write("Final_Result_Cluster$(cluster_id)_Gamma_$(Gamma).csv", final_results)
    end
end

solve_robust_models()
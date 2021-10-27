using JuMP, Combinatorics, Gurobi

include("./algorithms/TEAVAR.jl")
include("./algorithms/FFC.jl")
include("./algorithms/ARROW.jl")  
include("./algorithms/OPTIMAL.jl")
include("./algorithms/HYPERTHETICAL.jl")

## locate the cut fiberlinks, get affected IP links from cut fiber
## for example, cutfiber = [6,14], which is (1,6), (6,1), the down ip links are (1,5) (1,6) (5,1) (6,1)
function FailureLocator(OpticalTopo, optical_failure_scenario)
    damage_links_index = []

    for l in 1:length(optical_failure_scenario)
        if optical_failure_scenario[l] == 0
            push!(damage_links_index, l)
        end
    end
    return damage_links_index
end


## Traffic engineering module
function TrafficEngineering(GRB_ENV, IPTopo, OpticalTopo, algorithm, links, capacity, demand, flows, T, Tf, scenarios, fiber_scenarios, scenario_probs, scenario_restored_bw, optical_rerouting_K, tunnelK, beta, purb, verbose, solve_or_not)
    best_options = ones(size(scenarios,1))  # only randomized rouding will return this other just 1
    best_scenario_resored_bw = []

    nflows = size(flows,1)
    nedges = size(links,1)
    ntunnels = tunnelK
    TunnelBw = zeros(nflows, ntunnels)
    FlowBw = zeros(nflows)
    var = 0
    throughput = 0
    solve_runtime = 0
    best_options = []
    best_scenario_resored_bw = 0

    if algorithm == "TEAVAR"
        var, cvar, TunnelBw, scenario_loss, loss, solve_t, opt_t = TEAVAR(GRB_ENV, links, capacity, flows, demand, beta, T, Tf, scenarios, scenario_probs, average=true)
        for f in 1:nflows
            FlowBw[f] = demand[f] * (1-var)
        end
        throughput = sum(FlowBw)
        solve_runtime = solve_t
    
    elseif algorithm == "FFC2"
        IPScenarios, OpticalScenarios = GetAllScenarios(IPTopo, OpticalTopo, 0, true, 2)  # all double fiber cut scenarios
        scenarios = IPScenarios["code"][2:end]  # FFC only take failure scenarios except healthy state
        TunnelBw, FlowBw, obj, solve_t, opt_t = FFC(GRB_ENV, links, capacity, flows, demand, scenarios, T, Tf) # here the ffc TunnelBw is the reserved bw of tunnels > actual demand
        throughput = sum(FlowBw)
        solve_runtime = solve_t

    elseif algorithm == "FFC1"
        IPScenarios, OpticalScenarios = GetAllScenarios(IPTopo, OpticalTopo, 0, true, 1)  # all single fiber cut scenarios
        scenarios = IPScenarios["code"][2:end]  # FFC only take failure scenarios except healthy state
        TunnelBw, FlowBw, obj, solve_t, opt_t = FFC(GRB_ENV, links, capacity, flows, demand, scenarios, T, Tf) # here the ffc TunnelBw is the reserved bw of tunnels > actual demand
        throughput = sum(FlowBw)
        solve_runtime = solve_t
        
    elseif algorithm == "ECMP"
        SplitRatio = ones(size(Tf,1), ntunnels) ./ ntunnels   # ECMP is equal SplitRatio
        TunnelBw = SplitRatio .* demand
        FlowBw = demand
        throughput = sum(FlowBw)
        solve_runtime = 0
    
    elseif algorithm == "ARROW_NAIVE"   # one restoration option made at planning stage
        # here we only put one option inside the TE and do not make selections
        TunnelBw, FlowBw, obj, solve_t, opt_t = ARROW_ONE(GRB_ENV, links, capacity, scenario_restored_bw, flows, demand, scenarios, T, Tf, verbose)
        throughput = sum(FlowBw)
        solve_runtime = solve_t

    elseif algorithm == "ARROW"   # ARROW TE
        TunnelBw, FlowBw, obj, v_restore, solve_t_1, opt_t_1 = ARROW(GRB_ENV, links, capacity, scenario_restored_bw, flows, demand, scenarios, T, Tf, purb, verbose)
        best_options, virtual_restore, best_option_diviation = RestoreMatchMinLoss(v_restore, scenario_restored_bw) # find best option for each failure scenario
        if verbose println("best_options: ", best_options) end
        if verbose println("virtual_restore: ", virtual_restore) end
        if verbose println("purb for sum delta: ", purb) end
        if verbose println("best_option_diviation ", best_option_diviation) end

        best_scenario_resored_bw = []
        nscenarios = size(scenario_restored_bw,1)
        nedges = size(links,1)
        for s in 1:nscenarios
            best_restore_bw = []
            for e in 1:nedges
                push!(best_restore_bw, scenario_restored_bw[s][Int(best_options[s])][e])
            end
            push!(best_scenario_resored_bw, best_restore_bw)
        end
        if verbose 
            print("ARROW best_scenario_resored_bw: sum=")
            println(sum(best_scenario_resored_bw))
            for rr in 1:size(best_scenario_resored_bw, 1)
                println(best_scenario_resored_bw[rr])
            end
            println("\n")
        end

        TunnelBw, FlowBw, obj, solve_t_2, opt_t_2 = ARROW_ONE(GRB_ENV, links, capacity, best_scenario_resored_bw, flows, demand, scenarios, T, Tf, verbose)
        
        throughput = sum(FlowBw)
        solve_runtime = solve_t_1 + solve_t_2

    elseif algorithm == "ARROW_BIN"   # ARROW BINARY TE
        TunnelBw, FlowBw, obj, ticket_selection, solve_t, opt_t = ARROW_BINARY(GRB_ENV, links, capacity, scenario_restored_bw, flows, demand, scenarios, T, Tf)
        best_options = []
        for s in 1:size(ticket_selection,1)
            for z in 1:size(ticket_selection,2)
                if ticket_selection[s,z] == 0
                    push!(best_options, (1-ticket_selection[s,z])*z)
                    break
                end
            end
        end
        best_scenario_resored_bw = []
        nscenarios = size(scenario_restored_bw,1)
        nedges = size(links,1)
        for s in 1:nscenarios
            best_restore_bw = []
            for e in 1:nedges
                push!(best_restore_bw, scenario_restored_bw[s][Int(best_options[s])][e])
            end
            push!(best_scenario_resored_bw, best_restore_bw)
        end
        if verbose 
            print("ARROW best_scenario_resored_bw: sum=")
            println(sum(best_scenario_resored_bw))
            for rr in 1:size(best_scenario_resored_bw, 1)
                println(best_scenario_resored_bw[rr])
            end
            println("\n")
        end

        throughput = sum(FlowBw)
        println("best_options ", best_options)
        solve_runtime = solve_t
    
    elseif algorithm == "OPTIMAL"   # optimal cross-layer TE (super ILP with optical restoration RWA and IP TE)
        ILP_LP = 1
        time_limit = 36000  # 10 hours maximum optimization runtime
        if solve_or_not
            TunnelBw, FlowBw, obj, solve_t, opt_t, var_num, sum_constraint = OPTIMAL(GRB_ENV, links, capacity, flows, demand, scenarios, fiber_scenarios, T, Tf, OpticalTopo, optical_rerouting_K, ILP_LP, time_limit, solve_or_not)
            throughput = sum(FlowBw)
            solve_runtime = solve_t
        else
            var_num, sum_constraint = OPTIMAL(GRB_ENV, links, capacity, flows, demand, scenarios, fiber_scenarios, T, Tf, OpticalTopo, optical_rerouting_K, ILP_LP, time_limit, solve_or_not)
        end
        
    elseif algorithm == "OPTIMAL_LP"   # optimal cross-layer TE (super ILP with optical restoration RWA and IP TE)
        ILP_LP = 0
        time_limit = 36000  # 10 hours maximum optimization runtime
        if solve_or_not
            TunnelBw, FlowBw, obj, solve_t, opt_t, var_num, sum_constraint = OPTIMAL(GRB_ENV, links, capacity, flows, demand, scenarios, fiber_scenarios, T, Tf, OpticalTopo, optical_rerouting_K, ILP_LP, time_limit, solve_or_not)
            throughput = sum(FlowBw)
            solve_runtime = solve_t
        else
            var_num, sum_constraint = OPTIMAL(GRB_ENV, links, capacity, flows, demand, scenarios, fiber_scenarios, T, Tf, OpticalTopo, optical_rerouting_K, ILP_LP, time_limit, solve_or_not)
        end   

    elseif algorithm == "HYPERTHETICAL"  # a hyperthetical TE that has no failure scenarios (or all failures are restored)
        TunnelBw, FlowBw, solve_t, opt_t = HYPERTHETICAL(GRB_ENV, links, capacity, flows, demand, T, Tf) # here the ffc TunnelBw is the reserved bw of tunnels = actual demand (because no failure)
        throughput = sum(FlowBw)
        solve_runtime = solve_t

    else
        printstyled("Error: TE Algorithm not indentified.", color=:red)
    end

    return TunnelBw, FlowBw, var, throughput, solve_runtime, best_options, best_scenario_resored_bw
end


function RestoreMatchMinLoss(v_restore, scenario_restored_bw)
    noptions = size(scenario_restored_bw[1], 1)
    nscenarios = size(scenario_restored_bw,1)
    nedges = size(scenario_restored_bw[1][1],1)
    best_option = ones(nscenarios)
    virtual_restore = zeros(nscenarios)

    for s in 1:nscenarios
        min_loss = 9999999999
        max_sum_restorable = 0
        for z in 1:noptions
            current_loss = 0
            current_sum_restorable = sum(scenario_restored_bw[s][z])
            ## choose the option with the min positive virtual restorable capacity
            for e in 1:nedges
                if v_restore[s,z,e] > 0
                    current_loss += v_restore[s,z,e] 
                end
            end

            if current_loss < min_loss  # optimize for minimum virtual restorable capacity
                best_option[s] = z
                virtual_restore[s] = current_loss
                min_loss = current_loss
            elseif current_loss == min_loss  # if virtual restorable capacity to be the same, max restorable capacity
                if current_sum_restorable > max_sum_restorable
                    best_option[s] = z
                    max_sum_restorable = current_sum_restorable
                end
            end
        end
    end
    best_option_diviation = []
    return best_option, virtual_restore, best_option_diviation
end
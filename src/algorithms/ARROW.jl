## Restoration-Aware TE with multiple restoration options (lottery tickets) per failure scenario
function ARROW(GRB_ENV, edges, capacity, restored, flows, demand, scenarios, T, Tf, disturbance, verbose)
    nedges = size(edges,1)
    nflows = size(flows,1)
    ntunnels = size(T,1)  # all tunnels routing info on IP edge index
    noptions = size(restored[1], 1)
    nscenarios = size(scenarios,1)
    printstyled("\n** solving ARROW LP with $(noptions) actual lottery tickets...\n", color=:yellow)

    if verbose
        println("Arrow scenario number: ", size(restored,1))
        println("Arrow per-scenario options number: ", size(restored[1],1))
    end
    tunnel_num = 0 # tunnel number for each flow
    for x in 1:length(Tf)
        if size(Tf[x],1) > tunnel_num
            tunnel_num = size(Tf[x],1)
        end
    end

    # residual and restorable tunnels
    Tsf = []  # residual tunnels for all failure scenarios, will just repeat for different restoration options
    Taf = []  # restorable tunnels for all failure scenario and each restoration option
    for s in 1:nscenarios
        sft = []
        aft = []
        for r in 1:size(restored[s], 1)  # for every restore options in a scenario
            ssft = []
            aaft = []
            for f in 1:size(Tf,1)
                ft = []
                at = []
                for t in 1:size(Tf[f],1)
                    up = true
                    partial = false
                    if (length(T[Tf[f][t]]) == 0)
                        up = false
                    end
                    for e in T[Tf[f][t]]
                        if scenarios[s][e] == 0
                            if restored[s][r][e] > 0 # beyond binary failures, less than 1 are all failures
                                up = false
                                partial = true
                            else
                                up = false
                                partial = false
                            end
                        end
                    end
                    if up
                        push!(ft, t)
                    elseif partial
                        push!(at, t)
                    end
                end
                push!(ssft,ft)
                push!(aaft,at)
            end
            push!(sft,ssft)
            push!(aft,aaft)
        end
        push!(Tsf,sft)
        push!(Taf,aft)
    end

    # tunnel routing on IP links
    L = zeros(ntunnels, nedges)
    for t in 1:ntunnels
        for e in 1:nedges
            if in(e, T[t])
                L[t,e] = 1
            end
        end
    end
    
    model = Model(() -> Gurobi.Optimizer(GRB_ENV))
    set_optimizer_attribute(model, "OutputFlag", 0)
    set_optimizer_attribute(model, "Threads", 32)
    
    model_def_time = @elapsed begin
    ## The LP optimization model
    @variable(model, b[1:nflows] >= 0)
    @variable(model, a[1:nflows,1:tunnel_num] >= 0)  #tunnels bw
    @variable(model, v_restored[1:nscenarios,1:noptions,1:nedges])

    # Equation 1, flow bandwidth constraint
    for f in 1:nflows 
        @constraint(model, sum(a[f,t] for t in 1:size(Tf[f],1)) >= b[f])
    end

    # Equation 2, link capacity constraint
    for e in 1:nedges
        @constraint(model, sum(a[f,t] * L[Tf[f][t],e] for f in 1:nflows for t in 1:size(Tf[f],1)) <= capacity[e])   
    end

    # Equation 3, flow bandwidth no larger than demand
    for f in 1:nflows
        @constraint(model, b[f] <= demand[f])   #all allocated bandwidths must be less than the demand for that flow
    end

    # Equation 4, residual and restorable tunnels must be able to carry bandwidth for all scenarios
    for f in 1:nflows
        for s in 1:size(scenarios,1)
            for z in 1:size(restored[s], 1)
                @constraint(model, sum(a[f,t] for t in Tsf[s][z][f]) + sum(a[f,t] for t in Taf[s][z][f]) >= b[f])   
            end
        end
    end

    # Equation 5, restorable tunnels and restorable bandwidth capacity
    for s in 1:nscenarios
        for e in 1:nedges
            for z in 1:noptions
                @constraint(model, sum(a[f,t] * L[Tf[f][t],e] for f in 1:nflows for t in Taf[s][z][f]) <= restored[s][z][e] + v_restored[s,z,e]) 
            end
        end
    end

    # Equation 6, bound for slack restorable bandwidth capacity
    for s in 1:nscenarios
        for z in 1:noptions
            @constraint(model, sum(v_restored[s,z,e] for e in 1:nedges) <= disturbance[s])
        end
    end

    @objective(model, Max, sum(b[i] for i in 1:size(b,1)))
    end  # model_def_time end

    optimize!(model)
    solve_runtime = solve_time(model)
    opt_runtime = solve_runtime + model_def_time

    return value.(a), value.(b), objective_value(model), value.(v_restored), solve_runtime, opt_runtime
end


## Restoration-Aware TE with one restoration option per failure scenario
function ARROW_ONE(GRB_ENV, edges, capacity, restored, flows, demand, scenarios, T, Tf, verbose)
    printstyled("\n** solving ARROW LP using one option...\n", color=:yellow)
    # println(restored)

    nedges = size(edges,1)
    nflows = size(flows,1)
    ntunnels = size(T,1)  # all tunnels routing info on IP edge index
    nscenarios = size(scenarios,1)

    if verbose
        println("Arrow scenario number: ", size(restored,1))
        # println("Arrow per-scenario options number: ", size(restored[1],1))
        # println("restored: ", restored)
    end

    tunnel_num = 0 # tunnel number for each flow
    for x in 1:length(Tf)
        if size(Tf[x],1) > tunnel_num
            tunnel_num = size(Tf[x],1)
        end
    end

    # residual and restorable tunnels
    Tsf = []  # residual tunnels for all failure scenarios, will just repeat for different restoration options
    Taf = []  # restorable tunnels for all failure scenario and each restoration option
    for s in 1:nscenarios
        ssft = []
        aaft = []
        for f in 1:size(Tf,1)
            ft = []
            at = []
            for t in 1:size(Tf[f],1)
                up = true
                partial = false
                if (length(T[Tf[f][t]]) == 0)
                    up = false
                end
                for e in T[Tf[f][t]]
                    if scenarios[s][e] == 0
                        if restored[s][e] > 0 # beyond binary failures, less than 1 are all failures
                            up = false
                            partial = true
                        else
                            up = false
                            partial = false
                        end
                    end
                end
                if up
                    push!(ft, t)
                elseif partial
                    push!(at, t)
                end
            end
            push!(ssft,ft)
            push!(aaft,at)
        end
        push!(Tsf,ssft)
        push!(Taf,aaft)
    end

    # tunnel routing on IP links
    L = zeros(ntunnels, nedges)
    for t in 1:ntunnels
        for e in 1:nedges
            if in(e, T[t])
                L[t,e] = 1
            end
        end
    end

    model = Model(() -> Gurobi.Optimizer(GRB_ENV))
    set_optimizer_attribute(model, "OutputFlag", 0)
    set_optimizer_attribute(model, "Threads", 32)

    model_def_time = @elapsed begin
    ## The LP optimization model
    @variable(model, b[1:nflows] >= 0)
    @variable(model, a[1:nflows,1:tunnel_num] >= 0)  #tunnels bw

    # Equation 7, flow bandwidth constraint
    for f in 1:nflows 
        @constraint(model, sum(a[f,t] for t in 1:size(Tf[f],1)) >= b[f])
    end

    # Equation 8, link capacity constraint
    for e in 1:nedges
        @constraint(model, sum(a[f,t] * L[Tf[f][t],e] for f in 1:nflows for t in 1:size(Tf[f],1)) <= capacity[e])   
    end

    # Equation 9, flow bandwidth no larger than demand
    for f in 1:nflows
        @constraint(model, b[f] <= demand[f])   #all allocated bandwidths must be less than the demand for that flow
    end

    # Equation 10, residual and restorable tunnels must be able to carry bandwidth for all scenarios
    for f in 1:nflows
        for s in 1:size(scenarios,1)
            # for z in 1:size(restored[s], 1)
            @constraint(model, sum(a[f,t] for t in Tsf[s][f]) + sum(a[f,t] for t in Taf[s][f]) >= b[f])   
            # end
        end
    end

    # Equation 11, restorable tunnels and restorable bandwidth capacity
    for s in 1:nscenarios
        for e in 1:nedges
            @constraint(model, sum(a[f,t] * L[Tf[f][t],e] for f in 1:nflows for t in Taf[s][f]) <= restored[s][e]) 
        end
    end

    @objective(model, Max, sum(b[i] for i in 1:size(b,1)))
    end  # model_def_time end

    optimize!(model)
    solve_runtime = solve_time(model)
    opt_runtime = solve_runtime + model_def_time

    return value.(a), value.(b), objective_value(model), solve_runtime, opt_runtime
end


## Restoration-Aware TE with multiple restoration options (lottery tickets) and lottery ticket selection per failure scenario
function ARROW_BINARY(GRB_ENV, edges, capacity, restored, flows, demand, scenarios, T, Tf)
    println("solving ARROW Binary ILP")

    nedges = size(edges,1)
    nflows = size(flows,1)
    ntunnels = size(T,1)  # all tunnels routing info on IP edge index
    noptions = size(restored[1], 1)
    nscenarios = size(scenarios,1)

    println("Arrow scenario number: ", size(restored,1))
    println("Arrow per-scenario options number: ", size(restored[1],1))

    tunnel_num = 0 # tunnel number for each flow
    for x in 1:length(Tf)
        if size(Tf[x],1) > tunnel_num
            tunnel_num = size(Tf[x],1)
        end
    end

    # residual and restorable tunnels
    Tsf = []  # residual tunnels for all failure scenarios, will just repeat for different restoration options
    Taf = []  # restorable tunnels for all failure scenario and each restoration option
    for s in 1:nscenarios
        sft = []
        aft = []
        for r in 1:size(restored[s], 1)  # for every restore options in a scenario
            ssft = []
            aaft = []
            for f in 1:size(Tf,1)
                ft = []
                at = []
                for t in 1:size(Tf[f],1)
                    up = true
                    partial = false
                    if (length(T[Tf[f][t]]) == 0)
                        up = false
                    end
                    for e in T[Tf[f][t]]
                        if scenarios[s][e] == 0
                            if restored[s][r][e] > 0 # beyond binary failures, less than 1 are all failures
                                up = false
                                partial = true
                            else
                                up = false
                                partial = false
                            end
                        end
                    end
                    if up
                        push!(ft, t)
                    elseif partial
                        push!(at, t)
                    end
                end
                push!(ssft,ft)
                push!(aaft,at)
            end
            push!(sft,ssft)
            push!(aft,aaft)
        end
        push!(Tsf,sft)
        push!(Taf,aft)
    end

    # tunnel routing on IP links
    L = zeros(ntunnels, nedges)
    for t in 1:ntunnels
        for e in 1:nedges
            if in(e, T[t])
                L[t,e] = 1
            end
        end
    end

    model = Model(() -> Gurobi.Optimizer(GRB_ENV))
    set_optimizer_attribute(model, "OutputFlag", 0)
    set_optimizer_attribute(model, "Threads", 32)
    
    model_def_time = @elapsed begin
    @variable(model, b[1:nflows] >= 0)
    @variable(model, a[1:nflows,1:tunnel_num] >= 0)  #tunnels bw
    @variable(model, m[1:nscenarios,1:noptions] >= 0, Bin)

    ## Equation 28, flow bandwidth constraint
    for f in 1:nflows 
        @constraint(model, sum(a[f,t] for t in 1:size(Tf[f],1)) >= b[f])
    end

    # Equation 29, link capacity constraint
    for e in 1:nedges
        @constraint(model, sum(a[f,t] * L[Tf[f][t],e] for f in 1:nflows for t in 1:size(Tf[f],1)) <= capacity[e])   
    end

    # Equation 30, flow bandwidth no larger than demand
    for f in 1:nflows
        @constraint(model, b[f] <= demand[f])   #all allocated bandwidths must be less than the demand for that flow
    end

    # Equation 31, residual and restorable tunnels must be able to carry bandwidth for all scenarios
    for f in 1:nflows
        for s in 1:size(scenarios,1)
            for z in 1:size(restored[s], 1)
                @constraint(model, sum(a[f,t] for t in Tsf[s][z][f]) + sum(a[f,t] for t in Taf[s][z][f]) >= b[f] - 100000*(1-m[s,z]))   
            end
        end
    end

    # Equation 32, restorable tunnels and the selected restorable bandwidth capacity
    for s in 1:nscenarios
        for e in 1:nedges
            for z in 1:noptions
                @constraint(model, sum(a[f,t] * L[Tf[f][t],e] for f in 1:nflows for t in Taf[s][z][f]) <= restored[s][z][e] + 100000*(1-m[s,z]))
            end
        end
    end

    # Equation 33, lottery ticket selection
    for s in 1:nscenarios
        @constraint(model, sum(m[s,z] for z in 1:noptions) == 1)
    end

    @objective(model, Max, sum(b[i] for i in 1:size(b,1)))
    end  # model_def_time end

    optimize!(model)
    solve_runtime = solve_time(model)
    opt_runtime = solve_runtime + model_def_time

    return value.(a), value.(b), objective_value(model), value.(m), solve_runtime, opt_runtime
end
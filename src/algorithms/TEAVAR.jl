## TEAVAR TE
function TEAVAR(GRB_ENV, edges, capacity, flows, demand, beta, T, Tf, scenarios, scenario_probs; average=false)
    printstyled("\n** solving TEAVAR LP at beta $(beta)..\n", color=:yellow)    
    nedges = length(edges)
    nflows = length(flows)
    ntunnels = length(T)
    nscenarios = length(scenarios)
    p = scenario_probs
    
    tunnel_num = 0
    for x in 1:length(Tf)
        if size(Tf[x],1) > tunnel_num
            tunnel_num = size(Tf[x],1)
        end
    end

    #CREATE TUNNEL SCENARIO MATRIX
    X  = ones(nscenarios,ntunnels)
    for s in 1:nscenarios
        for t in 1:ntunnels
            if size(T[t],1) == 0
                X[s,t] = 0
            else
                for e in 1:nedges
                    if scenarios[s][e] == 0
                        back_edge = findfirst(x -> x == (edges[e][2],edges[e][1], edges[e][3]), edges)
                        if in(e, T[t]) || in(back_edge, T[t])
                        # if in(e, T[t])
                            X[s,t] = 0
                        end
                    end
                end
            end
        end
    end

    #CREATE TUNNEL EDGE MATRIX
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
    
    @variable(model, a[1:nflows, 1:tunnel_num] >= 0)
    @variable(model, alpha >= 0)
    @variable(model, umax[1:nscenarios] >= 0)
    @variable(model, u[1:nscenarios, 1:nflows] >= 0)
 
    for e in 1:nedges
        @constraint(model, sum(a[f,t] * L[Tf[f][t],e] for f in 1:nflows for t in 1:size(Tf[f],1)) <= capacity[e])   #overlapping flows cannot add up to the capacity of that link
    end

    # FLOW LEVEL LOSS
    @expression(model, satisfied[s=1:nscenarios, f=1:nflows], sum(a[f,t] * X[s,Tf[f][t]] for t in 1:size(Tf[f],1)) / demand[f])

    for s in 1:nscenarios
        for f in 1:nflows
            @constraint(model, u[s,f] == 1 - satisfied[s,f])
        end
    end

    for s in 1:nscenarios
        if average
            @constraint(model, umax[s] + alpha >= (sum(u[s,f] for f in 1:nflows)) / nflows)
        else
            for f in 1:nflows
                @constraint(model, umax[s] >= u[s,f] - alpha)
            end
        end
    end

    @objective(model, Min, alpha + (1 / (1 - beta)) * sum((p[s] * umax[s] for s in 1:nscenarios)))
    end  # model_def_time end

    optimize!(model)
    solve_runtime = solve_time(model)
    opt_runtime = solve_runtime + model_def_time
    
    return value.(alpha), objective_value(model), value.(a), value.(umax), value.(u), solve_runtime, opt_runtime
end
## vanilla hyperthetical TE without failure scenarios
function HYPERTHETICAL(GRB_ENV, edges, capacity, flows, demand, T, Tf)
    printstyled("\n** solving Vanilla TE LP... ", color=:yellow)

    nedges = size(edges,1)
    nflows = size(flows,1)
    ntunnels = size(T,1)

    tunnel_num = 0
    for x in 1:length(Tf)
        if size(Tf[x],1) > tunnel_num
            tunnel_num = size(Tf[x],1)
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

    @variable(model, b[1:nflows] >= 0)
    @variable(model, a[1:nflows,1:tunnel_num] >= 0)

    for f in 1:nflows
        @constraint(model, sum(a[f,t] for t in 1:size(Tf[f],1)) >= b[f])   #the sum of all allocated bandwidths on every flow must be >= the total bandwidth for that flow
    end

    for e in 1:nedges
        @constraint(model, sum(a[f,t] * L[Tf[f][t],e] for f in 1:nflows for t in 1:size(Tf[f],1)) <= capacity[e])   #overlapping flows cannot add up to the capacity of that link
    end

    for f in 1:nflows
        @constraint(model, b[f] >= 0)
    end

    for f in 1:nflows
        @constraint(model, b[f] <= demand[f])   #all allocated bandwidths must be less than the demand for that flow
        for t in 1:size(Tf[f],1)
            @constraint(model, a[f,t] >= 0)     #each allocated bandwidth on for flow f on tunnel t >= 0
        end
    end

    @objective(model, Max, sum((b[i] for i in 1:size(b,1))))
    end

    optimize!(model)
    solve_runtime = solve_time(model)
    opt_runtime = solve_runtime + model_def_time

    return value.(a), value.(b), solve_runtime, opt_runtime
end

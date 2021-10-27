## Cross-layer IP-optical restoration-aware TE
function OPTIMAL(GRB_ENV, edges, capacity, flows, demand, scenarios, fiber_scenarios, T, Tf, OpticalTopo, rerouting_K, ILP_LP, time_limit, solve_or_not)
    printstyled("\n** solving cross-layer RWA-TE Optimal super ILP...\n", color=:yellow)
    nedges = size(edges,1)
    nflows = size(flows,1)
    ntunnels = size(T,1)  # all tunnels routing info on IP edge index
    nscenarios = size(scenarios,1)
    nFibers = length(fiber_scenarios[1])
    FibercapacityCode = OpticalTopo["capacityCode"]
    nwavelength = size(FibercapacityCode,2)

    tunnel_num = 0 # tunnel number for each flow, some flow may have less number of tunnels, take the largest
    for x in 1:length(Tf)
        if size(Tf[x],1) > tunnel_num
            tunnel_num = size(Tf[x],1)
        end
    end

    # fiber links are bidirectional
    uni_IPedges = []
    reverse_IPedges = []
    for edge_index in 1:nedges
        e = findfirst(x -> x == (edges[edge_index][2], edges[edge_index][1], edges[edge_index][3]), edges)
        if edge_index < e
            push!(uni_IPedges, edge_index)
            push!(reverse_IPedges, e)
        end
    end

    AllIPedge = []
    for e in 1:nedges
        push!(AllIPedge, edges[e])
        push!(AllIPedge, (edges[e][2], edges[e][1], edges[e][3]))
    end

    IPBranchRoutingFiber, _, IPbranchIndexAll, IPbrachIndexGroup = AllIPWaveRerouting(OpticalTopo, AllIPedge, rerouting_K)
    nIPedgeBranchAll = length(IPbranchIndexAll)

    # for each failure scenario, generate the IP link health state matrix
    IPhealth = ones(nscenarios, nedges)
    for q in 1:nscenarios
        for e in 1:nedges
            IPhealth[q,e] = scenarios[q][e]
        end
    end

    # for each failure scenario, generate the Fiber health state matrix
    Fiberhealth = ones(nscenarios, nFibers)
    for q in 1:nscenarios
        for b in 1:nFibers
            Fiberhealth[q,b] = fiber_scenarios[q][b]
        end
    end

    # how tunnels are routed on IP links
    L = zeros(ntunnels, nedges)
    for t in 1:ntunnels
        for e in 1:nedges
            if in(e, T[t])
                L[t,e] = 1
            end
        end
    end

    # how each IP branch is routed on fibers
    pai = zeros(nIPedgeBranchAll, nFibers)
    for e in 1:nIPedgeBranchAll  # nIPedgeBranchAll is global indexed
        for f in 1:nFibers
            if in(f, IPBranchRoutingFiber[e])
                pai[e,f] = 1  # this IP branch is routed, but take care it this fiber may break in some scenarios
            end
        end
    end

    # CREATE RESIDUAL TUNNELS BY SCENARIO BY FLOW (References Tf): fiber cut scenarios
    Tsf = []  # residual tunnels after failure
    dTaf = []  # affected / restorable tunnels after failure
    for s in 1:size(scenarios,1)
        sft = []
        aft = []
        for f in 1:size(Tf,1)
            ft = []
            at = []
            for t in 1:size(Tf[f],1)
                up = true
                if (length(T[Tf[f][t]]) == 0)
                    up = false
                end
                for e in T[Tf[f][t]]
                    if scenarios[s][e] == 0
                        up = false
                    end
                end
                if up
                    push!(ft, t)  # this tunnel is not affected by failures
                else
                    push!(at, t)  # this tunnel is affected by failures
                end
            end
            push!(sft, ft)
            push!(aft, at)
        end
        push!(Tsf, sft)
        push!(dTaf, aft)
    end

    println("nscenarios ", nscenarios)
    println("nedges ", nedges)
    println("rerouting_K ", rerouting_K)
    println("nIPedgeBranchAll ", nIPedgeBranchAll)
    println("nFibers ", nFibers)
    println("nwavelength ", nwavelength)
    println("nflows ", nflows)
    println("tunnel_num ", tunnel_num)

    model = Model(() -> Gurobi.Optimizer(GRB_ENV))
    set_optimizer_attribute(model, "OutputFlag", 1)
    set_optimizer_attribute(model, "Threads", 32)
    set_time_limit_sec(model, time_limit)

    solve_runtime = 0
    model_def_time = @elapsed begin
    ## The super ILP formulation

    ## optical variables for the optical layer
    if ILP_LP == 1
        @variable(model, IPBranch_bw[1:nscenarios, 1:nedges, 1:rerouting_K] >= 0, Int)  # bandwidth allocation for all IP multipath branches during restoration
        @variable(model, lambda[1:nscenarios, 1:nIPedgeBranchAll, 1:nFibers, 1:nwavelength] >=0, Bin)  # if IP link's branch use fiber and wavelength
    else
        printstyled("** [super ILP model relaxed to LP]\n", color=:yellow)
        @variable(model, IPBranch_bw[1:nscenarios, 1:nedges, 1:rerouting_K] >= 0)  # bandwidth allocation for all IP multipath branches during restoration
        @variable(model, 0<=lambda[1:nscenarios, 1:nIPedgeBranchAll, 1:nFibers, 1:nwavelength] <=1)  # if IP link's branch use fiber and wavelength
    end

    ## TE variables for the entire IP layer network
    @variable(model, restored_capacity[1:nscenarios, 1:nedges] >= 0)   # the bw after restoration (if no failure original bw) for each IP links
    @variable(model, b[1:nflows] >= 0)  # flow bw
    @variable(model, a[1:nflows,1:tunnel_num] >= 0)  # tunnels bw, tunnels are per flow indexed

    # Equation 18, [IP] sum tunnel bandwidth larger than flow bandwidth
    for f in 1:nflows 
        @constraint(model, sum(a[f,t] for t in 1:size(Tf[f],1)) >= b[f])
    end
    
    # Equation 19, [IP] overlapping flows cannot add up to the capacity of that link
    for e in 1:nedges
        @constraint(model, sum(a[f,t] * L[Tf[f][t],e] for f in 1:nflows for t in 1:size(Tf[f],1)) <= capacity[e])   
    end

    # Equation 20, [IP] flow bw no larger than demand
    for f in 1:nflows
        @constraint(model, b[f] <= demand[f])
    end

    # Equation 21, [IP] residual tunnels + dynamic restorable tunnels must be able to carry bandwidth for all scenarios
    for f in 1:nflows
        for q in 1:nscenarios
            @constraint(model, sum(a[f,t] for t in Tsf[q][f]) + sum(a[f,t] for t in dTaf[q][f]) >= b[f])   
        end
    end

    # Equation 22, [IP] restorable tunnel bandwidth no larger than restored capacity of links
    for q in 1:nscenarios
        for e in 1:nedges
            @constraint(model, sum(a[f,t] * L[Tf[f][t],e] for f in 1:nflows for t in dTaf[q][f]) <= restored_capacity[q,e]) 
        end
    end

    # Equation 23, [optical] wavelength resource used only once if the resource is usable
    for q in 1:nscenarios
        for w in 1:nwavelength 
            for b in 1:nFibers
                @constraint(model, sum(lambda[q,t,b,w] for t in 1:nIPedgeBranchAll) <= FibercapacityCode[b,w])
            end
        end
    end

    # Equation 24, [optical] translate wavelength usage to IPBranch_bw
    for q in 1:nscenarios
        for e in 1:nedges
            for t in 1:rerouting_K  # t is the index for branches of the failIP link, not global branch index
                if t <= length(IPbrachIndexGroup[e]) 
                    for f in 1:nFibers 
                        @constraint(model, IPBranch_bw[q,e,t]*pai[IPbrachIndexGroup[e][t],f] == sum(lambda[q,IPbrachIndexGroup[e][t],f,w]*Fiberhealth[q,f] for w in 1:nwavelength))
                    end
                end
            end
        end
    end
    
    # Equation 25, [optical] wavelength continuity
    for q in 1:nscenarios
        for t in 1:nIPedgeBranchAll
            for b in IPBranchRoutingFiber[t]
                for bb in IPBranchRoutingFiber[t]
                    for w in 1:nwavelength
                        @constraint(model, lambda[q,t,b,w]*pai[t,b] == lambda[q,t,bb,w]*pai[t,bb])
                    end
                end
            end
        end
    end

    # Equation 26, [optical] restored capacity should not exceed the initial capacity
    for q in 1:nscenarios
        for e in 1:nedges 
            @constraint(model, restored_capacity[q,e] <= capacity[e])
            @constraint(model, restored_capacity[q,e] >= capacity[e]*IPhealth[q,e])
        end
    end

    # Equation 27, [optical] restored bw is the sum of all branches with modulation considered
    for q in 1:nscenarios
        for e in 1:nedges
            @constraint(model, restored_capacity[q,e] == 100*sum(IPBranch_bw[q,e,t] for t in 1:rerouting_K)) # modulation is 100 G per wave
        end
    end

    # Auxiliary: IP links are bidirectional (bandwidth equal)
    for q in 1:nscenarios
        for e in 1:length(uni_IPedges)
            @constraint(model, restored_capacity[q,uni_IPedges[e]] == restored_capacity[q,reverse_IPedges[e]])
        end
    end

    # Auxiliary: if surrogate fiber path is less than k
    for q in 1:nscenarios
        for e in 1:nedges
            for t in 1:rerouting_K
                if t > length(IPbrachIndexGroup[e])
                    @constraint(model, IPBranch_bw[q,e,t] == 0)
                end
            end
        end
    end

    @objective(model, Max, sum(b[i] for i in 1:size(b,1)))
    end  # model_def_time end

    # get problem size in terms of number of variables and constraints
    var_num = num_variables(model)
    println("var_num ", var_num)

    sum_constraint = 0
    xt = list_of_constraint_types(model)
    for x in xt
        println(x)
        cons_num = num_constraints(model, x[1], x[2])
        sum_constraint += cons_num
        println("cons_num ", cons_num)
    end
    println("sum_constraint ", sum_constraint)

    # solve the model or not
    if solve_or_not
        optimize!(model)
        solve_runtime = solve_time(model)
        opt_runtime = solve_runtime + model_def_time
        return value.(a), value.(b), objective_value(model), solve_runtime, opt_runtime, var_num, sum_constraint
    else
        return var_num, sum_constraint
    end
end
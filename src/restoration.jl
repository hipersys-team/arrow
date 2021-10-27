using JuMP, Gurobi


## routing of restored wavelength
function WaveRerouting(OpticalTopo, failed_IPedge, failed_fibers_index, rerouting_K)
    nfailedge = size(failed_IPedge, 1)
    rehoused_IProutingEdge = []  # routing of rehoused IP link in terms of fiber link index
    rehoused_IProuting = []  # routing of rehoused IP link in terms of fiber node sequence
    failedIPbranckIndexAll = []  # index of rehoused IP link branches
    failedIPbrachIndexGroup = []  # index group of rehoused IP link branches

    ## an optical topology after fiber cut (an optical scenario)
    num_nodes = length(OpticalTopo["nodes"])
    optical_graph = LightGraphs.SimpleDiGraph(num_nodes)
    distances = Inf*ones(num_nodes, num_nodes)
    num_edges = length(OpticalTopo["links"])
    
    for i in 1:num_edges
        if i in failed_fibers_index  # delete the failed fiber
            continue
        else
            LightGraphs.add_edge!(optical_graph, OpticalTopo["links"][i][1], OpticalTopo["links"][i][2])
            distances[OpticalTopo["links"][i][1], OpticalTopo["links"][i][2]] = OpticalTopo["fiber_length"][i]
            distances[OpticalTopo["links"][i][2], OpticalTopo["links"][i][1]] = OpticalTopo["fiber_length"][i]
        end
    end

    # find rerouting_K paths for each failed IP links, pay attention: IP links are bidirectional!
    global_IPbranch = 1
    for w in 1:nfailedge
        # println("failed IP src-dst: ", failed_IPedge[w][1], "-", failed_IPedge[w][2])
        state = LightGraphs.yen_k_shortest_paths(optical_graph, failed_IPedge[w][1], failed_IPedge[w][2], distances, rerouting_K)
        paths = state.paths
        # println("paths: ", paths)
        if length(paths) <= rerouting_K
            path_edges = []
            for p in 1:length(paths)
                k_path_edges = []
                for i in 1:length(paths[p])-1
                    e = findfirst(x -> x == (paths[p][i], paths[p][i+1]), OpticalTopo["links"])
                    append!(k_path_edges, e)
                end
                push!(path_edges, k_path_edges)
            end
            
            append!(rehoused_IProutingEdge, path_edges)
            append!(rehoused_IProuting, paths)
            append!(failedIPbranckIndexAll, range(global_IPbranch, length=length(paths), step=1))
            push!(failedIPbrachIndexGroup, range(global_IPbranch, length=length(paths), step=1))
            global_IPbranch += length(paths)
        end
    end

    return rehoused_IProutingEdge, rehoused_IProuting, failedIPbranckIndexAll, failedIPbrachIndexGroup
end


## wavelength assignment of restored wavelength, generating restoration link options that maximize restored capacity, this is an ILP
function RestoreILP(GRB_ENV, Fibers, FibercapacityCode, failedIPedges, failedIPBranchRoutingFiber, failedIPbranckIndexAll, failedIPbrachIndexGroup, failed_IP_initialbw, rerouting_K)
    println("solving restoration wavelength assignment ILP considering wavelength continuity")

    nFibers = length(Fibers)
    nfailedIPedges = length(failedIPedges)
    nfailedIPedgeBranchAll = length(failedIPbranckIndexAll)  # this number can be small than nfailedIPedges * nfailedIPedgeBranchPerLink
    nfailedIPedgeBranchPerLink = rerouting_K
    nwavelength = size(FibercapacityCode, 2)
    uni_failedIPedges = []
    reverse_failedIPedges = []
    for edge_index in 1:nfailedIPedges
        e = findfirst(x -> x == (failedIPedges[edge_index][2], failedIPedges[edge_index][1], failedIPedges[edge_index][3]), failedIPedges)
        if edge_index < e
            push!(uni_failedIPedges, edge_index)
            push!(reverse_failedIPedges, e)
        end
    end

    # how each IP branch is routed on fibers
    L = zeros(nfailedIPedgeBranchAll, nFibers)
    for t in 1:nfailedIPedgeBranchAll  # nfailedIPedgeBranchAll is global indexed
        for f in 1:nFibers
            if in(f, failedIPBranchRoutingFiber[t])
                L[t,f] = 1
            end
        end
    end

    if length(failedIPBranchRoutingFiber) > 0  # if this scenario has failures
        model = Model(() -> Gurobi.Optimizer(GRB_ENV))
        set_optimizer_attribute(model, "OutputFlag", 0)
        set_optimizer_attribute(model, "Threads", 32)

        @variable(model, restored_bw[1:nfailedIPedges] >= 0, Int)  
        @variable(model, IPBranch_bw[1:nfailedIPedges, 1:nfailedIPedgeBranchPerLink] >= 0, Int)  # bandwidth allocation for all IP branches
        @variable(model, lambda[1:nfailedIPedgeBranchAll, 1:nFibers, 1:nwavelength] >=0, Bin)  # if IP link's branch use fiber and wavelength

        # Equation 14, wavelength resource used only once if the resource is usable
        for w in 1:nwavelength 
            for f in 1:nFibers
                @constraint(model, sum(lambda[t,f,w] for t in 1:nfailedIPedgeBranchAll) <= FibercapacityCode[f,w])
            end
        end

        # Equation 15, translate wavelength usage to IPBranch_bw
        for l in 1:nfailedIPedges
            for t in 1:nfailedIPedgeBranchPerLink  # t is the index for branches of the failIP link, not global branch index
                if t <= length(failedIPbrachIndexGroup[l]) 
                    for f in 1:nFibers 
                        @constraint(model, IPBranch_bw[l,t]*L[failedIPbrachIndexGroup[l][t],f] == sum(lambda[failedIPbrachIndexGroup[l][t],f,w] for w in 1:nwavelength))
                    end
                else
                    @constraint(model, IPBranch_bw[l,t] == 0)
                end
            end
        end

        # Equation 16, wavelength continuity
        for t in 1:nfailedIPedgeBranchAll
            for f in failedIPBranchRoutingFiber[t]
                for ff in failedIPBranchRoutingFiber[t]
                    for w in 1:nwavelength
                        @constraint(model, lambda[t,f,w]*L[t,f] == lambda[t,ff,w]*L[t,ff])
                    end
                end
            end
        end

        # Equation 17, restored bw should no larger than initial bw, 100 is per wavelength gbps
        for l in 1:nfailedIPedges
            @constraint(model, restored_bw[l]*100 <= failed_IP_initialbw[l])
            @constraint(model, restored_bw[l] == sum(IPBranch_bw[l,t] for t in 1:nfailedIPedgeBranchPerLink))
        end

        # Auxiliary: bidirectional link bandwidth equal
        for e in 1:length(uni_failedIPedges)
            @constraint(model, restored_bw[uni_failedIPedges[e]] == restored_bw[reverse_failedIPedges[e]])
        end

        @objective(model, Max, sum(restored_bw[l] for l in 1:nfailedIPedges))  # maximizing total restorable bandwidth capacity
        optimize!(model)

        return value.(restored_bw), objective_value(model), value.(IPBranch_bw)

    else
        restored_bw = zeros(nfailedIPedges)
        IPBranch_bw = zeros(nfailedIPedges, nfailedIPedgeBranchPerLink)
        
        return restored_bw, 0, IPBranch_bw
    end
end


## wavelength assignment of restored wavelength, generating restoration link options that maximize restored capacity, this is a LP relaxed from previous ILP
function RestoreLP(GRB_ENV, Fibers, FibercapacityCode, failedIPedges, failedIPBranchRoutingFiber, failedIPbranckIndexAll, failedIPbrachIndexGroup, failed_IP_initialbw, rerouting_K)
    println("solving restoration wavelength assignment relaxed LP considering wavelength continuity")

    nFibers = length(Fibers)
    nfailedIPedges = length(failedIPedges)
    nfailedIPedgeBranchAll = length(failedIPbranckIndexAll)  # this number can be small than nfailedIPedges * nfailedIPedgeBranchPerLink
    nfailedIPedgeBranchPerLink = rerouting_K
    nwavelength = size(FibercapacityCode, 2)
    # println(nwavelength)
    uni_failedIPedges = []
    reverse_failedIPedges = []
    for edge_index in 1:nfailedIPedges
        e = findfirst(x -> x == (failedIPedges[edge_index][2], failedIPedges[edge_index][1], failedIPedges[edge_index][3]), failedIPedges)
        if edge_index < e
            push!(uni_failedIPedges, edge_index)
            push!(reverse_failedIPedges, e)
        end
    end

    # how each IP branch is routed on fibers
    L = zeros(nfailedIPedgeBranchAll, nFibers)
    for t in 1:nfailedIPedgeBranchAll  # nfailedIPedgeBranchAll is global indexed
        for f in 1:nFibers
            if in(f, failedIPBranchRoutingFiber[t])
                L[t,f] = 1
            end
        end
    end

    if length(failedIPBranchRoutingFiber) > 0  # if this scenario has failures
        model = Model(() -> Gurobi.Optimizer(GRB_ENV))
        set_optimizer_attribute(model, "OutputFlag", 0)
        set_optimizer_attribute(model, "Threads", 32)

        @variable(model, restored_bw[1:nfailedIPedges] >= 0)  # integer constraint relaxed
        @variable(model, IPBranch_bw[1:nfailedIPedges, 1:nfailedIPedgeBranchPerLink] >= 0)  # integer constraint relaxed, bandwidth allocation for all IP branches
        @variable(model, 0 <= lambda[1:nfailedIPedgeBranchAll, 1:nFibers, 1:nwavelength] <=1)  # integer constraint relaxed, if IP link's branch use fiber and wavelength

        # Equation 14, wavelength resource used only once if the resource is usable
        for w in 1:nwavelength 
            for f in 1:nFibers
                @constraint(model, sum(lambda[t,f,w] for t in 1:nfailedIPedgeBranchAll) <= FibercapacityCode[f,w])
            end
        end

        # Equation 15, translate wavelength usage to IPBranch_bw
        for l in 1:nfailedIPedges
            for t in 1:nfailedIPedgeBranchPerLink  # t is the index for branches of the failIP link, not global branch index
                if t <= length(failedIPbrachIndexGroup[l]) 
                    for f in 1:nFibers 
                        @constraint(model, IPBranch_bw[l,t]*L[failedIPbrachIndexGroup[l][t],f] == sum(lambda[failedIPbrachIndexGroup[l][t],f,w] for w in 1:nwavelength))
                    end
                else
                    @constraint(model, IPBranch_bw[l,t] == 0)
                end
            end
        end

        # Equation 16, wavelength continuity
        for t in 1:nfailedIPedgeBranchAll
            for f in failedIPBranchRoutingFiber[t]
                for ff in failedIPBranchRoutingFiber[t]
                    for w in 1:nwavelength
                        @constraint(model, lambda[t,f,w]*L[t,f] == lambda[t,ff,w]*L[t,ff])
                    end
                end
            end
        end

        # Equation 17, restored bw should no larger than initial bw, 100 is per wavelength gbps
        for l in 1:nfailedIPedges
            @constraint(model, restored_bw[l]*100 <= failed_IP_initialbw[l])
            @constraint(model, restored_bw[l] == sum(IPBranch_bw[l,t] for t in 1:nfailedIPedgeBranchPerLink))
        end

        # Auxiliary: bidirectional link bandwidth equal
        for e in 1:length(uni_failedIPedges)
            @constraint(model, restored_bw[uni_failedIPedges[e]] == restored_bw[reverse_failedIPedges[e]])
        end

        @objective(model, Max, sum(restored_bw[l] for l in 1:nfailedIPedges))  # maximizing total restorable bandwidth capacity
        optimize!(model)

        return value.(restored_bw), objective_value(model), value.(IPBranch_bw)

    else
        restored_bw = zeros(nfailedIPedges)
        IPBranch_bw = zeros(nfailedIPedges, nfailedIPedgeBranchPerLink)
        
        return restored_bw, 0, IPBranch_bw
    end
end


## check if a particular ticket satisfy the RWA constraints
function RestoreRWACheck(GRB_ENV, ticket_restored_bw, Fibers, FibercapacityCode, failedIPedges, failedIPBranchRoutingFiber, failedIPbranckIndexAll, failedIPbrachIndexGroup, failed_IP_initialbw, rerouting_K, verbose)
    if verbose println("[Checking] randomized rounding solution feasibility with optical-layer restoration ILP") end
    nFibers = length(Fibers)
    nfailedIPedges = length(failedIPedges)
    nfailedIPedgeBranchAll = length(failedIPbranckIndexAll)  # this number can be small than nfailedIPedges * nfailedIPedgeBranchPerLink
    nfailedIPedgeBranchPerLink = rerouting_K
    nwavelength = size(FibercapacityCode, 2)
    uni_failedIPedges = []
    reverse_failedIPedges = []
    for edge_index in 1:nfailedIPedges
        e = findfirst(x -> x == (failedIPedges[edge_index][2], failedIPedges[edge_index][1], failedIPedges[edge_index][3]), failedIPedges)
        if edge_index < e
            push!(uni_failedIPedges, edge_index)
            push!(reverse_failedIPedges, e)
        end
    end

    # how each IP branch is routed on fibers
    L = zeros(nfailedIPedgeBranchAll, nFibers)
    for t in 1:nfailedIPedgeBranchAll  # nfailedIPedgeBranchAll is global indexed
        for f in 1:nFibers
            if in(f, failedIPBranchRoutingFiber[t])
                L[t,f] = 1
            end
        end
    end

    if length(failedIPBranchRoutingFiber) > 0  # if this scenario has failures
        model = Model(() -> Gurobi.Optimizer(GRB_ENV))
        set_optimizer_attribute(model, "OutputFlag", 0)
        set_optimizer_attribute(model, "Threads", 32)

        @variable(model, restored_bw[1:nfailedIPedges] >= 0, Int)  
        @variable(model, IPBranch_bw[1:nfailedIPedges, 1:nfailedIPedgeBranchPerLink] >= 0, Int)  # bandwidth allocation for all IP branches
        @variable(model, lambda[1:nfailedIPedgeBranchAll, 1:nFibers, 1:nwavelength] <= 0, Bin)  # if IP link's branch use fiber and wavelength

        # Equation 14, wavelength resource used only once if the resource is usable
        for w in 1:nwavelength 
            for f in 1:nFibers
                @constraint(model, sum(lambda[t,f,w] for t in 1:nfailedIPedgeBranchAll) <= FibercapacityCode[f,w])
            end
        end

        # Equation 15, translate wavelength usage to IPBranch_bw
        for l in 1:nfailedIPedges
            for t in 1:nfailedIPedgeBranchPerLink  # t is the index for branches of the failIP link, not global branch index
                if t <= length(failedIPbrachIndexGroup[l]) 
                    for f in 1:nFibers 
                        @constraint(model, IPBranch_bw[l,t]*L[failedIPbrachIndexGroup[l][t],f] == sum(lambda[failedIPbrachIndexGroup[l][t],f,w] for w in 1:nwavelength))
                    end
                else
                    @constraint(model, IPBranch_bw[l,t] == 0)
                end
            end
        end

        # Equation 16, wavelength continuity
        for t in 1:nfailedIPedgeBranchAll
            for f in failedIPBranchRoutingFiber[t]
                for ff in failedIPBranchRoutingFiber[t]
                    for w in 1:nwavelength
                        @constraint(model, lambda[t,f,w]*L[t,f] == lambda[t,ff,w]*L[t,ff])
                    end
                end
            end
        end

        # Equation 17, restored bw should no larger than initial bw, 100 is per wavelength gbps
        for l in 1:nfailedIPedges
            @constraint(model, restored_bw[l]*100 <= failed_IP_initialbw[l])
            @constraint(model, restored_bw[l] == sum(IPBranch_bw[l,t] for t in 1:nfailedIPedgeBranchPerLink))
        end

        # Auxiliary: bidirectional link bandwidth equal
        for e in 1:length(uni_failedIPedges)
            @constraint(model, restored_bw[uni_failedIPedges[e]] == restored_bw[reverse_failedIPedges[e]])
        end

        # do not solve the model, but just check the solution feasibility
        result_dict = Dict(restored_bw[1] => ticket_restored_bw[1])
        for l in 2:nfailedIPedges
            result_dict = merge!(result_dict, Dict(restored_bw[l] => ticket_restored_bw[l]))
        end
        # println("result_dict: ", result_dict)
        feasibility = primal_feasibility_report(model, result_dict, skip_missing = true)
        # println("feasibility: ", feasibility)

        if length(feasibility) == 0
            if verbose 
                printstyled(" - $(ticket_restored_bw) feasibility true - ", color=:green)
                println(feasibility)
            end
            return true
        else
            if verbose
                printstyled(" - $(ticket_restored_bw) feasibility false - ", color=:yellow)
                println(feasibility)
            end
            return false
        end
    
    else
        return true  # non failure scenario
    end
end


## randomized rounding based on relaxed LP solution
function RandomRounding(GRB_ENV, LP_restored_bw, restored_bw_rwa, failedIPedges, failed_IP_initialbw, ticket_set_size, option_gap, OpticalTopo, rehoused_IProutingEdge, failedIPbranckindex, failedIPbrachGroup, optical_rerouting_K, verbose) 
    # println("Randomized rounding gap: ", option_gap)
    ilp_check = 1
    initial_wavelength_num = failed_IP_initialbw ./ 100  # 1 wavelength = 100 Gbps
    probabilities_up = []
    nrestored = size(LP_restored_bw, 1)
    nfailedIPedges = length(failedIPedges)
    # identify bidirectional IP relationship
    uni_failedIPedges = []
    reverse_failedIPedges = []
    for edge_index in 1:nfailedIPedges
        e = findfirst(x -> x == (failedIPedges[edge_index][2], failedIPedges[edge_index][1], failedIPedges[edge_index][3]), failedIPedges)
        if edge_index < e
            push!(uni_failedIPedges, edge_index)
            push!(reverse_failedIPedges, e)
        end
    end

    for i in 1:length(uni_failedIPedges)
        push!(probabilities_up, LP_restored_bw[uni_failedIPedges[i]] - floor(Int, LP_restored_bw[uni_failedIPedges[i]]))
    end

    outer_iteration = min(ticket_set_size*nrestored*10) # a large number for generating options
    theoretical_max_ticket = floor(Int128, sqrt(prod(initial_wavelength_num)))
    if sqrt(prod(initial_wavelength_num)) - floor(sqrt(prod(initial_wavelength_num))) > 0.001 && verbose
        println("initial_wavelength_num $(initial_wavelength_num)")
    end
    if verbose println("The max number of possible ticket in this failure scenario: $(theoretical_max_ticket)") end
    restored_bw = zeros(outer_iteration, nrestored)
    real_restored_bw = zeros(ticket_set_size, nrestored)  # generated tickets for this scenario, restorable bw for each failed IP link
    
    # have the first randoized rounding result to be the planning (arrow naive) result
    rounded_index = 1
    for b in 1:length(uni_failedIPedges)
        real_restored_bw[rounded_index,uni_failedIPedges[b]] = restored_bw_rwa[uni_failedIPedges[b]]
        real_restored_bw[rounded_index,reverse_failedIPedges[b]] = restored_bw_rwa[reverse_failedIPedges[b]]
    end

    # have the second randomized rouding result to be the generic rounding results from LP
    if ticket_set_size >= 2
        rounded_index = 2
        for b in 1:length(uni_failedIPedges)
            real_restored_bw[rounded_index,uni_failedIPedges[b]] = floor(LP_restored_bw[uni_failedIPedges[b]])
            real_restored_bw[rounded_index,reverse_failedIPedges[b]] = floor(LP_restored_bw[reverse_failedIPedges[b]])
        end
    end

    # starting from the third ticket, randomized generation
    progress = ProgressMeter.Progress(min(ticket_set_size,theoretical_max_ticket), .1, "Running randomized rounding $(ticket_set_size) tickets (this scenario of $(nrestored/2) failed links has max $(outer_iteration) trials)...\n", 50)
    if ticket_set_size > 2
        for m in 1:outer_iteration
            # m'th rounding attempt to get restored_bw[outer_iteration, nrestored]
            for b in 1:length(uni_failedIPedges)  # for each failed link to restore
                rounding_range = max(initial_wavelength_num[uni_failedIPedges[b]], floor(LP_restored_bw[uni_failedIPedges[b]]))  # rouding stride
                # rounding_range = initial_wavelength_num[uni_failedIPedges[b]] - floor(LP_restored_bw[uni_failedIPedges[b]])  # rouding stride
                rd = rand(1) # generate a random number between 0 and 1
                # probability of the b'th failed link
                if probabilities_up[b] == 0  ## handling integer LP solution
                    if rd[1] < 0.3  # round up
                        restored_bw[m,uni_failedIPedges[b]] = min(initial_wavelength_num[uni_failedIPedges[b]], ceil(Int, LP_restored_bw[uni_failedIPedges[b]]) + rand(1:rounding_range))
                        restored_bw[m,reverse_failedIPedges[b]] = restored_bw[m,uni_failedIPedges[b]]
                    elseif rd[1] < 0.7  # stay still
                        restored_bw[m,uni_failedIPedges[b]] = LP_restored_bw[uni_failedIPedges[b]]
                        restored_bw[m,reverse_failedIPedges[b]] = restored_bw[m,uni_failedIPedges[b]]
                    else  # round down
                        restored_bw[m,uni_failedIPedges[b]] = max(0, floor(LP_restored_bw[uni_failedIPedges[b]]) - rand(1:rounding_range))
                        restored_bw[m,reverse_failedIPedges[b]] = restored_bw[m,uni_failedIPedges[b]]
                    end
                else
                    if rd[1] < probabilities_up[b]  # round up
                        restored_bw[m,uni_failedIPedges[b]] = min(initial_wavelength_num[uni_failedIPedges[b]], ceil(Int, LP_restored_bw[uni_failedIPedges[b]]) + rand(1:rounding_range) - 1)
                        restored_bw[m,reverse_failedIPedges[b]] = restored_bw[m,uni_failedIPedges[b]]
                    else  # round down
                        restored_bw[m,uni_failedIPedges[b]] = max(0, floor(Int, LP_restored_bw[uni_failedIPedges[b]]) - rand(1:rounding_range) + 1)
                        restored_bw[m,reverse_failedIPedges[b]] = restored_bw[m,uni_failedIPedges[b]]
                    end
                end
            end
            
            # filter out bad options
            if round(Int, sum(restored_bw[m,:])) <= round(Int, sum(LP_restored_bw)) && round(Int, sum(restored_bw[m,:])) > option_gap*round(Int, sum(LP_restored_bw))  # make sure the tickets are within reasonable range of total restorable capacity
                # distill randomized tickets by removing duplicates
                duplicate_sign = 0
                for r in 1:rounded_index
                    if real_restored_bw[r,:] == restored_bw[m,:]
                        duplicate_sign = 1
                        # println("duplicate_sign")
                        break
                    end
                end
                if duplicate_sign == 0  # this is an unique ticket generated from randomized rounding
                    ## if all the restorable links happens to round down from LP, then it is feasible no need to check (this is probably not a good ticket)
                    weak_ticket = 1
                    for b in 1:nrestored
                        if restored_bw[m,b] > real_restored_bw[2,b]  # second ticket is LP result
                            weak_ticket = 0
                            break
                        end
                    end
                    if ilp_check == 1 && weak_ticket == 0  # not a weak ticket and need to run feasibility check
                        Fibers = OpticalTopo["links"]
                        FibercapacityCode = OpticalTopo["capacityCode"]
                        failedIPBranchRoutingFiber = rehoused_IProutingEdge
                        failedIPbranckIndexAll = failedIPbranckindex
                        failedIPbrachIndexGroup = failedIPbrachGroup
                        rerouting_K = optical_rerouting_K
                        check_time = @timed check_sign = RestoreRWACheck(GRB_ENV, restored_bw[m,:], Fibers, FibercapacityCode, failedIPedges, failedIPBranchRoutingFiber, failedIPbranckIndexAll, failedIPbrachIndexGroup, failed_IP_initialbw, rerouting_K, verbose)
                        if verbose println("check time $(check_time[2])") end
                        if check_sign  # feasibility check passed
                            rounded_index += 1  # append this ticket to real_restored_bw as feasible ticket
                            if verbose println("Get one feasible ticket $(restored_bw[m,:])") end
                            for b in 1:nrestored
                                real_restored_bw[rounded_index,b] = restored_bw[m,b]
                            end
                            ProgressMeter.next!(progress, showvalues = [])
                        end
                    else
                        rounded_index += 1  # append this ticket to real_restored_bw as feasible ticket
                        if verbose println("Get one feasible ticket $(restored_bw[m,:])") end
                        for b in 1:nrestored
                            real_restored_bw[rounded_index,b] = restored_bw[m,b]
                        end
                        ProgressMeter.next!(progress, showvalues = [])
                    end
                end
            end

            # we get desired number of rounded results or get the theoretical max number of tickets
            if rounded_index >= min(ticket_set_size, theoretical_max_ticket)
                if verbose println("Get desired number $(rounded_index) of tickets") end
                break
            end
        end
    end

    return real_restored_bw
end


## convert failure scenarios to IP link failure information
function ReadFailureScenario(scenario, IPedges, IPcapacity)
    nedges = size(IPedges,1)
    failed_IPedge = []
    failed_IP_initialindex = []
    failed_IP_initialbw = []
    for x in 1:nedges
        if scenario[x] < 1   # link failure
            push!(failed_IPedge, IPedges[x])
            push!(failed_IP_initialindex, x)
            push!(failed_IP_initialbw, IPcapacity[x])
        end
    end

    return failed_IPedge, failed_IP_initialindex, failed_IP_initialbw
end


## routing of restored wavelength for all IP links as a database only for OPTIMAL cross-layer formulation
function AllIPWaveRerouting(OpticalTopo, IPedges, rerouting_K)
    nIPedges = size(IPedges, 1)
    rehoused_IProutingEdge = []
    rehoused_IProutingPaths = []
    IPbranckIndexAll = []
    IPbrachIndexGroup = []

    ## an optical topology without fiber cut 
    num_nodes = length(OpticalTopo["nodes"])
    optical_graph = LightGraphs.SimpleDiGraph(num_nodes)
    distances = Inf*ones(num_nodes, num_nodes)
    
    num_edges = length(OpticalTopo["links"])
    for i in 1:num_edges
        LightGraphs.add_edge!(optical_graph, OpticalTopo["links"][i][1], OpticalTopo["links"][i][2])
        distances[OpticalTopo["links"][i][1], OpticalTopo["links"][i][2]] = OpticalTopo["fiber_length"][i]
        distances[OpticalTopo["links"][i][2], OpticalTopo["links"][i][1]] = OpticalTopo["fiber_length"][i]
    end

    # find rerouting_K paths for each IP links, pay attention: IP links are bidirectional!
    global_IPbranch = 1
    for w in 1:nIPedges
        state = LightGraphs.yen_k_shortest_paths(optical_graph, IPedges[w][1], IPedges[w][2], distances, rerouting_K)
        paths = state.paths
        # println("paths: ", paths)
        if length(paths) <= rerouting_K
            path_edges = []
            for p in 1:length(paths)
                k_path_edges = []
                for i in 1:length(paths[p])-1
                    e = findfirst(x -> x == (paths[p][i], paths[p][i+1]), OpticalTopo["links"])
                    append!(k_path_edges, e)
                end
                push!(path_edges, k_path_edges)
            end
            
            append!(rehoused_IProutingEdge, path_edges)
            append!(rehoused_IProutingPaths, paths)
            append!(IPbranckIndexAll, range(global_IPbranch, length=length(paths), step=1))
            push!(IPbrachIndexGroup, range(global_IPbranch, length=length(paths), step=1))
            global_IPbranch += length(paths)
        end
    end

    return rehoused_IProutingEdge, rehoused_IProutingPaths, IPbranckIndexAll, IPbrachIndexGroup
end
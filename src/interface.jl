using PyPlot

include("./topoprovision.jl")
include("./topodraw.jl")


## Increment Counter and Get Next Dir
function nextRun(dir, singleplot)
    # dir = joinpath(@__DIR__, "./$dir")
    if isfile("$(dir)/counter.txt") == false
        mkdir("$(dir)")
        writedlm("$(dir)/counter.txt", "1")
    end
    if singleplot
        c = Int(readdlm("$(dir)/counter.txt")[1])
        writedlm("$(dir)/counter.txt", c + 1)
        newdir = "$(dir)/$(c)"
        mkdir(newdir)
    else
        if Int(readdlm("$(dir)/counter.txt")[1]) == 1  # handling case when simulation last longer than a day
            c = Int(readdlm("$(dir)/counter.txt")[1])
            writedlm("$(dir)/counter.txt", c + 1)
            newdir = "$(dir)/$(c)"
            if isdir(newdir) == false
                mkdir(newdir)
            end
        else
            c = Int(readdlm("$(dir)/counter.txt")[1])-1
        end
        newdir = "$(dir)/$(c)"
    end

    return newdir
end


## Compute Weibull Probabilities
function weibullProbs(num; shape=.8, scale=.0001)
    w = Distributions.Weibull(shape, scale)
    probs = []
    for i in 1:num
        push!(probs, rand(w))
    end
    return probs
end


## get optical/IP topo 
function ReadCrossLayerTopo(dir, topology, topology_index, verbose, expanded_spectrum; weibull_failure=false, IPfromFile=false, tofile=false)
    topodir =  "./data/topology/$(topology)"
    input_ip_nodes = readdlm("$(topodir)/IP_nodes.txt", header=true)[1]
    input_optical_nodes = readdlm("$(topodir)/optical_nodes.txt", header=true)[1]
    input_topology_o = readdlm("$(topodir)/optical_topo.txt", header=true)[1]
    ignore = ()
    fromNodesOptical = input_topology_o[:,1]
    toNodesOptical = input_topology_o[:,2]
    lengthOptical = input_topology_o[:,3]
    if isdir("$(dir)/$(topology)") == false
        mkdir("$(dir)/$(topology)")
    end

    if weibull_failure 
        failureprobOptical = weibullProbs(length(lengthOptical), shape=.8, scale=.02)  # derive fiber cut probability from weibull
        ## draw initial weibull distribution CDF
        PyPlot.clf()
        sorted_failureprobOptical = sort(failureprobOptical)
        cdf = []
        for i in 1:length(sorted_failureprobOptical)
            push!(cdf, i/length(sorted_failureprobOptical))
        end
        PyPlot.plot(sorted_failureprobOptical, cdf, marker="P", linewidth=1, label="shape=.8, scale=.02")
        figname = "$(dir)/$(topology)/00_weibull_distribution.png"
        PyPlot.xlabel("Fiber Failure scenario probability")
        PyPlot.ylabel("CDF")
        PyPlot.legend(loc="best")
        PyPlot.xscale("log")
        PyPlot.savefig(figname)
    else
        failureprobOptical = input_topology_o[:,4]  # if read fiber cut probability from file
        ## draw initial weibull distribution CDF
        PyPlot.clf()
        sorted_failureprobOptical = sort(failureprobOptical)
        cdf = []
        for i in 1:length(sorted_failureprobOptical)
            push!(cdf, i/length(sorted_failureprobOptical))
        end
        PyPlot.plot(sorted_failureprobOptical, cdf, marker="P", linewidth=1, label="failure distribution from file")
        # PyPlot.plot(sorted_failureprobOptical.* 20, cdf, marker="P", linewidth=1, label="shifted")
        figname = "$(dir)/$(topology)/00_filefailure_distribution.png"
        PyPlot.xlabel("Fiber Failure scenario probability")
        PyPlot.ylabel("CDF")
        PyPlot.legend(loc="best")
        PyPlot.xscale("log")
        PyPlot.savefig(figname)
    end
    
    fiberlinks = []
    bidirect_links = []
    fiberlinkslength = []
    fiberlinksSpectrum = []
    fiberlinksFailure = []
    bidirect_fiberlinksFailure = []

    for i in 1:size(fromNodesOptical, 1)
        if (!(fromNodesOptical[i] in ignore) && !(toNodesOptical[i] in ignore))
            push!(fiberlinks, (Int(fromNodesOptical[i]), Int(toNodesOptical[i])))
            push!(fiberlinkslength, lengthOptical[i])
            push!(fiberlinksSpectrum, [])
            push!(fiberlinksFailure, failureprobOptical[i])
            if !in((Int(fromNodesOptical[i]), Int(toNodesOptical[i])), bidirect_links) && !in((Int(toNodesOptical[i]), Int(fromNodesOptical[i])), bidirect_links)
                push!(bidirect_links, (Int(fromNodesOptical[i]), Int(toNodesOptical[i])))
                push!(bidirect_fiberlinksFailure, failureprobOptical[i])
            end
        end
    end

    parsed_wavelength = []
    parsed_optical_route = []
    links_length = []
    if IPfromFile == true
        input_topology_ip = readdlm("$(topodir)/IP_topo_$(topology_index)/IP_topo_$(topology_index).txt", header=true)[1]
        if verbose println("Read IP layer topo from file: $(topodir)/IP_topo_$(topology_index)/IP_topo_$(topology_index).txt") end
        ignore = ()
        optical_route = input_topology_ip[:,5]
        wavelength = input_topology_ip[:,6]
        for x in 1:length(optical_route)
            current_wavelength = [parse(Int, ss) for ss in split(wavelength[x][2:end-1], ",")]  # example: [1,2,3,4,5,6,7]
            push!(parsed_wavelength, current_wavelength)
            current_optical_route = [parse(Int, ss) for ss in split(optical_route[x][2:end-1], ",")]
            push!(parsed_optical_route, current_optical_route)
            current_length = 0
            for j in 1:length(current_optical_route)
                current_length += lengthOptical[j]
                for t in 1:length(current_wavelength)
                    if current_wavelength[t] in fiberlinksSpectrum[current_optical_route[j]]
                        continue
                    else
                        push!(fiberlinksSpectrum[current_optical_route[j]],current_wavelength[t])
                    end
                end
            end  
            push!(links_length, current_length)
        end
    else
        input_topology_ip = ProvisionIPTopology(topology, tofile=tofile)  # generate IP provisioning only no output to file
        optical_route = input_topology_ip[:,5]
        wavelength = input_topology_ip[:,6]
        for x in 1:length(optical_route)
            current_wavelength = [parse(Int, ss) for ss in split(wavelength[x][5:end-1], ", ")]  # example: Any[1, 2, 3, 4, 5, 6, 7]
            push!(parsed_wavelength, current_wavelength)
            current_optical_route = [parse(Int, ss) for ss in split(optical_route[x][5:end-1], ", ")]
            push!(parsed_optical_route, current_optical_route)
            current_length = 0
            for j in 1:length(current_optical_route)
                current_length += lengthOptical[j]
                for t in 1:length(current_wavelength)
                    if current_wavelength[t] in fiberlinksSpectrum[current_optical_route[j]]
                        continue
                    else
                        push!(fiberlinksSpectrum[current_optical_route[j]], current_wavelength[t])
                    end
                end
            end  
            push!(links_length, current_length)
        end
    end
    
    fromNodes = input_topology_ip[:,1]
    toNodes = input_topology_ip[:,2]
    marker = input_topology_ip[:,3]
    capacity = input_topology_ip[:,4] .* 100  # we assume each wavelength is 100 Gbps
    failure_prob = input_topology_ip[:,7]
    
    links = []
    links_fiberroute = []
    links_wavelength = []
    links_hops = []
    # println("fromNodes ", fromNodes)

    for i in 1:size(fromNodes, 1)
        if (!(fromNodes[i] in ignore) && !(toNodes[i] in ignore))
            push!(links, (Int(fromNodes[i]), Int(toNodes[i]), Int(marker[i])))
            push!(links_fiberroute, parsed_optical_route[i])
            push!(links_wavelength, parsed_wavelength[i])
            push!(links_hops, length(parsed_optical_route[i]))
        end
    end

    # IP links are represented in uni-directional form
    IPTopo = Dict()
    IPTopo["nodes"] = input_ip_nodes
    IPTopo["links"] = links
    IPTopo["capacity"] = capacity
    IPTopo["link_probs"] = failure_prob
    IPTopo["link_fiberroute"] = links_fiberroute
    IPTopo["link_length"] = links_length
    IPTopo["link_wavelength"] = links_wavelength

    # optical fiber links are represented in uni-directional form
    OpticalTopo = Dict()
    OpticalTopo["nodes"] = input_optical_nodes
    OpticalTopo["links"] = fiberlinks  # unidirectional
    OpticalTopo["bidirect_links"] = bidirect_links
    OpticalTopo["fiber_length"] = fiberlinkslength
    OpticalTopo["fiber_spectrum"] = fiberlinksSpectrum
    OpticalTopo["fiber_probs"] = fiberlinksFailure
    OpticalTopo["bidirect_fiber_probs"] = bidirect_fiberlinksFailure
    OpticalTopo["capacity"] = [96+expanded_spectrum-length(x) for x in fiberlinksSpectrum]
    
    capacitycode = ones(length(fiberlinks), 96+expanded_spectrum)
    for fiber in 1:length(fiberlinksSpectrum)
        for slot in fiberlinksSpectrum[fiber]
            capacitycode[fiber, slot] = 0
        end
    end
    OpticalTopo["capacityCode"] = capacitycode  # 0 means occupied, 1 means available

    drawGraph(topology, IPTopo, topology_index, OpticalTopo, dir)

    return IPTopo, OpticalTopo
end


## different TM may have different sum demand, this function find the proper demand rescale if we want to consider a uniform constant demand time series
function FindDemandScale(topology, nodes_num, AllTraffic)
    demand_upscale = 1
    demand_downscale = 1
    sum_demands = []
    scaling_factor = []
    for traffic_num in 1:length(AllTraffic)
        initial_demand, flows = readDemand("$(topology)/demand", nodes_num, AllTraffic[traffic_num], demand_upscale, demand_downscale, false)  # read initial demand
        # println(sum(initial_demand))
        push!(sum_demands, sum(initial_demand))
    end

    min_demand = minimum(sum_demands)
    for i in 1:length(sum_demands)
        push!(scaling_factor, sum_demands[i]/min_demand)
    end

    return scaling_factor
end


## Read Demand
function readDemand(filename, num_nodes, num_demand, scale, downscale, rescale; matrix=true, sigfigs=1, zeroindex=false)
    filename = "./data/topology/$(filename)"
    input_demand = matrix ? ParseMatrix("$(filename).txt", num_nodes, num_demand) : IgnoreCycles(readdlm("$(filename)/$(num_demand).txt", header=true)[1], zeroindex=zeroindex)
    # println("input_demand ", input_demand)
    fromNodes = input_demand[:,1]
    toNodes = input_demand[:,2]
    flows = map(tup -> (Int(tup[2]), Int(toNodes[tup[1]])), enumerate(fromNodes))
    demand = convert(Array{Float64}, input_demand[:,3] ./ downscale .* scale)

    if rescale
        rescale_set = readdlm("$(filename)_rescale.txt", header=false)
        # println("rescale_set ", rescale_set)
        demand = demand ./ rescale_set[num_demand]
        println("Rescale demand $(num_demand) at $(rescale_set[num_demand]) -> $(sum(demand))")
    end

    return demand, flows
end


## IgnoreCycles
function IgnoreCycles(demand; zeroindex=false)
    z = [0 0 0;]
    for row in 1:size(demand,1)
        if demand[row, 1] != demand[row, 2]
            z = vcat(z, [demand[row,1] + zeroindex demand[row, 2] + zeroindex demand[row,3];])
            # z = vcat(z, transpose(demand[row,:]))
        end
    end
    return z[2:end,:]

end


## Parse Matrix
function ParseMatrix(filename, num_nodes, num_demand)
    ignore = ()
    start_range = 0
    end_range = Inf
    x = readdlm(filename)[num_demand,:]
    # println(x)
    m = zeros(length(x)-Int(sqrt(length(x))), 3)
    # m = zeros(length(x)-round(Int, sqrt(length(x))), 3)
    fromNode = 0
    count = 1
    for i in 0:(num_nodes^2-1)
        toNode = i%num_nodes + 1
        if toNode == 1
            fromNode += 1
        end
        if (fromNode != toNode && i >= start_range && i < end_range && !(fromNode in ignore) && !(toNode in ignore))
            m[count,1] = fromNode
            m[count,2] = toNode
            m[count,3] = x[i+1]
            count += 1
        end
    end
    ret = m
    for row in size(m,1):-1:1
        if (m[row,3] == 0)
            ret = ret[setdiff(1:end, row), :]
        end
    end
    return ret
end


## Tunnels routing
function getTunnels(IPtopo, flows, k, verbose, scenarios; edge_disjoint=1)  # 1 means k shortest path, 2 means IPedge disjoint, 3 means fiber disjoint
    nodes = IPtopo["nodes"]
    edges = IPtopo["links"]
    capacities = IPtopo["capacity"]
    fiberroute = IPtopo["link_fiberroute"]
    num_edges = length(edges)
    # print("num_edges:", num_edges)
    # print(edges)
    num_nodes = length(nodes)
    num_flows = length(flows)
    paral_edges = []
    # count number of paralle links for adding dummy links/nodes
    dummy_nodes = 0
    for l in 1:num_edges
        if edges[l][3] > 1  # parallel IP links
            dummy_nodes += 1
            push!(paral_edges, edges[l])
        end
    end

    graph = LightGraphs.SimpleDiGraph(num_nodes + dummy_nodes)  # considering parallel links
    distances = Inf*ones(num_nodes+dummy_nodes, num_nodes+dummy_nodes)

    # println("paral_edges: ", length(paral_edges), paral_edges)
    
    for i in 1:num_edges
        if edges[i][3] == 1
            LightGraphs.add_edge!(graph, edges[i][1], edges[i][2])
            if edge_disjoint == 5  # weight KSP
                distances[edges[i][1], edges[i][2]] = 1 / capacities[i]  # weight edge, more capacity means less distance
                distances[edges[i][2], edges[i][1]] = 1 / capacities[i]  # weight edge, more capacity means less distance
            else
                distances[edges[i][1], edges[i][2]] = 1 
                distances[edges[i][2], edges[i][1]] = 1 
            end
        else
            e = findfirst(x -> x == (edges[i][1], edges[i][2], edges[i][3]), paral_edges)
            # println("parallel link: ", e, paral_edges[e])
            LightGraphs.add_edge!(graph, edges[i][1], num_nodes+e)
            LightGraphs.add_edge!(graph, num_nodes+e, edges[i][2])
            distances[edges[i][1], num_nodes+e] = 0.5
            distances[num_nodes+e, edges[i][2]] = 0.5
            # distances[edges[i][2], num_nodes+e] = 0.5
            # distances[num_nodes+e, edges[i][1]] = 0.5
        end
    end

    T = []
    Tf = []
    ti = 1  # global tunnel index
    max_k = 1

    # KSP routing
    if edge_disjoint == 1
        printstyled("KSP tunnel routing\n", color=:blue)
        for f in 1:num_flows
            tf = []
            curr_k = 0

            state = LightGraphs.yen_k_shortest_paths(graph, flows[f][1], flows[f][2], distances, k)
            paths = state.paths
            edges_used = []
            fiber_used = []
            for i in 1:k
                t = []
                traversed_fiber = []
                path = i <= size(paths,1) ? paths[i] : []
                jump_flag = 0
                for n in 2:size(path,1)
                    if path[n] > num_nodes   # use parallel links
                        e = findfirst(x -> x == (path[n-1], path[n+1], paral_edges[path[n]-num_nodes][3]), edges)
                        jump_flag = 1
                        push!(t, e)
                    elseif jump_flag == 0
                        e = findfirst(x -> x == (path[n-1], path[n], 1), edges)
                        push!(t, e)
                        for b in 1:length(fiberroute[e])
                            if in(fiberroute[e][b], traversed_fiber)
                                continue
                            else
                                push!(traversed_fiber, fiberroute[e][b])
                            end
                        end
                        f = edges[e]
                    elseif jump_flag == 1
                        jump_flag = 0
                    end
                end
    
                if length(t) == 0 break end
                
                push!(T, t)
                push!(tf, ti)
                ti += 1
                curr_k += 1

            end
            push!(Tf, tf)
            if verbose println("K-shortest tunnel routing: $(paths)") end
        end

    # IPedge disjoint routing
    elseif edge_disjoint == 2
        printstyled("IP disjoint tunnel routing\n", color=:blue)
        for f in 1:num_flows
            tf = []
            disjoint_graph = deepcopy(graph)
            for i in 1:k
                state = LightGraphs.yen_k_shortest_paths(disjoint_graph, flows[f][1], flows[f][2], distances, 1)
                paths = state.paths
                # println("paths ", paths)
                t = []
                path = 0 < size(paths,1) ? paths[1] : []  # because we use KSP k=1
                # println("path ", path)
                for n in 2:size(path,1)
                    e = findfirst(x -> x == (path[n-1], path[n], 1), edges)
                    push!(t, e)
                    remove_status = LightGraphs.rem_edge!(disjoint_graph, path[n-1], path[n])
                    # println("remove edge $(path[n-1])-$(path[n]), $(remove_status)")
                    distances[path[n-1], path[n]] = Inf
                end
    
                if length(t) == 0 break end
    
                push!(T, t)
                push!(tf, ti)
                ti += 1
            end
            push!(Tf, tf)
        end
    
    # fiber disjoint routing
    elseif edge_disjoint == 3
        printstyled("fiber disjoint tunnel routing\n", color=:blue)
        for f in 1:num_flows
            tf = []
            disjoint_graph = deepcopy(graph)
            for i in 1:k
                state = LightGraphs.yen_k_shortest_paths(disjoint_graph, flows[f][1], flows[f][2], distances, 1)
                paths = state.paths
                # println("paths ", paths)
                t = []
                path = 0 < size(paths,1) ? paths[1] : []  # because we use KSP k=1
                # println("path ", path)
                for n in 2:size(path,1)
                    e = findfirst(x -> x == (path[n-1], path[n], 1), edges)
                    push!(t, e)
                    # remove all IP edges on related b fiber
                    for b in 1:length(fiberroute[e])  
                        for ee in 1:num_edges
                            if fiberroute[e][b] in fiberroute[ee]
                                remove_status = LightGraphs.rem_edge!(disjoint_graph, edges[ee][1], edges[ee][2])
                                # println("remove edge $(edges[ee][1])-$(edges[ee][2]), $(remove_status)")
                                distances[edges[ee][1], edges[ee][2]] = Inf
                            end
                        end
                    end
                    # the reverse path fiber should also be removed because fiber are bidirectional
                    re = findfirst(x -> x == (path[n], path[n-1], 1), edges)
                    for b in 1:length(fiberroute[re])  
                        for ee in 1:num_edges
                            if fiberroute[re][b] in fiberroute[ee]
                                remove_status = LightGraphs.rem_edge!(disjoint_graph, edges[ee][1], edges[ee][2])
                                # println("remove edge $(edges[ee][1])-$(edges[ee][2]), $(remove_status)")
                                distances[edges[ee][1], edges[ee][2]] = Inf
                            end
                        end
                    end
                end
    
                if length(t) == 0 break end
    
                push!(T, t)
                push!(tf, ti)
                ti += 1
            end
            push!(Tf, tf)
        end

    # failure aware routing, in real life tunnels should be properly routed such that failure will disrupt all tunnels of a flow
    elseif edge_disjoint == 4 || edge_disjoint == 5
        printstyled("failure aware tunnel routing\n", color=:blue)
        nscenarios = length(scenarios)
        for f in 1:num_flows
            accumulate_k = 0
            tf = []

            # failure scenario aware tunnel routing
            for s in 1:nscenarios
                disjoint_graph = deepcopy(graph)
                for q in 1:length(scenarios[s])
                    if scenarios[s][q] == 0
                        remove_status = LightGraphs.rem_edge!(disjoint_graph, edges[q][1], edges[q][2])
                        distances[edges[q][1], edges[q][2]] = Inf
                    end
                end
                state = LightGraphs.yen_k_shortest_paths(disjoint_graph, flows[f][1], flows[f][2], distances, 1)
                paths = state.paths
                t = []
                path = 0 < size(paths,1) ? paths[1] : []  # because we use KSP k=1
                
                for n in 2:size(path,1)
                    e = findfirst(x -> x == (path[n-1], path[n], 1), edges)
                    push!(t, e)
                end
    
                if length(t) == 0 break end
                
                if !in(t, T) && accumulate_k < k
                    push!(T, t)
                    push!(tf, ti)
                    ti += 1
                    accumulate_k += 1
                end
            end

            # if tunnel number is smaller than k, then use KSP to fill it
            if accumulate_k < k
                state = LightGraphs.yen_k_shortest_paths(graph, flows[f][1], flows[f][2], distances, k)
                paths = state.paths

                for i in 1:k
                    t = []
                    traversed_fiber = []
                    path = i <= size(paths,1) ? paths[i] : []
                    jump_flag = 0
                    for n in 2:size(path,1)
                        if path[n] > num_nodes   # use parallel links
                            e = findfirst(x -> x == (path[n-1], path[n+1], paral_edges[path[n]-num_nodes][3]), edges)
                            jump_flag = 1
                            push!(t, e)
                        elseif jump_flag == 0
                            e = findfirst(x -> x == (path[n-1], path[n], 1), edges)
                            push!(t, e)
                            for b in 1:length(fiberroute[e])
                                if in(fiberroute[e][b], traversed_fiber)
                                    continue
                                else
                                    push!(traversed_fiber, fiberroute[e][b])
                                end
                            end
                            f = edges[e]
                        elseif jump_flag == 1
                            jump_flag = 0
                        end
                    end
        
                    if length(t) == 0 break end
                    
                    if !in(t, T) && accumulate_k < k
                        push!(T, t)
                        push!(tf, ti)
                        ti += 1
                        accumulate_k += 1
                    end
                end
            end
            push!(Tf, tf)
        end
    end
    return T, Tf, max_k, graph
end


## parse tunnels from input files (format 1)
function parseTunnels(allocs_tunnels_paths, links)
    println("Reading tunnels from: $(allocs_tunnels_paths)")
    allocs_tunnels = readdlm(allocs_tunnels_paths)

    num_lines = size(allocs_tunnels,1)
    flows = []
    T = [[]]
    Tf = []
    tf = []
    max_t_paths = 0
    num_flows = 0

    for i in 1:num_lines
        # Reading flows
        if allocs_tunnels[i, 1] == "Flow:"
            flow_str = allocs_tunnels[i, 2][2:end-1]
            f1, f2 = split(flow_str, ",")
            f1, f2 = parse(Int64, f1) + 1, parse(Int64, f2) + 1
            flow = (f1, f2)

            push!(flows, flow)
            if num_flows > 0
                push!(Tf, tf)
            end

            num_flows = num_flows + 1
            tf = []

        # Reading tunnels and allocations
        elseif allocs_tunnels[i, 2] == ""
            _hops = split(allocs_tunnels[i, 1], ";")[1:end-1]
            t = []
            for _hop in _hops
                _hop_str = _hop[2:end-1]
                _h1, _h2 = split(_hop_str, ",")
                _h1, _h2 = parse(Int64, _h1) + 1, parse(Int64, _h2) + 1
                _hop_int = (_h1, _h2)

                if _h1 != 0 && _h2 != 0
                    e = findfirst(x -> (x[1], x[2]) == _hop_int, links)
                    if e !== nothing
                        push!(t, e)
                    end
                end
            end

            if !in(t, T)
                push!(T, t)
            end

            _t_idx = findfirst(x -> x == t, T)
            push!(tf, _t_idx)
            max_t_paths = max(max_t_paths, size(tf, 1))
        end
    end

    push!(Tf, tf)

    Tf_adjusted = []
    t_empty = findfirst(x -> x == [], T)

    for f in 1:size(flows, 1)
        tf = Tf[f]
        t = T[f]
        if length(tf) == max_t_paths
            push!(Tf_adjusted, tf)
        else
            missing_tunnels = max_t_paths - length(tf)

            for i in 1:missing_tunnels
                push!(tf, t_empty)
            end
            push!(Tf_adjusted, tf)
        end
    end

    return T, Tf_adjusted, flows
end


## parse tunnels from input files (format 2)
function parsePaths(filename, links, flows; zeroindex=false)
    filename = joinpath(@__DIR__, "./data/$filename")
    nflows = length(flows)
    x = readdlm(filename)
    T = []
    Tf = [[] for i=1:nflows]
    tf = []
    fromNode = 0
    toNode = 0
    num_flow = 0
    tindex = 1
    max_paths = 0
    paths = Matrix(undef, nflows, nflows)
    for row in 1:size(x,1)
        if "->" in x[row,:]
            max_paths = max(max_paths, size(tf, 1))
            if fromNode != 0 && num_flow != 0
                #add tunnel if not first run
                paths[fromNode, toNode] = tf
                Tf[num_flow] = tf
            end
            if x[row,1] isa Number
                fromNode = x[row, 1] + zeroindex
                toNode = x[row, 3] + zeroindex
            else
                fromNode = parse(Int, replace(x[row, 1], "h" => "")) + zeroindex
                toNode = parse(Int, replace(x[row, 3], "h" => "")) + zeroindex
            end
            num_flow = findfirst(x -> x == (fromNode, toNode), flows)
            if num_flow === nothing
                num_flow = 0
            end
            tf = []
        else
            t = []
            #parse each tunnel into edges
            for col in 2:size(x,2)
                if occursin("]", x[row,col])
                    break
                end
                r = replace(x[row,col][2:end-2], "s" => "")
                stringtup = split(r, ",")
                #find edge in edge matrix
                e = (parse(Int,stringtup[1]) + zeroindex, parse(Int,stringtup[2]) + zeroindex)
                index = findfirst(x -> x == e, links)
                push!(t, index)
            end
            #create new tunnel and add index to that flows tunnels
            if num_flow != 0
                push!(T, t)
                push!(tf, tindex)
                tindex += 1
            end
        end
    end

    #add last tunnel
    if num_flow != 0
        Tf[num_flow] = tf
        paths[fromNode, toNode] = tf
    end
    push!(T, [])

    for f in 1:size(Tf,1)
        for t in 1:max_paths
            try Tf[f][t]
            catch
                push!(Tf[f], tindex)
            end
        end
    end
    return T, Tf, max_paths
end
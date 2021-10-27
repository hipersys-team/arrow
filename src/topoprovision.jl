using DelimitedFiles, LightGraphs, Distributions, Random, PyPlot, JuMP, Gurobi


##  Generate IP link capacity distribution
function IPCapacityDistribution(topology, linknum)
    dir = "./data/topology/"
    data = readdlm("$(dir)/$(topology)/IPCapacityDistribution.txt", header=false)
    y = fit(Exponential, data)  # IP link - wavelength num follows exponential distribution
    capacity_float = rand(y, linknum) ./2
    capacity = round.(Int, capacity_float)
    println("generated capacity distribution: ", capacity)
    return capacity
end


##  Provision IP Topology, this function provision the wavelength routing for IP links
function ProvisionIPTopology(topology; scaling, density, linknum, ilp_planning, tofile=true)
    dir = "./data/topology/"
    if tofile == true  
        openstyle = "w"  
    else
        openstyle = "a"
    end
    open("$(dir)/$(topology)/IP_topo.txt", openstyle) do io   
        if tofile == true 
            println("Print IP topolog into file $(dir)/$(topology)/IP_topo.txt")
            writedlm(io, ["src" "dst" "index" "capacity" "fiberpath_index" "wavelength" "failure"])
        end
        data = readdlm("$dir/$(topology)/optical_topo.txt", header=true)
        fiberlinks = []
        occupied_spectrum = []
        ipnode = readdlm("$dir/$(topology)/IP_nodes.txt", header=true)
        max_node = Int(length(ipnode[1][:,1]))
        
        opticalnode = readdlm("$dir/$(topology)/optical_nodes.txt", header=true)
        max_optical_node = Int(length(opticalnode[1][:,1]))

        # topology
        graph = LightGraphs.SimpleDiGraph(max_optical_node)
        distances = Inf*ones(max_optical_node, max_optical_node)

        # not all node pairs are connected, IP links are bidirectional
        IPlink_num = round(Int, density*max_optical_node*(max_optical_node-1)/2)  # compute IP link number based on graph density
        IPlink_num = linknum  # exlicitly fix IP link number
        generateCapacity = IPCapacityDistribution(topology, IPlink_num)  # bidirectional IP links
        println("IPlink_num: ", IPlink_num)

        allCapacity = []
        for i in 1:size(generateCapacity, 1)
            if generateCapacity[i] > 0
                push!(allCapacity, round(Int, generateCapacity[i])+scaling)
            else
                push!(allCapacity, 1+scaling)
            end
        end
        println("generated capacity distribution: ", allCapacity)

        # plot capacity distribution
        PyPlot.clf()
        sorted_allCapacity = sort(allCapacity)
        cdf = []
        for i in 1:length(sorted_allCapacity)
            push!(cdf, i/length(sorted_allCapacity))
        end
        PyPlot.plot(sorted_allCapacity, cdf, marker="P", linewidth=1)
        figname = "$(dir)/$(topology)/wavelength_per_IP.png"
        PyPlot.xlabel("wavelength number per IP link")
        PyPlot.ylabel("CDF")
        PyPlot.savefig(figname)

        for x in 1:(max_node*(max_node-1)/2-IPlink_num)
            push!(allCapacity, 0)
        end
        perm_allCapacity = shuffle!(allCapacity)
        
        lastLinkInfo = []
        initialIndex = 1

        for i in 1:length(data[1][:,1])
            LightGraphs.add_edge!(graph, Int(data[1][:,1][i]), Int(data[1][:,2][i]))
            distances[Int(data[1][:,1][i]), Int(data[1][:,2][i])] = Int(data[1][:,3][i])
            push!(fiberlinks, (Int(data[1][:,1][i]), Int(data[1][:,2][i])))
            push!(occupied_spectrum, [])
        end
        Edge = []
        Tunnel = []
        for a in 1:max_node
            for b in 1:max_node
                if  a < b
                    push!(Edge, (a, b))
                    push!(Edge, (b, a))
                end
                if a != b
                    push!(Tunnel, (a, b, 1))  # first tunnel
                    push!(Tunnel, (a, b, 2))  # second tunnel
                end
            end
        end

        ilp_path = []
        if ilp_planning
            ## planning the IP topology to make sure each node pair has at least two fiber-disjoint tunnel path
            ## ILP for routing based on flow conservation
            printstyled("Planning IP topology with ILP for $(topology)\n", color=:yellow)
            model = Model(Gurobi.Optimizer)
            set_optimizer_attribute(model, "OutputFlag", 1)
            set_optimizer_attribute(model, "Threads", 32)
            
            time_limit = 3600
            set_time_limit_sec(model, time_limit)

            nedges = length(Edge)  # uni-directional edge
            println("Edge ", Edge)
            edge_index = []
            reverse_edge_index = []
            for e in 1:nedges
                r = findfirst(x -> x == (Edge[e][2], Edge[e][1]), Edge)
                if e < r
                    push!(edge_index, e)
                    push!(reverse_edge_index, r)
                end
            end

            nfibers = length(fiberlinks)  # uni-directional fiber
            println("fiberlinks ", fiberlinks)

            ntunnels = length(Tunnel)
            println("Tunnel ", Tunnel)  # uni-directional tunnel

            println("nfibers:$(nfibers), nedges:$(nedges), ntunnels:$(ntunnels)")

            @variable(model, IPRouting[1:nedges, 1:nfibers] >= 0, Bin)  # if IP link is routed on fibers
            @variable(model, IPup[1:nedges] >= 0, Bin)
            @variable(model, TunnelRouting[1:ntunnels, 1:nedges] >= 0, Bin)  # if tunnel is routed on IP links
            @variable(model, TunnelFiber[1:ntunnels, 1:nfibers] >= 0, Bin)
            @variable(model, Tunnelup[1:ntunnels] >= 0, Bin)
            
            ## flow conservation for IP link on optical layer
            for e in 1:nedges
                @constraint(model, sum(IPRouting[e,f] for f in 1:nfibers if fiberlinks[f][1] == Edge[e][1]) == IPup[e])
                @constraint(model, sum(IPRouting[e,f] for f in 1:nfibers if fiberlinks[f][2] == Edge[e][1]) == 0)
                @constraint(model, sum(IPRouting[e,f] for f in 1:nfibers if fiberlinks[f][1] == Edge[e][2]) == 0)
                @constraint(model, sum(IPRouting[e,f] for f in 1:nfibers if fiberlinks[f][2] == Edge[e][2]) == IPup[e])
                for k in 1:max_node
                    if k != Edge[e][1] && k != Edge[e][2]
                        @constraint(model, sum(IPRouting[e,f] for f in 1:nfibers if fiberlinks[f][1] == k) == sum(IPRouting[e,f] for f in 1:nfibers if fiberlinks[f][2] == k))
                        @constraint(model, sum(IPRouting[e,f] for f in 1:nfibers if fiberlinks[f][1] == k) <= IPup[e])
                    end
                end
            end

            ## flow conservation for tunnels on IP layer
            for t in 1:ntunnels
                @constraint(model, sum(TunnelRouting[t,e] for e in 1:nedges if Edge[e][1] == Tunnel[t][1]) == Tunnelup[t])
                @constraint(model, sum(TunnelRouting[t,e] for e in 1:nedges if Edge[e][2] == Tunnel[t][1]) == 0)
                @constraint(model, sum(TunnelRouting[t,e] for e in 1:nedges if Edge[e][1] == Tunnel[t][2]) == 0)
                @constraint(model, sum(TunnelRouting[t,e] for e in 1:nedges if Edge[e][2] == Tunnel[t][2]) == Tunnelup[t])
                for k in 1:max_node
                    if k != Tunnel[t][1] && k != Tunnel[t][2]
                        @constraint(model, sum(TunnelRouting[t,e] for e in 1:nedges if Edge[e][1] == k) == sum(TunnelRouting[t,e] for e in 1:nedges if Edge[e][2] == k))
                        @constraint(model, sum(TunnelRouting[t,e] for e in 1:nedges if Edge[e][1] == k) <= 1)
                    end
                end
            end

            ## if a tunnel use an IP link, then IP link should be up
            for e in 1:nedges
                @constraint(model, sum(TunnelRouting[t,e] for t in 1:ntunnels) >= IPup[e])
                @constraint(model, sum(TunnelRouting[t,e] for t in 1:ntunnels) <= 99999*IPup[e])
            end

            ## the two tunnels cannot share a fiber
            for f in 1:nfibers
                for t in 1:ntunnels
                    @constraint(model, TunnelFiber[t,f] <= sum(TunnelRouting[t,e]*IPRouting[e,f] for e in 1:nedges))
                    @constraint(model, TunnelFiber[t,f] >= sum(TunnelRouting[t,e]*IPRouting[e,f] for e in 1:nedges)/9999)
                    for tt in 1:ntunnels
                        if Tunnel[t][1] == Tunnel[tt][1] && Tunnel[t][2] == Tunnel[tt][2] && Tunnel[t][3] != Tunnel[tt][3]
                            @constraint(model, TunnelFiber[t,f] + TunnelFiber[tt,f] <= 1)
                        end
                    end
                end
            end
            
            @constraint(model, sum(IPup[e] for e in 1:nedges) == linknum)
            
            @objective(model, Max, sum(Tunnelup[t] for t in 1:ntunnels))
            optimize!(model)

            planned_paths = []
            printstyled("$(topology) IP topology provision results\n", color=:green)

            ## IP link routing result
            routing_result = value.(IPRouting)
            provisioned_edges_num = 0
            routing_path = []
            for e in 1:nedges
                edge_routing = []
                if sum(routing_result[e,:]) > 0
                    provisioned_edges_num += 1
                    print("IP $(Edge[e][1])-$(Edge[e][2]): ")
                    for f in 1:nfibers
                        if routing_result[e,f] == 1
                            print("$(fiberlinks[f][1])-$(fiberlinks[f][2]), ")
                            push!(edge_routing, fiberlinks[f][1])
                        end
                    end
                    println(routing_result[e,:])
                    push!(edge_routing, Edge[e][2])  # the last node
                end
                push!(routing_path, edge_routing)
            end
            ilp_path = routing_path

            println("provisioned_edges_num ", provisioned_edges_num)

            ## tunnel routing result
            tunnel_result = value.(TunnelRouting)
            provisioned_tunnel_num = 0
            for t in 1:ntunnels
                if sum(tunnel_result[t,:]) > 0
                    provisioned_tunnel_num += 1
                    print("Tunnel $(Tunnel[t][1])-$(Tunnel[t][2])-$(Tunnel[t][3]): ")
                    for e in 1:nedges
                        if tunnel_result[t,e] == 1
                            print("$(Edge[e][1])-$(Edge[e][2]), ")
                        end
                    end
                    # println(tunnel_result[t,:])
                end
            end
            println("provisioned_tunnel_num ", provisioned_tunnel_num)
        end

        ## assign wavelength number to IP links based on distribution
        spectrum_storage = Dict()
        optical_links_storage = Dict()
        failure_probability_storage = Dict()
        for src in 1:max_node
            for dst in 1:max_node
                spectrum = []
                optical_links = []
                reverse_optical_links = []
                capacity = 0
                if src < dst  # handling bidirectional
                    if ilp_planning
                        paths = []
                        # read from ILP results
                        for i in 1:length(ilp_path)
                            if src == ilp_path[i][1] && dst == ilp_path[i][end]
                                push!(paths, ilp_path[i])
                                break
                            end
                        end
                    else
                        k = 1
                        state = LightGraphs.yen_k_shortest_paths(graph, src, dst, distances, k)
                        paths = state.paths
                    end
                    # println("IP link's paths: ", paths)
                    for n in 2:length(paths[k])
                        e = findfirst(x -> x == (paths[k][n-1], paths[k][n]), fiberlinks)  # this is the fiber
                        push!(optical_links, e)
                        r = findfirst(x -> x == (paths[k][n], paths[k][n-1]), fiberlinks)  # this is the fiber
                        push!(reverse_optical_links, r)
                    end
                    capacity = perm_allCapacity[Int((2*max_node-src)*(src-1)/2+dst-src)]
                    Cband = 96  # number of available wavelength, we use the ITU-T grid standard with 50 GHz spacing
                    capacity_count = 0  # in terms of wavelength number
                    failure_probability = 0.001*length(paths[k])  # depend on fiber path hops, assume equal failure per fiber
                    if capacity > 0 
                        # First fit spectrum assignment
                        for f in 1:Cband
                            select_marker = 0
                            for e in optical_links
                                if f in occupied_spectrum[e]
                                    select_marker = 1
                                    break
                                end
                            end
                            if select_marker == 0
                                push!(spectrum, f)
                                for e in optical_links
                                    push!(occupied_spectrum[e], f)
                                end
                                capacity_count += 1
                            end
                            if capacity_count == capacity
                                break
                            end
                        end
                    else
                        spectrum = []
                    end
                    spectrum_storage[string(src)*"."*string(dst)] = spectrum
                    optical_links_storage[string(src)*"."*string(dst)] = reverse_optical_links
                    failure_probability_storage[string(src)*"."*string(dst)] = failure_probability
                elseif src > dst  # just look up for the other direction
                    spectrum = spectrum_storage[string(dst)*"."*string(src)]
                    optical_links = optical_links_storage[string(dst)*"."*string(src)]
                    capacity = length(spectrum)
                    failure_probability = failure_probability_storage[string(dst)*"."*string(src)]
                end
                println("src:$(src), dst:$(dst), capacity:$(capacity)")
                if tofile == true   
                    if capacity > 0
                        if length(spectrum) <= capacity && length(spectrum) > 0
                            writedlm(io, [src  dst  initialIndex  length(spectrum)  string(optical_links) string(spectrum) failure_probability])
                        end
                    end
                end
                if capacity > 0
                    if length(spectrum) <= capacity && length(spectrum) > 0
                        thislinkinfo = [src]
                        thislinkinfo = hcat(thislinkinfo, dst)
                        thislinkinfo = hcat(thislinkinfo, initialIndex)
                        thislinkinfo = hcat(thislinkinfo, length(spectrum))
                        thislinkinfo = hcat(thislinkinfo, string(optical_links))
                        thislinkinfo = hcat(thislinkinfo, string(spectrum))
                        thislinkinfo = hcat(thislinkinfo, failure_probability)
                        if length(lastLinkInfo) > 0
                            lastLinkInfo = vcat(lastLinkInfo, thislinkinfo)
                        else
                            lastLinkInfo = thislinkinfo
                        end
                    end
                end
            end
        end
        return lastLinkInfo
    end 
end

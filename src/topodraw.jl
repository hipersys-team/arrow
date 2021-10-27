using Compose, GraphPlot, Cairo, Gadfly


function drawTunnel(topology, a, T, Tf, edges, num_nodes, dir, algorithm)
    edgelabels = []
    graph = LightGraphs.SimpleDiGraph(num_nodes)
    ntunnels = length(T)
    nedges = length(edges)

    L = zeros(ntunnels, nedges)
    for t in 1:ntunnels
        for e in 1:nedges
            if in(e, T[t])
                L[t,e] = 1
            end
        end
    end
    for e in 1:size(edges,1)
        LightGraphs.add_edge!(graph, edges[e][1], edges[e][2])
        s = 0
        for f in 1:size(a,1)
            for t in 1:size(a,2)
                s += a[f,t] * L[Tf[f][t],e]
            end
        end
        s = round(s, digits=2)
        push!(edgelabels, s)
    end
    nodelabel = collect(1:num_nodes)
    Compose.draw(PNG("$(dir)/$(topology)/00_$(algorithm)_tunnel_graph.png", 1000, 1000), gplot(graph, edgelabelc="white", EDGELABELSIZE = 20.0, NODELABELSIZE=20.0, nodelabel=nodelabel, edgelabeldisty=0.5, edgelabel=edgelabels, EDGELINEWIDTH=3.0, arrowlengthfrac=.04))
end


function drawGraph(topology, IPTopo, topology_index, OpticalTopo, dir)
    graph = LightGraphs.SimpleDiGraph(length(IPTopo["nodes"]))
    for e in 1:length(IPTopo["links"])
        LightGraphs.add_edge!(graph, IPTopo["links"][e][1], IPTopo["links"][e][2])
        # println("$(IPTopo["links"][e][1])->$(IPTopo["links"][e][2])@$(IPTopo["capacity"][e])")
    end

    iplink_bw = []  # the sequence of labeling is internal decided, different from the sequence of input files
    for ss in 1:length(IPTopo["nodes"])
        for dd in 1:length(IPTopo["nodes"])
            if LightGraphs.has_edge(graph, ss, dd)
                for e in 1:length(IPTopo["links"])
                    if ss==IPTopo["links"][e][1] && dd==IPTopo["links"][e][2]
                        push!(iplink_bw, IPTopo["capacity"][e])
                    end
                end
            end
        end
    end

    nodelabel = collect(1:length(IPTopo["nodes"]))
    Compose.draw(PNG("$(dir)/$(topology)/00_IP_topo_graph.png", 1000, 1000), gplot(graph, edgelabelc="white", EDGELABELSIZE = 20.0, NODELABELSIZE=20.0, nodelabel=nodelabel, edgelabeldisty=0.5, edgelabel=iplink_bw, EDGELINEWIDTH=3.0, arrowlengthfrac=.04))
    if !isfile("data/topology/$(topology)/IP_topo_$(topology_index)/IP_topo_graph.png")
        Compose.draw(PNG("data/topology/$(topology)/IP_topo_$(topology_index)/IP_topo_graph.png", 1000, 1000), gplot(graph, edgelabelc="white", EDGELABELSIZE = 20.0, NODELABELSIZE=20.0, nodelabel=nodelabel, edgelabeldisty=0.5, edgelabel=iplink_bw, EDGELINEWIDTH=3.0, arrowlengthfrac=.04))
    end

    optical_graph = LightGraphs.SimpleDiGraph(length(OpticalTopo["nodes"]))
    for e in 1:length(OpticalTopo["links"])
        LightGraphs.add_edge!(optical_graph, OpticalTopo["links"][e][1], OpticalTopo["links"][e][2])
    end

    fiber_capacity = []  # the sequence of labeling is internal decided, different from the sequence of input files
    fiber_spectrum_availability = []
    for ss in 1:length(OpticalTopo["nodes"])
        for dd in 1:length(OpticalTopo["nodes"])
            if LightGraphs.has_edge(optical_graph, ss, dd)
                for e in 1:length(OpticalTopo["links"])
                    if ss==OpticalTopo["links"][e][1] && dd==OpticalTopo["links"][e][2]
                        fiber_available_wave_num = sum(OpticalTopo["capacityCode"][e,:])
                        push!(fiber_capacity, fiber_available_wave_num)
                        fiber_available_spectrum = []
                        for w in 1:length(OpticalTopo["capacityCode"][e,:])
                            if OpticalTopo["capacityCode"][e,w] == 1
                                push!(fiber_available_spectrum, w)
                            end
                        end
                        push!(fiber_spectrum_availability, fiber_available_spectrum)
                    end
                end
            end
        end
    end

    optical_nodelabel = collect(1:length(OpticalTopo["nodes"]))
    if !isfile("data/topology/$(topology)/optical_topo_graph.png")
        Compose.draw(PNG("data/topology/$(topology)/optical_topo_graph.png", 1000, 1000), gplot(optical_graph, edgelabelc="yellow", layout=spring_layout, NODELABELSIZE=20.0, nodelabel=optical_nodelabel, EDGELINEWIDTH=3.0, arrowlengthfrac=.04))
    end
    Compose.draw(PNG("$(dir)/$(topology)/00_optical_topo_graph_residual_fiber_capacity.png", 1000, 1000), gplot(optical_graph, edgelabelc="yellow", layout=spring_layout, EDGELABELSIZE = 20.0, NODELABELSIZE=20.0, nodelabel=optical_nodelabel, edgelabeldisty=0.5, edgelabel=fiber_capacity, EDGELINEWIDTH=3.0, arrowlengthfrac=.04))
    if !isfile("data/topology/$(topology)/IP_topo_$(topology_index)/optical_topo_graph_residual_fiber_capacity.png")
        Compose.draw(PNG("data/topology/$(topology)/IP_topo_$(topology_index)/optical_topo_graph_residual_fiber_capacity.png", 1000, 1000), gplot(optical_graph, edgelabelc="yellow", layout=spring_layout, EDGELABELSIZE = 20.0, NODELABELSIZE=20.0, nodelabel=optical_nodelabel, edgelabeldisty=0.5, edgelabel=fiber_capacity, EDGELINEWIDTH=3.0, arrowlengthfrac=.04))
    end
    Compose.draw(PNG("$(dir)/$(topology)/00_optical_topo_graph_spectrum_availability.png", 2000, 2000), gplot(optical_graph, edgelabelc="yellow", layout=spring_layout, EDGELABELSIZE = 15.0, NODELABELSIZE=20.0, nodelabel=optical_nodelabel, edgelabeldisty=0.5, edgelabel=fiber_spectrum_availability, EDGELINEWIDTH=3.0, arrowlengthfrac=.04))
    if !isfile("data/topology/$(topology)/IP_topo_$(topology_index)/optical_topo_graph_spectrum_availability.png")
        Compose.draw(PNG("data/topology/$(topology)/IP_topo_$(topology_index)/optical_topo_graph_spectrum_availability.png", 2000, 2000), gplot(optical_graph, edgelabelc="yellow", layout=spring_layout, EDGELABELSIZE = 15.0, NODELABELSIZE=20.0, nodelabel=optical_nodelabel, edgelabeldisty=0.5, edgelabel=fiber_spectrum_availability, EDGELINEWIDTH=3.0, arrowlengthfrac=.04))
    end
end

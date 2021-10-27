using ProgressMeter

include("./interface.jl")


## fiber cut scenarios and their affected IP links
function GetAllScenarios(IPTopo, OpticalTopo, cutoff, is_ffc_scenario, ffc_fiber_cut_num)
    if is_ffc_scenario
        # simutaneous fiber cut
        scenarios = []
        probs = []
        # healthy state
        n_unifibers = length(OpticalTopo["bidirect_links"])
        s0 = ones(n_unifibers)
        push!(scenarios, s0)
        push!(probs, 1)

        # failure states
        for bits in collect(combinations(1:n_unifibers,ffc_fiber_cut_num))
            s = ones(n_unifibers)
            current_prob = 1
            for bit in bits
                s[bit] = 0
                current_prob = current_prob * OpticalTopo["fiber_probs"][bit]
            end
            push!(scenarios, s)
            push!(probs, current_prob)  # because of uni-directional fibers
        end
        probs[1] = 1 - sum(probs[2:end])
    else
        # probabilistic fiber cut with cutoff
        scenarios, probs = subScenarios(OpticalTopo, IPTopo, cutoff, first=true, last=false)
    end
    # Note that here the scenario is on directional graph
    # println(scenarios, probs)

    oscenarios = []
    oprobs = probs
    # translate optical scenario to bidirectional because optical fibers are bidirectional
    for s in 1:size(scenarios, 1)
        current_scenario = ones(length(OpticalTopo["links"]))
        for i in 1:length(scenarios[s])
            if scenarios[s][i] == 0
                xx = findfirst(x -> x == (OpticalTopo["bidirect_links"][i][1], OpticalTopo["bidirect_links"][i][2]), OpticalTopo["links"])
                yy = findfirst(x -> x == (OpticalTopo["bidirect_links"][i][2], OpticalTopo["bidirect_links"][i][1]), OpticalTopo["links"])
                current_scenario[xx] = 0
                current_scenario[yy] = 0
            end
        end
        push!(oscenarios, current_scenario)
    end
    # println(oscenarios, oprobs)

    OpticalScenarios = Dict()
    OpticalScenarios["code"] = oscenarios
    OpticalScenarios["prob"] = oprobs

    ## map optical failures to IP failures (IP links are bidirectional)
    iscenarios_all = []
    iprobs_all = []
    for s in 1:length(oscenarios)
        iscenarios = ones(length(IPTopo["links"]))
        iprobs = oprobs[s]
        for i in 1:length(oscenarios[s])
            if oscenarios[s][i] == 0
                # this fiber fails
                for k in 1:length(IPTopo["links"])
                    # if i in IPTopo["link_fiberroute"][k]
                    if in(i, IPTopo["link_fiberroute"][k])
                        iscenarios[k] = 0
                    end
                end
            end
        end
        push!(iscenarios_all, iscenarios)
        push!(iprobs_all, Float64(iprobs))
    end
    IPScenarios = Dict()
    IPScenarios["code"] = iscenarios_all
    IPScenarios["prob"] = iprobs_all
    return IPScenarios, OpticalScenarios
end


## generate subscenarios
function subScenarios(optical_topo, IPTopo, cutoff; first=true, last=true, progress=true)
    original = optical_topo["bidirect_fiber_probs"]
    p = ProgressMeter.ProgressUnknown("Computing scenarios cutoff=$(cutoff)...")
    if progress
        scenarios, probabilities = subScenariosRecursion(optical_topo, IPTopo, original, cutoff, progress=p)
    else
        scenarios, probabilities = subScenariosRecursion(optical_topo, IPTopo, original, cutoff)
    end
    if first == false
        scenarios = scenarios[2:end]
        probabilities = probabilities[2:end]
    end
    if last
        push!(scenarios, zeros(length(scenarios[1])))
        push!(probabilities, 1 - sum(probabilities))
    end
    if sum(probabilities) < 1
        probabilities = probabilities ./ sum(probabilities)
    end
    ProgressMeter.finish!(p)
    return scenarios, probabilities
end


## recursively generate failure scenarios with probability
function subScenariosRecursion(optical_topo, IPTopo, original, cutoff, remaining=[], offset=0, partial=[], scenarios=[], probabilities=[]; progress=nothing)
    if (size(partial,1) == 0)   #first
        push!(scenarios, ones(size(original,1)))
        push!(probabilities, prod(1 .- original))
        remaining = original
    else (size(partial,1) > 0)
        probs = 1 .- original
        bitmap = ones(size(original, 1))   #create bitmap
        for i in 1:length(partial)
            probs[partial[i]] = original[partial[i]]
            bitmap[partial[i]] = 0  # this is bidirectioanl fiber failure bitmap
        end
        ## translate bidirectional fiber failure to directional fiber failure for connectivity check
        directional_bitmap = ones(length(optical_topo["links"]))
        for i in 1:length(bitmap)
            if bitmap[i] == 0
                xx = findfirst(x -> x == (optical_topo["bidirect_links"][i][1], optical_topo["bidirect_links"][i][2]), optical_topo["links"])
                yy = findfirst(x -> x == (optical_topo["bidirect_links"][i][2], optical_topo["bidirect_links"][i][1]), optical_topo["links"])
                directional_bitmap[xx] = 0
                directional_bitmap[yy] = 0
            end
        end
        product = prod(probs)
        if progress !== nothing
            ProgressMeter.next!(progress, showvalues = [(:cutoff,cutoff), (:scenarios_added,length(probabilities)), (:last, product)])
        end
        if product >= cutoff
            if OpticalGraphConnectivity(optical_topo, directional_bitmap)  # remove fiber cut events that disconnect fiber topo
                ## map optical failures to IP failures
                iscenarios = ones(length(IPTopo["links"]))
                for i in 1:length(directional_bitmap)
                    if directional_bitmap[i] == 0
                        # this fiber fails
                        for k in 1:length(IPTopo["links"])
                            if in(i, IPTopo["link_fiberroute"][k])
                                iscenarios[k] = 0
                            end
                        end
                    end
                end
                
                ## check if this IP failure will disconnecct IP topology
                if IPGraphConnectivity(IPTopo,iscenarios)
                    push!(scenarios, bitmap)  # return bidirectional fiber failure
                    push!(probabilities, product)
                end
            end
        else
            return
        end
    end

    for i in 1:size(remaining,1)
        offset = size(original,1) - size(remaining,1)
        n = offset + i
        subScenariosRecursion(optical_topo, IPTopo, original, cutoff, remaining[i+1:end], offset, vcat(partial, [n]), scenarios, probabilities, progress=progress)
    end
    return scenarios, probabilities
end


## make sure fiber cut does not make the fiber topology disconnected (in real life no fiber cut should not separate a graph)
function OpticalGraphConnectivity(optical_topo, optical_failure_bitmap)
    num_nodes = length(optical_topo["nodes"])
    graph = LightGraphs.SimpleDiGraph(num_nodes)  
    for f in 1:length(optical_topo["bidirect_links"])
        if optical_failure_bitmap[f] > 0
            LightGraphs.add_edge!(graph, optical_topo["bidirect_links"][f][1], optical_topo["bidirect_links"][f][2])
        end
    end
    if is_connected(graph)
        return true
    else
        return false
    end
end


## make sure fiber cut does not make the IP topology disconnected (in real life no fiber cut should not separate a graph)
function IPGraphConnectivity(IP_topo, IP_failure_bitmap)
    num_nodes = length(IP_topo["nodes"])
    graph = LightGraphs.SimpleDiGraph(num_nodes)  
    for f in 1:length(IP_topo["links"])
        if IP_failure_bitmap[f] > 0
            LightGraphs.add_edge!(graph, IP_topo["links"][f][1], IP_topo["links"][f][2])
        end
    end
    if is_connected(graph)
        return true
    else
        return false
    end
end

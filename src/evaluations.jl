include("./controller.jl")


## calculate value at risk for failure scenarios
function VAR(losses, probabilities, beta)
    usorted = []
    psorted = []
    umodified = losses
    pmodified = probabilities
    while length(umodified) > 0
        s = argmin(umodified)
        push!(usorted, umodified[s])
        push!(psorted, pmodified[s])
        umodified = umodified[1:end .!= s]
        pmodified = pmodified[1:end .!= s]
    end

    total = 0
    loss = 0
    for s in 1:size(usorted, 1)
        total += psorted[s]
        loss = usorted[s]
        if total >= beta
            break
        end
    end
    return loss
end


function TrafficReAssignment(links_utilization, edges, capacity, demand, flows, T, Tf, k, TunnelBw, FlowBw, scenarios, restored, algorithm, verbose; progress=false)
    nedges = length(edges)
    nflows = length(flows)
    ntunnels = length(T)
    nscenarios = length(scenarios)
    RouterPorts = deepcopy(links_utilization)
    arrow_algorithms = ["ARROW", "ARROW_NAIVE", "ARROW_BIN"]

    scenario_lost = []
    scenario_restored = []
    if verbose
        if in(algorithm, arrow_algorithms)
            for q in 1:nscenarios
                scenario_capacity = capacity .* scenarios[q]
                push!(scenario_lost, sum(capacity)-sum(scenario_capacity))
                push!(scenario_restored, sum(restored[q])-sum(scenario_capacity))
            end
            println("per scenario lost capacity ", scenario_lost)
            println("per scenario sum restored ", scenario_restored)
            println("$(algorithm) Scenario restoration ratio", scenario_restored ./ scenario_lost)
        else
            for q in 1:nscenarios
                scenario_capacity = capacity .* scenarios[q]
                push!(scenario_lost, sum(capacity)-sum(scenario_capacity))
                push!(scenario_restored, sum(restored[q]))
            end
            if sum(scenario_restored) > 0
                println("$(algorithm) selected per scenario sum restored ", scenario_restored)
                println("$(algorithm) Scenario restoration ratio", scenario_restored ./ scenario_lost)
                println("$(algorithm) sum scenario restored ", sum(scenario_restored))
                printstyled("Error! $(algorithm) has restorable capacity!\n", color=:red)
            end
        end
    end
    if verbose println("reassign demand: ", sum(demand), " ", demand) end
    if verbose println("reassign capacity: ", sum(capacity), " ", capacity) end
    if verbose println("reassign restored: ", sum(restored), " ", restored) end

    #CREATE TUNNEL SCENARIO MATRIX
    X  = ones(nscenarios,ntunnels)
    for s in 1:nscenarios
        for t in 1:ntunnels
            if size(T[t],1) == 0
                X[s,t] = 0
            else
                for e in 1:nedges
                    if scenarios[s][e] == 0 && restored[s][e] == 0  # both failed and non-restorable
                        back_edge = findfirst(x -> x == (edges[e][2],edges[e][1],edges[e][3]), edges)
                        if in(e, T[t]) || in(back_edge, T[t])
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

    routed = zeros(nscenarios, nflows, k)
    allowed = zeros(nscenarios)
    scenarioAffectedFlow = zeros(nscenarios)
    scenarioCongestionLoss = zeros(nscenarios)

    # SCENARIO LOSS PER FLOW
    for s in 1:nscenarios
        if verbose printstyled("== Process scenario $(s)\n", color=:yellow) end
        scenario_network_capacity = 0
        scenario_tunnel_bw = deepcopy(TunnelBw)  ## every failure scenario should start with the initial TE splitratio results
        scenario_flow_bw = deepcopy(FlowBw)
        affected_flows = zeros(nflows)

        ## healthy state should respect tunnel reservations (FFC, TEAVAR, ARROW), overflow traffic should be put on other 0 allocated tunnels
        ## in this case, the tunnel allocation will be modified because we are accepting more traffic than formulation output
        for f in 1:nflows
            if occursin("TEAVAR", algorithm)  || occursin("FFC", algorithm) || occursin("ARROW", algorithm) || occursin("ARROW_NAIVE", algorithm)  # reservation based TE
                if scenario_flow_bw[f] < demand[f]  # assign overflow traffic to 0 unallocated tunnels
                    overflow = demand[f] - scenario_flow_bw[f]
                    zero_unallocated_tunnel = zeros(size(Tf[f],1))
                    for t in 1:size(Tf[f],1)
                        if scenario_tunnel_bw[f,t] == 0
                            zero_unallocated_tunnel[t] = 1
                        end
                    end
                    if sum(zero_unallocated_tunnel) > 0  # there exist 0 unallocated tunnel
                        if verbose println("Flow $(f)'s overflow $(overflow) load balancing to $(sum(zero_unallocated_tunnel)) unallocated tunnels") end
                        for t in 1:size(Tf[f],1)
                            if zero_unallocated_tunnel[t] == 1
                                scenario_tunnel_bw[f,t] = round(overflow/sum(zero_unallocated_tunnel), digits=16)  # actual allocation without reservation
                            end
                        end
                    end
                end
            end
        end

        if verbose println("scenario_tunnel_bw ", scenario_tunnel_bw) end

        ## calculate demand loss due to local proportional routing under failure scenarios
        for f in 1:nflows
            ## for reservation based TE, use reservation first, if all reservation fails, use other 0 allocated tunnels with local proportional routing for traffic
            totalup = 0
            for t in 1:size(Tf[f],1)
                totalup += round(scenario_tunnel_bw[f,t] * X[s,Tf[f][t]], digits=16)  # split ratio sum of residual (or restorable) tunnels
            end
            if totalup == 0
                scenario_tunnel_bw[f,:] = scenario_tunnel_bw[f,:] .+ 1
                if verbose println("ECMP for local proportional routing because of no/failed reserved tunnels of flow $(f)") end
                for t in 1:size(Tf[f],1)
                    totalup += round(scenario_tunnel_bw[f,t] * X[s,Tf[f][t]], digits=16)  # sum split ratios of survived tunnels
                end
            end
            for t in 1:size(Tf[f],1)
                if totalup != 0
                    routed[s,f,t] = round(scenario_tunnel_bw[f,t] * X[s,Tf[f][t]] / totalup, digits=16) * round(demand[f], digits=16)  # local proportional routing
                else
                    if verbose println("flow $(f)'s original $(t) tunnels all fail (original bw $(scenario_tunnel_bw[f,t]), $(TunnelBw[f,t]))") end
                end
            end
            if round((sum(routed[s,f,:]) - demand[f])/demand[f],  digits=6) < 0
                affected_flows[f] = 1
            end
        end
        allowed[s] = round(Float64(sum(routed[s,:,:])),  digits=16)  # expected throughput via local proportional routing (congestion included)
        if verbose println("$(algorithm) allowed: $(allowed), demand: $(demand)") end

        ## calculate demand loss due to link congestion after local proportional routing
        congestion_loss = 0
        for e in 1:nedges
            edge_utilization = 0
            for f in 1:nflows  # edge utilization after local proportional routing
                edge_utilization += round(Float64(sum(routed[s,f,t] * L[Tf[f][t],e] * X[s,Tf[f][t]] for t in 1:size(Tf[f],1))),  digits=16)
            end
            # println("Edge: ", edges[e])
            # println(max(0, edge_utilization - capacity[e]))
            if restored[s][e] > 0 && scenarios[s][e] == 0
                per_link_current_capacity = restored[s][e]
            elseif restored[s][e] > 0 && scenarios[s][e] > 0
                per_link_current_capacity = capacity[e]
            elseif restored[s][e] == 0 && scenarios[s][e] > 0
                per_link_current_capacity = capacity[e]
            elseif restored[s][e] == 0 && scenarios[s][e] == 0
                per_link_current_capacity = 0
            end
            scenario_network_capacity += per_link_current_capacity

            # RouterPorts[e] = max(RouterPorts[e], max(0, min(edge_utilization, per_link_current_capacity)-restored[s][e]*scenarios[s][e]))
            RouterPorts[e] = max(RouterPorts[e], min(edge_utilization, per_link_current_capacity))
            congestion_loss += max(0, round(Float64(edge_utilization - per_link_current_capacity), digits=6))

            # if there is a link congested, then all tunnels (flows) on that link will be affected (uniformly)
            if round(Float64(edge_utilization - per_link_current_capacity), digits=6) > 0
                for f in 1:nflows
                    flow_affect = 0
                    for t in 1:size(Tf[f],1)
                        if L[Tf[f][t],e] > 0 && scenario_tunnel_bw[f,t] > 0  # all non-zero tunnel after local proportional routing running on the failed link
                            flow_affect = 1  # t is the global index of all tunnels
                        end
                    end
                    affected_flows[f] = max(flow_affect, affected_flows[f])
                end
                if verbose printstyled("$(algorithm) network $(s) scenario's $(e) link: restored-$(restored[s][e])/capacity-$(capacity[e])/fail-$(scenarios[s][e]) edge_utilization $(edge_utilization) per_link_current_capacity $(per_link_current_capacity) affected flow $(sum(affected_flows)) \n", color=:red) end
            end
        end
        if verbose println("scenario_network_capacity ", scenario_network_capacity) end
        scenarioAffectedFlow[s] = sum(affected_flows)  # number of affected flows
        scenarioCongestionLoss[s] += congestion_loss   # amount of affected traffic
    end

    if scenarioCongestionLoss[1] > 0 && verbose
        printstyled("healthy $(algorithm) network $(scenarioAffectedFlow[1]) flows has congestion loss $(scenarioCongestionLoss[1]): demand too much!\n", color=:yellow)
    end
    if verbose println("allowed ", allowed) end

    umax = []
    for l in 1:nscenarios
        if sum(demand) == 0
            push!(umax, 1)  # if demand overscaling, no bw accessible, loss is equivalent 100%
            scenarioAffectedFlow[l] = nflows  # all flow loss
        else
            push!(umax, 1-round((allowed[l] - scenarioCongestionLoss[l])/sum(demand), digits=6))
        end
    end

    umax_zero_indices = findall(x -> x == 0, umax)
    flows_zero_indices = findall(x -> x == 0, scenarioAffectedFlow)

    if umax_zero_indices != flows_zero_indices && verbose
        printstyled("Losses don't match on zero indices\n", color=:red)
        printstyled("$(algorithm) allowed  $(allowed)\n", color=:red)
        printstyled("$(algorithm) scenarioCongestionLoss $(scenarioCongestionLoss)\n", color=:red)
        printstyled("$(algorithm) Loss ratio $(umax)\n", color=:red)
        printstyled("$(algorithm) scenarioAffectedFlow $(scenarioAffectedFlow)\n", color=:red)
    end

    return umax, scenarioAffectedFlow, RouterPorts
end


## percentage of scenarios that sustain 100% throughput
function ScenarioAvailability(losses, probabilities, sla, conditional)
    usorted = []
    psorted = []
    if conditional
        umodified = deepcopy(losses[2:end])
        pmodified = deepcopy(probabilities[2:end])
        pmodified = pmodified / (1 - probabilities[1])
    else
        umodified = deepcopy(losses)
        pmodified = deepcopy(probabilities)
    end

    while length(umodified) > 0
        s = argmin(umodified)
        push!(usorted, umodified[s])
        push!(psorted, pmodified[s])
        umodified = umodified[1:end .!= s]
        pmodified = pmodified[1:end .!= s]
    end

    total = 0
    loss = 0
    for s in 1:length(usorted)
        loss = usorted[s]
        if loss > sla
            break
        end
        total += psorted[s]  # all-or-nothing scenario level availability
    end

    return total
end


## percentage of flows weighted by scenarios that sustain 100% throughput
function FlowAvailability(losses, affectflows, flows, probabilities, sla, conditional)
    usorted = []
    psorted = []
    if conditional
        umodified = deepcopy(losses[2:end])
        pmodified = deepcopy(probabilities[2:end])
        pmodified = pmodified / (1 - probabilities[1])
    else
        umodified = deepcopy(losses)
        pmodified = deepcopy(probabilities)
    end

    while length(umodified) > 0
        s = argmin(umodified)
        push!(usorted, umodified[s])
        push!(psorted, pmodified[s])
        umodified = umodified[1:end .!= s]
        pmodified = pmodified[1:end .!= s]
    end
    total = 0
    loss = 0
    for s in 1:length(usorted)
        loss = usorted[s]
        if loss > sla  # there is loss
            total += (psorted[s]) * (1 - (affectflows[s] / length(flows)))  # flow level availability
        else
            total += (psorted[s])
        end
    end
    return total
end


# percentage of un-affected traffic weighted by sccenario that sustain 100% throughput
function BandwidthAvailability(losses, probabilities, sla, conditional)
    usorted = []
    psorted = []
    if conditional
        umodified = deepcopy(losses[2:end])
        pmodified = deepcopy(probabilities[2:end])
        pmodified = pmodified / (1 - probabilities[1])
    else
        umodified = deepcopy(losses)
        pmodified = deepcopy(probabilities)
    end

    while length(umodified) > 0
        s = argmin(umodified)
        push!(usorted, umodified[s])
        push!(psorted, pmodified[s])
        umodified = umodified[1:end .!= s]
        pmodified = pmodified[1:end .!= s]
    end

    total = 0
    loss = 0
    for s in 1:length(usorted)
        loss = usorted[s]
        if loss > sla  # there is loss
            total += (psorted[s]) * (1 - loss)  # bandwidth level availability
        else
            total += (psorted[s])
        end
    end

    return total
end


## compute link utilization in units of bw
function computeLinksUtilization(edges, capacity, demand, flows, T, Tf, k, splittingratios_original; progress=false)
    nedges = length(edges)
    nflows = length(flows)
    ntunnels = length(T)

    #CREATE TUNNEL EDGE MATRIX
    L = zeros(ntunnels, nedges)
    for t in 1:ntunnels
        for e in 1:nedges
            if in(e, T[t])
                L[t,e] = 1
            end
        end
    end

    splittingratios = deepcopy(splittingratios_original)

    # compute how reassignment is done under no failure scenario
    routed = zeros(nflows, ntunnels)
    for f in 1:nflows
        totalup = 0
        for t in 1:size(Tf[f],1)
            totalup += Float64(splittingratios[f,t])
        end
        ## if the only tunnel fails, other original 0 allocated tunnels should be used
        # if totalup == 0
        #     splittingratios[f,:] = splittingratios[f,:] .+ 1
        #     for t in 1:size(Tf[f],1)
        #         totalup += Float64(splittingratios[f,t])
        #     end
        # end

        for t in 1:size(Tf[f],1)
            if totalup != 0
                routed[f,t] = Float64(splittingratios[f,t] / totalup * demand[f])
            else
                routed[f,t] = 0  # no traffic routed for this flow
            end
        end
    end

    links_utilization = [0.0 for e in 1:nedges]
    for e in 1:nedges
        e_utilization = sum(routed[f,t] * L[Tf[f][t],e] for f in 1:nflows for t in 1:size(Tf[f],1))
        links_utilization[e] = e_utilization
    end

    return links_utilization
end

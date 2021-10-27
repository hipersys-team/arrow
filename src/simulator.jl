using Dates, HDF5, JLD


include("./enviroment.jl")
include("./evaluations.jl")
include("./restoration.jl")
include("./plotting.jl")


## distill (remove duplicates) randomized rounded tickets among all scenarios, but do not consider the 0 restored capacity in those non-restorable scenarios
function distill_tickets(rr_scenario_restored_bw, IPTopo, IPScenarios, verbose)
    distill_rr_scenario_restored_bw = []
    max_ticket_num = 0
    for q in 1:length(IPScenarios["code"])
        for r in 1:size(rr_scenario_restored_bw[q], 1)
            # println("rr_scenario_restored_bw[q][r] ", rr_scenario_restored_bw[q][r])
            # println(zeros(length(IPTopo["capacity"])))
            if rr_scenario_restored_bw[q][r] == IPTopo["capacity"] .* IPScenarios["code"][q]  # recognize no restoration happens, 0 paddings
                if r > max_ticket_num
                    max_ticket_num = r
                end
            end
        end
    end
    if verbose println("max_ticket_num ", max_ticket_num) end

    for q in 1:length(IPScenarios["code"])
        distill_rr_current_scenario_restored_bw = []
        for r in 1:max_ticket_num
            push!(distill_rr_current_scenario_restored_bw, rr_scenario_restored_bw[q][r])
        end
        push!(distill_rr_scenario_restored_bw, distill_rr_current_scenario_restored_bw)
    end

    return distill_rr_scenario_restored_bw
end


## Generating/Reading lottery tickets, if generating, run in parallel mode, if reading, run in single thread mode
function lottery_ticket_generation(GRB_ENV, ticket_dir, RWAFileName, LPFileName, TicketFileName, IPTopo, IPScenarios, OpticalTopo, OpticalScenarios, scenario_generation_only, optical_rerouting_K, option_num, option_gap, scenario_id, topology_index, verbose, ticket_or_not, progress0)
    rwa_scenario_restored_bw = []  # list of rwa solutions for different scenarios
    rwa_lp_scenario_restored_bw = []  # list of rwa lp solutions for different scenarios
    rr_scenario_restored_bw = []  # list of lottery tickets for different scenarios
    absolute_gap = zeros(length(IPScenarios["code"]))  # the gap of sum tickets to LP solution for each scenario

    fiber_lost = []
    fiber_provisioned = []
    fiber_restorationratio = []

    if scenario_generation_only == 0
        PyPlot.clf()  # plotting lottery tickets
    end

    ## iterating each possible failure scenario in the scenario file, this can be parallelized for each scenario in the scenario file
    for q in 1:length(IPScenarios["code"])
        ## only generate tickets for this given failure scenario
        if scenario_generation_only > 0
            if verbose println("Parallel generating lottery tickets for $(scenario_generation_only) scenario") end
            q = scenario_generation_only
        end
        if verbose println("Generating tickets for fiber cut scenario: ", OpticalScenarios["code"][q]) end

        ## store tickets for the current scenario
        rwa_current_scenario_restored_bw = []
        rwa_lp_current_scenario_restored_bw = []
        rr_current_scenario_restored_bw = []
       
        ## this is a failure scenario
        if sum(IPScenarios["code"][q]) < length(IPScenarios["code"][q])
            ## locate failure scenario on cross-layer topo
            failed_fibers_index = FailureLocator(OpticalTopo, OpticalScenarios["code"][q])
            failed_IPedge, failed_IP_initialindex, failed_IP_initialbw = ReadFailureScenario(IPScenarios["code"][q], IPTopo["links"], IPTopo["capacity"])
            push!(fiber_provisioned, sum(failed_IP_initialbw)/100)
            if verbose println("\nfailed_IPedge: ", failed_IPedge) end
            if verbose println("failed_IP_initialbw (wavelength number): ", sum(failed_IP_initialbw)/100, " ", failed_IP_initialbw./100) end

            ## routing of restored wavelengths
            rehoused_IProutingEdge, rehoused_IProuting, failedIPbranckindex, failedIPbrachGroup = WaveRerouting(OpticalTopo, failed_IPedge, failed_fibers_index, optical_rerouting_K)
            if verbose println("rehoused_IProutingEdge: ", rehoused_IProutingEdge) end
            if verbose println("rehoused_IProuting: ", rehoused_IProuting) end
            if verbose println("failedIPbranckindex: ", failedIPbranckindex) end
            if verbose println("failedIPbrachGroup: ", failedIPbrachGroup) end

            ## wavelength assignment of routed restored wavelengths (ILP)
            rwa_runtime = @timed restored_bw_rwa, obj, IPBranch_bw = RestoreILP(GRB_ENV, OpticalTopo["links"], OpticalTopo["capacityCode"], failed_IPedge, rehoused_IProutingEdge, failedIPbranckindex, failedIPbrachGroup, failed_IP_initialbw, optical_rerouting_K)
            if verbose println("wavelength continuous ILP results: ", sum(restored_bw_rwa), " ", restored_bw_rwa) end
            if verbose println("wavelength continuous ILP IP branch results:", IPBranch_bw) end
            if verbose println("wavelength continuous ILP runtime: ", rwa_runtime[2]) end
            rwa_full_capacity = deepcopy(IPTopo["capacity"])
            for i in 1:length(failed_IP_initialindex)
                rwa_full_capacity[failed_IP_initialindex[i]] = Int(round(restored_bw_rwa[i])) * 100  # each wave 100 Gbps
            end
            rwa_current_scenario_restored_bw = rwa_full_capacity  # network capacity vector of all links after rwa restoration
            push!(rwa_scenario_restored_bw, rwa_current_scenario_restored_bw)
            if verbose println("wavelength continuous ILP full capacity: ", rwa_current_scenario_restored_bw) end
            
            ## wavelength assignment of routed restored wavelengths (relaxed LP)
            lp_runtime = @timed lp_restored_bw, obj, lp_IPBranch_bw = RestoreLP(GRB_ENV, OpticalTopo["links"], OpticalTopo["capacityCode"], failed_IPedge, rehoused_IProutingEdge, failedIPbranckindex, failedIPbrachGroup, failed_IP_initialbw, optical_rerouting_K)
            if verbose println("relaxed LP results: ", sum(lp_restored_bw), " ", lp_restored_bw) end
            if verbose println("relaxed LP IP branch results:", lp_IPBranch_bw) end
            if verbose println("relaxed LP runtime: ", lp_runtime[2]) end
            rwa_lp_full_capacity = deepcopy(IPTopo["capacity"])
            for i in 1:length(failed_IP_initialindex)
                rwa_lp_full_capacity[failed_IP_initialindex[i]] = Int(round(lp_restored_bw[i])) * 100  # each wave 100 Gbps
            end
            rwa_lp_current_scenario_restored_bw = rwa_lp_full_capacity  # network capacity vector of all links after rwa restoration
            push!(rwa_lp_scenario_restored_bw, rwa_lp_current_scenario_restored_bw)
            if verbose println("wavelength continuous LP full capacity: ", rwa_lp_current_scenario_restored_bw) end
            
            ## only load lottery tickets if it is ARROW
            if ticket_or_not == 2  
                ## absolute gap for bounding the ARROW tickets
                absolute_gap[q]= (1-option_gap) * sum(lp_restored_bw) * 100

                ## Randomized rounding
                if verbose printstyled("Now - Running randomized rounding algorithm\n", color=:blue) end
                restored_bw_rr = RandomRounding(GRB_ENV, lp_restored_bw, restored_bw_rwa, failed_IPedge, failed_IP_initialbw, option_num, option_gap, OpticalTopo, rehoused_IProutingEdge, failedIPbranckindex, failedIPbrachGroup, optical_rerouting_K, verbose)
                if verbose println("randomized rounding results: ", restored_bw_rr) end                
                if verbose println("randomized rounding capacities: ") end
                for x in 1:size(restored_bw_rr,1)  # different rr scenarios
                    if verbose println("Ticket $(x) sum restore capacity: ", sum(restored_bw_rr[x,:])) end
                    if verbose println("Ticket $(x) restore capacity: ", restored_bw_rr[x,:]) end

                    ## print and calculate restoration ratios for visualization of non-parallel generation
                    if scenario_generation_only == 0 
                        scenario_restorationratio = []
                        for e in 1:size(restored_bw_rr,2)
                            edge_restore_ratio = restored_bw_rr[x,e] / (failed_IP_initialbw[e]/100)
                            # println("edge_restore_ratio: ", edge_restore_ratio)
                            push!(scenario_restorationratio, edge_restore_ratio)
                        end
                        sorted_edge_restore_ratio = sort(scenario_restorationratio)
                        cdf = []
                        for i in 1:length(sorted_edge_restore_ratio)
                            push!(cdf, i/length(sorted_edge_restore_ratio))
                        end
                        PyPlot.plot(sorted_edge_restore_ratio, cdf, marker="P", alpha = 0.6, linewidth=0.5)
                        if verbose println("Ticket $(x) scenario_restorationratio: ", scenario_restorationratio) end
                    end
                end
                # if it is randomize rounding then there are multiple restored_bw options
                for t in 1:size(restored_bw_rr, 1)
                    rr_full_capacity = deepcopy(IPTopo["capacity"])
                    for i in 1:length(failed_IP_initialindex)
                        rr_full_capacity[failed_IP_initialindex[i]] = Int(round(restored_bw_rr[t,i])) * 100
                    end
                    push!(rr_current_scenario_restored_bw, rr_full_capacity)  # network capacity vector of all links after rr restoration
                end
                push!(rr_scenario_restored_bw, rr_current_scenario_restored_bw)
            end

            # if it not randomize rounding then only one restored_bw options
            if scenario_generation_only == 0
                push!(fiber_lost, (sum(IPTopo["capacity"])-sum(rwa_scenario_restored_bw[q]))/100)
            end

        # this is a non-failure scenario
        else
            if verbose println("Healthy network without failures") end
            rwa_current_scenario_restored_bw = deepcopy(IPTopo["capacity"])
            push!(rwa_scenario_restored_bw, rwa_current_scenario_restored_bw)
            
            rwa_lp_current_scenario_restored_bw = deepcopy(IPTopo["capacity"])
            push!(rwa_lp_scenario_restored_bw, rwa_lp_current_scenario_restored_bw)
                    
            if ticket_or_not == 2  # only load lottery tickets if it is ARROW
                rr_current_scenario_restored_bw_0 = deepcopy(IPTopo["capacity"])
                for i in 1:option_num
                    push!(rr_current_scenario_restored_bw, rr_current_scenario_restored_bw_0)
                end
                push!(rr_scenario_restored_bw, rr_current_scenario_restored_bw)
            end

            absolute_gap[q] = 0
        end
        ProgressMeter.next!(progress0, showvalues = [])

        ## single operation of a parallel ticket generation
        if scenario_generation_only > 0
            break
        end
    end

    ## if not parallel generation, we distill tickets here, otherwise, distill at aggregation function
    if scenario_generation_only == 0
        distill_rr_scenario_restored_bw = distill_tickets(rr_scenario_restored_bw, IPTopo, IPScenarios, verbose)

        ## finising the plotting of randomized rounding tickets
        figname = "$(ticket_dir)/02_restorationratio_IP_rr_topo$(topology_index)_scenario$(scenario_id)_wave$(size(OpticalTopo["capacityCode"],2)).png"
        PyPlot.xlabel("Restoration ratio for IP links")
        PyPlot.ylabel("CDF")
        PyPlot.savefig(figname)
        if verbose
            println("fiber_lost ", fiber_lost)
            println("fiber_provisioned ", fiber_provisioned)
        end
        
        ## plotting restoration ratios (CDF) of RWA
        PyPlot.clf()
        fiber_restorationratio = []
        for t in 1:length(fiber_lost)
            push!(fiber_restorationratio, (fiber_provisioned[t]-fiber_lost[t])/fiber_provisioned[t])
        end
        sorted_fiber_restorationratio = sort(fiber_restorationratio)
        cdf = []
        for i in 1:length(sorted_fiber_restorationratio)
            push!(cdf, i/length(sorted_fiber_restorationratio))
        end
        PyPlot.plot(sorted_fiber_restorationratio, cdf, marker="P", linewidth=1)
        figname = "$(ticket_dir)/02_restorationratio_fiber_rwa_cdf_topo$(topology_index)_scenario$(scenario_id)_wave$(size(OpticalTopo["capacityCode"],2)).png"
        PyPlot.xlabel("Scenario restoration ratio on fibers")
        PyPlot.ylabel("CDF")
        PyPlot.savefig(figname)

        ## plotting restoration ratios (scatter points) of RWA
        PyPlot.clf()
        PyPlot.scatter(fiber_provisioned, fiber_restorationratio, alpha = 0.25)
        figname = "$(ticket_dir)/02_restorationratio_fiber_rwa_scatter_topo$(topology_index)_scenario$(scenario_id)_wave$(size(OpticalTopo["capacityCode"],2)).png"
        PyPlot.xlabel("Scenario's lost wavelengths on fiber")
        PyPlot.ylabel("Restoration ratio")
        PyPlot.savefig(figname)
    else
        distill_rr_scenario_restored_bw = rr_scenario_restored_bw
    end

    ## save the tickets into .jld
    JLD.save(RWAFileName, "rwa_scenario_restored_bw", rwa_scenario_restored_bw)
    open(replace(RWAFileName, ".jld"=>".txt"), "w+") do io
        for q in 1:length(IPScenarios["code"])
            if scenario_generation_only > 0
                q = scenario_generation_only
                writedlm(io, (IPScenarios["code"][q], rwa_scenario_restored_bw[1]))
                break
            else
                writedlm(io, (IPScenarios["code"][q], rwa_scenario_restored_bw[q]))
            end
            
        end
    end

    JLD.save(LPFileName, "rwa_lp_scenario_restored_bw", rwa_lp_scenario_restored_bw)
    open(replace(LPFileName, ".jld"=>".txt"), "w+") do io
        for q in 1:length(IPScenarios["code"])
            if scenario_generation_only > 0
                q = scenario_generation_only
                writedlm(io, (IPScenarios["code"][q], rwa_lp_scenario_restored_bw[1]))
                break
            else
                writedlm(io, (IPScenarios["code"][q], rwa_lp_scenario_restored_bw[q]))
            end
        end
    end
    
    if ticket_or_not == 2  # only handle lottery tickets if it is ARROW
        JLD.save(TicketFileName, "lottery_ticket_restored_bw", distill_rr_scenario_restored_bw)
        open(replace(TicketFileName, ".jld"=>".txt"), "w+") do io
            for q in 1:length(IPScenarios["code"])
                if scenario_generation_only > 0
                    q = scenario_generation_only
                    writedlm(io, (IPScenarios["code"][q], distill_rr_scenario_restored_bw[1]))
                    break
                else
                    writedlm(io, (IPScenarios["code"][q], distill_rr_scenario_restored_bw[q]))
                end
            end
        end
    end

    return rwa_scenario_restored_bw, distill_rr_scenario_restored_bw, absolute_gap
end


## loading existing lottery tickets
function lottery_ticket_loading(RWAFileName, LPFileName, TicketFileName, IPScenarios, option_gap, progress0)
    rwa_scenario_restored_bw = load(RWAFileName, "rwa_scenario_restored_bw")  # load RWA ILP results
    rwa_lp_scenario_restored_bw = load(LPFileName, "rwa_lp_scenario_restored_bw")  # load RWA LP results
    lottery_ticket_restored_bw = load(TicketFileName, "lottery_ticket_restored_bw")  # load existing tickets

    absolute_gap = zeros(length(IPScenarios["code"]))  # the gap of sum tickets to LP solution for each scenario

    ## iterating each possible failure scenario in the scenario file, this can be parallelized for each scenario in the scenario file
    for q in 1:length(IPScenarios["code"])
        lp_restored_bw = rwa_lp_scenario_restored_bw[q]
        absolute_gap[q]= (1-option_gap) * sum(lp_restored_bw) * 100
    end
    ProgressMeter.next!(progress0, showvalues = [])

    return rwa_scenario_restored_bw, lottery_ticket_restored_bw, absolute_gap
end


## get failure scenarios files
function get_failure_scenarios(dir, topology, topology_index, verbose, scenario_cutoff, scenario_id, weibull_or_k, failure_free, expanded_spectrum)
    if scenario_cutoff == 0
        weibull_failure = false  ## no cutoff needed, parse failure distribution from files
    else
        weibull_failure = true  ## apply cutoff to weibull distribution for link failure distribution
    end

    ## Get the network topology
    IPTopo, OpticalTopo = ReadCrossLayerTopo(dir, topology, topology_index, verbose, expanded_spectrum, weibull_failure=weibull_failure, IPfromFile=true, tofile=false)

    ## plotting spectrum utilization
    fiber_capacity = OpticalTopo["capacity"]
    if verbose println("fiber_capacity $(fiber_capacity)") end
    if verbose println("fiber capacity code $(OpticalTopo["capacityCode"])") end
    fiber_utilization = []
    cdf = []
    for x in 1:length(fiber_capacity)
        push!(fiber_utilization, 96+expanded_spectrum-fiber_capacity[x])
        push!(cdf, x/length(fiber_capacity))
    end
    fiber_utilization = sort(fiber_utilization)

    open("$(dir)/$(topology)/00_fiber_spectrum.txt", "w+") do io
        writedlm(io, ("spectrum", fiber_utilization))
        writedlm(io, ("cdf", cdf))
    end

    PyPlot.clf()
    PyPlot.plot(fiber_utilization, cdf, marker="P", alpha = 0.8)
    figname = "$(dir)/$(topology)/00_fiber_spectrum.png"
    PyPlot.xlabel("Occupied wavelength number per fiber")
    PyPlot.ylabel("CDF")
    PyPlot.savefig(figname)

    if failure_free
        ## there is no fiber cut scenarios
        IPScenarios = Dict()
        IPScenarios["code"] = [ones(length(IPTopo["links"]))]
        IPScenarios["prob"] = [1]
        OpticalScenarios = Dict()
        OpticalScenarios["code"] = [ones(length(OpticalTopo["links"]))]
        OpticalScenarios["prob"] = [1]
    else 
        ## get all fiber cut scenarios on this topology, and store them into file
        if verbose println("Computing fiber cut scenarios...cutoff=$(scenario_cutoff)") end
        failureFileName =  "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_ip_scenarios_$(scenario_id).jld"
        if isfile(failureFileName) == false
            if weibull_or_k == 1
                IPScenarios, OpticalScenarios = GetAllScenarios(IPTopo, OpticalTopo, scenario_cutoff, false, 1)
            else
                IPScenarios, OpticalScenarios = GetAllScenarios(IPTopo, OpticalTopo, 0, true, 1)  # all single fiber cut scenario
            end
            JLD.save(failureFileName, "IPScenarios", IPScenarios, "OpticalScenarios", OpticalScenarios)
            open("./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_ip_scenarios_$(scenario_id).txt", "w+") do io
                for i in 1:size(IPScenarios["code"],1)
                    writedlm(io, (IPScenarios["prob"][i], IPScenarios["code"][i]))
                end
            end
        else
            data = load(failureFileName)
            IPScenarios, OpticalScenarios = data["IPScenarios"], data["OpticalScenarios"]
        end
        if verbose println("Scenario number: ", size(IPScenarios["code"],1)) end

        ## plot failure distribution
        failureprobIP = IPScenarios["prob"]
        cdf_IP = []
        for x in 1:length(failureprobIP)
            push!(cdf_IP, x/length(failureprobIP))
        end
        sorted_failureprobIP = sort(failureprobIP)
        PyPlot.clf()
        PyPlot.plot(sorted_failureprobIP, cdf_IP, marker="P", alpha = 0.8, label=topology)
        figname = "$(dir)/$(topology)/01_failure_scenario_prob_$(scenario_id).png"
        PyPlot.xscale("log")
        PyPlot.legend(loc="upper left")
        PyPlot.savefig(figname)
    end

    return IPTopo, OpticalTopo, IPScenarios, OpticalScenarios
end


## abstracting optical layer's restoration candidates considering failure scenarios
function abstract_optical_layer(GRB_ENV, IPTopo, OpticalTopo, IPScenarios, OpticalScenarios, scenario_generation_only, dir, topology, topology_index, verbose, scenario_cutoff, scenario_id, optical_rerouting_K, partial_load_full_tickets, option_num, large_option_num, option_gap, ticket_or_not, expanded_spectrum)
    ## if we read partial tickets
    partial_tickets = large_option_num
    if partial_load_full_tickets
        if option_num < large_option_num
            partial_tickets = deepcopy(option_num)
            option_num = large_option_num
        end
    end
    if ticket_or_not > 0
        ## generate lottery tickets using random rounding based on failure scenarios
        ticket_dir = "$(dir)/$(topology)"
        if scenario_generation_only == 0  # generate tickets for all scenarios in a scenario file
            if expanded_spectrum == 0
                RWAFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_rwa_scenario_restored_$(scenario_id).jld"
                LPFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_lp_bw_scenario_restored_$(scenario_id).jld"
                TicketFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_lotterytickets$(option_num)_$(scenario_id).jld"
            else
                RWAFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_rwa_scenario_restored_$(scenario_id)_extend_$(expanded_spectrum).jld"
                LPFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_lp_bw_scenario_restored_$(scenario_id)_extend_$(expanded_spectrum).jld"
                TicketFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_lotterytickets$(option_num)_$(scenario_id)_extend_$(expanded_spectrum).jld"
            end
        else  # generate tickets for only for expanded_spectrum'th scenarios in a scenario file
            if expanded_spectrum == 0
                RWAFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_rwa_scenario_restored_$(scenario_id)_$(scenario_generation_only).jld"
                LPFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_lp_bw_scenario_restored_$(scenario_id)_$(scenario_generation_only).jld"
                TicketFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_lotterytickets$(option_num)_$(scenario_id)_$(scenario_generation_only).jld"
            else
                RWAFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_rwa_scenario_restored_$(scenario_id)_$(scenario_generation_only)_extend_$(expanded_spectrum).jld"
                LPFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_lp_bw_scenario_restored_$(scenario_id)_$(scenario_generation_only)_extend_$(expanded_spectrum).jld"
                TicketFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_lotterytickets$(option_num)_$(scenario_id)_$(scenario_generation_only)_extend_$(expanded_spectrum).jld"
            end
        end

        ## check the file exists or not to determine generate new or load existing lottery tickets
        RWA_exists = false
        if isfile(RWAFileName)
            RWA_exists = true
        end
        LP_exists = false
        if isfile(LPFileName)
            LP_exists = true
        end
        Ticket_exists = false
        if isfile(TicketFileName)
            Ticket_exists = true
        end

        if RWA_exists && LP_exists && Ticket_exists
            ## load existing lottery tickets
            progress0 = ProgressMeter.Progress(length(IPScenarios["code"]), .1, "Loading $(partial_tickets)/$(option_num) lottery tickets (restoration options) on $(size(OpticalTopo["capacityCode"],2)) wave fiber under failure scenario file-$(scenario_id) from file...\n", 50)
            if scenario_generation_only == 0
                rwa_scenario_restored_bw, full_rr_scenario_restored_bw, absolute_gap = lottery_ticket_loading(RWAFileName, LPFileName, TicketFileName, IPScenarios, option_gap, progress0)
                rr_scenario_restored_bw = []
                for q in 1:length(IPScenarios["code"])
                    push!(rr_scenario_restored_bw, full_rr_scenario_restored_bw[q][1:partial_tickets])
                end
            else
                rwa_scenario_restored_bw = []
                rr_scenario_restored_bw = []
                absolute_gap = []
            end
        else
            ## generate new lottery tickets
            if scenario_generation_only == 0 
                progress0 = ProgressMeter.Progress(length(IPScenarios["code"]), .1, "[Serial] Computing $(option_num) lottery tickets (restoration options) on $(size(OpticalTopo["capacityCode"],2)) wave fiber under failure scenario file-$(scenario_id)...\n", 50)
            else
                progress0 = ProgressMeter.Progress(length(IPScenarios["code"]), .1, "[Parallel] Computing $(option_num) lottery tickets (restoration options) on $(size(OpticalTopo["capacityCode"],2)) wave fiber under failure scenario file-$(scenario_id) & scenario-$(scenario_generation_only)...\n", 50)
            end

            rwa_scenario_restored_bw, rr_scenario_restored_bw, absolute_gap = lottery_ticket_generation(GRB_ENV, ticket_dir, RWAFileName, LPFileName, TicketFileName, IPTopo, IPScenarios, OpticalTopo, OpticalScenarios, scenario_generation_only, optical_rerouting_K, option_num, option_gap, scenario_id, topology_index, verbose, ticket_or_not, progress0)
        end

        # print intermediate results for debug
        if verbose
            for rr in 1:size(rwa_scenario_restored_bw, 1)
                if sum(rwa_scenario_restored_bw[rr]) != sum(rr_scenario_restored_bw[rr][1])
                    println("RWA results: ", sum(rwa_scenario_restored_bw[rr]), " ", rwa_scenario_restored_bw[rr])
                    println("RR results: ", sum(rr_scenario_restored_bw[rr][1]), " ", rr_scenario_restored_bw[rr][1])
                end
            end
        end
    else
        ## This is not ARROW or ARROW-NAIVE, hence no need to solve restoration formulation
        rwa_scenario_restored_bw = []
        rr_scenario_restored_bw = []
        absolute_gap = []
    end
    return rwa_scenario_restored_bw, rr_scenario_restored_bw, absolute_gap
end


## The traffic engineering simulator master function
function simulator(GRB_ENV, dir, AllTopologies, AllTopoIndex, AllTunnelNum, AllAlgorithms, All_demand_upscale, All_demand_downscale, AllTraffic, scenario_cutoff, beta, scales, optical_rerouting_K, partial_load_full_tickets, option_num, large_option_num, option_gap, verbose, parallel_dir, singleplot, scenario_id, tunnel_rounting, failure_simulation, failure_free, expanded_spectrum)
    if verbose println("please find logs files in ", dir) end
    traffic_id = 0
    scale_id = 0

    for t in 1:length(AllTopologies)
        for ii in 1:length(AllTopoIndex)
            DirectThroughput = Dict{String,Array{Float64,2}}()
            SecureThroughput = Dict{String,Array{Float64,2}}()
            Scenario_Availability = Dict{String,Array{Float64,2}}()
            conditional_Scenario_Availability = Dict{String,Array{Float64,2}}()
            Algo_LinksUtilization = Dict{String,Array{Float64,3}}()
            Algo_RouterPorts = Dict{String,Array{Float64,3}}()
            Flow_Availability = Dict{String,Array{Float64,2}}()
            conditional_Flow_Availability = Dict{String,Array{Float64,2}}()
            Bandwidth_Availability = Dict{String,Array{Float64,2}}()
            conditional_Bandwidth_Availability = Dict{String,Array{Float64,2}}()
            Algo_Runtime = Dict{String,Array{Float64,2}}()
            scenario_number=0
            Algo_var = Dict{String,Array{Float64,2}}()
            Algo_accommodate_ratio = Dict{String,Array{Float64,2}}()

            topology = AllTopologies[t]
            topology_index = AllTopoIndex[ii]
            predefine_tunnel_num = AllTunnelNum[t]
            tunnelK = parse(Int64, predefine_tunnel_num)
            demand_upscale = All_demand_upscale[t]
            demand_downscale = All_demand_downscale[t]

            if in("ARROW", AllAlgorithms) || in("ARROW_BIN", AllAlgorithms)
                ticket_or_not = 2  # ARROW algorithms that need multiple tickets
            elseif in("ARROW_NAIVE", AllAlgorithms)
                ticket_or_not = 1  # ARROW NAIVE with only one ticket
            else
                ticket_or_not = 0
            end

            ## abstracting optical layer for TE
            if verbose println("\n - evaluating topology: ", topology, "-", topology_index, " ,upscale: ", demand_upscale, " ,downscale: ", demand_downscale) end
            weibull_or_k = 0  # does not affect because we do not generate tickets here
            scenario_generation_only = 0  # does not affect because here we read all tickets, not generating tickets, but if generate, 0 means non-parallel
            IPTopo, OpticalTopo, IPScenarios, OpticalScenarios = get_failure_scenarios(dir, topology, topology_index, verbose, scenario_cutoff, scenario_id, weibull_or_k, failure_free, expanded_spectrum)
            rwa_scenario_restored_bw, rr_scenario_restored_bw, absolute_gap = abstract_optical_layer(GRB_ENV, IPTopo, OpticalTopo, IPScenarios, OpticalScenarios, scenario_generation_only, dir, topology, topology_index, verbose, scenario_cutoff, scenario_id, optical_rerouting_K, partial_load_full_tickets, option_num, large_option_num, option_gap, ticket_or_not, expanded_spectrum)
            scenario_number = length(IPScenarios["code"])
            
            ## record the TE settings
            open("$(dir)/$(topology)/00_setup.txt", "w+") do io
                writedlm(io, ("AllAlgorithms", AllAlgorithms))
                writedlm(io, ("AllTopoIndex", AllTopoIndex))
                writedlm(io, ("AllTunnelNum", AllTunnelNum))
                writedlm(io, ("All_demand_upscale", All_demand_upscale))
                writedlm(io, ("All_demand_downscale", All_demand_downscale))
                writedlm(io, ("AllTraffic", AllTraffic))
                writedlm(io, ("tunnelK", tunnelK))
                writedlm(io, ("tunnelType", tunnel_rounting))
                writedlm(io, ("scenario_cutoff", scenario_cutoff))
                writedlm(io, ("beta", beta))
                writedlm(io, ("scales", scales))
                writedlm(io, ("target option_num", option_num))
                if ticket_or_not == 2 writedlm(io, ("actual option_num", size(rr_scenario_restored_bw[1],1))) end
                writedlm(io, ("number of scenarios", scenario_number))
                writedlm(io, ("parallel results", parallel_dir))
                writedlm(io, ("scenario_id", scenario_id))
            end

            ## Traffic engineering module
            progress = ProgressMeter.Progress(length(AllAlgorithms)*length(AllTraffic)*length(scales), .1, "Running TE simulations ...\n", 50)
            for algorithm in AllAlgorithms
                if verbose println("\n\n   - evaluating TE algorithm: ", algorithm) end
                DirectThroughput[algorithm] = zeros(length(AllTraffic), length(scales))
                SecureThroughput[algorithm] = zeros(length(AllTraffic), length(scales))
                Scenario_Availability[algorithm] = zeros(length(AllTraffic), length(scales))
                Flow_Availability[algorithm] = zeros(length(AllTraffic), length(scales))
                Bandwidth_Availability[algorithm] = zeros(length(AllTraffic), length(scales))
                conditional_Scenario_Availability[algorithm] = zeros(length(AllTraffic), length(scales))
                conditional_Flow_Availability[algorithm] = zeros(length(AllTraffic), length(scales))
                conditional_Bandwidth_Availability[algorithm] = zeros(length(AllTraffic), length(scales))
                Algo_LinksUtilization[algorithm] = zeros(length(AllTraffic), length(scales), length(IPTopo["links"]))
                Algo_RouterPorts[algorithm] = zeros(length(AllTraffic), length(scales), length(IPTopo["links"]))
                Algo_Runtime[algorithm] = zeros(length(AllTraffic), length(scales))
                Algo_var[algorithm] = zeros(length(AllTraffic), length(scales))
                Algo_accommodate_ratio[algorithm] = zeros(length(AllTraffic), length(scales))

                for traffic_num in 1:length(AllTraffic)
                    # parsing demand from demand matrices
                    initial_demand, initial_flows = readDemand("$(topology)/demand", length(IPTopo["nodes"]), AllTraffic[traffic_num], demand_upscale, demand_downscale, false)  # no rescaled
                    rescaled_demand = initial_demand
                    flows = initial_flows
                    traffic_id = AllTraffic[traffic_num]

                    ## tunnel routing
                    T1, Tf1 = getTunnels(IPTopo, flows, tunnelK, verbose, IPScenarios["code"], edge_disjoint=tunnel_rounting)

                    if tunnel_rounting > 0
                        tunnel_style = "KSP"  # default tunnel
                        if tunnel_rounting == 5
                            tunnel_style = "FailureAwareCapacityAware"
                        elseif tunnel_rounting == 4
                            tunnel_style = "FailureAware"
                        elseif tunnel_rounting == 3
                            tunnel_style = "FiberDisjoint"
                        elseif tunnel_rounting == 2
                            tunnel_style = "IPedgeDisjoint"
                        end

                        ## save tunnel routings
                        if isdir("data/topology/$(topology)/IP_topo_$(topology_index)/tunnels_$(tunnel_style)") == false
                            mkdir("data/topology/$(topology)/IP_topo_$(topology_index)/tunnels_$(tunnel_style)")
                            open("data/topology/$(topology)/IP_topo_$(topology_index)/tunnels_$(tunnel_style)/tunnels_edges.txt", "w+") do io
                                for f in 1:length(flows)
                                    for t in 1:size(Tf1[f],1)
                                        edge_list = [IPTopo["links"][x] for x in T1[Tf1[f][t]]]
                                        line = "Flow: $(flows[f]) and Tunnel: $(edge_list)"
                                        println(io, (line))
                                    end
                                end
                            end
                            open("data/topology/$(topology)/IP_topo_$(topology_index)/tunnels_$(tunnel_style)/tunnels.txt", "w+") do io
                                writedlm(io, ("Flows", flows))
                                writedlm(io, ("All Tunnels", T1))
                                writedlm(io, ("Flow Tunnels", Tf1))
                                writedlm(io, ("IP edges", IPTopo["links"]))
                            end
                            open("data/topology/$(topology)/IP_topo_$(topology_index)/tunnels_$(tunnel_style)/IPedges.txt", "w+") do io
                                for e in 1:length(IPTopo["links"])
                                    println(io, (IPTopo["links"][e]))
                                end
                            end
                        end
                    else
                        printstyled("parse tunnels from file\n", color=:blue)
                        ## read tunnels from files
                        tunnel_file = "data/topology/$(topology)/IP_topo_$(topology_index)/tunnels_ParseExternalTunnel/tunnels.txt"
                        T1, Tf1, flows = parseTunnels(tunnel_file, IPTopo["links"])
                    end

                    if verbose println("T1: ", T1) end
                    if verbose println("Tf1: ", Tf1) end
                    if verbose println("flows: ", flows) end
                    flow_matched_demand = []
                    for d in 1:length(rescaled_demand)
                        flow_index = findfirst(x->x==flows[d], initial_flows)
                        push!(flow_matched_demand, rescaled_demand[flow_index])
                    end

                    if verbose println("rescaled_demand: ", flow_matched_demand) end

                    for s in 1:length(scales)
                        scale_id = scales[s]
                        demand = convert(Array{Float64}, rescaled_demand .* scales[s])
                        demand = convert(Array{Float64}, flow_matched_demand .* scales[s])
                        open("$(dir)/$(topology)/00_setup.txt", "a+") do io
                            writedlm(io, ("demand scale", scale_id))
                            writedlm(io, ("current total demand", sum(demand)))
                        end
                        if verbose
                            println("\nscale: ", scales[s])
                            println("demand: ", demand)
                            println("total demand: ", sum(demand))
                            println("topology: ", topology)
                        end

                        ## Provision the network with current TE
                        if algorithm == "ARROW_NAIVE"
                            scenario_restored_bw = rwa_scenario_restored_bw
                        elseif algorithm == "ARROW" || algorithm == "ARROW_BIN"
                            scenario_restored_bw = rr_scenario_restored_bw
                        else
                            scenario_restored_bw = []
                        end

                        TunnelBw, var, initial_throughput, TEruntime, best_options, best_scenario_resored_bw = 0, 0, 0, 0, 0, 0, 0

                        ## TE optimization with given tunnels
                        solve_or_not = false  # if we solve the optimal super ILP
                        TunnelBw, FlowBw, var, initial_throughput, TEruntime, best_options, best_scenario_resored_bw = TrafficEngineering(GRB_ENV, IPTopo, OpticalTopo, algorithm, IPTopo["links"], IPTopo["capacity"], demand, flows, T1, Tf1, IPScenarios["code"], OpticalScenarios["code"], IPScenarios["prob"], scenario_restored_bw, optical_rerouting_K, tunnelK, beta, absolute_gap, verbose, solve_or_not)
                        drawTunnel(topology, TunnelBw, T1, Tf1, IPTopo["links"], length(IPTopo["nodes"]), dir, algorithm)   # draw tunnel bandwidth graph
                        
                        if verbose
                            println("$(sum(TunnelBw)) - $(length(FlowBw)) - TunnelBw: ", TunnelBw)
                            println("$(sum(FlowBw)) - $(length(FlowBw)) - Flowbw", FlowBw)
                            norm_FlowBw = []
                            for i in 1:length(FlowBw)
                                push!(norm_FlowBw, FlowBw[i]/demand[i])
                            end
                            println("$(sum(norm_FlowBw)) - $(length(norm_FlowBw)) - Flowbw", norm_FlowBw)
                        end

                        ## store results
                        DirectThroughput[algorithm][traffic_num, s] = Float64(initial_throughput/sum(demand))
                        Algo_Runtime[algorithm][traffic_num, s] = Float64(TEruntime)

                        if failure_simulation  # if we run failure simulation after TE optimization
                            ## prepare the restorable capacity (full capacity for all links) for TE failure simulation
                            if algorithm == "ARROW_NAIVE"
                                selected_scenario_restored_bw = scenario_restored_bw
                            elseif algorithm == "ARROW" || algorithm == "ARROW_BIN"
                                selected_scenario_restored_bw = best_scenario_resored_bw  # ARROW selected restoration option (installed on ROADM)
                            else
                                selected_scenario_restored_bw = []
                                for s in 1:size(IPScenarios["code"], 1)
                                    push!(selected_scenario_restored_bw, zeros(Int8, length(IPTopo["links"])))
                                end
                            end

                            ## for debug
                            if verbose
                                for rr in 1:size(rwa_scenario_restored_bw, 1)
                                    if sum(rwa_scenario_restored_bw[rr]) != sum(selected_scenario_restored_bw[rr])
                                        println("initial RWA restoration results: ", sum(rwa_scenario_restored_bw[rr]))
                                        println("after TE restoration results: ", sum(selected_scenario_restored_bw[rr]))
                                    end
                                end
                                println("$(sum(TunnelBw)) - TunnelBw: ", TunnelBw)
                                println("$(sum(FlowBw)) - $(length(FlowBw)) - ", FlowBw)
                            end

                            ## post failure evaluation under different failure scenarios
                            links_utilization = computeLinksUtilization(IPTopo["links"], IPTopo["capacity"], demand, flows, T1, Tf1, tunnelK, TunnelBw)
                            losses, affected_flows, required_RouterPorts = TrafficReAssignment(links_utilization, IPTopo["links"], IPTopo["capacity"], demand, flows, T1, Tf1, tunnelK, TunnelBw, FlowBw, IPScenarios["code"], selected_scenario_restored_bw, algorithm, verbose)
                            
                            ## compute evaluation metrics
                            scenario_availability = ScenarioAvailability(losses, IPScenarios["prob"], 0, false)  # conditional=false
                            flow_availability = FlowAvailability(losses, affected_flows, flows, IPScenarios["prob"], 0, false)  # conditional=false
                            bw_availability = BandwidthAvailability(losses, IPScenarios["prob"], 0, false)   # conditional=false
                            conditional_scenario_availability = ScenarioAvailability(losses, IPScenarios["prob"], 0, true)  # conditional=true
                            conditional_flow_availability = FlowAvailability(losses, affected_flows, flows, IPScenarios["prob"], 0, true)  # conditional=true
                            conditional_bw_availability = BandwidthAvailability(losses, IPScenarios["prob"], 0, true)  # conditional=true
                            
                            ## store results
                            Scenario_Availability[algorithm][traffic_num, s] = Float64(scenario_availability)
                            Flow_Availability[algorithm][traffic_num, s] = Float64(flow_availability)
                            Bandwidth_Availability[algorithm][traffic_num, s] = Float64(bw_availability)
                            conditional_Scenario_Availability[algorithm][traffic_num, s] = Float64(conditional_scenario_availability)
                            conditional_Flow_Availability[algorithm][traffic_num, s] = Float64(conditional_flow_availability)
                            conditional_Bandwidth_Availability[algorithm][traffic_num, s] = Float64(conditional_bw_availability)
                            Algo_LinksUtilization[algorithm][traffic_num, s, :] = Float64.(links_utilization)
                            Algo_RouterPorts[algorithm][traffic_num, s, :] = Float64.(required_RouterPorts)
                            Algo_accommodate_ratio[algorithm][traffic_num, s] = Float64(initial_throughput/sum(demand))

                            allowed = 0
                            var = VAR(losses, IPScenarios["prob"], beta)
                            if var < 1
                                allowed = initial_throughput * (1-var)
                            end
                            Algo_var[algorithm][traffic_num, s] = var
                            SecureThroughput[algorithm][traffic_num, s] = round(allowed/sum(demand), digits=16)

                            if verbose
                                println("var: ", var)
                                println("scenario prob: ", sum(IPScenarios["prob"]), " ", IPScenarios["prob"])
                                println("scenario losses: ", losses)
                                println("scenario affected_flows num: ", affected_flows)
                                println("direct throughput: ", initial_throughput)
                                println("allowed throughput: ", allowed)
                                println("scenario availability: ", scenario_availability)
                                println("flow availability: ", flow_availability)
                                println("bandwidth availability: ", bw_availability)
                                println("initial link bandwidth: $(IPTopo["capacity"]) - ", IPTopo["capacity"])
                                println("links utilization: $(sum(links_utilization)) - ", links_utilization)
                                println("router ports: $(sum(required_RouterPorts)) - ", required_RouterPorts)
                            end
                        end
                        ProgressMeter.next!(progress, showvalues = [])
                    end
                end

                DirectThroughput_Filename = "$(parallel_dir)/$(topology)/jld/$(algorithm)/Direct_Throughput_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id)_$(option_num).jld"
                JLD.save(DirectThroughput_Filename, "DirectThroughput", DirectThroughput)
                Algo_Runtime_Filename = "$(parallel_dir)/$(topology)/jld/$(algorithm)/Algo_Runtime_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id)_$(option_num).jld"
                JLD.save(Algo_Runtime_Filename, "Algo_Runtime", Algo_Runtime)

                if failure_simulation  # if we run failure simulation after TE optimization
                    ## write results to jld files for parallel processing
                    Scenario_Availability_FileName = "$(parallel_dir)/$(topology)/jld/$(algorithm)/Scenario_Availability_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id)_$(option_num).jld"
                    JLD.save(Scenario_Availability_FileName, "Scenario_Availability", Scenario_Availability)
                    Flow_Availability_FileName = "$(parallel_dir)/$(topology)/jld/$(algorithm)/Flow_Availability_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id)_$(option_num).jld"
                    JLD.save(Flow_Availability_FileName, "Flow_Availability", Flow_Availability)
                    Bandwidth_Availability_FileName = "$(parallel_dir)/$(topology)/jld/$(algorithm)/Bandwidth_Availability_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id)_$(option_num).jld"
                    JLD.save(Bandwidth_Availability_FileName, "Bandwidth_Availability", Bandwidth_Availability)

                    conditional_Scenario_Availability_FileName = "$(parallel_dir)/$(topology)/jld/$(algorithm)/conditional_Scenario_Availability_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id)_$(option_num).jld"
                    JLD.save(conditional_Scenario_Availability_FileName, "conditional_Scenario_Availability", conditional_Scenario_Availability)
                    conditional_Flow_Availability_FileName = "$(parallel_dir)/$(topology)/jld/$(algorithm)/conditional_Flow_Availability_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id)_$(option_num).jld"
                    JLD.save(conditional_Flow_Availability_FileName, "conditional_Flow_Availability", conditional_Flow_Availability)
                    conditional_Bandwidth_Availability_FileName = "$(parallel_dir)/$(topology)/jld/$(algorithm)/conditional_Bandwidth_Availability_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id)_$(option_num).jld"
                    JLD.save(conditional_Bandwidth_Availability_FileName, "conditional_Bandwidth_Availability", conditional_Bandwidth_Availability)

                    SecureThroughput_Filename = "$(parallel_dir)/$(topology)/jld/$(algorithm)/Secure_Throughput_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id)_$(option_num).jld"
                    JLD.save(SecureThroughput_Filename, "SecureThroughput", SecureThroughput)

                    Algo_RouterPorts_Filename = "$(parallel_dir)/$(topology)/jld/$(algorithm)/Algo_RouterPorts_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id)_$(option_num).jld"
                    JLD.save(Algo_RouterPorts_Filename, "Algo_RouterPorts", Algo_RouterPorts)
                end
            end

            if singleplot
                if failure_simulation  # if we run failure simulation after TE optimization
                    open("$(dir)/$(topology)/03_availability_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id).txt", "w+") do io
                        writedlm(io, ("ScenarioAvailability",))
                        for alg in AllAlgorithms
                            writedlm(io, (alg, Scenario_Availability[alg]))
                        end
                        writedlm(io, ("FlowAvailability",))
                        for alg in AllAlgorithms
                            writedlm(io, (alg, Flow_Availability[alg]))
                        end
                        writedlm(io, ("Bandwidth_Availability",))
                        for alg in AllAlgorithms
                            writedlm(io, (alg, Bandwidth_Availability[alg]))
                        end
                    end
                    open("$(dir)/$(topology)/04_secure_throughput_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id).txt", "w+") do io
                        writedlm(io, ("Guaranteed Throughput",))
                        for alg in AllAlgorithms
                            writedlm(io, (alg, SecureThroughput[alg]))
                        end
                    end
                    open("$(dir)/$(topology)/06_links_utilization.txt", "w+") do io
                        writedlm(io, ("Algo_LinksUtilization", Algo_LinksUtilization))
                    end
                    # plot scenario availability
                    xname = "Demand scales"
                    yname = "Scenario availability"
                    figname = "$(dir)/$(topology)/03_scenario_availability.png"
                    figname2 = "$(dir)/$(topology)/03_scenario_availability_ribbon.png"
                    line_plot(scales, Scenario_Availability, xname, yname, figname, figname2, AllAlgorithms, false, true, true, false)
                    line_plot(scales, Scenario_Availability, xname, yname, figname, figname2, AllAlgorithms, false, true, false, false)
                    figname_zoom = "$(dir)/$(topology)/03_scenario_availability_zoom.png"
                    figname_zoom2 = "$(dir)/$(topology)/03_scenario_availability_zoom_ribbon.png"
                    line_plot(scales, Scenario_Availability, xname, yname, figname_zoom, figname_zoom2, AllAlgorithms, true, true, true, false)
                    line_plot(scales, Scenario_Availability, xname, yname, figname_zoom, figname_zoom2, AllAlgorithms, true, true, false, false)

                    figname_med = "$(dir)/$(topology)/03_scenario_availability_med.png"
                    figname2_med = "$(dir)/$(topology)/03_scenario_availability_ribbon_med.png"
                    line_plot(scales, Scenario_Availability, xname, yname, figname_med, figname2_med, AllAlgorithms, false, false, false, false)
                    figname_zoom_med = "$(dir)/$(topology)/03_scenario_availability_zoom_med.png"
                    figname_zoom2_med = "$(dir)/$(topology)/03_scenario_availability_zoom_ribbon_med.png"
                    line_plot(scales, Scenario_Availability, xname, yname, figname_zoom_med, figname_zoom2_med, AllAlgorithms, true, false, false, false)

                    ## plot flow level availability
                    xname = "Demand scales"
                    yname = "Flow availability"
                    figname = "$(dir)/$(topology)/03_flow_availability.png"
                    figname2 = "$(dir)/$(topology)/03_flow_availability_ribbon.png"
                    line_plot(scales, Flow_Availability, xname, yname, figname, figname2, AllAlgorithms, false, true, true, false)
                    line_plot(scales, Flow_Availability, xname, yname, figname, figname2, AllAlgorithms, false, true, false, false)
                    figname_zoom = "$(dir)/$(topology)/03_flow_availability_zoom.png"
                    figname_zoom2 = "$(dir)/$(topology)/03_flow_availability_zoom_ribbon.png"
                    line_plot(scales, Flow_Availability, xname, yname, figname_zoom, figname_zoom2, AllAlgorithms, true, true, true, false)
                    line_plot(scales, Flow_Availability, xname, yname, figname_zoom, figname_zoom2, AllAlgorithms, true, true, false, false)

                    figname_med = "$(dir)/$(topology)/03_flow_availability_med.png"
                    figname2_med = "$(dir)/$(topology)/03_flow_availability_ribbon_med.png"
                    line_plot(scales, Flow_Availability, xname, yname, figname_med, figname2_med, AllAlgorithms, false, false, false, false)
                    figname_zoom_med = "$(dir)/$(topology)/03_flow_availability_zoom_med.png"
                    figname_zoom2_med = "$(dir)/$(topology)/03_flow_availability_zoom_ribbon_med.png"
                    line_plot(scales, Flow_Availability, xname, yname, figname_zoom_med, figname_zoom2_med, AllAlgorithms, true, false, false, false)

                    ## plot flow level availability
                    xname = "Demand scales"
                    yname = "Bandwidth availability"
                    figname = "$(dir)/$(topology)/03_bandwidth_availability.png"
                    figname2 = "$(dir)/$(topology)/03_bandwidth_availability_ribbon.png"
                    line_plot(scales, Bandwidth_Availability, xname, yname, figname, figname2, AllAlgorithms, false, true, true, false)
                    line_plot(scales, Bandwidth_Availability, xname, yname, figname, figname2, AllAlgorithms, false, true, false, false)
                    figname_zoom = "$(dir)/$(topology)/03_bandwidth_availability_zoom.png"
                    figname_zoom2 = "$(dir)/$(topology)/03_bandwidth_availability_zoom_ribbon.png"
                    line_plot(scales, Bandwidth_Availability, xname, yname, figname_zoom, figname_zoom2, AllAlgorithms, true, true, true, false)
                    line_plot(scales, Bandwidth_Availability, xname, yname, figname_zoom, figname_zoom2, AllAlgorithms, true, true, false, false)

                    figname_med = "$(dir)/$(topology)/03_bandwidth_availability_med.png"
                    figname2_med = "$(dir)/$(topology)/03_bandwidth_availability_ribbon_med.png"
                    line_plot(scales, Bandwidth_Availability, xname, yname, figname_med, figname2_med, AllAlgorithms, false, false, false, false)
                    figname_zoom_med = "$(dir)/$(topology)/03_bandwidth_availability_zoom_med.png"
                    figname_zoom2_med = "$(dir)/$(topology)/03_bandwidth_availability_zoom_ribbon_med.png"
                    line_plot(scales, Bandwidth_Availability, xname, yname, figname_zoom_med, figname_zoom2_med, AllAlgorithms, true, false, false, false)

                    ## plot network throughput
                    xname = "Demand scales"
                    yname = "Guaranteed throughput under Availability $(beta)"
                    figname = "$(dir)/$(topology)/04_SecureThroughput.png"
                    figname2 = "$(dir)/$(topology)/04_SecureThroughput_ribbon.png"
                    line_plot(scales, SecureThroughput, xname, yname, figname, figname2, AllAlgorithms, false, true, true, false)
                    line_plot(scales, SecureThroughput, xname, yname, figname, figname2, AllAlgorithms, false, true, false, false)

                    figname_med = "$(dir)/$(topology)/04_SecureThroughput_med.png"
                    figname2_med = "$(dir)/$(topology)/04_SecureThroughput_ribbon_med.png"
                    line_plot(scales, SecureThroughput, xname, yname, figname_med, figname2_med, AllAlgorithms, false, false, true, false)
                    line_plot(scales, SecureThroughput, xname, yname, figname_med, figname2_med, AllAlgorithms, false, false, false, false)

                    xname = "Demand scales"
                    yname = "Value at Risk under Availability $(beta)"
                    figname = "$(dir)/$(topology)/04_ValueAtRisk.png"
                    figname2 = "$(dir)/$(topology)/04_ValueAtRisk_ribbon.png"
                    line_plot(scales, Algo_var, xname, yname, figname, figname2, AllAlgorithms, false, true, true, false)
                    line_plot(scales, Algo_var, xname, yname, figname, figname2, AllAlgorithms, false, true, false, false)

                    figname_med = "$(dir)/$(topology)/04_ValueAtRisk_med.png"
                    figname2_med = "$(dir)/$(topology)/04_ValueAtRisk_ribbon_med.png"
                    line_plot(scales, Algo_var, xname, yname, figname_med, figname2_med, AllAlgorithms, false, false, false, false)

                    xname = "Demand scales"
                    yname = "Demand satisfaction ratio"
                    figname = "$(dir)/$(topology)/04_AccomodationRatio.png"
                    figname2 = "$(dir)/$(topology)/04_AccomodationRatio_ribbon.png"
                    line_plot(scales, Algo_accommodate_ratio, xname, yname, figname, figname2, AllAlgorithms, false, true, true, false)
                    line_plot(scales, Algo_accommodate_ratio, xname, yname, figname, figname2, AllAlgorithms, false, true, false, false)

                    figname_med = "$(dir)/$(topology)/04_AccomodationRatio_med.png"
                    figname2_med = "$(dir)/$(topology)/04_AccomodationRatio_ribbon_med.png"
                    line_plot(scales, Algo_accommodate_ratio, xname, yname, figname_med, figname2_med, AllAlgorithms, false, false, false, false)

                    ## plot links utilization: the throughput carried across each link when there are no failures
                    for s in 1:length(scales)
                        PyPlot.clf()
                        nbars = length(AllAlgorithms)
                        sum_routerports = zeros(nbars)
                        for aa in 1:length(AllAlgorithms)
                            algorithm = AllAlgorithms[aa]
                            average_utilization = zeros(length(IPTopo["links"]))
                            average_routerports = zeros(length(IPTopo["links"]))
                            for e in 1:length(IPTopo["links"])
                                for traffic_num in 1:length(AllTraffic)
                                    average_utilization[e] += Algo_LinksUtilization[algorithm][traffic_num, s, e]
                                    average_routerports[e] += Algo_RouterPorts[algorithm][traffic_num, s, e]
                                end
                                average_utilization[e] /= length(AllTraffic)
                                average_routerports[e] /= length(AllTraffic)
                            end
                            sum_routerports[aa] = sum(average_routerports)
                            average_utilization_sorted = sort(average_utilization)
                            n_data = length(average_utilization_sorted)
                            indices = collect(0:1:n_data-1) ./ (n_data-1)
                            PyPlot.plot(average_utilization_sorted, indices)
                        end
                        PyPlot.legend(AllAlgorithms, loc="best")
                        PyPlot.xlabel("Link load (utilization)")
                        PyPlot.ylabel("CDF")
                        figname = "$(dir)/$(topology)/06_links_utilization_cdf_$(scales[s]).png"
                        PyPlot.savefig(figname)

                        PyPlot.clf()
                        nbars = length(AllAlgorithms)
                        sum_routerports = zeros(nbars)
                        for aa in 1:length(AllAlgorithms)
                            algorithm = AllAlgorithms[aa]
                            average_utilization = zeros(length(IPTopo["links"]))
                            average_routerports = zeros(length(IPTopo["links"]))
                            for e in 1:length(IPTopo["links"])
                                for traffic_num in 1:length(AllTraffic)
                                    average_utilization[e] += Algo_LinksUtilization[algorithm][traffic_num, s, e] / IPTopo["capacity"][e]
                                    average_routerports[e] += Algo_RouterPorts[algorithm][traffic_num, s, e]
                                end
                                average_utilization[e] /= length(AllTraffic)
                                average_routerports[e] /= length(AllTraffic)
                            end
                            sum_routerports[aa] = sum(average_routerports)
                            average_utilization_sorted = sort(average_utilization)
                            n_data = length(average_utilization_sorted)
                            indices = collect(0:1:n_data-1) ./ (n_data-1)
                            PyPlot.plot(average_utilization_sorted, indices)
                        end
                        PyPlot.legend(AllAlgorithms, loc="best")
                        PyPlot.xlabel("Link load (utilization)")
                        PyPlot.ylabel("CDF")
                        figname = "$(dir)/$(topology)/06_links_utilization_ratio_cdf_$(scales[s]).png"
                        PyPlot.savefig(figname)

                        PyPlot.clf()
                        barWidth = 1/(nbars + 1)
                        for aa in 1:length(AllAlgorithms)
                            # calculate secure throughput
                            vectorized = reshape(SecureThroughput[AllAlgorithms[aa]][:,:,s], size(SecureThroughput[AllAlgorithms[aa]][:,:,s],1)*size(SecureThroughput[AllAlgorithms[aa]][:,:,s],2))
                            null_position = findall(x->x==-1, vectorized)
                            real_vectorized = deleteat!(vectorized, null_position)
                            throughput_avg = round(sum(real_vectorized)/length(real_vectorized), digits=16)
                            sum_routerports[aa] = sum_routerports[aa] / throughput_avg
                        end
                        max_routerports = maximum(sum_routerports)
                        normalized_sum_routerports = sum_routerports ./ max_routerports
                        for aa in 1:length(AllAlgorithms)
                            if AllAlgorithms[aa] != "ARROW_NAIVE"
                                PyPlot.bar(AllAlgorithms[aa], normalized_sum_routerports[aa], width=barWidth, alpha = 0.8, label=AllAlgorithms[aa])
                            end
                        end
                        subAllAlgorithms = deleteat!(AllAlgorithms, findall(x->x=="ARROW_NAIVE", AllAlgorithms))
                        PyPlot.legend(subAllAlgorithms, loc="best")
                        PyPlot.xlabel("TE algorithms")
                        PyPlot.ylabel("overall subscribed link bandwidth")
                        figname = "$(dir)/$(topology)/06_links_utilization_bar_$(scales[s]).png"
                        PyPlot.savefig(figname)
                    end
                end

                open("$(dir)/$(topology)/04_direct_throughput_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id).txt", "w+") do io
                    writedlm(io, ("Direct Throughput",))
                    for alg in AllAlgorithms
                        writedlm(io, (alg, DirectThroughput[alg]))
                    end
                end

                xname = "Demand scales"
                yname = "Direct throughput"
                figname = "$(dir)/$(topology)/04_DirectThroughput.png"
                figname2 = "$(dir)/$(topology)/04_DirectThroughput_ribbon.png"
                line_plot(scales, DirectThroughput, xname, yname, figname, figname2, AllAlgorithms, false, true, false, false)
                figname_med = "$(dir)/$(topology)/04_DirectThroughput_med.png"
                figname2_med = "$(dir)/$(topology)/04_DirectThroughput_ribbon_med.png"
                line_plot(scales, DirectThroughput, xname, yname, figname_med, figname2_med, AllAlgorithms, false, false, false, false)                
            end

            open("$(dir)/$(topology)/05_runtime.txt", "w+") do io
                writedlm(io, ("Algo_Runtime", Algo_Runtime))
            end            

            ## plot gurobi solver runtime
            PyPlot.clf()
            nbars = length(AllAlgorithms)
            barWidth = 1/(nbars + 1)
            for bar in 1:nbars
                PyPlot.bar(AllAlgorithms[bar], sum(Algo_Runtime[AllAlgorithms[bar]])/(length(scales)*length(AllTraffic)), width=barWidth, alpha = 0.8, label=AllAlgorithms[bar])
            end
            PyPlot.legend(loc="best")
            PyPlot.xticks(rotation=-45)
            PyPlot.xlabel("TE Algorithms")
            PyPlot.ylabel("Gurobi solver runtime (second)")
            figname = "$(dir)/$(topology)/05_solver_runtime.png"
            PyPlot.savefig(figname)

            ## plot the gurobi runtime vs scenario number
            PyPlot.clf()
            for bar in 1:nbars
                PyPlot.scatter(scenario_number, sum(Algo_Runtime[AllAlgorithms[bar]])/(length(scales)*length(AllTraffic)), alpha = 0.25)
            end
            PyPlot.legend(loc="best")
            PyPlot.xticks(rotation=-45)
            PyPlot.xlabel("Number of scenarios")
            PyPlot.ylabel("Gurobi solver runtime (second)")
            figname = "$(dir)/$(topology)/05_scenario_num_runtime.png"
            PyPlot.savefig(figname)
        end
    end
end
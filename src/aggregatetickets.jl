using ArgParse, JLD, Dates


include("./interface.jl")
include("./simulator.jl")


## aggregating parallel generated tickets into a lottery ticket file corresponding to the scenario file
function aggregating_parallel_tickets()
    s = ArgParseSettings(description = "arg parse here for parallel experimentation")
    @add_arg_table! s begin
        "--scenarionum", "-s"  # total number of scenarios in this scenario file
        "--topology", "-t"  # topology name
        "--topoindex", "-i"  # index of IP topology
        "--cutoff", "-c"  # failure scenario cutoff
        "--scenarioID", "-o"  # generate new failure scenarios from weibull
        "--expandspectrum", "-e"  # expand fiber spectrum (e.g. to L band) for tunable restoration ratios
        "--ticketsnum", "-k"  # number of lottery tickets
        "--aggregaterwa", "-a"  # number of lottery tickets
    end
    parsed_args = parse_args(s) # the result is a Dict{String,Any}
    scenario_count = parse(Int64, parsed_args["scenarionum"])
    topology = parsed_args["topology"]
    topology_index = parsed_args["topoindex"]
    scenario_cutoff = parse(Float64, parsed_args["cutoff"])
    scenario_id = parsed_args["scenarioID"]
    expanded_spectrum = parse(Int64, parsed_args["expandspectrum"])
    option_num = parse(Int64, parsed_args["ticketsnum"])
    aggregate_rwa = parse(Bool, parsed_args["aggregaterwa"])

    rwa_scenario_restored_bw = []
    rwa_lp_scenario_restored_bw = []
    lottery_ticket_restored_bw = []

    progress = ProgressMeter.Progress(scenario_count, .1, "Aggregating parallel generated $(option_num) lottery tickets for scenario file $(scenario_id)...\n", 50)
    for single_scenario in 1:scenario_count
        if expanded_spectrum == 0
            RWAFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_rwa_scenario_restored_$(scenario_id)_$(single_scenario).jld"
            LPFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_lp_bw_scenario_restored_$(scenario_id)_$(single_scenario).jld"
            TicketFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_lotterytickets$(option_num)_$(scenario_id)_$(single_scenario).jld"
        else
            RWAFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_rwa_scenario_restored_$(scenario_id)_$(single_scenario)_extend_$(expanded_spectrum).jld"
            LPFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_lp_bw_scenario_restored_$(scenario_id)_$(single_scenario)_extend_$(expanded_spectrum).jld"
            TicketFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_lotterytickets$(option_num)_$(scenario_id)_$(single_scenario)_extend_$(expanded_spectrum).jld"
        end

        ## move the intermediate files (parallel tickets) into a folder
        if !isdir("./data/topology/$(topology)/IP_topo_$(topology_index)/parallel_tickets")
            mkdir("./data/topology/$(topology)/IP_topo_$(topology_index)/parallel_tickets")
        end

        if isfile(RWAFileName) 
            rwa_current_scenario_restored_bw = load(RWAFileName, "rwa_scenario_restored_bw")  # load RWA ILP results
            push!(rwa_scenario_restored_bw, rwa_current_scenario_restored_bw[1])
            if aggregate_rwa
                mvRWAFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/parallel_tickets/$(scenario_cutoff)_rwa_scenario_restored_$(scenario_id)_$(single_scenario).jld"
                mv(RWAFileName, mvRWAFileName)
                mv(replace(RWAFileName, ".jld"=>".txt"), replace(mvRWAFileName, ".jld"=>".txt"))   
            end 
        else
            printstyled("Missing ticket file $(RWAFileName)\n", color=:yellow)
        end
        if isfile(LPFileName)
            rwa_lp_current_scenario_restored_bw = load(LPFileName, "rwa_lp_scenario_restored_bw")  # load RWA LP results
            push!(rwa_lp_scenario_restored_bw, rwa_lp_current_scenario_restored_bw[1])
            if aggregate_rwa
                mvLPFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/parallel_tickets/$(scenario_cutoff)_lp_bw_scenario_restored_$(scenario_id)_$(single_scenario).jld"
                mv(LPFileName, mvLPFileName)
                mv(replace(LPFileName, ".jld"=>".txt"), replace(mvLPFileName, ".jld"=>".txt"))   
            end 
        else
            printstyled("Missing ticket file $(LPFileName)\n", color=:yellow)
        end

        if !aggregate_rwa
            if isfile(TicketFileName)
                lottery_ticket_current_restored_bw = load(TicketFileName, "lottery_ticket_restored_bw")  # load existing tickets
                push!(lottery_ticket_restored_bw, lottery_ticket_current_restored_bw[1])
                mvTicketFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/parallel_tickets/$(scenario_cutoff)_lotterytickets$(option_num)_$(scenario_id)_$(single_scenario).jld"
                mv(TicketFileName, mvTicketFileName)
                mv(replace(TicketFileName, ".jld"=>".txt"), replace(mvTicketFileName, ".jld"=>".txt"))    
            else
                printstyled("Missing ticket file $(TicketFileName)\n", color=:yellow)
            end  
        end

        ## remove the intermediate files (parallel tickets)
        # rm(RWAFileName)
        # rm(replace(RWAFileName, ".jld"=>".txt"))
        # rm(LPFileName)
        # rm(replace(LPFileName, ".jld"=>".txt"))
        # rm(TicketFileName)
        # rm(replace(TicketFileName, ".jld"=>".txt"))

        ProgressMeter.next!(progress, showvalues = [])
    end

    if !aggregate_rwa
        ## get failure scenarios
        dirname = "./data/experiment/exp-$(string(today()))"
        singleplot=false
        dir = nextRun(dirname, singleplot)
        verbose = false
        weibull_or_k = 1
        failure_free = false
        IPTopo, OpticalTopo, IPScenarios, OpticalScenarios = get_failure_scenarios(dir, topology, topology_index, verbose, scenario_cutoff, scenario_id, weibull_or_k, failure_free, expanded_spectrum)

        ## distill parallel generated tickets
        distill_rr_scenario_restored_bw = distill_tickets(lottery_ticket_restored_bw, IPTopo, IPScenarios, verbose)

        ## plotting of randomized rounding tickets
        fiber_lost = []
        fiber_provisioned = []
        for q in 1:length(IPScenarios["code"])
            if sum(IPScenarios["code"][q]) < length(IPScenarios["code"][q]) 
                failed_IPedge, failed_IP_initialindex, failed_IP_initialbw = ReadFailureScenario(IPScenarios["code"][q], IPTopo["links"], IPTopo["capacity"])
                push!(fiber_provisioned, sum(failed_IP_initialbw)/100)
                push!(fiber_lost, (sum(IPTopo["capacity"])-sum(rwa_scenario_restored_bw[q]))/100)
            end
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
        figname = "./data/topology/$(topology)/IP_topo_$(topology_index)/restorationratio_fiber_rwa_cdf_topo$(topology_index)_scenario$(scenario_id)_wave$(size(OpticalTopo["capacityCode"],2)).png"
        PyPlot.xlabel("Scenario restoration ratio on fibers")
        PyPlot.ylabel("CDF")
        PyPlot.savefig(figname)

        ## plotting restoration ratios (scatter points) of RWA
        PyPlot.clf()
        PyPlot.scatter(fiber_provisioned, fiber_restorationratio, alpha = 0.25)
        figname = "./data/topology/$(topology)/IP_topo_$(topology_index)/restorationratio_fiber_rwa_scatter_topo$(topology_index)_scenario$(scenario_id)_wave$(size(OpticalTopo["capacityCode"],2)).png"
        PyPlot.xlabel("Scenario's lost wavelengths on fiber")
        PyPlot.ylabel("Restoration ratio")
        PyPlot.savefig(figname)

        ## save the tickets into .jld
        if expanded_spectrum == 0
            agg_RWAFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_rwa_scenario_restored_$(scenario_id).jld"
            agg_LPFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_lp_bw_scenario_restored_$(scenario_id).jld"
            agg_TicketFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_lotterytickets$(option_num)_$(scenario_id).jld"
        else
            agg_RWAFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_rwa_scenario_restored_$(scenario_id)_extend_$(expanded_spectrum).jld"
            agg_LPFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_lp_bw_scenario_restored_$(scenario_id)_extend_$(expanded_spectrum).jld"
            agg_TicketFileName = "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_lotterytickets$(option_num)_$(scenario_id)_extend_$(expanded_spectrum).jld"
        end

        JLD.save(agg_RWAFileName, "rwa_scenario_restored_bw", rwa_scenario_restored_bw)
        open(replace(agg_RWAFileName, ".jld"=>".txt"), "w+") do io
            for q in 1:scenario_count
                writedlm(io, (IPScenarios["code"][q], rwa_scenario_restored_bw[q]))
            end
        end

        JLD.save(agg_LPFileName, "rwa_lp_scenario_restored_bw", rwa_lp_scenario_restored_bw)
        open(replace(agg_LPFileName, ".jld"=>".txt"), "w+") do io
            for q in 1:scenario_count
                writedlm(io, (IPScenarios["code"][q], rwa_lp_scenario_restored_bw[q]))
            end
        end
        
        JLD.save(agg_TicketFileName, "lottery_ticket_restored_bw", lottery_ticket_restored_bw)
        open(replace(agg_TicketFileName, ".jld"=>".txt"), "w+") do io
            for q in 1:scenario_count
                writedlm(io, (IPScenarios["code"][q], lottery_ticket_restored_bw[q]))
            end
        end
    end
end

aggregating_parallel_tickets()
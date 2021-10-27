using ArgParse, HDF5, JLD

include("./simulator.jl")


function check_missing(missingfile, topology, algorithm, topology_index, scenario_id, traffic_id, scale_id, option_num)
    targetfile = "/home/arrow-data-process/arrow-data/availability/$(topology)/jld/$(algorithm)/Bandwidth_Availability_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id)_$(option_num).jld"
    
    missingfile_list = readdlm(missingfile, header=false)
    println(missingfile_list)

    if in(targetfile, missingfile_list)
        printstyled("running missing file $(targetfile)\n", color=:blue)
        return true
    else
        printstyled("skipping file $(targetfile)\n", color=:blue)
        return false
    end
end


function main()
    s = ArgParseSettings(description = "arg parse here for parallel experimentation")
    @add_arg_table! s begin
        "--traffic"  # traffic ID        
        "--scale", "-s"  # demand scale
        "--topology", "-t"  # topology name
        "--te", "-a"  # TE algorithm
        "--verbose", "-v"  # stdout of not
        "--parallel", "-p"  # parallel file location
        "--downscale", "-d"  # location   
        "--singleplot", "-g"  # have only one folder in regular plot
        "--topoindex", "-i"  # index of IP topology
        "--cutoff", "-c"  # failure scenario cutoff
        "--tunnel", "-n"  # tunnel number per node pair
        "--scenarioID", "-o"  # generate new failure scenarios from weibull
        "--ticketsnum", "-k"  # number of lottery tickets
        "--largeticketsnum", "-j"  # number of lottery tickets in the largest tickets file
        "--abstractoptical", "-b"  # only run abstract optical layer (weibull or K scenarios) or not
        "--teavarbeta", "-x"  # target availability for teavar
        "--tunneltype", "-u"  # TE tunnel type
        "--missing", "-m"  # run for missing file or not
        "--simulation", "-l"  # run failure simulation after TE optimization or not
        "--failurefree", "-f"  # if running fully restorable TE without failure
        "--expandspectrum", "-e"  # expand fiber spectrum (e.g. to L band) for tunable restoration ratios
        "--scenariogeneration", "-r"  # -1 if do not genearte any tickets, 0 if generate tickets for all scenarios, or generate tickets for the r'th scenario
    end
    parsed_args = parse_args(s) # the result is a Dict{String,Any}

    AllTopologies = [parsed_args["topology"]]
    verbose = parse(Bool, parsed_args["verbose"])
    AllTopoIndex = [parsed_args["topoindex"]]
    scenario_cutoff = parse(Float64, parsed_args["cutoff"])
    scenario_id = parsed_args["scenarioID"]
    option_num = parse(Int64, parsed_args["ticketsnum"])
    large_option_num = parse(Int64, parsed_args["largeticketsnum"])
    abstractoptical = parse(Int64, parsed_args["abstractoptical"])
    singleplot = parse(Bool, parsed_args["singleplot"])
    beta = parse(Float64, parsed_args["teavarbeta"])
    tunnel_rounting = parse(Int64, parsed_args["tunneltype"])
    missingmode = parse(Bool, parsed_args["missing"])
    failure_simulation = parse(Bool, parsed_args["simulation"])
    failure_free = parse(Bool, parsed_args["failurefree"])
    expanded_spectrum = parse(Int64, parsed_args["expandspectrum"])
    scenario_generation_only = parse(Int64, parsed_args["scenariogeneration"])

    All_demand_upscale = [1]

    # randomized rounding gap (how much slack variable delta can go beyond naive restoration solution)
    option_gap = 0  # default sum relaxation without randomized rounding
    if AllTopologies[1] == "B4"
        option_gap = 0.95  # the sum relaxation for lottery selection, 0.95 for B4, 0.9 for IBM
    elseif AllTopologies[1] == "IBM"
        option_gap = 0.9  # the sum relaxation for lottery selection, 0.95 for B4, 0.9 for IBM
    end
    
    optical_rerouting_K = 3  # number of surrogate fiber paths for restoration on optical layer
    partial_load_full_tickets = true  # in the ticket scaling evaluation, we only generate a ticket file with large ticket number and partial load to get smaller tickets, otherwise, we need dedicated ticket file for each ticket number
    dirname = "./data/experiment/exp-$(string(today()))"
    dir = nextRun(dirname, singleplot)

    GRB_ENV = Gurobi.Env()

    if abstractoptical > 0
        ## only generating failure scenarios into files
        weibull_or_k = 1  # generate failure scenarios using weibull
        if abstractoptical == 2
            weibull_or_k = 0  # generate failure scenarios considering K simutaneous fiber cut
        end
        
        if option_num > 1
            ticket_or_not = 2  # ARROW, multiple tickets
        elseif option_num == 1
            ticket_or_not = 1  # ARROW-NAIVE, one single ticket
        else
            ticket_or_not = 0  # All other TEs
        end
        
        IPTopo, OpticalTopo, IPScenarios, OpticalScenarios = get_failure_scenarios(dir, AllTopologies[1], AllTopoIndex[1], verbose, scenario_cutoff, scenario_id, weibull_or_k, failure_free, expanded_spectrum)
        if scenario_generation_only >= 0
            ## parallel generating tickets for each scenarios in a scenario file
            abstract_optical_layer(GRB_ENV, IPTopo, OpticalTopo, IPScenarios, OpticalScenarios, scenario_generation_only, dir, AllTopologies[1], AllTopoIndex[1], verbose, scenario_cutoff, scenario_id, optical_rerouting_K, partial_load_full_tickets, option_num, large_option_num, option_gap, ticket_or_not, expanded_spectrum)
            printstyled("Abstracting $(AllTopologies[1]) optical layer with $(scenario_cutoff) cutoff and $(option_num) lottery ticket for scenario file ID $(scenario_id) index $(scenario_generation_only) completed!\n", color=:blue)
        end
    else
        ## run TE optimization and failure simulation based on failure scenarios parsed from files
        AllTraffic = [parse(Int64, parsed_args["traffic"])]
        scales = [parse(Float64, parsed_args["scale"])]
        AllAlgorithms = split(parsed_args["te"], ",")
        parallel_dir = parsed_args["parallel"]
        All_demand_downscale = [parse(Float64, parsed_args["downscale"])]
        AllTunnelNum = [parsed_args["tunnel"]]

        if isfile("$(parallel_dir)/$(AllTopologies[1])/parallel_setup.txt") == false
            mkdir("$(parallel_dir)/$(AllTopologies[1])")
        end

        open("$(parallel_dir)/$(AllTopologies[1])/parallel_setup.txt", "w+") do io
            writedlm(io, ("AllAlgorithms", AllAlgorithms))
            writedlm(io, ("AllTopoIndex", AllTopoIndex))
            writedlm(io, ("AllTunnelNum", AllTunnelNum))
            writedlm(io, ("All_demand_upscale", All_demand_upscale))
            writedlm(io, ("All_demand_downscale", All_demand_downscale))
            writedlm(io, ("AllTraffic", AllTraffic))
            writedlm(io, ("scenario_cutoff", scenario_cutoff))
            writedlm(io, ("beta", beta))
            writedlm(io, ("scales", scales))
            writedlm(io, ("option_num", option_num))
            writedlm(io, ("single experiment results", dir))
            writedlm(io, ("scenario_id", scenario_id))
            writedlm(io, ("tunnel_rounting", tunnel_rounting))
        end

        ## here we assume all single run, no serial otherwise error
        topology = AllTopologies[1]
        algorithm = AllAlgorithms[1]
        topology_index = AllTopoIndex[1]
        scenario_id = scenario_id
        traffic_id = AllTraffic[1]
        scale_id = scales[1]
        option_num = option_num
        missingfile = "./data/topology/$(topology)/IP_topo_$(topology_index)/missing_data_$(algorithm)_availability.txt"

        accumulate_running = 0
        if missingmode
            if check_missing(missingfile, topology, algorithm, topology_index, scenario_id, traffic_id, scale_id, option_num)
                accumulate_running += 1
                println("Running simulation number $(accumulate_running)")
                simulator(GRB_ENV, dir, AllTopologies, AllTopoIndex, AllTunnelNum, AllAlgorithms, All_demand_upscale, All_demand_downscale, AllTraffic, scenario_cutoff, beta, scales, optical_rerouting_K, partial_load_full_tickets, option_num, large_option_num, option_gap, verbose, parallel_dir, singleplot, scenario_id, tunnel_rounting, failure_simulation, failure_free, expanded_spectrum)
                printstyled("Find parallel run results of traffic-$(parsed_args["traffic"]) scale-$(parsed_args["scale"]) this parallel run in $(parallel_dir)\n", color=:blue)
                printstyled("Find single run results of traffic-$(parsed_args["traffic"]) scale-$(parsed_args["scale"]) this parallel run in $(dir)\n", color=:blue)
            else
                printstyled("Skip traffic-$(parsed_args["traffic"]) scale-$(parsed_args["scale"]) this parallel run in $(parallel_dir)\n", color=:green)
            end
        else
            @time simulator(GRB_ENV, dir, AllTopologies, AllTopoIndex, AllTunnelNum, AllAlgorithms, All_demand_upscale, All_demand_downscale, AllTraffic, scenario_cutoff, beta, scales, optical_rerouting_K, partial_load_full_tickets, option_num, large_option_num, option_gap, verbose, parallel_dir, singleplot, scenario_id, tunnel_rounting, failure_simulation, failure_free, expanded_spectrum)
            printstyled("Find parallel run results of traffic-$(parsed_args["traffic"]) scale-$(parsed_args["scale"]) this parallel run in $(parallel_dir)\n", color=:blue)
            printstyled("Find single run results of traffic-$(parsed_args["traffic"]) scale-$(parsed_args["scale"]) this parallel run in $(dir)\n", color=:blue)
        end
    end
end

main()

using ArgParse, JLD

include("./src/simulator.jl")


function parallel_plot()
    s = ArgParseSettings(description = "arg parse here for parallel experimentation")
    @add_arg_table! s begin
        "--location"  # data file location    
        "--topology", "-t"  # topology name
        "--te", "-a"  # TE algorithm
        "--plottype", "-p"  # type of plot needed
        "--option", "-o"  # if availability, option number, otherwise just placeholder
        "--scale", "-s"  # if throughput, scale number, otherwise just placeholder
        "--plotname", "-n"  # the name of plot
        "--inverselog", "-i"  # inverse log for availability
        "--lotteryticketset", "-l"  # set of lottery tickets for optimization runtime plot
    end
    parsed_args = parse_args(s) # the result is a Dict{String,Any}
    # println("Parsed args:")
    # for (key,val) in parsed_args
    #     println("  $key  =>  $(repr(val))")
    # end
    # println(parsed_args)

    dir = parsed_args["location"]
    topology = parsed_args["topology"]
    AllAlgorithms = split(parsed_args["te"], ",")
    plottype = parsed_args["plottype"]
    option_num = parse(Int64, parsed_args["option"])  # for demand scaling
    scale_num = parse(Float64, parsed_args["scale"])  # for ticket scaling
    plotname = parsed_args["plotname"]
    inverse_log = parse(Bool, parsed_args["inverselog"])
    lotteryticket_set = split(parsed_args["lotteryticketset"], ",") 

    ## demand scaling 
    scales = []
    availability_AllTraffic = []
    if topology == "B4"
        scales = collect(1.0:0.5:6.0)
        availability_AllTraffic = collect(1:1:30)
        scenarios = collect(1:1:5)
        topology_indexes = [1]
    elseif topology == "IBM"
        scales = collect(1.0:0.5:7.0)
        availability_AllTraffic = collect(1:1:30)
        scenarios = collect(1:1:3)
        topology_indexes = [1]
    end

    ## ticket number scaling
    tickets = []
    tickets_AllTraffic = []
    if topology == "B4"
        tickets = vcat(collect(1:1:9), collect(10:5:80))
        tickets_AllTraffic = collect(1:1:30)
        tickets_scenarios = collect(1:1:5)
        tickets_topology_indexes = [1]
    elseif topology == "IBM"
        tickets = vcat(collect(1:1:9), collect(10:5:90))
        tickets_AllTraffic = collect(1:1:30)
        tickets_scenarios = collect(1:1:3)
        tickets_topology_indexes = [1]
    end

    ## optimization runtime
    if topology == "B4"
        runtime_tickets = [1,10,40,80,90,120]
        runtime_AllTraffic = collect(1:1:30)
        runtime_scenarios = collect(1:1:5)
        runtime_topology_indexes = [1]
    elseif topology == "IBM"
        runtime_tickets = [1,10,40,80,90,120]
        runtime_AllTraffic = collect(1:1:30)
        runtime_scenarios = collect(1:1:3)
        runtime_topology_indexes = [1]
    end

    Scenario_Availability = Dict{String,Array{Float64,4}}()
    Flow_Availability = Dict{String,Array{Float64,4}}()
    Bandwidth_Availability = Dict{String,Array{Float64,4}}()
    conditional_Scenario_Availability = Dict{String,Array{Float64,4}}()
    conditional_Flow_Availability = Dict{String,Array{Float64,4}}()
    conditional_Bandwidth_Availability = Dict{String,Array{Float64,4}}()
    DirectThroughput = Dict{String,Array{Float64,4}}()
    SecureThroughput = Dict{String,Array{Float64,4}}()

    ticket_DirectThroughput = Dict{String,Array{Float64,4}}()
    ticket_SecureThroughput = Dict{String,Array{Float64,4}}()

    Algo_RouterPorts = Dict{String,Array{Float64,4}}()
    Algo_SolveTime = Dict{String,Array{Float64,4}}()

    progress = ProgressMeter.Progress(length(AllAlgorithms)*length(topology_indexes)*length(scenarios)*length(availability_AllTraffic)*length(scales), .1, "Computing $(plottype)-$(plotname) plotting data...", 50)
    for algorithm in AllAlgorithms
        ## jld data aggregation and processing
        if plottype == "availability"
            Scenario_Availability[algorithm] = zeros(length(topology_indexes), length(scenarios), length(availability_AllTraffic), length(scales))
            Flow_Availability[algorithm] = zeros(length(topology_indexes), length(scenarios), length(availability_AllTraffic), length(scales))
            Bandwidth_Availability[algorithm] = zeros(length(topology_indexes), length(scenarios), length(availability_AllTraffic), length(scales))
            conditional_Scenario_Availability[algorithm] = zeros(length(topology_indexes), length(scenarios), length(availability_AllTraffic), length(scales))
            conditional_Flow_Availability[algorithm] = zeros(length(topology_indexes), length(scenarios), length(availability_AllTraffic), length(scales))
            conditional_Bandwidth_Availability[algorithm] = zeros(length(topology_indexes), length(scenarios), length(availability_AllTraffic), length(scales))
            DirectThroughput[algorithm] = zeros(length(topology_indexes), length(scenarios), length(availability_AllTraffic), length(scales))
            SecureThroughput[algorithm] = zeros(length(topology_indexes), length(scenarios), length(availability_AllTraffic), length(scales))
            
            for tid in 1:length(topology_indexes)
                topology_index = topology_indexes[tid]
                for sid in 1:length(scenarios)
                    scenario_id = scenarios[sid]
                    for t in 1:length(availability_AllTraffic)
                        traffic_id = availability_AllTraffic[t]
                        for s in 1:length(scales)
                            scale_id = scales[s]

                            if plotname == "scenario_availability" || plotname == "all"
                                Scenario_Availability_FileName = "$(dir)/$(topology)/jld/$(algorithm)/Scenario_Availability_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id)_$(option_num).jld"
                                if isfile(Scenario_Availability_FileName) == true
                                    current_Scenario_Availability = load(Scenario_Availability_FileName, "Scenario_Availability")
                                    Scenario_Availability[algorithm][tid, sid, t, s] = current_Scenario_Availability[algorithm][1,1]  # assume parallel for single traffic and single scale
                                else
                                    printstyled("Missing datafile $(Scenario_Availability_FileName)\n", color=:yellow)
                                    Scenario_Availability[algorithm][tid, sid, t, s] = -1
                                end
                            end
                            
                            if plotname == "flow_availability" || plotname == "all"
                                Flow_Availability_FileName = "$(dir)/$(topology)/jld/$(algorithm)/Flow_Availability_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id)_$(option_num).jld"
                                if isfile(Flow_Availability_FileName) == true
                                    current_Flow_Availability = load(Flow_Availability_FileName, "Flow_Availability")
                                    Flow_Availability[algorithm][tid, sid, t, s] = current_Flow_Availability[algorithm][1,1]  # assume parallel for single traffic and single scale
                                else
                                    printstyled("Missing datafile $(Flow_Availability_FileName)\n", color=:yellow)
                                    Flow_Availability[algorithm][tid, sid, t, s] = -1
                                end
                            end

                            if plotname == "bandwidth_availability" || plotname == "all"
                                Bandwidth_Availability_FileName = "$(dir)/$(topology)/jld/$(algorithm)/Bandwidth_Availability_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id)_$(option_num).jld"
                                if isfile(Bandwidth_Availability_FileName) == true
                                    current_Bandwidth_Availability = load(Bandwidth_Availability_FileName, "Bandwidth_Availability")
                                    Bandwidth_Availability[algorithm][tid, sid, t, s] = current_Bandwidth_Availability[algorithm][1,1]  # assume parallel for single traffic and single scale
                                else
                                    printstyled("Missing datafile $(Bandwidth_Availability_FileName)\n", color=:yellow)
                                    Bandwidth_Availability[algorithm][tid, sid, t, s] = -1
                                end
                            end

                            if plotname == "conditional_scenario_availability" || plotname == "all"
                                conditional_Scenario_Availability_FileName = "$(dir)/$(topology)/jld/$(algorithm)/conditional_Scenario_Availability_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id)_$(option_num).jld"
                                if isfile(conditional_Scenario_Availability_FileName) == true
                                    conditional_current_Scenario_Availability = load(conditional_Scenario_Availability_FileName, "conditional_Scenario_Availability")
                                    conditional_Scenario_Availability[algorithm][tid, sid, t, s] = conditional_current_Scenario_Availability[algorithm][1,1]  # assume parallel for single traffic and single scale
                                else
                                    printstyled("Missing datafile $(conditional_Scenario_Availability_FileName)\n", color=:yellow)
                                    conditional_Scenario_Availability[algorithm][tid, sid, t, s] = -1
                                end
                            end
                            
                            if plotname == "conditional_flow_availability" || plotname == "all"
                                conditional_Flow_Availability_FileName = "$(dir)/$(topology)/jld/$(algorithm)/conditional_Flow_Availability_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id)_$(option_num).jld"
                                if isfile(conditional_Flow_Availability_FileName) == true
                                    conditional_current_Flow_Availability = load(conditional_Flow_Availability_FileName, "conditional_Flow_Availability")
                                    conditional_Flow_Availability[algorithm][tid, sid, t, s] = conditional_current_Flow_Availability[algorithm][1,1]  # assume parallel for single traffic and single scale
                                else
                                    printstyled("Missing datafile $(conditional_Flow_Availability_FileName)\n", color=:yellow)
                                    conditional_Flow_Availability[algorithm][tid, sid, t, s] = -1
                                end
                            end
                            
                            if plotname == "conditional_bandwidth_availability" || plotname == "all"
                                conditional_Bandwidth_Availability_FileName = "$(dir)/$(topology)/jld/$(algorithm)/conditional_Bandwidth_Availability_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id)_$(option_num).jld"
                                if isfile(conditional_Bandwidth_Availability_FileName) == true
                                    conditional_current_Bandwidth_Availability = load(conditional_Bandwidth_Availability_FileName, "conditional_Bandwidth_Availability")
                                    conditional_Bandwidth_Availability[algorithm][tid, sid, t, s] = conditional_current_Bandwidth_Availability[algorithm][1,1]  # assume parallel for single traffic and single scale
                                else
                                    printstyled("Missing datafile $(conditional_Bandwidth_Availability_FileName)\n", color=:yellow)
                                    conditional_Bandwidth_Availability[algorithm][tid, sid, t, s] = -1
                                end
                            end
                            
                            if plotname == "direct_throughput" || plotname == "all"
                                DirectThroughput_FileName = "$(dir)/$(topology)/jld/$(algorithm)/Direct_Throughput_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id)_$(option_num).jld"
                                if isfile(DirectThroughput_FileName) == true
                                    current_DirectThroughput = load(DirectThroughput_FileName, "DirectThroughput")
                                    DirectThroughput[algorithm][tid, sid, t, s] = current_DirectThroughput[algorithm][1,1]  # assume parallel for single traffic and single scale
                                else
                                    printstyled("Missing datafile $(DirectThroughput_FileName)\n", color=:yellow)
                                    DirectThroughput[algorithm][tid, sid, t, s] = -1
                                end
                            end

                            if plotname == "secure_throughput" || plotname == "all"
                                SecureThroughput_FileName = "$(dir)/$(topology)/jld/$(algorithm)/Secure_Throughput_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id)_$(option_num).jld"
                                if isfile(SecureThroughput_FileName) == true
                                    current_SecureThroughput = load(SecureThroughput_FileName, "SecureThroughput")
                                    SecureThroughput[algorithm][tid, sid, t, s] = current_SecureThroughput[algorithm][1,1]  # assume parallel for single traffic and single scale
                                else
                                    printstyled("Missing datafile $(SecureThroughput_FileName)\n", color=:yellow)
                                    SecureThroughput[algorithm][tid, sid, t, s] = -1
                                end
                            end

                            ProgressMeter.next!(progress, showvalues = [])
                        end
                    end
                end
            end
        end
        
        if plottype == "throughput" 
            ticket_DirectThroughput[algorithm] = zeros(length(tickets_topology_indexes), length(tickets_scenarios), length(tickets_AllTraffic), length(tickets))
            ticket_SecureThroughput[algorithm] = zeros(length(tickets_topology_indexes), length(tickets_scenarios), length(tickets_AllTraffic), length(tickets))
            if algorithm == "ARROW" || algorithm == "ARROW_BIN"
                for tid in 1:length(tickets_topology_indexes)
                    topology_index = tickets_topology_indexes[tid]
                    for sid in 1:length(tickets_scenarios)
                        scenario_id = tickets_scenarios[sid]
                        for t in 1:length(tickets_AllTraffic)
                            traffic_id = tickets_AllTraffic[t]
                            for k in 1:length(tickets)
                                ticket_id = tickets[k]
                                ticket_DirectThroughput_FileName = "$(dir)/$(topology)/jld/$(algorithm)/Direct_Throughput_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_num)_$(ticket_id).jld"
                                if isfile(ticket_DirectThroughput_FileName) == true
                                    ticket_current_DirectThroughput = load(ticket_DirectThroughput_FileName, "DirectThroughput")
                                    ticket_DirectThroughput[algorithm][tid, sid, t, k] = ticket_current_DirectThroughput[algorithm][1,1]  # assume parallel for single traffic and single ticket num
                                else
                                    printstyled("Missing datafile $(ticket_DirectThroughput_FileName)\n", color=:yellow)
                                    ticket_DirectThroughput[algorithm][tid, sid, t, k] = -1
                                end

                                ticket_SecureThroughput_FileName = "$(dir)/$(topology)/jld/$(algorithm)/Secure_Throughput_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_num)_$(ticket_id).jld"
                                if isfile(ticket_SecureThroughput_FileName) == true
                                    ticket_current_SecureThroughput = load(ticket_SecureThroughput_FileName, "SecureThroughput")
                                    ticket_SecureThroughput[algorithm][tid, sid, t, k] = ticket_current_SecureThroughput[algorithm][1,1]  # assume parallel for single traffic and single ticket num
                                else
                                    printstyled("Missing datafile $(ticket_SecureThroughput_FileName)\n", color=:yellow)
                                    ticket_SecureThroughput[algorithm][tid, sid, t, k] = -1
                                end
                                ProgressMeter.next!(progress, showvalues = [])
                            end
                        end
                    end
                end
            else  # FFC,TEAVAR,ARROW_NAIVE
                for tid in 1:length(tickets_topology_indexes)
                    topology_index = tickets_topology_indexes[tid]
                    for sid in 1:length(tickets_scenarios)
                        scenario_id = tickets_scenarios[sid]
                        for t in 1:length(tickets_AllTraffic)
                            traffic_id = tickets_AllTraffic[t]
                            for k in 1:length(tickets)
                                ticket_id = 1
                                ticket_DirectThroughput_FileName = "$(dir)/$(topology)/jld/$(algorithm)/Direct_Throughput_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_num)_$(ticket_id).jld"
                                if isfile(ticket_DirectThroughput_FileName) == true
                                    ticket_current_DirectThroughput = load(ticket_DirectThroughput_FileName, "DirectThroughput")
                                    ticket_DirectThroughput[algorithm][tid, sid, t, k] = ticket_current_DirectThroughput[algorithm][1,1]  # assume parallel for single traffic and single ticket num
                                else
                                    printstyled("Missing datafile $(ticket_DirectThroughput_FileName)\n", color=:yellow)
                                    ticket_DirectThroughput[algorithm][tid, sid, t, k] = -1
                                end

                                ticket_SecureThroughput_FileName = "$(dir)/$(topology)/jld/$(algorithm)/Secure_Throughput_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_num)_$(ticket_id).jld"
                                if isfile(ticket_SecureThroughput_FileName) == true
                                    ticket_current_SecureThroughput = load(ticket_SecureThroughput_FileName, "SecureThroughput")
                                    ticket_SecureThroughput[algorithm][tid, sid, t, k] = ticket_current_SecureThroughput[algorithm][1,1]  # assume parallel for single traffic and single ticket num
                                else
                                    printstyled("Missing datafile $(ticket_SecureThroughput_FileName)\n", color=:yellow)
                                    ticket_SecureThroughput[algorithm][tid, sid, t, k] = -1
                                end
                                ProgressMeter.next!(progress, showvalues = [])
                            end
                        end
                    end
                end
            end
        end

        if plottype == "routerports" 
            Algo_RouterPorts[algorithm] = zeros(length(topology_indexes), length(scenarios), length(availability_AllTraffic), length(scales))
            SecureThroughput[algorithm] = zeros(length(topology_indexes), length(scenarios), length(availability_AllTraffic), length(scales))

            for tid in 1:length(topology_indexes)
                topology_index = topology_indexes[tid]
                for sid in 1:length(scenarios)
                    scenario_id = scenarios[sid]
                    for t in 1:length(availability_AllTraffic)
                        traffic_id = availability_AllTraffic[t]
                        for s in 1:length(scales)
                            scale_id = scales[s]
                            Algo_RouterPorts_Filename = "$(dir)/$(topology)/jld/$(algorithm)/Algo_RouterPorts_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id)_$(option_num).jld"
                            if isfile(Algo_RouterPorts_Filename) == true
                                current_Algo_RouterPorts = load(Algo_RouterPorts_Filename, "Algo_RouterPorts")
                                Algo_RouterPorts[algorithm][tid, sid, t, s] = sum(current_Algo_RouterPorts[algorithm][1,1,:])  # assume parallel for single traffic and single scale
                                # println(Algo_RouterPorts[algorithm][tid, sid, t, s])
                            else
                                printstyled("Missing datafile $(Algo_RouterPorts_Filename)\n", color=:yellow)
                                Algo_RouterPorts[algorithm][tid, sid, t, s] = -1
                                # println(Algo_RouterPorts[algorithm][tid, sid, t, s])
                            end

                            SecureThroughput_FileName = "$(dir)/$(topology)/jld/$(algorithm)/Secure_Throughput_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_id)_$(option_num).jld"
                            if isfile(SecureThroughput_FileName) == true
                                current_SecureThroughput = load(SecureThroughput_FileName, "SecureThroughput")
                                SecureThroughput[algorithm][tid, sid, t, s] = current_SecureThroughput[algorithm][1,1]  # assume parallel for single traffic and single scale
                            else
                                printstyled("Missing datafile $(SecureThroughput_FileName)\n", color=:yellow)
                                SecureThroughput[algorithm][tid, sid, t, s] = -1
                            end
                            ProgressMeter.next!(progress, showvalues = [])
                        end
                    end
                end
            end
        end

        if plottype == "optimizationtime" 
            Algo_SolveTime[algorithm] = zeros(length(topology_indexes), length(scenarios), length(availability_AllTraffic), length(scales))

            for tid in 1:length(runtime_topology_indexes)
                topology_index = runtime_topology_indexes[tid]
                for sid in 1:length(runtime_scenarios)
                    scenario_id = runtime_scenarios[sid]
                    for t in 1:length(runtime_AllTraffic)
                        traffic_id = runtime_AllTraffic[t]
                        for k in 1:length(runtime_tickets)
                            runtime_option_num = runtime_tickets[k]
                            Algo_Runtime_Filename = "$(dir)/$(topology)/jld/$(algorithm)/Algo_Runtime_$(topology_index)_$(scenario_id)_$(traffic_id)_$(scale_num)_$(runtime_option_num).jld"
                            if isfile(Algo_Runtime_Filename) == true
                                current_Algo_SolveTime = load(Algo_Runtime_Filename, "Algo_Runtime")
                                Algo_SolveTime[algorithm][tid, sid, t, k] = current_Algo_SolveTime[algorithm][1,1]  # assume parallel for single traffic and single scale
                            else
                                printstyled("Missing datafile $(Algo_Runtime_Filename)\n", color=:yellow)
                                Algo_SolveTime[algorithm][tid, sid, t, k] = -1
                            end
                        end
                    end
                end
            end
        end
    end

    ## plotting
    if plottype == "availability"
        if plotname == "scenario_availability" || plotname == "all"
            println("plotting $(plotname)")
            xname = "Demand scales"
            yname = "Scenario availability"
            figname = "$(dir)/$(topology)/scenario_availability.png"
            figname2 = "$(dir)/$(topology)/scenario_availability_ribbon.png"
            line_plot(scales, Scenario_Availability, xname, yname, figname, figname2, AllAlgorithms, false, true, inverse_log, false)
            figname_zoom = "$(dir)/$(topology)/scenario_availability_zoom.png"
            figname_zoom2 = "$(dir)/$(topology)/scenario_availability_zoom_ribbon.png"
            line_plot(scales, Scenario_Availability, xname, yname, figname_zoom, figname_zoom2, AllAlgorithms, true, true, inverse_log, false)
            figname_med = "$(dir)/$(topology)/scenario_availability_med.png"
            figname2_med = "$(dir)/$(topology)/scenario_availability_ribbon_med.png"
            line_plot(scales, Scenario_Availability, xname, yname, figname_med, figname2_med, AllAlgorithms, false, false, inverse_log, false)
            figname_zoom_med = "$(dir)/$(topology)/scenario_availability_zoom_med.png"
            figname_zoom2_med = "$(dir)/$(topology)/scenario_availability_zoom_ribbon_med.png"
            line_plot(scales, Scenario_Availability, xname, yname, figname_zoom_med, figname_zoom2_med, AllAlgorithms, true, false, inverse_log, false)
        end
        
        if plotname == "flow_availability" || plotname == "all"
            println("plotting $(plotname)")
            xname = "Demand scales"
            yname = "Flow availability"
            figname = "$(dir)/$(topology)/flow_availability.png"
            figname2 = "$(dir)/$(topology)/flow_availability_ribbon.png"
            line_plot(scales, Flow_Availability, xname, yname, figname, figname2, AllAlgorithms, false, true, inverse_log, false)
            figname_zoom = "$(dir)/$(topology)/flow_availability_zoom.png"
            figname_zoom2 = "$(dir)/$(topology)/flow_availability_zoom_ribbon.png"
            line_plot(scales, Flow_Availability, xname, yname, figname_zoom, figname_zoom2, AllAlgorithms, true, true, inverse_log, false)
            figname_med = "$(dir)/$(topology)/flow_availability_med.png"
            figname2_med = "$(dir)/$(topology)/flow_availability_ribbon_med.png"
            line_plot(scales, Flow_Availability, xname, yname, figname_med, figname2_med, AllAlgorithms, false, false, inverse_log, false)
            figname_zoom_med = "$(dir)/$(topology)/flow_availability_zoom_med.png"
            figname_zoom2_med = "$(dir)/$(topology)/flow_availability_zoom_ribbon_med.png"
            line_plot(scales, Flow_Availability, xname, yname, figname_zoom_med, figname_zoom2_med, AllAlgorithms, true, false, inverse_log, false)
        end
        
        if plotname == "bandwidth_availability" || plotname == "all"
            println("plotting $(plotname)")
            xname = "Demand scales"
            yname = "Bandwidth availability"
            figname = "$(dir)/$(topology)/bandwidth_availability.png"
            figname2 = "$(dir)/$(topology)/bandwidth_availability_ribbon.png"
            line_plot(scales, Bandwidth_Availability, xname, yname, figname, figname2, AllAlgorithms, false, true, inverse_log, false)
            figname_zoom = "$(dir)/$(topology)/bandwidth_availability_zoom.png"
            figname_zoom2 = "$(dir)/$(topology)/bandwidth_availability_zoom_ribbon.png"
            line_plot(scales, Bandwidth_Availability, xname, yname, figname_zoom, figname_zoom2, AllAlgorithms, true, true, inverse_log, false)
            figname_med = "$(dir)/$(topology)/bandwidth_availability_med.png"
            figname2_med = "$(dir)/$(topology)/bandwidth_availability_ribbon_med.png"
            line_plot(scales, Bandwidth_Availability, xname, yname, figname_med, figname2_med, AllAlgorithms, false, false, inverse_log, false)
            figname_zoom_med = "$(dir)/$(topology)/bandwidth_availability_zoom_med.png"
            figname_zoom2_med = "$(dir)/$(topology)/bandwidth_availability_zoom_ribbon_med.png"
            line_plot(scales, Bandwidth_Availability, xname, yname, figname_zoom_med, figname_zoom2_med, AllAlgorithms, true, false, inverse_log, false)
        end
        
        if plotname == "conditional_scenario_availability" || plotname == "all"
            println("plotting $(plotname)")
            xname = "Demand scales"
            yname = "conditional_Scenario availability"
            figname = "$(dir)/$(topology)/conditional_scenario_availability.png"
            figname2 = "$(dir)/$(topology)/conditional_scenario_availability_ribbon.png"
            line_plot(scales, conditional_Scenario_Availability, xname, yname, figname, figname2, AllAlgorithms, false, true, inverse_log, false)
            figname_zoom = "$(dir)/$(topology)/conditional_scenario_availability_zoom.png"
            figname_zoom2 = "$(dir)/$(topology)/conditional_scenario_availability_zoom_ribbon.png"
            line_plot(scales, conditional_Scenario_Availability, xname, yname, figname_zoom, figname_zoom2, AllAlgorithms, true, true, inverse_log, false)
            figname_med = "$(dir)/$(topology)/conditional_scenario_availability_med.png"
            figname2_med = "$(dir)/$(topology)/conditional_scenario_availability_ribbon_med.png"
            line_plot(scales, conditional_Scenario_Availability, xname, yname, figname_med, figname2_med, AllAlgorithms, false, false, inverse_log, false)
            figname_zoom_med = "$(dir)/$(topology)/conditional_scenario_availability_zoom_med.png"
            figname_zoom2_med = "$(dir)/$(topology)/conditional_scenario_availability_zoom_ribbon_med.png"
            line_plot(scales, conditional_Scenario_Availability, xname, yname, figname_zoom_med, figname_zoom2_med, AllAlgorithms, true, false, inverse_log, false)
        end
        
        if plotname == "conditional_flow_availability" || plotname == "all"
            println("plotting $(plotname)")
            xname = "Demand scales"
            yname = "conditional_Flow availability"
            figname = "$(dir)/$(topology)/conditional_flow_availability.png"
            figname2 = "$(dir)/$(topology)/conditional_flow_availability_ribbon.png"
            line_plot(scales, conditional_Flow_Availability, xname, yname, figname, figname2, AllAlgorithms, false, true, inverse_log, false)
            figname_zoom = "$(dir)/$(topology)/conditional_flow_availability_zoom.png"
            figname_zoom2 = "$(dir)/$(topology)/conditional_flow_availability_zoom_ribbon.png"
            line_plot(scales, conditional_Flow_Availability, xname, yname, figname_zoom, figname_zoom2, AllAlgorithms, true, true, inverse_log, false)
            figname_med = "$(dir)/$(topology)/conditional_flow_availability_med.png"
            figname2_med = "$(dir)/$(topology)/conditional_flow_availability_ribbon_med.png"
            line_plot(scales, conditional_Flow_Availability, xname, yname, figname_med, figname2_med, AllAlgorithms, false, false, inverse_log, false)
            figname_zoom_med = "$(dir)/$(topology)/conditional_flow_availability_zoom_med.png"
            figname_zoom2_med = "$(dir)/$(topology)/conditional_flow_availability_zoom_ribbon_med.png"
            line_plot(scales, conditional_Flow_Availability, xname, yname, figname_zoom_med, figname_zoom2_med, AllAlgorithms, true, false, inverse_log, false)
        end

        if plotname == "conditional_bandwidth_availability" || plotname == "all"
            println("plotting $(plotname)")
            xname = "Demand scales"
            yname = "conditional Bandwidth availability"
            figname = "$(dir)/$(topology)/conditional_bandwidth_availability.png"
            figname2 = "$(dir)/$(topology)/conditional_bandwidth_availability_ribbon.png"
            line_plot(scales, conditional_Bandwidth_Availability, xname, yname, figname, figname2, AllAlgorithms, false, true, inverse_log, false)
            figname_zoom = "$(dir)/$(topology)/conditional_bandwidth_availability_zoom.png"
            figname_zoom2 = "$(dir)/$(topology)/conditional_bandwidth_availability_zoom_ribbon.png"
            line_plot(scales, conditional_Bandwidth_Availability, xname, yname, figname_zoom, figname_zoom2, AllAlgorithms, true, true, inverse_log, false)
            figname_med = "$(dir)/$(topology)/conditional_bandwidth_availability_med.png"
            figname2_med = "$(dir)/$(topology)/conditional_bandwidth_availability_ribbon_med.png"
            line_plot(scales, conditional_Bandwidth_Availability, xname, yname, figname_med, figname2_med, AllAlgorithms, false, false, inverse_log, false)
            figname_zoom_med = "$(dir)/$(topology)/conditional_bandwidth_availability_zoom_med.png"
            figname_zoom2_med = "$(dir)/$(topology)/conditional_bandwidth_availability_zoom_ribbon_med.png"
            line_plot(scales, conditional_Bandwidth_Availability, xname, yname, figname_zoom_med, figname_zoom2_med, AllAlgorithms, true, false, inverse_log, false)
        end

        if plotname == "direct_throughput" || plotname == "all"
            println("plotting $(plotname)")
            xname = "Demand scales"
            yname = "Direct throughput"
            figname = "$(dir)/$(topology)/DirectThroughput.png"
            figname2 = "$(dir)/$(topology)/DirectThroughput_ribbon.png"
            line_plot(scales, DirectThroughput, xname, yname, figname, figname2, AllAlgorithms, false, true, false, true)
            figname_med = "$(dir)/$(topology)/DirectThroughput_med.png"
            figname2_med = "$(dir)/$(topology)/DirectThroughput_ribbon_med.png"
            line_plot(scales, DirectThroughput, xname, yname, figname_med, figname2_med, AllAlgorithms, false, false, false, true)
        end

        if plotname == "secure_throughput" || plotname == "all"
            println("plotting $(plotname)")
            xname = "Demand scales"
            yname = "Guaranteed throughput under Availability"
            figname = "$(dir)/$(topology)/SecureThroughput.png"
            figname2 = "$(dir)/$(topology)/SecureThroughput_ribbon.png"
            line_plot(scales, SecureThroughput, xname, yname, figname, figname2, AllAlgorithms, false, true, false, true)
            figname_med = "$(dir)/$(topology)/SecureThroughput_med.png"
            figname2_med = "$(dir)/$(topology)/SecureThroughput_ribbon_med.png"
            line_plot(scales, SecureThroughput, xname, yname, figname_med, figname2_med, AllAlgorithms, false, false, false, true)
        end

        open("$(dir)/$(topology)/Availability.txt", "w+") do io
            writedlm(io, ("ScenarioAvailability",))
            for alg in AllAlgorithms
                writedlm(io, (alg, Scenario_Availability[alg]))
            end
            writedlm(io, ("FlowAvailability",))
            for alg in AllAlgorithms
                writedlm(io, (alg, Flow_Availability[alg]))
            end
            writedlm(io, ("BandwidthAvailability",))
            for alg in AllAlgorithms
                writedlm(io, (alg, Bandwidth_Availability[alg]))
            end
        end

        if plotname == "direct_throughput" || plotname == "secure_throughput" || plotname == "all"
            open("$(dir)/$(topology)/Throughput.txt", "w+") do io
                writedlm(io, ("Guaranteed Throughput",))
                for alg in AllAlgorithms
                    writedlm(io, (alg, SecureThroughput[alg]))
                end
                writedlm(io, ("Direct Throughput",))
                for alg in AllAlgorithms
                    writedlm(io, (alg, DirectThroughput[alg]))
                end
            end
        end
    end

    if plottype == "throughput"
        xname = "Number of Lottery Tickets"
        yname = "Guaranteed throughput under Availability"
        figname = "$(dir)/$(topology)/SecureThroughput.png"
        figname2 = "$(dir)/$(topology)/SecureThroughput_ribbon.png"
        line_plot(tickets, ticket_SecureThroughput, xname, yname, figname, figname2, AllAlgorithms, false, true, false, true)
        figname_med = "$(dir)/$(topology)/SecureThroughput_med.png"
        figname2_med = "$(dir)/$(topology)/SecureThroughput_ribbon_med.png"
        line_plot(tickets, ticket_SecureThroughput, xname, yname, figname_med, figname2_med, AllAlgorithms, false, false, false, true)
        
        xname = "Number of Lottery Tickets"
        yname = "Direct throughput"
        figname = "$(dir)/$(topology)/DirectThroughput.png"
        figname2 = "$(dir)/$(topology)/DirectThroughput_ribbon.png"
        line_plot(tickets, ticket_DirectThroughput, xname, yname, figname, figname2, AllAlgorithms, false, true, false, true)
        figname_med = "$(dir)/$(topology)/DirectThroughput_med.png"
        figname2_med = "$(dir)/$(topology)/DirectThroughput_ribbon_med.png"
        line_plot(tickets, ticket_DirectThroughput, xname, yname, figname_med, figname2_med, AllAlgorithms, false, false, false, true)
        
        open("$(dir)/$(topology)/Throughput.txt", "w+") do io
            writedlm(io, ("Guaranteed Throughput",))
            for alg in AllAlgorithms
                writedlm(io, (alg, ticket_SecureThroughput[alg]))
            end
            writedlm(io, ("Direct Throughput",))
            for alg in AllAlgorithms
                writedlm(io, (alg, ticket_DirectThroughput[alg]))
            end
        end
    end

    if plottype == "routerports" 
        colormap = Dict(
            "HYPERTHETICAL" => "black",
            "ARROW" => "red",
            "ARROW_NAIVE" => "blue", 
            "ARROW_BIN" => "red", 
            "FFC1" => "green", 
            "FFC2" => "yellow", 
            "TEAVAR" => "purple",
            "ECMP" => "orange",
        )
        all_sum_routerports = zeros(length(AllAlgorithms))
        nbars = length(AllAlgorithms)
        barWidth = 1/(nbars + 1)
        open("$(dir)/$(topology)/routerports.txt", "w+") do io
            writedlm(io, ("Router Ports",))
            for s in 1:length(scales)
                scale_id = scales[s]
                average_routerports = zeros(length(AllAlgorithms))
                for aa in 1:length(AllAlgorithms)
                    algorithm = AllAlgorithms[aa]
                    vectorized = reshape(Algo_RouterPorts[algorithm][:,:,:,s], size(Algo_RouterPorts[algorithm][:,:,:,s],1)*size(Algo_RouterPorts[algorithm][:,:,:,s],2)*size(Algo_RouterPorts[algorithm][:,:,:,s],3))
                    null_position = findall(x->x==-1, vectorized)
                    vectorized = deleteat!(vectorized, null_position)
                    nan_position = findall(x->isnan(x), vectorized)
                    real_vectorized = deleteat!(vectorized, nan_position)
                    average_routerports[aa] = sum(real_vectorized)
                end
                average_routerports /= length(availability_AllTraffic)*length(scenarios)
    
                PyPlot.clf()
                sum_routerports = zeros(length(AllAlgorithms))
                for aa in 1:length(AllAlgorithms)
                    # calculate secure throughput
                    vectorized = reshape(SecureThroughput[AllAlgorithms[aa]][:,:,:,s], size(SecureThroughput[AllAlgorithms[aa]][:,:,:,s],1)*size(SecureThroughput[AllAlgorithms[aa]][:,:,:,s],2)*size(SecureThroughput[AllAlgorithms[aa]][:,:,:,s],3))
                    null_position = findall(x->x==-1, vectorized)
                    vectorized = deleteat!(vectorized, null_position)
                    nan_position = findall(x->isnan(x), vectorized)
                    real_vectorized = deleteat!(vectorized, nan_position)
                    throughput_avg = round(sum(real_vectorized)/length(real_vectorized), digits=4)
                    if throughput_avg == 0 || isnan(average_routerports[aa]) || isnan(throughput_avg)
                        sum_routerports[aa] = 0
                    else
                        # println("average_routerports[aa] ", average_routerports[aa], " throughput_avg ", throughput_avg)
                        sum_routerports[aa] = average_routerports[aa] / throughput_avg
                    end
                    all_sum_routerports[aa] += sum_routerports[aa]
                    writedlm(io, (scale_id, AllAlgorithms[aa], average_routerports[aa], throughput_avg, sum_routerports[aa]))
                end
                ## Normalized with respect to max router ports
                # max_routerports = maximum(sum_routerports)
                # normalized_sum_routerports = sum_routerports ./ max_routerports

                ## Normalized with respect to hyperthetical TE
                hyperthetical_routerports = sum_routerports[1]  # fix the first one to be hyperthetical
                normalized_sum_routerports = sum_routerports ./ hyperthetical_routerports

                # println("normalized_sum_routerports ", normalized_sum_routerports)
                for aa in 1:length(AllAlgorithms)
                    PyPlot.bar(AllAlgorithms[aa], normalized_sum_routerports[aa], width=barWidth, alpha = 0.8, label=AllAlgorithms[aa], color=colormap[AllAlgorithms[aa]])
                end
                PyPlot.xlabel("TE algorithms")
                PyPlot.ylabel("Router ports (overall subscribed link bw)")
                PyPlot.xticks(rotation=45)
                figname = "$(dir)/$(topology)/router_ports_$(scale_id).png"
                PyPlot.title(topology)
                PyPlot.savefig(figname)
            end
        end

        PyPlot.clf()
        ## Normalized with respect to max router ports
        # max_all_routerports = maximum(all_sum_routerports)
        # normalized_all_sum_routerports = all_sum_routerports ./ max_all_routerports

        ## Normalized with respect to hyperthetical TE
        hyperthetical_all_routerports = all_sum_routerports[1]  # fix the first one to be hyperthetical
        normalized_all_sum_routerports = all_sum_routerports ./ hyperthetical_all_routerports

        println("normalized_all_sum_routerports ", normalized_all_sum_routerports)
        for aa in 1:length(AllAlgorithms)
            PyPlot.bar(AllAlgorithms[aa], normalized_all_sum_routerports[aa], width=barWidth, alpha = 0.8, label=AllAlgorithms[aa], color=colormap[AllAlgorithms[aa]])
        end
        PyPlot.xlabel("TE algorithms")
        PyPlot.ylabel("Router ports (overall subscribed link bw)")
        PyPlot.xticks(rotation=45)
        figname = "$(dir)/$(topology)/router_ports_all.png"
        PyPlot.title(topology)
        PyPlot.savefig(figname)

        open("$(dir)/$(topology)/routerports_agg.txt", "w+") do io
            writedlm(io, ("Normalized Router Ports",))
            for aa in 1:length(AllAlgorithms)
                writedlm(io, (AllAlgorithms[aa], normalized_all_sum_routerports[aa]))
            end
        end
    end

    if plottype == "optimizationtime" 
        average_runtime = zeros(length(AllAlgorithms),length(lotteryticket_set))
        for aa in 1:length(AllAlgorithms)
            algorithm = AllAlgorithms[aa]
            for k in 1:length(lotteryticket_set)
                vectorized = reshape(Algo_SolveTime[algorithm][:,:,:,k], size(Algo_SolveTime[algorithm][:,:,:,k],1)*size(Algo_SolveTime[algorithm][:,:,:,k],2)*size(Algo_SolveTime[algorithm][:,:,:,k],3))
                null_position = findall(x->x==-1, vectorized)
                vectorized = deleteat!(vectorized, null_position)
                nan_position = findall(x->isnan(x), vectorized)
                real_vectorized = deleteat!(vectorized, nan_position)
                average_runtime[aa,k] = round(sum(real_vectorized)/length(real_vectorized), digits=4)
            end
        end

        PyPlot.clf()
        nbars = length(AllAlgorithms)
        barWidth = 1/(nbars + 1)
        for aa in 1:length(AllAlgorithms)
            for k in 1:length(lotteryticket_set)
                PyPlot.bar(lotteryticket_set[k], average_runtime[aa,k], width=barWidth, alpha = 0.8, label=lotteryticket_set[k])
            end
        end
        PyPlot.xlabel("Number of Lottery Tickets")
        PyPlot.ylabel("Optimization Solve Time (seconds)")
        PyPlot.xticks(rotation=45)
        figname = "$(dir)/$(topology)/optimization_solve_time.png"
        PyPlot.title(topology)
        PyPlot.savefig(figname)

        open("$(dir)/$(topology)/optimization_solve_time.txt", "w+") do io
            writedlm(io, ("Optimization solve time",))
            for aa in 1:length(AllAlgorithms)
                writedlm(io, (AllAlgorithms[aa], average_runtime[aa]))
            end
        end
    end

    printstyled("\nTE simulation completed! Please find $(topology)'s [$(plottype) ($(plotname))] results in $(dir)\n\n", color=:blue)
end

parallel_plot()

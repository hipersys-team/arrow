using ArgParse, DelimitedFiles, JLD


function readScenarioNum()
    s = ArgParseSettings(description = "arg parse here for parallel experimentation")
    @add_arg_table! s begin
        "--topology", "-t"  # topology name
        "--topoindex", "-i"  # index of IP topology
        "--cutoff", "-c"  # failure scenario cutoff
        "--scenarioID", "-o"  # generate new failure scenarios from weibull
    end
    parsed_args = parse_args(s) # the result is a Dict{String,Any}
    topology = parsed_args["topology"]
    topology_index = parsed_args["topoindex"]
    scenario_cutoff = parse(Float64, parsed_args["cutoff"])
    scenario_id = parsed_args["scenarioID"]

    failure_num = 0
    failureFileName =  "./data/topology/$(topology)/IP_topo_$(topology_index)/$(scenario_cutoff)_ip_scenarios_$(scenario_id).jld"
    if isfile(failureFileName) 
        data = load(failureFileName)
        failure_num = length(data["IPScenarios"]["prob"])
    else
        failure_num = 0
    end
    println(failure_num)
end

readScenarioNum()
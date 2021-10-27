#!/bin/bash

proc_num=0
today=$(date +'%Y-%m-%d')
dirname="./data/parallel_experiment/exp-${today}"
paradir=$(julia src/nextpararun.jl --location ${dirname})

## experiment settings
teavar=0.999  # target availability (beta) for teavar
abstract_optical=1  # 1 for weibull failures, 2 for k simutaneous failure, 0 only run TE does not generate tickets, 9 for aggregating parallel-generated tickets
tunnel_type=4  # 4 for failure aware tunnel, 3 for fiber disjoint tunnel, 2 for IP disjoint tunnel, 1 is KSP tunnel， 0 is KSP for PCF
exp_topo="B4"  # experiment topology
cutoff_value=0.001  # probabilistic scenario cutoff
missing_mode=false
failure_simulation=true
failure_free=false
expand_spectrum=0
generate_scenario_file=false  # parse existing failure scenario files

## topology related parameters
if [ $exp_topo = "B4" ]
then
    option_num_set=80  # a single large ticket file, then read partially
    # option_num_set=$(seq 1 1 9; seq 10 5 80)  # generate independent ticket files, if so, make "partial_load_full_tickets = false" in main.jl
    tunnel_count="8"  # TE tunnel number per flow
    cutoff_value=0.001  # probabilistic scenario cutoff
    topo_index="1"
    scenario_set=$(seq 1 1 5)
elif [ $exp_topo = "IBM" ]
then
    option_num_set=90  # a single large ticket file, then read partially
    # option_num_set=$(seq 1 1 9; seq 10 5 80)  # generate independent ticket files, if so, make "partial_load_full_tickets = false" in main.jl
    tunnel_count="12"  # TE tunnel number per flow
    cutoff_value=0.001  # probabilistic scenario cutoff
    topo_index="1"
    scenario_set=$(seq 1 1 3)
fi

## generating failure scenarios
if [ $generate_scenario_file = true ]; then
    for scenario_id in ${scenario_set}; do 
        julia src/main.jl --topology ${exp_topo} --verbose false --topoindex ${topo_index} --cutoff ${cutoff_value} --scenarioID ${scenario_id} --singleplot false --ticketsnum 0 --largeticketsnum 0 --abstractoptical ${abstract_optical} --teavarbeta ${teavar} --tunneltype ${tunnel_type} --missing ${missing_mode} --simulation ${failure_simulation} --failurefree ${failure_free} --expandspectrum ${expand_spectrum} --scenariogeneration 0 &
        pids[proc_num]=$!;
        ((proc_num=proc_num+1));
        sleep 15;
    done
    wait
fi

## parallel generating lottery tickets
for scenario_id in ${scenario_set}; do 
    scenario_count=$(julia src/getscenarionum.jl --topology ${exp_topo} --topoindex ${topo_index} --cutoff ${cutoff_value} --scenarioID ${scenario_id})
    generate_ticket_scenario_set=$(seq 1 1 ${scenario_count})
    for generate_ticket_scenario in ${generate_ticket_scenario_set}; do
        for option_num in ${option_num_set}; do  # if option_num > 1 then call ARROW randomized rounding, if = 1 only run restore ILP for PLANNING, otherwise only generate failure scenarios for other TE
            julia src/main.jl --topology ${exp_topo} --verbose false --topoindex ${topo_index} --cutoff ${cutoff_value} --scenarioID ${scenario_id} --singleplot false --ticketsnum ${option_num} --largeticketsnum ${option_num} --abstractoptical ${abstract_optical} --teavarbeta ${teavar} --tunneltype ${tunnel_type} --missing ${missing_mode} --simulation ${failure_simulation} --failurefree ${failure_free} --expandspectrum ${expand_spectrum} --scenariogeneration ${generate_ticket_scenario} &
            pids[proc_num]=$!;
            ((proc_num=proc_num+1));
            sleep 5;
        done
    done
    for pid in ${pids[*]}; do
        wait $pid 
    done
done
wait

for pid in ${pids[*]}; do
    wait $pid 
done

## aggregating parallel generated tickets
for scenario_id in ${scenario_set}; do 
    scenario_count=$(julia src/getscenarionum.jl --topology ${exp_topo} --topoindex ${topo_index} --cutoff ${cutoff_value} --scenarioID ${scenario_id})
    for option_num in ${option_num_set}; do 
        julia src/aggregatetickets.jl --scenarionum ${scenario_count} --topology ${exp_topo} --topoindex ${topo_index} --cutoff ${cutoff_value} --scenarioID ${scenario_id} --expandspectrum ${expand_spectrum} --ticketsnum ${option_num} --aggregaterwa false &
        sleep 15;
    done
    wait
    julia src/aggregatetickets.jl --scenarionum ${scenario_count} --topology ${exp_topo} --topoindex ${topo_index} --cutoff ${cutoff_value} --scenarioID ${scenario_id} --expandspectrum ${expand_spectrum} --ticketsnum 0 --aggregaterwa true &
done 
wait
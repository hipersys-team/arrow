#!/bin/bash

proc_num=0
today=$(date +'%Y-%m-%d')
dirname="./data/parallel_experiment/exp-${today}"
paradir=$(julia src/nextpararun.jl --location ${dirname})

## experiment settings
teavar=0.999  # target availability (beta) for teavar
abstract_optical=0  # 1 for weibull failures, 2 for k simutaneous failure, 0 only run TE does not generate tickets
tunnel_type=4  # 4 for failure aware tunnel, 3 for fiber disjoint tunnel, 2 for IP disjoint tunnel, 1 is KSP tunnel， 0 is KSP for PCF
exp_topo="B4"  # experiment topology
missing_mode=false
failure_simulation=true
failure_free=false
expand_spectrum=0
generate_ticket_scenario=0  # read all scenarios in a scenario file together

## topology related parameters
if [ $exp_topo = "B4" ]
then
    scale_num=4.2  # demand scale
    tunnel_count="8"  # TE tunnel number per flow
    cutoff_value=0.001  # probabilistic scenario cutoff
    demand_downscale=12000
    topo_index="1"
    traffic_matrices=$(seq 1 1 30)
    lotteryticket_set=$(seq 1 1 9; seq 10 5 80)
    largest_lotteryticket=80
    scenario_set=$(seq 1 1 5)
elif [ $exp_topo = "IBM" ]
then
    scale_num=5.5
    tunnel_count="12"
    cutoff_value=0.001
    demand_downscale=12000
    topo_index="1"
    traffic_matrices=$(seq 1 1 30)
    lotteryticket_set=$(seq 1 1 9; seq 10 5 90)
    largest_lotteryticket=90
    scenario_set=$(seq 1 1 3)
fi

julia src/author.jl

## 1) parallel running experiments with different parameters if using different ticket files
startpoint=$1
for traffic_num in ${traffic_matrices}; do
    for option_num in ${lotteryticket_set}; do 
        for scenario_id in ${scenario_set}; do
            if ((proc_num == 0))
            then 
                plot_single=true 
                sleeptime=30
            else 
                plot_single=false 
                sleeptime=2
            fi
            ((iter_traffic_num=${startpoint}+traffic_num))
            julia src/main.jl --topology ${exp_topo} --traffic ${iter_traffic_num} --scale ${scale_num} --te ARROW --verbose false --parallel ${paradir} --downscale ${demand_downscale} --singleplot ${plot_single} --topoindex ${topo_index} --cutoff ${cutoff_value} --tunnel ${tunnel_count} --scenarioID ${scenario_id} --ticketsnum ${option_num} --largeticketsnum ${largest_lotteryticket} --abstractoptical ${abstract_optical} --teavarbeta ${teavar} --tunneltype ${tunnel_type} --missing ${missing_mode} --simulation ${failure_simulation} --failurefree ${failure_free} --expandspectrum ${expand_spectrum} --scenariogeneration ${generate_ticket_scenario} &
            pids[proc_num]=$!;
            ((proc_num=proc_num+1));
            sleep ${sleeptime};
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

## plotting results
julia plot_all.jl --location ${paradir} --topology ${exp_topo} --te ARROW --option 0 --scale ${scale_num} --plottype "throughput"  --inverselog false --lotteryticketset 0

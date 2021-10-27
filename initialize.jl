using Pkg

## add necessary Julia Packets
Pkg.add("JLD")
Pkg.add("Plots")
Pkg.add("Gadfly")
Pkg.add("Debugger")
Pkg.add("PyPlot")
Pkg.add("GR")
Pkg.add("ProgressMeter")
Pkg.add("Combinatorics")
Pkg.add("ArgParse")
Pkg.add("DelimitedFiles")
Pkg.add("Compose")
Pkg.add("Random")
Pkg.add("Cairo")
Pkg.add("Gurobi")
Pkg.add("HDF5")
Pkg.add("LightGraphs")
Pkg.add("HypothesisTests")
Pkg.add("GraphPlot")
Pkg.add("Dates")
Pkg.add("JuMP")
Pkg.add("Distributions")

Pkg.build()

## initialize the results folder
if !isdir("./data/experiment")
    println("Initializing results folder ./data/experiment.")
    mkdir("./data/experiment")
else
    println("Results folder ./data/experiment exists.")
end

if !isdir("./data/parallel_experiment")
    println("Initializing results folder ./data/parallel_experiment")
    mkdir("./data/parallel_experiment")
else
    println("Results folder ./data/parallel_experiment exists.")
end
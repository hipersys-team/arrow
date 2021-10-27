# ARROW: Agile Restorable Optical Wavelength

## 1. Overview
ARROW is a Traffic Engineering (TE) system. It is built with the Julia programmaing language (https://julialang.org/) using Gurobi (https://www.gurobi.com/) as its optimizer.

Fiber cut events reduce the capacity of wide-area networks (WANs) by several Tbps. In this paper, we revive the lost capacity by reconfiguring the wavelengths from cut fibers into healthy fibers.

In most cases, the restored capacity would be less than its lost capacity, resulting in partial restoration. This poses a cross-layer challenge from the Traffic Engineering (TE) perspective that has not been considered before: “Which IP links should be restored and by how much to best match the TE objective?”

ARROW solves the problem by proposing a novel restoration-aware TE system, that takes a set of partial restoration candidates (that we call LotteryTickets) as input and proactively finds the best restoration plan within reasonable runtime.

For a full technical description on ARROW, please read our ACM SIGCOMM 2021 paper:

> Z. Zhong, M. Ghobadi, A. Khaddaj, J. Leach, Y. Xia, Y. Zhang, "ARROW: Restoration-Aware Traffic Engineering," ACM SIGCOMM, 2021. http://arrow.csail.mit.edu/files/2021_SIGCOMM_ARROW.pdf

For more details on ARROW, please visit our website: http://arrow.csail.mit.edu

For code questions, please contact Zhizhen Zhong at zhizhenz [at] mit.edu. We welcome contributions and feedbacks.

## 2. Artifact Structure

### 2.1. Source code for the TE simulation for ARROW.

|  Source Files                 |  Description                                                 |
|  -----                        |  -----                                                       |
|  `algorithms/`                |  Folder of different TE algorithms (ARROW, FFC, TeaVaR, etc.)|
|  `plotall.jl`                 |  Plotting parallel generated results                         |
|  `src/aggregatetickets.jl`    |  Aggregating parallel generated tickets                      |
|  `src/author.jl`              |  Code contributors information                               |
|  `src/controller.jl`          |  Traffic engineering controller                              |
|  `src/environment.jl`         |  Fiber cut scenario generator                                |
|  `src/evaluation.jl`          |  Evaluating TE algorithms with fiber cut scenarios           |
|  `src/getscenarionum.jl`      |  Get the number of failure scenarios in each scenario file   |
|  `src/interface.jl`           |  Parse input parameters for the simulator                    |
|  `src/main.jl`                |  Simulation main file                                        |
|  `src/nextpararun.jl`         |  Generating data folder for simulation results               |
|  `src/plotting.jl`            |  Plotting functions                                          |
|  `src/provision.jl`           |  Execute IP topology provisioning                            |
|  `src/restoration.jl`         |  Optical restoration on the optical layer under failures     |
|  `src/simulator.jl`           |  Traffic engineering simulator                               |
|  `src/topodraw.jl`            |  Visualize network topology and tunnel flows                 |
|  `src/topoprovision.jl`       |  Provision IP topology on top of given optical topology      |

### 2.2. Input and output data in the TE simulation for ARROW.

|  Data Files                     |  Description                                              |
|  -----                          |  -----                                                    |
|  `data/topology/`               |  Input topology data                                      |
|  `data/topology/DATAFORMATS.md` |  Explain the data format for input topology data          |
|  `data/experiment/`             |  Simulation results will be saved here                    |
|  `data/parallel_experiment/`    |  Simulation results of parallel runs will be saved here   |

### 2.3. Executable shells for the running TE simulation for ARROW.

|  Executable Files             |  Description                                          |
|  -----                        |  -----                                                |
|  `abstract_optical_layer.sh`  |  Generating LotteryTickets to abstract optical layer  |
|  `parallel_demand_exp.sh`     |  Parallel run for different demand scales             |
|  `parallel_tickets_exp.sh`    |  Parallel run for different LotteryTicket numbers     |
|  `optimization_solvetime.sh`  |  Parallel run for optimization solve time             |
|  `router_ports.sh`            |  Parallel run for required number of router ports     |

### 2.4. Running simulation
First, initialize the Julia environment by installing related packages, and prepare results directories.
```
julia initialize.jl
```

Generating LotteryTickets using only optical-layer information (Section 3.2 in the paper).
```
bash abstract_optical_layer.sh
```

Traffic engineering algorithms' availability performance with different demand scales (Section 3.3 and 6.1 in the paper).
```
bash parallel_demand_exp.sh
```

Traffic engineering algorithms' throughput performance with different LotteryTicket numbers (Section 3.3 and 6.2 in the paper).
```
bash parallel_tickets_exp.sh
```

Traffic engineering algorithms' optimizatiom solve time performance with different LotteryTicket numbers (Section 3.3 and 6.2 in the paper).
```
bash optimization_solvetime.sh
```

Traffic engineering algorithms' required network cost (in terms of number of router ports) to support the same throughput with the same
availability level(Section 3.3 and 6.3 in the paper).
```
bash router_ports.sh
```

Note that large-scale TE simulations that support a certain amount of failure scenarios and traffic matrices require sufficient computing resources (CPU cores and memory). We recommend to run experiments with servers with at least 32 CPU cores and 256 GB RAM.

## 3. Major Dependencies
* Julia 1.6.1
* JuMP 0.21.6
* Gurobi 9.1.2


## 4. License
ARROW is MIT-licensed.

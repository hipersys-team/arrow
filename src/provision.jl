include("./topoprovision.jl")

ProvisionIPTopology("B4", scaling=5, density=0.98, linknum=52, ilp_planning=false, tofile=true)
ProvisionIPTopology("IBM", scaling=2, density=0.98, linknum=85, ilp_planning=false, tofile=true)

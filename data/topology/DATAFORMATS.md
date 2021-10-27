## Optical fiber topology files
`./${topology}/optical_nodes.txt`, each line represents a node on the optical layer.
>[Format] *String_node_names* (the node on the optical layer).

`./${topology}/optical_topo.txt`, each line represents a fiber link.
>[Format] *to_node* (the source node of the fiber link), *from_node* (the destination node of the fiber link), *metric* (the routing calculation metric of the fiber link, e.g., distance), *failure_prob* (the failure probability of the fiber link if specified from this input file).

`./${topology}/optical_topo_graph.png`, graphical plot of the optical-layer network topology.


## IP topology files
`./${topology}/IP_nodes.txt`, each line represents a node on the IP layer.
>[Format] *String_node_names* (the node on the IP layer).

`./${topology}/IP_topo_${IPTOPO_ID}/IP_topo_${IPTOPO_ID}.txt`, each line represents an IP link. 
>[Format] *src* (the source node of the IP link), *dst* (the destination node of the IP link), *index* (the index of the IP link (if parallel IP link exists), *capacity* (the capacity of the IP links (related to the number of wavelengths of this IP link), *fiberpath_index* (the set of fiber link indices that this IP link is routed through), *wavelength* (the set of wavelengths that supports this IP link), *failure* (the failure probability of the IP link if specified from this input file).

`./${topology}/IP_topo_${IPTOPO_ID}/IP_topo_graph.png`, graphical plot of the IP-layer network topology.

`./${topology}/IP_topo_${IPTOPO_ID}/optical_topo_graph_spectrum_availability.png`, graphical plot of the optical-layer network topology and fiber's available wavelength indices when the current IP topology is already provisioned.

`./${topology}/IP_topo_${IPTOPO_ID}/optical_topo_graph_residual_fiber_capacity.png`, graphical plot of the optical-layer network topology and fiber's available capacity when the current IP topology is already provisioned.


## Failure scenarios
`./$(topology)/IP_topo_${IPTOPO_ID}/${CUT_OFF}_ip_scenario_${SCENARIO_ID}.jld`, each line represents a IP-layer scenario (mapped from fiber cut scenarios) generated following a certain distribution (e.g., weibull).
>[Format] *failure_scenario_probability* (probability of this failure scenario), *{status_of_IP_link}* (the IP link up/down status of this failure scenario, where 1 means up, 0 means down).


## Lottery tickets
`./${topology}/IP_topo_${IPTOPO_ID}/${CUT_OFF}_lotterytickets${TICKET_NUM}_${SCENARIO_ID}.jld`, odd lines represent IP link status, even links represent `TICKET_NUM` lottery tickets.
>[Format] *{status_of_IP_link}* (the IP link up/down status of this failure scenario, where 1 means up, 0 means down), *{IP_link_capacity_after_restoration}* (different combinations of possible the IP link capacity after optical-layer restoration, which we call lottery ticket the ARROW paper).


## Traffic demand matrix
`./demand.txt`, each line represents a traffic matrix.
>[Format] *{traffic_demand_src_to_dst}* (the amount of traffic demand from IP source node to IP destination node).


## TE tunnels
`./${topology}/IP_topo_${IPTOPO_ID}/tunnels_${TUNNEL_TYPE}/IPedges.txt`, each line represents an IP link.
>[Format] *(IP_src_node, IP_dst_node, IP_edge_index)* (the source node, destination node, IP link index of the IP link).

`./${topology}/IP_topo_${IPTOPO_ID}/tunnels_${TUNNEL_TYPE}/tunnels_edges.txt`, each line represents how a flow's tunnels are routed on IP links.
>[Format] *Flow: (src_node, dst_node) and Tunnel: [(IP_src_node, IP_dst_node, IP_edge_index)]* (flow is represent by its source IP node and destination IP node, and tunnel is routed on IP links).

`./${topology}/IP_topo_${IPTOPO_ID}/tunnels_${TUNNEL_TYPE}/tunnels.txt`,this file contains the set of all flows, the set of all tunnels, the set of all flow-to-tunnel mapping, and the set of all IP links.
>[Format] *All Flows* (the set of all flows), *All Tunnels* (the set of all tunnels), *All Flow Tunnels* (the set of all flow-to-tunnel mappings), *IP edges* (the set of all IP links).

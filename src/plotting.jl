using Plots, GR, Distributions, HypothesisTests, Statistics

GR.inline("png")

## plotting
function line_plot(xset, yset, xname, yname, figname, figname2, AllAlgorithms, availability_zoom, avg_med, inverse_log, x_log)
    colormap = Dict(
        "HYPERTHETICAL" => "black",
        "ARROW_NAIVE" => "blue", 
        "FFC1" => "green", 
        "FFC2" => "yellow", 
        "TEAVAR" => "purple",
        "ECMP" => "orange",
    )
    markermap = Dict(
        "HYPERTHETICAL" => "o",
        "ARROW_NAIVE" => "o", 
        "FFC1" => "o", 
        "FFC2" => "o", 
        "TEAVAR"=>"P", 
        "ECMP" => "o",
    )
    arrowmarkermap = Dict(
        "HYPERTHETICAL" => "o",
        "ARROW"=>"o", 
        "ARROW_BIN"=>"P",
    )
    datafilename = replace(figname, ".png"=>".txt")
    if inverse_log figname = replace(figname, ".png"=>"_r.png") end
    if inverse_log figname2 = replace(figname2, ".png"=>"_r.png") end
    open(datafilename, "w+") do io
        PyPlot.clf()
        Plots.plot()
        for algorithm in AllAlgorithms
            line = []
            line_ci_min = []
            line_ci_max = []
            for s in 1:length(xset)
                vectorized = reshape(yset[algorithm][:,:,:,s], size(yset[algorithm][:,:,:,s],1)*size(yset[algorithm][:,:,:,s],2)*size(yset[algorithm][:,:,:,s],3))
                null_position = findall(x->x==-1, vectorized)
                real_vectorized = deleteat!(vectorized, null_position)
                if avg_med
                    metric = round(sum(real_vectorized)/length(real_vectorized), digits=16)
                    avg = metric
                else
                    if length(real_vectorized) > 0
                        metric = median(real_vectorized)
                    else
                        metric = nothing
                    end
                    avg = round(sum(real_vectorized)/length(real_vectorized), digits=16)
                end
                push!(line, metric)
                if length(real_vectorized) > 1
                    if avg_med
                        conf = confint(OneSampleTTest(real_vectorized, avg))  # confidence interval calculation based on average
                    else
                        medianinterval(d,p = 0.95) = quantile(d,1-(1+p)/2),quantile(d,(1+p)/2)
                        conf = medianinterval(real_vectorized)
                    end
                    push!(line_ci_min, min(metric - conf[1], metric))
                    push!(line_ci_max, min(conf[2] - metric, 1 - metric))
                elseif length(real_vectorized) > 0
                    push!(line_ci_min, metric - minimum(real_vectorized))
                    push!(line_ci_max, maximum(real_vectorized) - metric)
                end
            end
            writedlm(io, (yname,))
            if algorithm == "ARROW" || algorithm == "ARROW_BIN"
                if inverse_log
                    reverse_line = []
                    for i in 1:length(line)
                        if line[i] === nothing
                            push!(reverse_line, nothing)
                        else
                            push!(reverse_line, 1-line[i])
                        end
                    end
                    PyPlot.plot(xset, reverse_line, linewidth=1, marker=arrowmarkermap[algorithm], alpha = 0.8, label=algorithm, color="red")
                else
                    PyPlot.plot(xset, line, linewidth=1, marker=arrowmarkermap[algorithm], alpha = 0.8, label=algorithm, color="red")
                end
                writedlm(io, (algorithm, line))
            else
                if inverse_log
                    reverse_line = []
                    for i in 1:length(line)
                        if line[i] === nothing
                            push!(reverse_line, nothing)
                        else
                            push!(reverse_line, 1-line[i])
                        end
                    end
                    PyPlot.plot(xset, reverse_line, linewidth=1, marker=markermap[algorithm], alpha = 0.8, label=algorithm, color=colormap[algorithm])
                else
                    PyPlot.plot(xset, line, linewidth=1, marker=markermap[algorithm], alpha = 0.8, label=algorithm, color=colormap[algorithm])
                end
                writedlm(io, (algorithm, line))
            end
            writedlm(io, (yname,"error border"))
            if availability_zoom
                if inverse_log
                    if length(line_ci_min) > 0 && length(line_ci_max) > 0 
                        Plots.plot!(xset, 1 .- line; ribbon=(line_ci_min, line_ci_max), fillalpha=0.2, xaxis=xname, yaxis=yname, label=algorithm, ylims = (0.00001, 0.01), linewidth=2, marker=:auto, yscale=:log10, yflip=true)
                        Plots.plot!(yticks=([0.01, 0.001, 0.0001, 0.00001], [0.99, 0.999, 0.9999, 0.99999]))
                        Plots.plot!(layout=1, legend=:bottomleft)
                    end
                else
                    if length(line_ci_min) > 0 && length(line_ci_max) > 0  
                        Plots.plot!(xset, line; ribbon=(line_ci_min, line_ci_max), fillalpha=0.2, xaxis=xname, yaxis=yname, label=algorithm, ylims = (0.99, 1.001), linewidth=2, marker=:auto)
                        Plots.plot!(layout=1, legend=:bottomleft)
                    end
                end
                writedlm(io, (algorithm, line_ci_min, line_ci_max))
            else
                if inverse_log
                    if length(line_ci_min) > 0 && length(line_ci_max) > 0  
                        Plots.plot!(xset, 1 .- line; ribbon=(line_ci_min, line_ci_max), fillalpha=0.2, xaxis=xname, yaxis=yname, label=algorithm, linewidth=2, marker=:auto, yscale=:log10, yflip=true)
                        Plots.plot!(yticks=([0.1, 0.01, 0.001, 0.0001, 0.00001], [0.9, 0.99, 0.999, 0.9999, 0.99999]))
                        Plots.plot!(layout=1, legend=:bottomleft)
                    end
                else
                    if length(line_ci_min) > 0 && length(line_ci_max) > 0  
                        Plots.plot!(xset, line; ribbon=(line_ci_min, line_ci_max), fillalpha=0.2, xaxis=xname, yaxis=yname, label=algorithm, linewidth=2, marker=:auto)
                        Plots.plot!(layout=1, legend=:bottomleft)
                    end
                end
            end
        end
        PyPlot.legend(loc="best")
        PyPlot.xlabel(xname)
        PyPlot.ylabel(yname)
        if x_log PyPlot.xscale("log") end
        if inverse_log
            PyPlot.yscale("log")
            PyPlot.yticks([0.1, 0.01, 0.001, 0.0001, 0.00001], [0.9, 0.99, 0.999, 0.9999, 0.99999])
            PyPlot.gca().invert_yaxis()
        end
        if availability_zoom
            PyPlot.ylim((0.99, 1.001))
            if inverse_log
                PyPlot.ylim((0.00001, 0.01))
                PyPlot.yticks([0.01, 0.001, 0.0001, 0.00001], [0.99, 0.999, 0.9999, 0.99999])
                PyPlot.gca().invert_yaxis()
            end
        end
        PyPlot.savefig(figname)
        Plots.savefig(figname2)
    end
end

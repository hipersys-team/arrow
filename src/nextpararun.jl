using ArgParse, DelimitedFiles


function nextParaRun()
    s = ArgParseSettings(description = "arg parse here for parallel experimentation")
    @add_arg_table! s begin
        "--location", "-l"  # location    
    end
    parsed_args = parse_args(s) # the result is a Dict{String,Any}
    dir = parsed_args["location"]

    if isfile("$(dir)/counter.txt") == false
        mkdir("$(dir)")
        writedlm("$(dir)/counter.txt", "1")
    end
    c = Int(readdlm("$(dir)/counter.txt")[1])
    writedlm("$(dir)/counter.txt", c + 1)
    newdir = "$(dir)/$(c)"
    mkdir(newdir)
    println(newdir)
end

nextParaRun()
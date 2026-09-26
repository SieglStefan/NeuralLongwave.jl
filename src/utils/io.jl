### IO Utilities
###
### Functions for saving and loading and preparing directories
###         - 1) Root and directory paths
###         - 2) Directory preparation
###         - 3) Saving and loading functions
###         - 4) .csv handling
###         - 5) Information logging










### 1) Root and directory paths

# Root path of the package
const ROOT = normpath(joinpath(@__DIR__, "..", ".."))


# Data folder paths
raw_data_dir(scheme, series, unit)  = joinpath(ROOT, "data", "raw_data", scheme, series, unit)                  # raw datasets used as base for other datasets
restart_states_dir(scheme, unit)    = joinpath(ROOT, "data", "restart_states", scheme, unit)                    # restart datasets for spinup
column_io_dir(scheme, unit)         = joinpath(ROOT, "data", "column_io", scheme, unit)                         # target datasets for offline training
zscore_dir(scheme, unit)            = joinpath(ROOT, "data", "zscore", scheme, unit)                            # zscore statistics


# Results folder paths
emulator_dir(experiment, series, unit)  = joinpath(ROOT, "results", experiment, series, unit, "emulator")       # trained emulators
rollout_dir(experiment, series, unit)   = joinpath(ROOT, "results", experiment, series, unit, "rollout")        # generated rollouts
timing_dir(experiment, series)          = joinpath(ROOT, "results", experiment, series, "timing")               # runtime of all units of a series (one job)
reference_dir(scheme, name)             = joinpath(ROOT, "results", scheme, name)                               # reference runs of a target scheme (climate_ref, climate_noise, grey, spinup, ...)









### 2) Directory preparation

# Prepare output directory without overwriting existing content
function prepare_out_dir(base_dir; name=nothing, overwrite=false)
    
    # Check if name is provided
    if isnothing(name)
        out_dir = base_dir
    else
        out_dir = joinpath(base_dir, name)
    end

    # Check if folder already exists and throw error if not allowed to overwrite
    if isdir(out_dir) && !overwrite
        error("Folder already exists ($out_dir): Task canceled! (not overwritten).")
    elseif isdir(out_dir) && overwrite
        rm(out_dir; recursive = true)
    end

    # Create folder
    return mkpath(out_dir)
end










### 3) Saving and loading functions

# Function for saving an object to a .jld2 file
function save(object; dir, file)
    
    # Create path and put together filepath
    mkpath(dir)
    filepath = joinpath(dir, file)

    # Save object
    JLD2.jldsave(filepath; object)

    return filepath
end


# Function for loading an object from a .jld2 file
function load(; dir, file)

    # Load object
    filepath = joinpath(dir, file)
    object = JLD2.load(filepath, "object")

    return object
end



# Load the logged metrics of one training run (plus validation if present)
function load_run(dir)

    # Load training results
    train = csv_read(; dir, file = "training.csv")

    # Load validation results (if present)
    val = isfile(joinpath(dir, "validation.csv")) ? csv_read(; dir, file = "validation.csv") : nothing

    return (; train, val)
end

# Utility function for loading one reference artifact of a target scheme, e.g. ("OBLW", "climate_noise", "climate.jld2")
load_reference(scheme, name, file) = load(; dir = reference_dir(scheme, name), file)

# Utility function for loading the timing of a series (all units were timed in one job, one file)
load_timings(experiment, series) = load(; dir = timing_dir(experiment, series), file = "timing.jld2")



# Utility function for collecting training run data
collect_runs(experiment, series, units) = (; 
    (Symbol(unit) => load_run(emulator_dir(experiment, series, unit)) for unit in units)...
)
# Utility function for collecting emulators
collect_emulators(experiment, series, units) = (; 
    (Symbol(unit) => load(; dir = emulator_dir(experiment, series, unit), file = "emulator.jld2") for unit in units)...
)
# Utility function for collecting rollouts
collect_rollouts(experiment, series, units; leg = :weather) = (;
    (Symbol(unit) => load(; dir = rollout_dir(experiment, series, unit), file = "$(leg).jld2") for unit in units)...
)



# Write a figure at its true size: .pdf for the thesis (vector), .png for everything else
function save_figure(fig, filepath; px_per_unit = 4)

    # Create directory and save fig
    isempty(dirname(filepath)) || mkpath(dirname(filepath))
    CairoMakie.save(filepath, fig; pt_per_unit = 1, px_per_unit)

    return filepath
end










### 4) .csv handling

# Initialize .csv file for training info
function csv_init(head_keys, metric_keys; dir="", file="")

    # Create path and put together filepath
    mkpath(dir)
    filepath = joinpath(dir, file)

    # Write header
    open(filepath, "w") do io
        println(io, join(head_keys, ",") * "," * join(metric_keys, ","))
    end

    # Print information
    @info ".csv file created and initialized at $(filepath)!"

    return filepath
end


# Write a row of training data to .csv
function csv_row!(head::NamedTuple; metrics, dir="", file="")

    # Put together filepath
    filepath = joinpath(dir, file)

    # Write a data row
    open(filepath, "a") do io
        println(io, join((values(head)..., values(metrics)...), ","))
    end

    return nothing
end


# Read .csv data for plotting
function csv_read(; dir="", file="")

    # Put together filepath
    filepath = joinpath(dir, file)

    # Read .csv data
    return CSV.read(filepath, DataFrame; comment="#")
end










### 5) Information logging (info.toml)

# Writes a info.toml file with the given keyword arguments
function write_info(; dir="", file="info.toml", kwargs...)
    
    # Create info dictonary out of keyword arguments
    info = Dict(string(k) => info_value(v) for (k, v) in kwargs)

    # Create path and put together filepath
    mkpath(dir)
    filepath = joinpath(dir, file)

    # Write info to .toml file
    open(filepath, "w") do io
        TOML.print(io, info; sorted = true)
    end

    # Print information
    @info "Info file written to $(filepath)!"

    return filepath
end



# Convert a value into one the info.toml file can store (Symbols, Types, nothing, ... become strings)
info_value(x)                 = x
info_value(x::AbstractFloat)  = Float64(x)                                             
info_value(x::Symbol)         = string(x)
info_value(::Nothing)         = ""
info_value(x::Type)           = string(nameof(x))
info_value(x::Function)       = string(x)
info_value(x::Period)         = string(x)
info_value(x::AbstractDict)   = Dict(string(k) => info_value(v) for (k, v) in x)
info_value(x::NamedTuple)     = Dict(string(k) => info_value(v) for (k, v) in pairs(x))
info_value(x::AbstractVector) = [info_value(v) for v in x]
info_value(x::Tuple)          = [info_value(v) for v in x]


# Git state of the repo that produced an artifact
function git_info()
    commit = try readchomp(`git -C $(ROOT) rev-parse --short HEAD`) catch; "unknown" end        # Commit ID
    dirty  = try !isempty(readchomp(`git -C $(ROOT) status --porcelain`)) catch; true end       # If there are uncommitted changes
    return (; commit, dirty)
end


# Provenance of an artifact: when, with which versions and from which git state it was created
function provenance()
    return (;
        created = now(),
        julia   = string(VERSION),
        sw_vers = string(pkgversion(SpeedyWeather)),
        git     = git_info(),
    )
end
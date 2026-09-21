### Column IO samples extraction
###
### Collects and prepares column samples from raw data for zscore, offline target and evaluation
###         - 1) Derive and create column IO
###         - 2) Column IO Extraction Utilities
###
### Format of the stored fields:
###     - profile (T, dT, q):           (npoints, nlayers, n_states_total)
###     - scalars (p, olw, slwd,...):   (npoints, n_states_total)
### where:
###     - npoints:          number of global columns (grid points)
###     - nlayers:          number of vertical layers
###     - n_states_total:   total number of samples over all ics (1 state = 1 full global simulation.variables)










### 1) Derive and create column IO

# Create column IO and save them
function derive_column_io(;
    raw_dir,                    # directory containing raw data
    scheme,                     # scheme folder for storing column IO data
    unit,                       # unit folder for storing
    ic_subset,                  # initial conditions to process from raw data 
)

    # Extract inputs and outputs from raw data and column calls
    column_io = create_column_io(raw_dir, ic_subset)

    # Extract spectral grid
    spectral_grid, model_type = with_raw_data(d -> (d.spectral_grid, d.model_type), raw_dir, first(ic_subset))
       

    # Dataset dimensions
    (; npoints, nlayers) = column_io.dims
    n_states_total = size(column_io.fields.dT, 3)

    # Calculate number of states per IC and check for consistency
    n_states_ic, rest = divrem(n_states_total, length(ic_subset))
    rest == 0 || error("$(n_states_total) states over $(length(ic_subset)) ICs — not equally sized!")


    # Save column IO data
    dir = column_io_dir(scheme, unit)
    save((; column_io..., spectral_grid, model_type); dir, file = "column_io.jld2")

    # Write info and print log
    write_info(; dir,
        source          = raw_dir,                      # raw data used for creating column IO
        ic_subset       = collect(ic_subset),           # subset of ICs used
        n_ics           = length(ic_subset),            # number of ICs used

        npoints         = npoints,                      # grid columns per global state
        nlayers         = nlayers,                      # number of vertical layers
        n_states_ic     = n_states_ic,                  # stored states per IC
        n_states_total  = n_states_total,               # total number of stored states over all ICs

        n_samples_ic    = npoints * n_states_ic,        # training samples one IC contributes
        n_samples_total = npoints * n_states_total,     # ... and all ICs together
    )

    # Print log
    @info "Column IO dataset $(scheme)_$(unit) stored at $(dir)! " *
          "$(npoints * n_states_total) samples ($(npoints * n_states_ic) per IC)"

    return nothing
end



# Extract column Inputs and Outputs from raw_data in shape (npoints, nlayers, n_states_total)
function create_column_io(raw_dir, ic_subset)

    # Rebuild simulation
    sim = with_raw_data(raw_dir, first(ic_subset)) do d
        initialize!(d.model_type(d.spectral_grid; longwave_radiation = d.lw_scheme))
    end

    # Shortcut variables
    vars = sim.variables
    model = sim.model
    lw = model.longwave_radiation

    # Grid dimensions
    npoints, nlayers = size(vars.grid.temperature)


    # Total number of samples over all ICs
    n_states_total = sum(with_raw_data(d -> d.n_states, raw_dir, ic) for ic in ic_subset)

    # Extract number of inputs and layouts
    n_in = n_inputs(INPUTS, nlayers)                # scalar
    layout = input_layout(INPUTS, nlayers)          # e.g. (; T=1:8, ps=9:9, sinlat2=10:10, lf=11:11, ...))


    # Container for inputs
    inp = zeros(Float32, npoints, n_in, n_states_total)
    
    # Containers for target outputs
    dT = zeros(Float32, npoints, nlayers, n_states_total)
    olw = zeros(Float32, npoints, n_states_total)
    slwd = zeros(Float32, npoints, n_states_total)
    slwu = zeros(Float32, npoints, n_states_total)



    ### Main loop: read every stored state and evaluate the target scheme on it
    idx = 1

    # Loop over all chosen initial conditions
    for ic in ic_subset
        with_raw_data(raw_dir, ic) do d


            # Loop over all stored samples (full global variables of one specific sample time) per ic
            for j in 0:d.n_states-1

                # Load the stored state sample into the simulation
                copy!(vars, d[j])


                # Store inputs and outputs
                for ij in 1:npoints

                    # Inputs
                    fill_inputs!(view(inp, ij, :, idx), INPUTS, ij, vars, model, lw)

                    # Outputs
                    olw[ij, idx], slwd[ij, idx], slwu[ij, idx] = fill_targets!(view(dT, ij, :, idx), ij, vars, model)
                end

                idx += 1
            end

            @info "IC $(ic): $(d.n_states) states read!"
        end
    end


    # Splits the input vector inp into named touples
    inputs = map(r -> length(r) == 1 ? Array(view(inp, :, first(r), :)) : Array(view(inp, :, r, :)), layout)

    # Calculate net upward flux profile between layers, reconstructed from heating rates
    F = reconstruct_net_flux(dT, olw, inputs.ps, flux_to_dT_fac(model))
    check_net_flux(F, slwu, slwd)

    return (;
        fields      = (; inputs..., dT, olw, slwd, slwu, F),
        dims        = (; npoints, nlayers, truncation = model.spectral_grid.truncation),
        ic_subset   = collect(ic_subset),
        source      = raw_dir,
    )
end










### 2) Column IO Extraction Utilities

# Fills offline training target variables (dT, olw, slwd) from variables and model, for one column ij
function fill_targets!(dT, ij, vars, model)

    # Shortcut variables
    lw = model.longwave_radiation
    dTdt = SpeedyWeather.get_tendency_step(vars.tendencies.grid.temperature, model.time_stepping, lw)

    # Reset this columns temperature tendencies
    for k in axes(dTdt, 2)
        dTdt[ij,k] = 0f0
    end

    # Apply column parameterization
    SpeedyWeather.parameterization!(ij, vars, lw, model)

    # Copy out tendencies
    for k in axes(dTdt, 2)
        dT[k] = dTdt[ij,k]
    end

    # Return fluxes
    return  vars.parameterizations.outgoing_longwave[ij], 
            vars.parameterizations.surface_longwave_down[ij],
            vars.parameterizations.surface_longwave_up[ij]
end



# Reconstructing net fluxes recursively from 
#   - Summed from the top, where no longwave comes in from space:  F[1] = olw
function reconstruct_net_flux(dT, olw, ps, flux_to_dT)

    # Container of shape (npoints, nlayers+1, n_states)
    npoints, nlayers, n_states = size(dT)
    F = zeros(Float32, npoints, nlayers+1, n_states)

    # Loop over samples and columns, adding up the flux difference of every layer from the top down
    for s in 1:n_states, ij in 1:npoints
        F[ij, 1, s] = olw[ij, s]
        for k in 1:nlayers
            F[ij, k+1, s] = F[ij, k, s] + dT[ij, k, s] * ps[ij, s] / flux_to_dT[k]
        end
    end

    return F
end

# Check the reconstructed net fluxes against the schemes own surface fluxes:
#   - F at the surface must equal to slwu - slwd
function check_net_flux(F, slwu, slwd; tol = 0.1f0)

    # Largest deviation over all columns and samples [W/m²]
    err = maximum(abs.(F[:, end, :] .- (slwu .- slwd)))

    # Throw error if flux reconstruction failed
    err < tol || error("Net flux reconstruction does not close at the surface: max error $(err) W/m² (tol $(tol) W/m²)")
    @info "Net flux reconstruction closes at the surface: max error $(err) W/m²"

    return err
end
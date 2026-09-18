### Compile / smoke test for NeuralParam
###
### Run from the repo root:
###     julia --project=. tests/test_compile.jl
###
### Checks:
###   1. the package precompiles and loads
###   2. every EXPORTED name is actually defined (Julia allows exporting undefined names silently)
###   3. cheap runtime checks (construction + pure functions) — no simulation, no training
###
### Scheme constructors need a z-score stats file and the reference reader needs a store, so
### this script writes small synthetic fixtures into data/ and removes them again at the end.

using NeuralParam
using Test
using Lux
using SpeedyWeather
using Random

const NLAYERS     = 8
const SG          = SpectralGrid(trunc = 31, nlayers = NLAYERS)
const FIXTURE     = "_test_compile_L$(NLAYERS)"
const REF_FIXTURE = "_test_compile_ref"



### Fixtures

# Synthetic z-score stats: one mean/std block per name, one group per output form
function make_stats_fixture(nlayers)
    prof(μ, σ) = (; mean = fill(Float32(μ), nlayers), std = fill(Float32(σ), nlayers))
    scal(μ, σ) = (; mean = Float32[μ], std = Float32[σ])

    affine() = (;
        a = prof(-5f-8, 5f-8), b = prof(1f-5, 1f-5),
        c = scal(10, 5), d = scal(0.5, 0.2), e = scal(0.4, 0.2),
        f = scal(-20, 10), g = scal(1.2, 0.3),
    )

    return (;
        inputs = (;
            T   = prof(250, 30),   q   = prof(-4, 1),
            p   = scal(1f5, 5f3),  lat = scal(0, 45),   lf = scal(0.3, 0.4),
            sst = scal(288, 12),   lst = scal(285, 15), Ts = scal(287, 13),
        ),

        direct = (; dT = prof(-1f-5, 1f-5), olw = scal(240, 40), slwd = scal(300, 60)),
        linear = affine(),
        planck = affine(),

        nlayers = nlayers,
        trunc   = 31,
    )
end


# Synthetic sample container, shaped exactly like the one collect_samples returns
#   - the targets are exact affine functions of the form's own predictor, so the fit must
#     recover the coefficients — this is what checks that predictor() is wired into affine_stats
#   - predictors are kept small and well spread, so the Float32 least squares stays conditioned
function make_samples(form = LinearOutput(); npoints = 4, nlayers = 2, nsamples = 8, rng = Xoshiro(1))

    prof() = rand(rng, Float32, npoints, nlayers, nsamples) .* 2f0 .+ 1f0
    scal() = rand(rng, Float32, npoints, nsamples)

    T  = prof()
    Ts = scal() .* 2f0 .+ 1f0

    # Transformed predictors of this output form (identity for linear, ^4 for planck)
    P  = NeuralParam.predictor(form, T)
    Ps = NeuralParam.predictor(form, Ts)

    # Exact coefficients the fit has to reproduce
    co = (; a = -0.2f0, b = 0.5f0, c = 1f0, d = 0.5f0, e = 0.25f0, f = 7f0, g = 2f0)

    s = (;
        # inputs
            T = T, q = prof() .* -1f0, p = scal(), lat = scal(),
            lf = scal(), sst = Ts, lst = Ts, Ts = Ts,
        # targets, built from the predictors with the coefficients above
            dT   = co.a .* P .+ co.b,
            olw  = co.c .+ co.d .* P[:, NeuralParam.mid_layer(nlayers), :] .+ co.e .* Ps,
            slwd = co.f .+ co.g .* P[:, nlayers, :],
    )

    return s, co
end


# Write the fixtures
NeuralParam.save(make_stats_fixture(NLAYERS); dir = stats_dir(FIXTURE), file = "zscore.jld2")

save_store(; dir = reference_dir(REF_FIXTURE), file = "reference.jld2") do store
    grid  = (; temperature = ones(Float32, 4, 2))
    param = (; outgoing_longwave = ones(Float32, 4))

    # day 0 carries a param group, day 1 does not — exercises the verify_state fallback
    store["day_0/full"]  = (; grid = grid, parameterizations = param)
    store["day_0/grid"]  = grid
    store["day_0/param"] = param

    store["day_1/full"]  = (; grid = grid, parameterizations = param)
    store["day_1/grid"]  = grid

    store["full_gap"] = 1
    store["sim_days"] = 1
end



try

@testset "NeuralParam compile & smoke" begin

    @testset "all exported names are defined" begin
        exported  = filter(!=(:NeuralParam), names(NeuralParam))
        undefined = [s for s in exported if !isdefined(NeuralParam, s)]
        isempty(undefined) || @warn "Exported but undefined" undefined
        @test isempty(undefined)
    end


    @testset "metrics" begin
        x = Float32[1, 2, 3]; y = Float32[1, 2, 4]
        w = ones(Float32, 3)

        @test NeuralParam.rmse(x, y)  ≈ sqrt(1/3)
        @test NeuralParam.bias(x, y)  ≈ 1/3            # y - x
        @test NeuralParam.wmean(x, w) ≈ 2

        # weighted pair used by both the training log and the rollouts: bias is x - y
        @test NeuralParam.wrmse(x, y, w) ≈ sqrt(1/3)
        @test NeuralParam.wbias(x, y, w) ≈ -1/3

        # weights of mean 1 reproduce the unweighted result
        @test NeuralParam.wrmse(x, y, w) ≈ NeuralParam.rmse(x, y)

        @test NeuralParam.tree_l2norm((; a = Float32[3], b = 4f0)) ≈ 5

        # batch helpers used by the n_batch gradient averaging
        g1 = (; a = Float32[1, 2], b = 1f0)
        g2 = (; a = Float32[3, 4], b = 3f0)
        s  = NeuralParam.tree_add(g1, g2)
        @test s.a == Float32[4, 6] && s.b == 4f0
        h  = NeuralParam.tree_scale(s, 0.5f0)
        @test h.a == Float32[2, 3] && h.b == 2f0
    end


    @testset "zscore math" begin
        @test NeuralParam.zscore(2f0, 1f0, 0.5f0) ≈ 2f0
        @test NeuralParam.inv_zscore(NeuralParam.zscore(3f0, 1f0, 2f0), 1f0, 2f0) ≈ 3f0
        v = Float32[1, 5, 9]
        @test NeuralParam.inv_zscore.(NeuralParam.zscore.(v, 2f0, 3f0), 2f0, 3f0) ≈ v

        # non-finite entries are dropped (sst is NaN over land, lst over ocean)
        @test NeuralParam.mean_std(Float32[1, 3, NaN32]).mean[1] ≈ 2
        @test NeuralParam.mean_std_layers(Float32[1 NaN32; 3 5]).mean ≈ Float32[2, 5]
    end


    @testset "utils" begin
        @test steps_from_days(1, 1800) == 48
        @test days_from_steps(48, 1800) ≈ 1
        @test extract_layer(2, [Float32[1 2; 3 4]]) == [Float32[2, 4]]
    end


    @testset "dirs" begin
        @test occursin("reference", reference_dir("y"))
        @test occursin("stats",     stats_dir("z"))
        @test occursin("schemes",   scheme_dir("x"))
        @test occursin("rollouts",  rollout_dir("w"))
    end


    @testset "input spec and layout" begin
        @test keys(IN_NLW_OBLW) == (:T, :Ts, :lat)
        @test NeuralParam.n_inputs(IN_NLW_OBLW, NLAYERS) == NLAYERS + 2
        @test NeuralParam.input_spec() == (;)

        # the layout maps every input onto its slice of the flat buffer fill_inputs! writes
        lay = NeuralParam.input_layout(IN_NLW_OBLW, NLAYERS)
        @test keys(lay) == (:T, :Ts, :lat)
        @test lay.T == 1:NLAYERS
        @test lay.Ts == NLAYERS+1:NLAYERS+1
        @test lay.lat == NLAYERS+2:NLAYERS+2

        # the layout must cover the buffer exactly, for every registered input
        full = NeuralParam.input_layout(NeuralParam.INPUTS, NLAYERS)
        @test keys(full) == keys(NeuralParam.INPUTS)
        @test last(last(values(full))) == NeuralParam.n_inputs(NeuralParam.INPUTS, NLAYERS)
    end


    @testset "output forms" begin
        for form in (LinearOutput(), PlanckOutput())
            @test NeuralParam.n_outputs(form, NLAYERS) == 2 * NLAYERS + 5
            @test output_keys(form) == (:a, :b, :c, :d, :e, :f, :g)
        end

        @test NeuralParam.n_outputs(DirectOutput(), NLAYERS) == NLAYERS + 2
        @test output_keys(DirectOutput()) == (:dT, :olw, :slwd)

        @test output_group(DirectOutput()) === :direct
        @test output_group(LinearOutput()) === :linear
        @test output_group(PlanckOutput()) === :planck

        @test NeuralParam.mid_layer(NLAYERS) == NLAYERS ÷ 2
        @test NeuralParam.predictor(LinearOutput(), Float32[2, 3]) == Float32[2, 3]
        @test NeuralParam.predictor(PlanckOutput(), Float32[2, 3]) == Float32[16, 81]
    end


    @testset "decode! writes tendencies and returns fluxes" begin
        # Y layout (affine forms): a(1:n), b(n+1:2n), c, d, e, f, g
        n     = 2
        Y     = Float32[2, 3,  10, 20,  1, 0.5, 0.25,  7, 2]
        state = (; T_prof = Float32[100, 200], Ts = 300f0, nlayers = n)
        k_olw = NeuralParam.mid_layer(n)

        dTdt = zeros(Float32, n)
        olw, slwd = NeuralParam.decode!(LinearOutput(), dTdt, Y, state)
        @test dTdt ≈ Float32[2*100 + 10, 3*200 + 20]                        # dT = a*T + b
        @test olw  ≈ 1f0 + 0.5f0*state.T_prof[k_olw] + 0.25f0*300f0         # c + d*T[k] + e*Ts
        @test slwd ≈ 7f0 + 2f0*200f0                                        # f + g*T[nlayers]

        # decode! ACCUMULATES into dTdt, it does not overwrite
        NeuralParam.decode!(LinearOutput(), dTdt, Y, state)
        @test dTdt ≈ Float32[2*(2*100 + 10), 2*(3*200 + 20)]

        # Y must not be modified
        @test Y == Float32[2, 3,  10, 20,  1, 0.5, 0.25,  7, 2]

        # PlanckOutput is the same form on the 4th power of the predictors
        dTp = zeros(Float32, n)
        olwp, slwdp = NeuralParam.decode!(PlanckOutput(), dTp, Y, state)
        @test dTp  ≈ Float32[2*100f0^4 + 10, 3*200f0^4 + 20]
        @test olwp ≈ 1f0 + 0.5f0*state.T_prof[k_olw]^4 + 0.25f0*300f0^4
        @test slwdp ≈ 7f0 + 2f0*200f0^4

        # DirectOutput passes dT/olw/slwd straight through and reads only nlayers
        Yd  = Float32[1, 2, 3, 4]
        dTd = zeros(Float32, n)
        olwd, slwdd = NeuralParam.decode!(DirectOutput(), dTd, Yd, (; nlayers = n))
        @test dTd == Float32[1, 2]
        @test olwd == 3f0 && slwdd == 4f0
    end


    @testset "statistics recover known coefficients" begin
        nlayers = 2
        s, _ = make_samples(; nlayers)

        # input stats follow the registry: profiles get one pair per layer, scalars one
        istats = NeuralParam.input_stats(s, NeuralParam.input_spec(:T, :Ts))
        @test keys(istats) == (:T, :Ts)
        @test length(istats.T.mean) == nlayers
        @test length(istats.Ts.mean) == 1

        # every affine form must recover the coefficients its own samples were built from
        for form in (LinearOutput(), PlanckOutput())
            sf, co = make_samples(form; nlayers)
            fit = NeuralParam.output_stats(form, sf)

            @test keys(fit) == output_keys(form)
            @test all(≈(co.a; rtol = 1f-2), fit.a.mean)
            @test all(≈(co.b; rtol = 1f-2), fit.b.mean)
            @test fit.c.mean[1] ≈ co.c rtol = 1f-2
            @test fit.d.mean[1] ≈ co.d rtol = 1f-2
            @test fit.e.mean[1] ≈ co.e rtol = 1f-2
            @test fit.f.mean[1] ≈ co.f rtol = 1f-2
            @test fit.g.mean[1] ≈ co.g rtol = 1f-2
        end

        # direct stats are plain moments of the targets
        dir = NeuralParam.output_stats(DirectOutput(), s)
        @test keys(dir) == output_keys(DirectOutput())
        @test length(dir.dT.mean) == nlayers

        # every form must return exactly the keys ZScoreStats will look for
        for form in (DirectOutput(), LinearOutput(), PlanckOutput())
            @test keys(NeuralParam.output_stats(form, s)) == output_keys(form)
        end
    end


    @testset "ZScoreStats assembly" begin
        # inputs are concatenated in spec order: T(1:8), Ts(9), lat(10)
        z = ZScoreStats(FIXTURE, IN_NLW_OBLW, LinearOutput(), NLAYERS)
        @test length(z.input_mean) == NLAYERS + 2
        @test z.input_mean[1:NLAYERS] == fill(250f0, NLAYERS)
        @test z.input_mean[NLAYERS+1] == 287f0        # Ts
        @test z.input_mean[NLAYERS+2] == 0f0          # lat
        @test all(>(0), z.input_std)
        @test z.zscore_name == FIXTURE

        # outputs follow output_keys: a(1:8), b(9:16), c, d, e, f, g
        @test length(z.output_mean) == 2 * NLAYERS + 5
        @test z.output_mean[2*NLAYERS+1] == 10f0      # c
        @test z.output_mean[2*NLAYERS+5] == 1.2f0     # g
        @test eltype(z.output_mean) == Float32

        # every output form finds its own group in the file
        for form in (DirectOutput(), LinearOutput(), PlanckOutput())
            zf = ZScoreStats(FIXTURE, (;), form, NLAYERS)
            @test length(zf.output_mean) == NeuralParam.n_outputs(form, NLAYERS)
        end

        # ConstLW selects no inputs at all
        @test isempty(ZScoreStats(FIXTURE, (;), LinearOutput(), NLAYERS).input_mean)

        # guards
        @test_throws ErrorException ZScoreStats(FIXTURE, IN_NLW_OBLW, LinearOutput(), NLAYERS - 1)
        @test_throws ErrorException NeuralParam.collect_stats(
            make_stats_fixture(NLAYERS).inputs, (:nope,), FIXTURE, "input")

        @test load_zscore(FIXTURE).nlayers == NLAYERS
    end


    @testset "ConstLW construct / update / info" begin
        s1 = ConstLW(SG, LinearOutput(), FIXTURE)
        @test s1 isa ConstLW && s1 isa SpeedyWeather.AbstractLongwave
        @test s1.n_out == 2 * NLAYERS + 5
        @test all(iszero, s1.ps)                      # zeros = calibrated mean

        ps2 = fill(0.5f0, s1.n_out)
        s2  = NeuralParam.update_ps(s1, ps2)
        @test s2.ps == ps2
        @test s2.zscore === s1.zscore                 # everything else preserved
        @test all(iszero, s1.ps)                      # original untouched

        info = info_scheme(s1)
        @test info.scheme == "ConstLW"
        @test info.output_form == "LinearOutput"
        @test info.zscore_stats == FIXTURE

        @test ConstLW(SG, DirectOutput(), FIXTURE).n_out == NLAYERS + 2
        @test ConstLW(SG, PlanckOutput(), FIXTURE).n_out == 2 * NLAYERS + 5
    end


    @testset "NeuralLW construct / update / forward" begin
        cfg = MLPConfig(n_hidden = 1, width = 8)
        nlw = NeuralLW(SG, cfg, IN_NLW_OBLW, LinearOutput(), FIXTURE)

        @test nlw isa NeuralLW && nlw isa SpeedyWeather.AbstractLongwave
        @test nlw.n_in  == NLAYERS + 2
        @test nlw.n_out == 2 * NLAYERS + 5
        @test length(nlw.input_buffer) == nlw.n_in

        # forward pass produces the right output size / eltype
        Y, _ = Lux.apply(nlw.nn, zeros(Float32, nlw.n_in), nlw.ps, nlw.st)
        @test length(Y) == nlw.n_out
        @test eltype(Y) == Float32

        # update_ps rebuilds with new ps and preserves nn / st / arch / zscore
        nlw2 = NeuralParam.update_ps(nlw, nlw.ps)
        @test nlw2.nn          === nlw.nn
        @test nlw2.st          === nlw.st
        @test nlw2.arch_config === nlw.arch_config
        @test nlw2.zscore      === nlw.zscore

        info = info_scheme(nlw)
        @test info.scheme == "NeuralLW"
        @test info.inputs == ["T", "Ts", "lat"]
        @test info.width  == cfg.width               # info_arch merged in
    end


    @testset "MLP architecture" begin
        cfg = MLPConfig()
        nn, ps, st = NeuralParam.setup_arch(cfg, 8, 16)
        @test nn !== nothing
        @test NeuralParam.info_arch(cfg).width == cfg.width
    end


    @testset "configs" begin
        @test RunConfig() isa RunConfig
        @test RunConfig().loss_config === nothing

        lc = LossConfig(SG, FIXTURE)
        @test lc.weights.T == 1f0 && lc.weights.olw == 1f0 && lc.weights.slwd == 1f0
        @test length(lc.field_norm.T) == NLAYERS
        @test lc.field_norm.olw  == 40f0
        @test lc.field_norm.slwd == 60f0
        @test RunConfig(loss_config = lc).loss_config === lc

        # explicit weights are carried through
        lc2 = LossConfig(SG, FIXTURE; weights = (; T = 1f0, olw = 0f0, slwd = 0f0))
        @test lc2.weights.olw == 0f0

        # nlayers mismatch is rejected at construction
        @test_throws ErrorException LossConfig(
            SpectralGrid(trunc = 31, nlayers = NLAYERS - 1), FIXTURE)
    end


    @testset "area weights" begin
        w = NeuralParam.area_weights(SG)
        @test length(w) == SG.npoints            # one weight per grid point, not per ring
        @test w isa AbstractVector               # NOT reshaped: must broadcast against (npoints,) fluxes
        @test all(>(0), w)
        @test sum(w) / length(w) ≈ 1 rtol=1e-5   # normalized to mean 1
    end


    @testset "probes and rollout reduction" begin
        @test keys(PROBES) == (:T, :olw, :slwd, :slwu)

        # column helpers: profiles have one entry per layer, scalars exactly one
        v = Float32[1, 2, 3]; m = Float32[1 2; 3 4]
        @test NeuralParam.n_cols(v) == 1
        @test NeuralParam.n_cols(m) == 2
        @test NeuralParam.get_col(v, 1) == v
        @test NeuralParam.get_col(m, 2) == Float32[2, 4]

        # rmse combines over the column dimension in quadrature, bias as a mean
        a = cat(fill(3.0, 2, 2), fill(4.0, 2, 2); dims = 3)      # (day, traj, col)
        @test NeuralParam.reduce_cols(a, :rmse) ≈ fill(sqrt(12.5), 2, 2, 1)
        @test NeuralParam.reduce_cols(a, :bias) ≈ fill(3.5, 2, 2, 1)

        # a reduced curve has one entry per lead day
        r = (; days = 1:2, err = (; T = (; rmse = a, bias = a)))
        @test length(rollout_curve(r, :T, :rmse)) == 2
        @test rollout_curve(r, :T, :bias; layer = 1) ≈ [3.0, 3.0]
    end


    @testset "reference store" begin
        with_reference(REF_FIXTURE) do ref
            @test ref.sim_days == 1
            @test ref.full_gap == 1
            @test NeuralParam.restart_days(ref) == 0:1:1

            # day 0 has a param group and is read without touching the full state
            vs = verify_state(ref, 0)
            @test vs.grid.temperature == ones(Float32, 4, 2)
            @test vs.parameterizations.outgoing_longwave == ones(Float32, 4)

            # day 1 has none, so verify_state falls back to the full state
            vs1 = verify_state(ref, 1)
            @test vs1.grid.temperature == ones(Float32, 4, 2)
            @test vs1.parameterizations.outgoing_longwave == ones(Float32, 4)

            # the full state is what a rollout restarts from
            @test ref[0].grid.temperature == ones(Float32, 4, 2)
            @test grid_state(ref, 0).temperature == ones(Float32, 4, 2)
        end
    end


    @testset "save / load roundtrip" begin
        s   = ConstLW(SG, LinearOutput(), FIXTURE)
        s   = NeuralParam.update_ps(s, collect(1f0:s.n_out))
        dir = mktempdir()
        NeuralParam.save(s; dir, file = "s.jld2")
        s_loaded = NeuralParam.load(; dir, file = "s.jld2")
        @test s_loaded isa ConstLW
        @test s_loaded.ps == s.ps
        @test s_loaded.zscore.output_mean == s.zscore.output_mean
    end


    @testset "csv logging roundtrip" begin
        dir = mktempdir()
        metrics = (; loss_total = 1f0, rmse_T = 4f0, bias_T = 5f0)

        NeuralParam.csv_init(keys(metrics); dir, file = "t.csv")
        NeuralParam.csv_row!(1, 2, 5, 1f-2; metrics, dir, file = "t.csv")

        df = NeuralParam.csv_read(; dir, file = "t.csv")
        @test size(df, 1) == 1
        @test propertynames(df) == [:ic, :traj, :n_steps, :eta, :loss_total, :rmse_T, :bias_T]
        @test df.loss_total[1] == 1f0 && df.rmse_T[1] == 4f0
    end


    @testset "write_info / out dirs" begin
        dir = mktempdir()
        write_info(; dir, file = "i.toml", a = 1, b = 2.0, c = (; d = 3), e = [1, 2, 3])
        @test isfile(joinpath(dir, "i.toml"))

        base = mktempdir()
        d = prepare_out_dir(base, "run1")
        @test isdir(d)
        @test_throws ErrorException prepare_out_dir(base, "run1")   # overwrite protection
        @test isdir(fresh_out_dir(base, "run1"))                    # fresh_ overwrites
    end

end

finally
    rm(stats_dir(FIXTURE);         recursive = true, force = true)
    rm(reference_dir(REF_FIXTURE); recursive = true, force = true)
end

println("COMPILE_OK")

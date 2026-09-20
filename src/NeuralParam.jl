module NeuralParam


using SpeedyWeather

using Lux
using Optimisers

using Enzyme
using Checkpointing

import JLD2
using CSV
using DataFrames
using TOML

using Random
using Dates
using Statistics
using LinearAlgebra

using CairoMakie
using GeoMakie
using RingGrids

using Accessors





export
        ### utils
        # io.jl
                        #ROOT,
                raw_data_dir,
                restart_states_dir,
                column_io_dir,
                zscore_dir,
                emulator_dir,
                rollout_dir,
                prepare_out_dir,
                        #save,
                        #load,
                        #load_run,
                collect_runs,
                collect_schemes,
                collect_rollouts,
                save_figure,
                        #csv_init,
                        #csv_row!,
                        #csv_read,
                write_info,
                        #info_value,
                        #git_info,
                provenance,
        # overrides.jl
                checked_merge,
                print_unit_config,
                        #short_string,
        # probes.jl
                        #S0,
                PROBES,
                WEATHER_PROBES,
                CLIMATE_PROBES,
        # statistics.jl
                        #rmse,
                        #bias,
                        #correlation,
                        #maxdiff,
                        #wmean,
                        #wrmse,
                        #wbias,
                        #field_mse,
                        #area_weights,
                        #fit_linear,
        # simulation.jl
                        #perturb_grid_field!,
                        #sim_timesteps!,
                        #spinup_leapfrog!,
                        #force_reinitialize!,
                        #restart_from!,
                        #steps_from_days,
                        #days_from_steps,
                        #flux_to_dT_fac,

        ### emulators
        # abstract_longwave.jl
                        #AbstractEmulatorLW,
        # input.jl
                        #in_T,
                        #in_log10q,
                        #in_sst,
                        #in_lst,
                        #in_lf,
                        #in_sinlat2,
                        #in_p,
                        #in_Usfc,
                        #INPUTS,
                        #input_spec,
                        #n_inputs,
                        #input_layout,
                        #fill_inputs!,
        # output.jl
                        #mid_layer,
                DirectOutput,
                LinearOutput,
                PlanckOutput,
                        #output_group,
                        #output_keys,
                        #pred,
                        #decode!,
                        #decode,
                        #write_lw!,
        # emulator_zero.jl
                ZeroLW,
                        #update_ps,
        # emulator_const.jl
                ConstLW,
        # emulator_neural.jl
                NeuralLW,
        # utils_scheme.jl
                build_scheme,
                info_scheme,
                        #apply_offline,
                        #offline_parts,
                        #emulator_inputs,
                check_continuation,

        ### data
        # zscore.jl
                        #zscore,
                        #inv_zscore,
                        #ZScoreStats,
                        #collect_zscore,
                        #collect_center,
        # generate_raw_data.jl
                generate_raw_data,
                        #RawData,
                        #with_raw_data,
        # derive_restart_states.jl
                derive_restart_states,
                        #restart_file,
                        #restart_state,
        # derive_column_io.jl
                derive_column_io,
                        #create_column_io,
                        #fill_targets!,
                        #reconstruct_net_flux,
                        #check_net_flux,
        # derive_zscore.jl
                derive_zscore,
                fit_coeffs,
                        #field_stats,
                        #coeff_stats,
                        #mean_std,
                        #mean_std_layers,
        # generate_rollout.jl
                generate_rollout,
                        #rollout_weather,
                        #rollout_climate,
                        #get_layer,

        ### architectures
        # abstract_arch.jl
                        #AbstractArchConfig,
        # mlp.jl
                MLPConfig,
                        #info_arch,
                        #setup_arch,
        # rnn.jl
                RNNConfig,
                        #VerticalRNN,
                        #step_cell,
                        #layer_features,
                        #sweep_up,
                        #sweep_down,

        ### training
        # param_trees.jl
                        #tree_l2sum,
                        #tree_l2norm,
                        #tree_add,
                        #tree_scale,
        # loss.jl
                        #loss,
                LossConfig,
                LossConfigOffline,
                        #batch_config,
                        #zscore_norm_weights,
                        #loss_offline,
                        #residuals_offline,
                        #loss_online,
                        #residuals_online,
                        #seed_loss,
        # config.jl
                TrainConfigOffline,
                TrainConfigOnline,
        # gradients.jl
                        #compute_gradients,
                        #checkpointed_timesteps!,
        # setup.jl
                        #setup_optimiser,
                        #setup_target,
                        #extract_set,
                        #take_batch,
                        #setup_simulations,
                        #prepare_reference,
                        #pick_restart_state,
        # logging.jl
                        #compute_metrics,
                        #print_config,
                        #eta_budget,
        # training_online.jl
                        #training_online,
        # training_offline.jl
                        #training_offline,
        # run_training.jl
                run_training,
                        #train,

        ### evaluation
        # style.jl
                JL_BLUE,
                JL_GREEN,
                JL_RED,
                JL_PURPLE,
                FIELD_COLORS,
                        #base_style,
                        #probes_style,
                        #correlation_style,
                        #hist_style,
                        #training_style,
                        #shares_style,
                        #rmse_style,
                        #heatmap_style,
                        #lonlat_style,
                        #growth_style,
                        #profile_style,
                        #zonal_style,
                        #drift_style,
                        #skill_style,
                        #probe_label,
                        #metric_label,
                        #axis_label,
                        #look_of,
                        #unit_names,
                        #n_legend_entries,
                        #grid_shape,
                        #new_figure,
                        #panel,
                        #add_legend!,
                        #add_title!,
                        #positive,
        # maps.jl
                        #color_scale,
                        #lonlat_matrix,
                plot_lonlat,
                plot_zonal,
        # raw_data.jl
                        #sample_axis,
                global_means,
                ic_distance,
                running_mean,
                rmse_caps,
                mean_curves,
                growth_rate,
                plot_probes,
        # dataset.jl
                        #n_layers,
                        #flat_layer,
                        #layer_name,
                        #thin_sample,
                plot_correlation,
                plot_hist,
        # training.jl
                        #block_mean,
                        #block_ends,
                        #val_rows,
                        #rmse_label,
                        #rmse_scale,
                plot_training,
                plot_loss_shares,
                plot_rmse,
                save_training_plots,
                summarize_series,
                        #epoch_settled,
        # rollout_common.jl
                        #day_index,
                        #traj_stats,
                        #draw_curve!,
        # rollout_weather.jl
                        #reduce_metric,
                weather_growth,
                weather_profile,
                weather_zonal,
                weather_skill,
                plot_weather_growth,
                plot_weather_profile,
                plot_weather_zonal,
        # rollout_climate.jl
                        #year_bias,
                        #crop,
                        #translate_metric,
                climate_drift,
                climate_lonlat,
                climate_zonal,
                climate_skill,
                plot_climate_drift,
                plot_climate_lonlat,
                plot_climate_zonal,
        # rollout_skill.jl
                test_reference,
                skill_table,
                plot_skill_plane




# General utils
include("utils/io.jl")
include("utils/overrides.jl")
include("utils/probes.jl")
include("utils/statistics.jl")
include("utils/simulation.jl")


# Emulators
include("emulators/abstract_longwave.jl")
include("emulators/input.jl")
include("emulators/output.jl")
include("emulators/emulator_zero.jl")
include("emulators/emulator_const.jl")
include("emulators/emulator_neural.jl")
include("emulators/utils_scheme.jl")


# Data
include("data/zscore.jl")
include("data/generate_raw_data.jl")
include("data/derive_restart_states.jl")
include("data/derive_column_io.jl")
include("data/derive_zscore.jl")
include("data/generate_rollout.jl")


# Architectures
include("architectures/abstract_arch.jl")
include("architectures/mlp.jl")
include("architectures/rnn.jl")


# Training
include("training/param_trees.jl")
include("training/loss.jl")
include("training/config.jl")
include("training/gradients.jl")
include("training/setup.jl")
include("training/logging.jl")
include("training/training_online.jl")
include("training/training_offline.jl")
include("training/run_training.jl")


# Evaluation
include("evaluation/style.jl")
include("evaluation/maps.jl")
include("evaluation/raw_data.jl")
include("evaluation/dataset.jl")
include("evaluation/training.jl")
include("evaluation/rollout_common.jl")
include("evaluation/rollout_weather.jl")
include("evaluation/rollout_climate.jl")
include("evaluation/rollout_skill.jl")

end

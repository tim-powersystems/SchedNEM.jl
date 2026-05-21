"""
    get_system_parameters(res, t, max_horizon, genOpDetails)

# Extract all the relevant parameters from the results object to get the correct initial conditions for the model for reoptimisation
"""
function get_system_parameters(res, t, max_horizon, genOpDetails, genAvSample)

    # Extract all the relevant parameters from the results object to get the correct initial conditions for the model
    initial_soc_stor = (t == 1 ? [] : res.stor_energy[:, t - 1]) # Initial state of charge of storage at the start of the event
    initial_soc_genstor = (t == 1 ? [] : res.genstor_energy[:, t - 1]) # Initial state of charge of genstorage at the start of the event

    if genOpDetails.ramping
        p_gen_initial = (t == 1 ? [] : res.p_gen[:, t - 1] .* genAvSample[:, t - 1]) # Initial generation at the start of the event, needed for ramping constraints
    else
        p_gen_initial = []
    end

    if genOpDetails.uc
        gon_initial = (t == 1 ? [] : res.gon[:, t - 1] .* genAvSample[:, t - 1]) # Initial commitment status of generators at the start of the event
        
        # Startup/shutdown profile of generators before the event, needed for startup and shutdown constraints (pad with leading zeros, if t is smaller than max_horizon)
        stup_before = hcat(fill(0, size(res.stup, 1), max(0, max_horizon - t + 1)), res.stup[:, max(1, t - max_horizon):t - 1]) 
        shdw_before = hcat(fill(0, size(res.shdw, 1), max(0, max_horizon - t + 1)), res.shdw[:, max(1, t - max_horizon):t - 1]) # Shutdown profile of generators before the event, needed for shutdown constraints

        # Given that this is just the initial status before the event, it is okay to just set gen_fail_before at the last timestep to 1 if generator is out
        gen_fail_before = zeros(Int, size(genAvSample, 1), max_horizon)
        gen_fail_before[:, end] = (genAvSample[:, max(1, t - 1)] .== 0)
    else
        gon_initial = []
        stup_before = []
        shdw_before = []
        gen_fail_before = []
    end

    return initial_soc_stor, initial_soc_genstor, p_gen_initial, gon_initial, stup_before, shdw_before, gen_fail_before
end

#%%
"""
        get_all_simulation_windows(df_results, N, Nsamples, statechange_times; default_horizon::Int=24, min_time_after_event::Int=4)

Function to calculate the simulation windows for reoptimisation for each sample.

"""
function get_all_simulation_windows(df_results, N, Nsamples, statechange_times; default_horizon::Int=24, min_time_after_event::Int=4)

    # If df_results is a string, use the get_all_events function to create the dataframe from the results files
    if typeof(df_results) <: String
        df_results = PRASNEM.get_all_events(df_results)
    end

    all_simulation_times = [(start_idxs=[], end_idxs=[], sim_time=[]) for _ in 1:Nsamples]
    for group in DataFrames.groupby(df_results, :sample)
        sample = group.sample[1]

        # Calculate the last state change time before each event in this sample (i.e. the last outage that occurred before the event)
        simulation_start_times = statechange_times[sample][[findlast(statechange_times[sample] .<= group.start_index[i]) for i in 1:DataFrames.nrow(group)]]
        
        # Calculate all the timesteps that should be simulated for this sample
        timesteps_to_simulate = zeros(Int, N)
        for i in 1:DataFrames.nrow(group)
            start_time = simulation_start_times[i]
            end_time = min(max(start_time + default_horizon - 1, group.end_index[i] + min_time_after_event), N)
            timesteps_to_simulate[start_time:end_time] .= 1
        end
        diff = vcat([timesteps_to_simulate[1] > 0 ? 1 : 0], timesteps_to_simulate[2:end] .- timesteps_to_simulate[1:end-1], [timesteps_to_simulate[end] > 0 ? -1 : 0])
        start_indices = findall(diff .== 1)
        end_indices = findall(diff .== -1) .- 1

        all_simulation_times[sample] = (start_idxs=start_indices, end_idxs=end_indices, sim_time=end_indices .- start_indices .+ 1)
    end

    return all_simulation_times
end
#%%
"""

"""
function run_reoptimisation_perfect_foresight(m, res, sys, start_idx, end_idx, genAvSample, lineAvSample)
    
    optimisation_window = m[:N]
    move_forward = m[:move_forward]

    # Return object to store the load shedding results
    load_shedding = zeros(Int, length(sys.regions.names), end_idx - start_idx + 1)
    
    # Get the initial model parameters from the res object values
    initial_soc_stor, initial_soc_genstor, p_gen_initial, gon_initial, stup_before, shdw_before, gen_fail_before = get_system_parameters(res, start_idx, optimisation_window, m[:genOpDetails], genAvSample)      

    # Now run the rolling horizon simulation and save the load shedding results
    simulation_start_idxs = start_idx:move_forward:(end_idx - 1)
    for t in simulation_start_idxs
        t_end = min(t + optimisation_window - 1, end_idx)

        # Determine initial state of charge for storages and generator-storages
        if t > simulation_start_idxs[1] # Not for fist time-step
            if m[:Nstors] > 0
                initial_soc_stor = value.(m[:e_stor])[:,move_forward]
            end
            if m[:Ngenstors] > 0
                initial_soc_genstor = value.(m[:e_genstor])[:,move_forward]
            end
            if m[:genOpDetails].ramping
                # get the generation at the last time step of previous window
                p_gen_initial = value.(m[:p_gen])[:,move_forward]
            end
            if m[:genOpDetails].uc
                # Get the commitment status, start-up and shut-down at the last time step of previous window
                gon_initial = value.(m[:gon])[:,move_forward]

                stup_before = zeros(size(m[:stup_before][:,:]))
                shdw_before = zeros(size(m[:shdw_before][:,:]))
                # Shift the startup and shutdown indicators
                stup_before[:,1:move_forward] = value.(m[:stup_before])[:,move_forward+1:end] # Get the earlier time steps from the second previous optimisation
                stup_before[:,move_forward+1:end] = value.(m[:stup])[:,1:move_forward] # Get the last time steps from within the previous optimisation
                shdw_before[:,1:move_forward] = value.(m[:shdw_before])[:,move_forward+1:end]
                shdw_before[:,move_forward+1:end] = value.(m[:shdw])[:,1:move_forward]
            end
        end

        # Update model parameters
        update_model_parameters!(m, sys, t; 
            initial_soc_stor=initial_soc_stor, initial_soc_genstor=initial_soc_genstor,
            end_index=t_end,
            p_gen_initial=p_gen_initial, gon_initial=gon_initial, stup_before=stup_before, shdw_before=shdw_before)
        
        # Update the generation and line availability for this time step
        updateGenAvailabilityFullHorizon!(m, genAvSample, t; end_index=t_end)
        updateLineAvailabilityFullHorizon!(m, sys, t, lineAvSample; end_index=t_end)

        # Optimize the model
        optimize!(m)
        
        if !is_solved_and_feasible(m)
            @warn "Optimization failed at time step $start_idx. Ending simulation and returning infeasible model."
            return m
        end

        load_shedding[:,(t - start_idx + 1):(t_end - start_idx + 1)] = round.(Int, value.(m[:load_shedding][:, 1:(t_end - t + 1)]))

    end

    return load_shedding
end

#%%
"""

"""
function run_reoptimisation_imperfect_foresight(m, res, sys, start_idx, end_idx, genAvSample, lineAvSample, statechange_times_sample)
    
    optimisation_window = m[:N]
    move_forward_max = m[:move_forward]

    @assert move_forward_max <= optimisation_window "Error: move_forward should be less than or equal to the optimisation window to ensure that the model is updated with the new availability information at each step."

    # Return object to store the results
    #load_shedding = zeros(Int, length(sys.regions.names), end_idx - start_idx + 1)
    res_out = SchedData(sys; N=end_idx - start_idx + 1)
    
    # Get the initial model parameters from the res object values
    initial_soc_stor, initial_soc_genstor, p_gen_initial, gon_initial, stup_before, shdw_before, gen_fail_before = get_system_parameters(res, start_idx, optimisation_window, m[:genOpDetails], genAvSample)      

    # Initial parameters for DSP maxEnergy constraint (assume that normal operation doesn't lead to DSP activation)
    # TODO: Remove these assumptions and get the values from the res_out
    drs_borrow_before = []
    drs_remaining_energy_included_time = 0

    # Now run the rolling horizon simulation and save the load shedding results
    t = start_idx # First simulation at the start_idx
    while t <= end_idx
        
        # =========================================================
        # SCHEDULE THE SYSTEM

        # Determine the end of the optimisation
        t_end = min(t + optimisation_window - 1, end_idx)

        # Update model parameters
        update_model_parameters!(m, sys, t; 
            initial_soc_stor=initial_soc_stor, initial_soc_genstor=initial_soc_genstor,
            end_index=t_end,
            p_gen_initial=p_gen_initial, gon_initial=gon_initial, stup_before=stup_before, shdw_before=shdw_before,
            gen_fail_before=gen_fail_before, drs_borrow_before=drs_borrow_before, drs_remaining_energy_included_time=drs_remaining_energy_included_time)
        
        # Update the generation and line availability from t for the whole optimisation window
        updateGenAvailabilityStep!(m, genAvSample, t) # end index is not needed since not updating from sys
        updateLineAvailabilityStep!(m, sys, lineAvSample, t; end_index=t_end) # passing end index because we need to get the line capacity from sys for the future time steps, not just the current time step

        # Optimize the model
        optimize!(m)

        # Optional - temporary plotting to check the results at each step
        #plot_timeseries_results(m, sys; region=[5,6,7,8], title="Start_idx: $t")
        #Plots.xticks!(1:2:length(t:t_end), string.(t:2:t_end))
        #Plots.xlims!(0.5, length(t:t_end)+0.5)
        #Plots.savefig("./_temp/dispatch_start_idx_$(t).png")
        #println("Storage energy for region 7 at $t: $(sum(value.(m[:e_stor])[:,1]))")
        #non_tas_genstors = setdiff(1:length(sys.generatorstorages.names), sys.region_genstor_idxs[10]) 
        #println("GenStor energy for all: $(sum(value.(m[:e_genstor])[non_tas_genstors,1]))")
        #println("DSP 35 borrowing $t - $(t_end): \n", value.(m[:p_borrow_drs])[sys.region_dr_idxs[7][5],1:(t_end - t + 1)])
        
        if !is_solved_and_feasible(m)
            @warn "Optimization failed for $t - $t_end (full window: $start_idx - $end_idx). Ending simulation for this horizon and returning load shedding results. Conflicting constraints:"

            # Try to compute the conflict and print it
            compute_conflict!(m)
            if get_attribute(m, MOI.ConflictStatus()) == MOI.CONFLICT_FOUND
                iis_model, _ = copy_conflict(m)
                print(iis_model)
            end

            return res_out
        end

        # =========================================================
        # READ OUT RESULTS AND GET NEXT STEP

        res_temp = get_results(m)
        res_out = update_SchedData!(res_out, t - start_idx + 1:t_end - start_idx + 1, res_temp, 1:(t_end - t + 1))

        # Read out load shedding for the whole optimisation window
        #load_shedding[:,(t - start_idx + 1):(t_end - start_idx + 1)] = round.(Int, value.(m[:load_shedding][:, 1:(t_end - t + 1)]))

        # Find the next time step for the simualation
        if isnothing(findfirst(statechange_times_sample .> t))
            next_state_change_time = end_idx + 1 # No more state changes, so we can theoretically move to the end of the simulation
        else
            next_state_change_time = statechange_times_sample[findfirst(statechange_times_sample .> t)]
        end
        move_forward = min(next_state_change_time - t, move_forward_max)

        # Move the simulation forward by the move_forward parameter, or to the next state change time, whichever comes first
        t = t + move_forward
        # If the next time step is after the end of the simulation, end the simulation
        if t > end_idx
            break
        end

        # =========================================================
        # UPDATE THE INITIAL CONDITIONS FOR THE NEXT OPTIMISATION BASED ON THE RESULTS OF THIS OPTIMISATION

        # Extract the results from the solution
        #res_temp = get_results(m)

        # Get the initial state of charge for storages and generator-storages from the results
        if m[:Nstors] > 0
            initial_soc_stor = res_temp.stor_energy[:,move_forward]
        end
        if m[:Ngenstors] > 0
            initial_soc_genstor = res_temp.genstor_energy[:,move_forward]
        end
        if m[:genOpDetails].ramping
            # get the generation at the last time step of previous window
            p_gen_initial = value.(m[:p_gen])[:,move_forward]
        end
        if m[:genOpDetails].uc
            # Get the commitment status, start-up and shut-down at the last time step of previous window
            gon_initial = res_temp.gon[:,move_forward]

            stup_before = zeros(size(m[:stup_before][:,:]))
            shdw_before = zeros(size(m[:shdw_before][:,:]))
            
            # Shift the startup and shutdown indicators 
            stup_before[:,1:end-move_forward] = parameter_value.(m[:stup_before])[:,move_forward+1:end] # Get the earlier time steps from the second previous optimisation
            stup_before[:,end-move_forward+1:end] = res_temp.stup[:,1:move_forward] # Get the last time steps from within the previous optimisation
            shdw_before[:,1:end-move_forward] = parameter_value.(m[:shdw_before])[:,move_forward+1:end]
            shdw_before[:,end-move_forward+1:end] = res_temp.shdw[:,1:move_forward]

            gen_fail_before = zeros(size(m[:gen_fail_before][:,:]))
            gen_fail_before[:,1:end-move_forward] = parameter_value.(m[:gen_fail_before])[:,move_forward+1:end] # Get the earlier time steps from the second previous optimisation
            gen_fail_before[:,end-move_forward+1:end] = parameter_value.(m[:gen_fail])[:,1:move_forward] # Get the last time steps from within the previous optimisation
        end

        if m[:Ndrs] > 0 
            # Get the DSP activation and borrowed energy for the last time steps of the previous optimisation to update the initial conditions for the next optimisation
            drs_borrow_before = zeros(m[:Ndrs])
            drs_remaining_energy_included_time = 0
            if any(res_temp.drs_borrowing[:,1:move_forward] .> 0) # If there is any DSP activation in the last time steps of the previous optimisation
                drs_borrow_before = drs_borrow_before .+ sum(res_temp.drs_borrowing[:,1:move_forward], dims=2)[:] # Get the total borrowed energy in the last time steps of the previous optimisation as the initial borrowed energy for the next optimisation
                drs_remaining_energy_included_time = m[:drs_max_energy_time_window] - move_forward - drs_remaining_energy_included_time # Set the time until which the maxEnergy constraint should be applied for including the borrowed energy before the start of the optimisation (for maxEnergy constraint) to be equal to the move_forward parameter, assuming that the borrowed energy will be paid back within this time frame. This is a simplification, but it allows us to include the effect of DSP activation on the next optimisation.
            end
        end

        # Then go back to the start of the loop and run the next optimisation with the updated initial conditions and availability information
    end

    return res_out
end
"""
    update_model_parameters!(m, sys, start_index; end_index::Int=0, initial_soc_stor=[], initial_soc_genstor=[],
        gon_initial=[], stup_before=[], shdw_before=[], p_gen_initial=[], gen_fail_before=[])

- start_index and end_index are in terms of the time steps in sys, not the model indices.


Ramping: If ramping is activated and p_gen_initial is empty, set p_gen_initial to 0.5 * the max capacity for all generators.
Initial SOC: If initial_soc_stor or initial_soc_genstor are empty, set them to 0% and 50% of energy capacity as defaults, respectively.

"""
function update_model_parameters!(m, sys, start_index; end_index::Int=0, initial_soc_stor=[], initial_soc_genstor=[],
    gon_initial=[], stup_before=[], shdw_before=[], p_gen_initial=[], gen_fail_before=[], 
    drs_borrow_before=[], drs_remaining_energy_included_time::Int=0)

    total_length, _ = PRAS.get_params(sys)

    if total_length < start_index + m[:N] - 1
        end_index = total_length
        N = end_index - start_index + 1
        @debug "Last optimisation window is shorter ($N) than optimisation_window ($(m[:N])) - disabling the remaining time steps."
    else
        N = m[:N]
    end

    # If end_index is not provided or is zero, use the full window length
    if end_index > 0
        if start_index > end_index
            error("Error: start_index should be less than end_index when updating system parameters.")
        end
        # Define the time steps for which parameters will be updated
        t = 1:(end_index - start_index + 1)
        idxs = start_index .+ t .- 1
        # Define the remaining time steps, where the parameters will be set to zero
        remaining_t = (end_index - start_index + 2):(m[:N])
    else
        t = 1:N
        idxs = start_index .+ t .- 1
        # Empty range for remaining time steps, as we are using the full window
        remaining_t = 1:0
    end

    # Some parameters should always be updated for the full window length, to avoid infeasibility.
    t_full = 1:N
    idxs_full = start_index .+ t_full .- 1

    # Extract system parameters
    Nstors = m[:Nstors]
    Ngenstors = m[:Ngenstors]
    Ndrs = m[:Ndrs]
    
    # Update the load in all regions
    set_parameter_value.(m[:dem][:,t], sys.regions.load[:, idxs])
    # If the end_index is less than the full window length, set the remaining load to zero to not have any additional unserved energy
    if end_index < start_index + m[:N] - 1
        set_parameter_value.(m[:dem][:,remaining_t], fill(0.0, size(m[:dem][:,remaining_t])))
    end

    # Update generator capacities
    set_parameter_value.(m[:gen_cap][:,t], sys.generators.capacity[:, idxs])
    # If the end_index is less than the full window length, set the remaining generator capacity to zero
    if end_index < start_index + m[:N] - 1
        set_parameter_value.(m[:gen_cap][:,remaining_t], fill(0.0, size(m[:gen_cap][:,remaining_t])))
    end

    # Update line capacities
    set_parameter_value.(m[:interface_limit_forward][:,t], sys.interfaces.limit_forward[:, idxs])
    set_parameter_value.(m[:interface_limit_backward][:,t], sys.interfaces.limit_backward[:, idxs])

    # Update storage parameters
    if Nstors > 0
        set_parameter_value.(m[:stor_charge_cap][:,t], sys.storages.charge_capacity[:, idxs])
        set_parameter_value.(m[:stor_discharge_cap][:,t], sys.storages.discharge_capacity[:, idxs])
        set_parameter_value.(m[:stor_energy_cap][:,t_full], sys.storages.energy_capacity[:, idxs_full])

        # Storage efficiencies
        set_parameter_value.(m[:stor_carryover_eff][:,t], sys.storages.carryover_efficiency[:, idxs])
        set_parameter_value.(m[:stor_charge_eff][:,t], sys.storages.charge_efficiency[:, idxs])
        set_parameter_value.(m[:stor_discharge_eff_inverse][:,t], 1.0 ./ sys.storages.discharge_efficiency[:, idxs])

        # Update initial state of charge
        if isempty(initial_soc_stor)
            @debug "Initial state of charge for storages not provided. Setting to 0% of energy capacity as a default."
            initial_soc_stor = fill(0.0, Nstors)
        end
        set_parameter_value.(m[:stor_initial_soc][:], initial_soc_stor[:])

        # Set all the remaining times the charge/discharge capacity to zero
        set_parameter_value.(m[:stor_charge_cap][:,remaining_t], fill(0.0, size(m[:stor_charge_cap][:,remaining_t])))
        set_parameter_value.(m[:stor_discharge_cap][:,remaining_t], fill(0.0, size(m[:stor_discharge_cap][:,remaining_t])))
    end

    # Update generator-storage parameters
    if Ngenstors > 0
        set_parameter_value.(m[:genstor_charge_cap][:,t], sys.generatorstorages.gridwithdrawal_capacity[:, idxs])
        set_parameter_value.(m[:genstor_discharge_cap][:,t], sys.generatorstorages.discharge_capacity[:, idxs])
        set_parameter_value.(m[:genstor_energy_cap][:,t_full], sys.generatorstorages.energy_capacity[:, idxs_full])
        set_parameter_value.(m[:genstor_inflow][:,t_full], sys.generatorstorages.inflow[:, idxs_full])

        # Genstor efficiencies
        set_parameter_value.(m[:genstor_carryover_eff][:,t], sys.generatorstorages.carryover_efficiency[:, idxs])
        set_parameter_value.(m[:genstor_charge_eff][:,t], sys.generatorstorages.charge_efficiency[:, idxs])
        set_parameter_value.(m[:genstor_discharge_eff_inverse][:,t], 1.0 ./ sys.generatorstorages.discharge_efficiency[:, idxs])

        # Update initial state of charge
        if isempty(initial_soc_genstor)
            @debug "Initial state of charge for generator-storages not provided. Setting to 0% of energy capacity as a default."
            initial_soc_genstor = fill(0.0, size(sys.generatorstorages.energy_capacity[:,start_index]))
        end
        set_parameter_value.(m[:genstor_initial_soc][:], initial_soc_genstor[:])

        # Set all the remaining times the charge/discharge capacity to zero
        set_parameter_value.(m[:genstor_charge_cap][:,remaining_t], fill(0.0, size(m[:genstor_charge_cap][:,remaining_t])))
        set_parameter_value.(m[:genstor_discharge_cap][:,remaining_t], fill(0.0, size(m[:genstor_discharge_cap][:,remaining_t])))
    end

    # Update demand response parameters
    if Ndrs > 0
        set_parameter_value.(m[:drs_borrow_cap][:,t], sys.demandresponses.borrow_capacity[:, idxs])
        set_parameter_value.(m[:drs_payback_cap][:,t], sys.demandresponses.payback_capacity[:, idxs])
        
        # WARNING: Currently setting the energy interest to -1.0 for all time steps
        #set_parameter_value.(m[:drs_energy_interest][:,t], sys.demandresponses.borrowed_energy_interest[:, idxs])
        set_parameter_value.(m[:drs_energy_interest][:,t], -1.0)
        # If EV exists
        if !isempty(m[:drs_idxs_EV])
            set_parameter_value.(m[:drs_energy_interest][m[:drs_idxs_EV],t], sys.demandresponses.borrowed_energy_interest[m[:drs_idxs_EV], idxs]) # Set the energy interest for EVs to the correct values since they can borrow energy over multiple time steps and the energy needs to be paid back
            set_parameter_value.(m[:drs_energy_cap][m[:drs_idxs_EV],t], sys.demandresponses.energy_capacity[m[:drs_idxs_EV], idxs]) # Set the energy capacity for EVs to the correct values since they can borrow energy over multiple time steps and the energy needs to be paid back
        end

        # Set the borrow capacity for the remaining time steps to the last value
        set_parameter_value.(m[:drs_borrow_cap][:,remaining_t], sys.demandresponses.borrow_capacity[:, idxs[end]]) # Keep the borrow capacity for the remaining time steps to keep the max energy constraint correct
        
        # Set the payback capacity and energy interest for the remaining time steps to zero to not allow any later borrowing
        set_parameter_value.(m[:drs_payback_cap][:,remaining_t], fill(0.0, size(m[:drs_payback_cap][:,remaining_t])))
        set_parameter_value.(m[:drs_energy_interest][:,remaining_t], fill(0.0, size(m[:drs_energy_interest][:,remaining_t])))
        
        # And set the information if DSP has been used before and maxEnergy constraint is activated
        if !isempty(drs_borrow_before)
            # Check that the borrowed energy before the start of the optimisation does not exceed the energy capacity
            for drs in 1:Ndrs
                if sys.demandresponses.borrowed_energy_interest[drs, start_index] > -1.0
                    drs_borrow_before[drs] = min(drs_borrow_before[drs], sys.demandresponses.energy_capacity[drs, start_index])
                else
                    drs_borrow_before[drs] = 0.0 # If interest is -1.0, set the borrowed energy before the start of the optimisation to zero since it cannot be paid back
                end
            end
            set_parameter_value.(m[:drs_borrow_before][:], drs_borrow_before[:]) # Make sure that the borrowed energy before the start of the optimisation does not exceed the energy capacity
        else
            @debug "Borrowed energy before the start of the optimisation not provided for demand response. Setting to zero as a default."
            set_parameter_value.(m[:drs_borrow_before][:], fill(0.0, size(m[:drs_borrow_before][:])))
        end

        # And select the times that should be included in the maxEnergy constraint from before
        set_parameter_value.(m[:drs_remaining_energy_included], 0.0)
        if !iszero(drs_remaining_energy_included_time)
            # Set the time until which the maxEnergy constraint should be applied for including the borrowed energy before the start of the optimisation (for maxEnergy constraint)
            set_parameter_value.(m[:drs_remaining_energy_included][:,1:drs_remaining_energy_included_time], 1.0)
        end
    end

    # Update initial generator on/off status if unit commitment is enabled
    if m[:genOpDetails].uc
        if !isempty(stup_before)
            set_parameter_value.(m[:stup_before][:,:], stup_before[:,:])
        else
            @debug "Start-up indicator values not provided. Setting all to zero at the first time step."
            set_parameter_value.(m[:stup_before][:,:], fill(0.0, size(m[:stup_before][:,:])))
        end
        if !isempty(shdw_before)
            set_parameter_value.(m[:shdw_before][:,:], shdw_before[:,:])
        else
            @debug "Shut-down indicator values not provided. Setting all to zero at the first time step."
            set_parameter_value.(m[:shdw_before][:,:], fill(0.0, size(m[:shdw_before][:,:])))
        end

        if !isempty(gen_fail_before)
            set_parameter_value.(m[:gen_fail_before][:,:], gen_fail_before[:,:])
        else
            @debug "Ramping/UC slack parameter values not provided. Setting all to zero at the first time step (i.e., no failure)."
            set_parameter_value.(m[:gen_fail_before][:,:], fill(0.0, size(m[:gen_fail_before][:,:])))
        end
        # Set the initial gon status
        if !isempty(gon_initial)
            set_parameter_value.(m[:gon_initial][:], gon_initial[:])
        else
            @debug "Initial generator on/off status not provided. Setting all generators to on at the first time step."
            set_parameter_value.(m[:gon_initial][:], fill(1.0, size(m[:gon_initial][:])))
        end
        
        # Make sure that gon_initial fits to the preceeding stup/shdw status before to avoid infeasibility in the first time step 
        # (see function in update_utils.jl for details)
        updateParameters_gon_feasible!(m)
    end

    if m[:genOpDetails].ramping
        # If ramping is activated, also update the ramping limits based on the new generator capacities and the previous time step's generation
        if !isempty(p_gen_initial)
            set_parameter_value.(m[:p_gen_initial][:], p_gen_initial[:])
        else
            #@warn "Initial generation values not provided for ramping. Setting all to half the capacity before first time step."
            set_parameter_value.(m[:p_gen_initial][:], sys.generators.capacity[:, max(idxs[1]-1, 1)] * 0.5) # Set initial generation to 50% of capacity as a default
        end

        # Make sure that the initial generation values fit to the gon_initial status to avoid infeasibility in the first time step due to ramping limits, especially if UC is linearised.
        # (See function in update_utils.jl for details)
        updateParameters_p_gen_feasible!(m) 
    end

    if m[:genOpDetails].uc || m[:genOpDetails].ramping
        # If ramping of UC, reset ramping slack but then set the ramping slack to 1.0 at end to disable ramping constraint in last timestep
        set_parameter_value.(m[:gen_fail], fill(0.0, size(m[:gen_fail])))
        if length(remaining_t) > 0
            set_parameter_value.(m[:gen_fail][:,remaining_t[1]], fill(1.0, size(m[:gen_fail][:,remaining_t[1]])))
        end
    end

    return m
end
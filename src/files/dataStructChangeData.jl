"""
    SchedChangeData{N, Ngens, Nstors, Ngenstors, Ndrs}

The struct for the schedule data returned by the operation model.
"""
struct SchedChangeData{N, Ngens, Nstors, Ngenstors, Ndrs, Nregions, Nsamples}

    # Storge variables
    stor_charging::Array{Int, 3}
    stor_discharging::Array{Int, 3}
    stor_energy::Array{Int, 3}

    # Generator-storage variables
    genstor_charging::Array{Int, 3}
    genstor_discharging::Array{Int, 3}
    genstor_energy::Array{Int, 3}

    # Demand response variables
    drs_borrowing::Array{Int, 3}
    drs_payback::Array{Int, 3}

    # Generator variables (for UC and ramping)
    gon::Array{Int,3}
    stup::Array{Int, 3}
    shdw::Array{Int, 3}

    p_gen::Array{Int, 3}
    p_gen_max::Array{Int, 3}

    # Shortfall variables
    shortfall::Array{Int, 3}

    # keys
    keys::Tuple

    # Constructor without arguments, initializes all fields with empty matrices
    function SchedChangeData(sys::PRAS.SystemModel; N::Int=0, Nsamples::Int=100, include_fields::Tuple=(:all,))
        if N == 0
            N = PRAS.get_params(sys)[1]
        end

        if include_fields == (:all,)
            include_fields = (:shortfall, :drs_borrowing, :stor_energy, :stor_charging, :stor_discharging, :genstor_charging, :genstor_discharging, :genstor_energy, :drs_payback, :gon, :stup, :shdw, :p_gen, :p_gen_max)
        end

        # Generator fields
        Ngens_gon = :gon in include_fields ? length(sys.generators.names) : 0
        Ngens_stup = :stup in include_fields ? length(sys.generators.names) : 0
        Ngens_shdw = :shdw in include_fields ? length(sys.generators.names) : 0

        Ngens_p_gen = :p_gen in include_fields ? length(sys.generators.names) : 0
        Ngens_p_gen_max = :p_gen_max in include_fields ? length(sys.generators.names) : 0

        # Storage fields
        Nstors_charging = :stor_charging in include_fields ? length(sys.storages.names) : 0
        Nstors_discharging = :stor_discharging in include_fields ? length(sys.storages.names) : 0
        Nstors_energy = :stor_energy in include_fields ? length(sys.storages.names) : 0

        # Generator-storage fields
         Ngenstors_charging = :genstor_charging in include_fields ? length(sys.generatorstorages.names) : 0
         Ngenstors_discharging = :genstor_discharging in include_fields ? length(sys.generatorstorages.names) : 0
         Ngenstors_energy = :genstor_energy in include_fields ? length(sys.generatorstorages.names) : 0

         # Demand response fields
         Ndrs_borrowing = :drs_borrowing in include_fields ? length(sys.demandresponses.names) : 0
         Ndrs_payback = :drs_payback in include_fields ? length(sys.demandresponses.names) : 0

         # Shortfall fields
         Nregions = :shortfall in include_fields ? length(sys.regions.names) : 0

        new{N, max(Ngens_gon, Ngens_stup, Ngens_shdw), max(Nstors_charging, Nstors_discharging, Nstors_energy), max(Ngenstors_charging, Ngenstors_discharging, Ngenstors_energy), max(Ndrs_borrowing, Ndrs_payback), Nregions, Nsamples}(
            zeros(Int, Nstors_charging, N, Nsamples), zeros(Int, Nstors_discharging, N, Nsamples), zeros(Int, Nstors_energy, N, Nsamples),
            zeros(Int, Ngenstors_charging, N, Nsamples), zeros(Int, Ngenstors_discharging, N, Nsamples), zeros(Int, Ngenstors_energy, N, Nsamples),
            zeros(Int, Ndrs_borrowing, N, Nsamples), zeros(Int, Ndrs_payback, N, Nsamples),
            zeros(Int, Ngens_gon, N, Nsamples), zeros(Int, Ngens_stup, N, Nsamples), zeros(Int, Ngens_shdw, N, Nsamples),
            zeros(Int, Ngens_p_gen, N, Nsamples), zeros(Int, Ngens_p_gen_max, N, Nsamples),
            zeros(Int, Nregions, N, Nsamples), include_fields)
    end

    function SchedChangeData(params; include_fields::Tuple=(:all,))
         if include_fields == (:all,)
            include_fields = (:shortfall, :drs_borrowing, :stor_energy, :stor_charging, :stor_discharging, :genstor_charging, :genstor_discharging, :genstor_energy, :drs_payback, :gon, :stup, :shdw, :p_gen, :p_gen_max)
         end
        N, Ngens, Nstors, Ngenstors, Ndrs, Nregions, Nsamples = params
        new{params...}(
            zeros(Int, Nstors, N, Nsamples), zeros(Int, Nstors, N, Nsamples), zeros(Int, Nstors, N, Nsamples),
            zeros(Int, Ngenstors, N, Nsamples), zeros(Int, Ngenstors, N, Nsamples), zeros(Int, Ngenstors, N, Nsamples),
            zeros(Int, Ndrs, N, Nsamples), zeros(Int, Ndrs, N, Nsamples),
            zeros(Int, Ngens, N, Nsamples), zeros(Int, Ngens, N, Nsamples), zeros(Int, Ngens, N, Nsamples),
            zeros(Int, Ngens, N, Nsamples), zeros(Int, Ngens, N, Nsamples),
            zeros(Int, Nregions, N, Nsamples), include_fields)
    end

    # Constructor with all fields
    function SchedChangeData(stor_charging, stor_discharging, stor_energy, genstor_charging, genstor_discharging, genstor_energy, drs_borrowing, drs_payback, gon, stup, shdw, p_gen, p_gen_max, shortfall)
        new{size(stor_charging, 1), size(gon, 1), size(stor_charging, 1), size(genstor_charging, 1), size(drs_borrowing, 1), size(shortfall, 1), size(stor_charging, 3)}(stor_charging, stor_discharging, stor_energy, genstor_charging, genstor_discharging, genstor_energy, drs_borrowing, drs_payback, gon, stup, shdw, p_gen, p_gen_max, shortfall)
    end

end

# ===========================================================================================================
"""

Defining a number of functions to access the SchedChangeData

"""
function Base.show(io::IO, ::MIME"text/plain", res::SchedChangeData{N, Ngens, Nstors, Ngenstors, Ndrs, Nregions, Nsamples}) where {N, Ngens, Nstors, Ngenstors, Ndrs, Nregions, Nsamples}
    println(io, "Schedule Change Data for system with $N timesteps and $Nsamples samples:")
    println(io, "Keys: $(get_keys(res))")
    if sum(res.shortfall; init=0) != 0
        println(io, "Average shortfall: $(sum(res.shortfall) / Nsamples) MWh")
    end
end

get_params(::SchedChangeData{N, Ngens, Nstors, Ngenstors, Ndrs, Nregions, Nsamples}) where {N, Ngens, Nstors, Ngenstors, Ndrs, Nregions, Nsamples} = (N, Ngens, Nstors, Ngenstors, Ndrs, Nregions, Nsamples)


"""
    get_value(res::SchedData{N, Ngens, Nstors, Ngenstors, Ndrs}, key::Symbol) where {N, Ngens, Nstors, Ngenstors, Ndrs}

Returns the value of the specified key in the SchedData object.
"""
function get_value(res::SchedChangeData{N, Ngens, Nstors, Ngenstors, Ndrs, Nregions, Nsamples}, key::Symbol) where {N, Ngens, Nstors, Ngenstors, Ndrs, Nregions, Nsamples}
    if key == :stor_charging
        return res.stor_charging
    elseif key == :stor_discharging
        return res.stor_discharging
    elseif key == :stor_energy
        return res.stor_energy
    elseif key == :genstor_charging
        return res.genstor_charging
    elseif key == :genstor_discharging
        return res.genstor_discharging
    elseif key == :genstor_energy
        return res.genstor_energy
    elseif key == :drs_borrowing
        return res.drs_borrowing
    elseif key == :drs_payback
        return res.drs_payback
    elseif key == :gon
        return res.gon
    elseif key == :stup
        return res.stup
    elseif key == :shdw
        return res.shdw
    elseif key == :p_gen
        return res.p_gen
    elseif key == :p_gen_max
        return res.p_gen_max
    elseif key == :shortfall
        return res.shortfall
    else
        error("Invalid key: $key")
    end
end

get(res::SchedChangeData{N, Ngens, Nstors, Ngenstors, Ndrs, Nregions, Nsamples}, key::Symbol, default) where {N, Ngens, Nstors, Ngenstors, Ndrs, Nregions, Nsamples} =
    key in get_keys(res) ? get_value(res, key) : default

get_keys(input::SchedChangeData{N, Ngens, Nstors, Ngenstors, Ndrs, Nregions, Nsamples}) where {N, Ngens, Nstors, Ngenstors, Ndrs, Nregions, Nsamples} = input.keys

function set_value!(res::SchedChangeData{N, Ngens, Nstors, Ngenstors, Ndrs, Nregions, Nsamples}, key, value) where {N, Ngens, Nstors, Ngenstors, Ndrs, Nregions, Nsamples}
    if key == :stor_charging
        res.stor_charging .= value
    elseif key == :stor_discharging
        res.stor_discharging .= value
    elseif key == :stor_energy
        res.stor_energy .= value
    elseif key == :genstor_charging
        res.genstor_charging .= value
    elseif key == :genstor_discharging
        res.genstor_discharging .= value
    elseif key == :genstor_energy
        res.genstor_energy .= value
    elseif key == :drs_borrowing
        res.drs_borrowing .= value
    elseif key == :drs_payback
        res.drs_payback .= value
    elseif key == :gon
        res.gon .= value
    elseif key == :stup
        res.stup .= value
    elseif key == :shdw
        res.shdw .= value
    elseif key == :p_gen
        res.p_gen .= value
    elseif key == :p_gen_max
        res.p_gen_max .= value
    elseif key == :shortfall
        res.shortfall .= value
    else
        error("Invalid key: $key")
    end
end

#% ===========================================================================================================
"""
    update_SchedChangeData!(res::SchedChangeData, original_res::SchedData, idxs_update, res_window, idxs_window, idx_sample)

Function to write some data in a slice of the full SchedChangeData object

- idxs_update: The indices in the SchedChangeData and SchedData objects
- idxs_window: The indices in the window result

"""
function update_SchedChangeData!(res::SchedChangeData, original_res::SchedData, idxs_update, res_window, idxs_window, idx_sample)
   
    for key in get_keys(res)
        vals_window = get(res_window, key, NaN)
        vals_original = get_value(original_res, key)
        updated_vals = get_value(res, key)

        updated_vals[:, idxs_update, idx_sample] = vals_window[:, idxs_window] .- vals_original[:, idxs_update]
        set_value!(res, key, updated_vals)
    end

    return res
end
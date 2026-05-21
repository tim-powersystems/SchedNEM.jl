"""
    SchedData{N, Ngens, Nstors, Ngenstors, Ndrs}

The struct for the schedule data returned by the operation model.
"""
struct SchedData{N, Ngens, Nstors, Ngenstors, Ndrs, Nregions}

    # Storge variables
    stor_charging::Array{Int,2}
    stor_discharging::Array{Int,2}
    stor_energy::Array{Int,2}

    # Generator-storage variables
    genstor_charging::Array{Int,2}
    genstor_discharging::Array{Int,2}
    genstor_energy::Array{Int,2}

    # Demand response variables
    drs_borrowing::Array{Int,2}
    drs_payback::Array{Int,2}

    # Generator variables (for UC and ramping)
    gon::Array{Int,2}
    stup::Array{Int,2}
    shdw::Array{Int,2}

    p_gen::Array{Int,2}
    p_gen_max::Array{Int,2}

    # Shortfall variables
    shortfall::Array{Int,2}

    # Constructor without arguments, initializes all fields with empty matrices
    function SchedData(sys::PRAS.SystemModel; N=0)
        if N == 0
            N = PRAS.get_params(sys)[1]
        end

        Ngens = length(sys.generators.names)
        Nstors = length(sys.storages.names)
        Ngenstors = length(sys.generatorstorages.names)
        Ndrs = length(sys.demandresponses.names)
        Nregions = length(sys.regions.names)

        new{N, Ngens, Nstors, Ngenstors, Ndrs, Nregions}(
            zeros(Int, Nstors, N), zeros(Int, Nstors, N), zeros(Int, Nstors, N),
            zeros(Int, Ngenstors, N), zeros(Int, Ngenstors, N), zeros(Int, Ngenstors, N),
            zeros(Int, Ndrs, N), zeros(Int, Ndrs, N),
            zeros(Int, Ngens, N), zeros(Int, Ngens, N), zeros(Int, Ngens, N),
            zeros(Int, Ngens, N), zeros(Int, Ngens, N),
            zeros(Int, Nregions, N))
    end

    function SchedData(params)
        N, Ngens, Nstors, Ngenstors, Ndrs, Nregions = params
        new{params...}(
            zeros(Int, Nstors, N), zeros(Int, Nstors, N), zeros(Int, Nstors, N),
            zeros(Int, Ngenstors, N), zeros(Int, Ngenstors, N), zeros(Int, Ngenstors, N),
            zeros(Int, Ndrs, N), zeros(Int, Ndrs, N),
            zeros(Int, Ngens, N), zeros(Int, Ngens, N), zeros(Int, Ngens, N),
            zeros(Int, Ngens, N), zeros(Int, Ngens, N),
            zeros(Int, Nregions, N))
    end

    # Constructor with all fields
    function SchedData(stor_charging, stor_discharging, stor_energy, genstor_charging, genstor_discharging, genstor_energy, drs_borrowing, drs_payback, gon, stup, shdw, p_gen, p_gen_max, shortfall)
        new{size(stor_charging, 1), size(gon, 1), size(stor_charging, 1), size(genstor_charging, 1), size(drs_borrowing, 1), size(shortfall, 1)}(stor_charging, stor_discharging, stor_energy, genstor_charging, genstor_discharging, genstor_energy, drs_borrowing, drs_payback, gon, stup, shdw, p_gen, p_gen_max, shortfall)
    end

end

# ===========================================================================
"""

Defining a number of functions to access the SchedData

"""

function Base.show(io::IO, ::MIME"text/plain", res::SchedData{N, Ngens, Nstors, Ngenstors, Ndrs, Nregions}) where {N, Ngens, Nstors, Ngenstors, Ndrs, Nregions}
    println(io, "Schedule Data for system with $N timesteps and:")
    println(io, "   $Ngens generators")
    println(io, "   $Nstors storages")
    println(io, "   $Ngenstors generator-storages")
    println(io, "   $Ndrs demand responses")
    println(io, "   $Nregions regions")
    if sum(res.shortfall) > 0
        println(io, "SHORTFALL: $(sum(res.shortfall)) MWh")
    end
end

get_params(::SchedData{N, Ngens, Nstors, Ngenstors, Ndrs, Nregions}) where {N, Ngens, Nstors, Ngenstors, Ndrs, Nregions} = (N, Ngens, Nstors, Ngenstors, Ndrs, Nregions)

get_keys(::SchedData{N, Ngens, Nstors, Ngenstors, Ndrs, Nregions}) where {N, Ngens, Nstors, Ngenstors, Ndrs, Nregions} = 
    (:stor_charging, :stor_discharging, :stor_energy,
            :genstor_charging, :genstor_discharging, :genstor_energy,
            :drs_borrowing, :drs_payback,
            :gon, :stup, :shdw,
            :p_gen, :p_gen_max, :shortfall)


"""
    get_value(res::SchedData{N, Ngens, Nstors, Ngenstors, Ndrs}, key::Symbol) where {N, Ngens, Nstors, Ngenstors, Ndrs}

Returns the value of the specified key in the SchedData object.
"""
function get_value(res::SchedData{N, Ngens, Nstors, Ngenstors, Ndrs, Nregions}, key::Symbol) where {N, Ngens, Nstors, Ngenstors, Ndrs, Nregions}
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

function set_value!(res::SchedData{N, Ngens, Nstors, Ngenstors, Ndrs, Nregions}, key, value) where {N, Ngens, Nstors, Ngenstors, Ndrs, Nregions}
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

get(res::SchedData{N, Ngens, Nstors, Ngenstors, Ndrs, Nregions}, key::Symbol, default) where {N, Ngens, Nstors, Ngenstors, Ndrs, Nregions} = key in get_keys(res) ? get_value(res, key) : default

# ===========================================================================
"""
    update_SchedData!(...)

Function to write some data in a slice of the full SchedData object

- idxs_update: The indices in the SchedData object
- idxs_window: The indices in the window result

"""
function update_SchedData!(res::SchedData, idxs_update, res_window, idxs_window)

    res.stor_charging[:, idxs_update] = res_window.stor_charging[:, idxs_window]
    res.stor_discharging[:, idxs_update] = res_window.stor_discharging[:, idxs_window]
    res.stor_energy[:, idxs_update] = res_window.stor_energy[:, idxs_window]

    res.genstor_charging[:, idxs_update] = res_window.genstor_charging[:, idxs_window]
    res.genstor_discharging[:, idxs_update] = res_window.genstor_discharging[:, idxs_window]
    res.genstor_energy[:, idxs_update] = res_window.genstor_energy[:, idxs_window]

    res.drs_borrowing[:, idxs_update] = res_window.drs_borrowing[:, idxs_window]
    res.drs_payback[:, idxs_update] = res_window.drs_payback[:, idxs_window]

    res.p_gen[:, idxs_update] = res_window.p_gen[:, idxs_window]
    res.p_gen_max[:, idxs_update] = res_window.p_gen_max[:, idxs_window]
    res.gon[:, idxs_update] = res_window.gon[:, idxs_window]
    res.stup[:, idxs_update] = res_window.stup[:, idxs_window]
    res.shdw[:, idxs_update] = res_window.shdw[:, idxs_window]

    res.shortfall[:, idxs_update] = res_window.shortfall[:, idxs_window]

    return res
end
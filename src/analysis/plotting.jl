# A collection of analysis and plotting functions for visualizing the results of the optimization model.

"""
    plot_timeseries_results(m, sys; region::Vector{Int}=[])

Function to plot the time series results of the optimization model for a specific region.

# Arguments
- region: A vector of region indices to plot. If empty, all regions will be plotted.

"""
function plot_timeseries_results(m, sys; region::Vector=[], title="", legend=:outertopright, filename="")

    if isempty(region)
        region = collect(1:m[:Nregions])
    end

    dem = sum(value.(m[:dem][region, :]), dims=1)[:] # Sum over all regions in the vector

    all_gens_in_region = vcat(collect.(sys.region_gen_idxs[region])...)
    idx_pv = intersect(findall(n -> n in ["RoofPV", "LargePV"], sys.generators.categories), all_gens_in_region)
    idx_w = intersect(findall(n -> n in ["Wind"], sys.generators.categories), all_gens_in_region)
    ixd_gas = intersect(findall(n -> n in ["CCGT", "OCGT", "Hydrogen-based gas turbines"], sys.generators.categories), all_gens_in_region)
    idx_diesel = intersect(findall(n -> n in ["Diesel"], sys.generators.categories), all_gens_in_region)
    idx_other = setdiff(all_gens_in_region, vcat(idx_pv, idx_w, ixd_gas, idx_diesel))

    gen_pv = sum(value.(m[:p_gen][idx_pv, :]); dims=1, init=0.0)[:]
    gen_w = sum(value.(m[:p_gen][idx_w, :]); dims=1, init=0.0)[:]
    gen_gas = sum(value.(m[:p_gen][ixd_gas, :]), dims=1, init=0.0)[:]
    gen_diesel = sum(value.(m[:p_gen][idx_diesel, :]), dims=1, init=0.0)[:]
    gen_other = sum(value.(m[:p_gen][idx_other, :]), dims=1, init=0.0)[:]

    if m[:Nstors] > 0
        all_stors_in_region = vcat(collect.(sys.region_stor_idxs[region])...)
        stor_discharge = sum(value.(m[:p_stor_discharge][all_stors_in_region, :]); dims=1, init=0.0)[:]
        stor_charge = sum(value.(m[:p_stor_charge][all_stors_in_region, :]); dims=1, init=0.0)[:]
    else
        stor_discharge = zeros(m[:N])
        stor_charge = zeros(m[:N])
    end

    if m[:Ngenstors] > 0
        all_genstors_in_region = vcat(collect.(sys.region_genstor_idxs[region])...)
        genstor_discharge = sum(value.(m[:p_genstor_discharge][all_genstors_in_region, :]); dims=1, init=0.0)[:]
        genstor_charge = sum(value.(m[:p_genstor_charge][all_genstors_in_region, :]); dims=1, init=0.0)[:]
    else
        genstor_discharge = zeros(m[:N])
        genstor_charge = zeros(m[:N])
    end

    if m[:Ndrs] > 0
        all_drs_in_region = vcat(collect.(sys.region_dr_idxs[region])...)
        idxs_dsp = intersect(findall(n -> n == "DSP", sys.demandresponses.categories), all_drs_in_region)
        idxs_ev = intersect(findall(n -> n == "EV", sys.demandresponses.categories), all_drs_in_region)
        drs_dsp_borrow = sum(value.(m[:p_borrow_drs][idxs_dsp, :]), dims=1)[:]
        drs_ev_borrow = sum(value.(m[:p_borrow_drs][idxs_ev, :]), dims=1)[:]
        drs_dsp_payback = sum(value.(m[:p_payback_drs][idxs_dsp, :]), dims=1)[:]
        drs_ev_payback = sum(value.(m[:p_payback_drs][idxs_ev, :]), dims=1)[:]
    else
        drs_dsp_borrow = zeros(m[:N])
        drs_ev_borrow = zeros(m[:N])
        drs_dsp_payback = zeros(m[:N])
        drs_ev_payback = zeros(m[:N])
    end

    if m[:Ninterfaces] > 0
        # Find all the lines that are connected to the regions (both import and export)
        import_idxs = findall(m[:connection_matrix][:, region] .> 0)
        import_lines = [(i[1]) for i in import_idxs]

        export_idxs = findall(m[:connection_matrix][:, region] .< 0)
        export_lines = [(i[1]) for i in export_idxs]

        # Remove all the lines that are within the seelcted region
        internal_lines = intersect(import_lines, export_lines)
        import_lines = setdiff(import_lines, internal_lines)
        export_lines = setdiff(export_lines, internal_lines)

        p_import = sum(value.(m[:p_interface_forward][import_lines, :]), dims=1)[:] .+ sum(value.(m[:p_interface_backward][export_lines, :]), dims=1)[:] 
        p_export = sum(value.(m[:p_interface_forward][export_lines, :]), dims=1)[:] .+ sum(value.(m[:p_interface_backward][import_lines, :]), dims=1)[:] 
    else
        p_import = zeros(m[:N])
        p_export = zeros(m[:N])
    end

    shed = sum(value.(m[:load_shedding][region, :]), dims=1)[:] # Sum over all regions in the vector

    t = 1:length(dem)
    gen_stack = hcat(gen_other, gen_gas, gen_diesel, gen_w, gen_pv, genstor_discharge, stor_discharge, p_import, shed, drs_dsp_borrow, drs_ev_borrow)
    charge_stack = hcat(-genstor_charge, -stor_charge, -p_export, -drs_dsp_payback, -drs_ev_payback)

    x = vcat(repeat(0.5:1.0:length(dem), inner=2)[2:end], length(dem) + 0.5)
    y_pos = hcat([repeat(gen_stack[:,i], inner=2) for i in axes(gen_stack,2)]...)
    y_neg = hcat([repeat(charge_stack[:,i], inner=2) for i in axes(charge_stack,2)]...)
    y_dem = repeat(dem, inner=2)
    y_dem_net = repeat(dem .- drs_dsp_borrow .- drs_ev_borrow, inner=2)

    comp_labels = ["Coal" "Gas" "Diesel" "Wind" "Solar PV" "Hydro" "Battery" "Imports/Exports" "Load shedding" "DSP" "EV (shifting)"]
    comp_labels[findall(x -> x == 0.0, sum(gen_stack, dims=1)[:])] .= ""

    plt = Plots.areaplot(x, y_pos ./ 1e3, color=[:black :grey 2 8 5 10 11 3 :red :orange :blue], fillalpha = 0.8, 
    labels = comp_labels, lw=0, palette=:Spectral_11, legend=legend,
    size=(700, 400))
    Plots.areaplot!(plt, x, y_neg ./ 1e3, color=[10 11 3 :orange :blue], fillalpha = 0.8, labels=["" ""], lw=0, palette=:Spectral_11)
    Plots.plot!(plt, x, y_dem  ./ 1e3; label = "", lw = 1, lc = :black, ls=:dash)
    Plots.plot!(plt, x, y_dem_net ./ 1e3; label = "Net Demand", lw = 2, lc = :black)
    #Plots.areaplot!(plt, t, gen_pv ./ 1e3; label = "Solar PV", lw = 2, lc = :yellow)

    Plots.xlabel!("Hour")
    Plots.ylabel!("Power [GW]")
    Plots.xticks!(1:6:length(dem), string.(1:6:length(dem)))
    if title != ""
        Plots.title!(title)
    else
        Plots.title!("Regions: $region | ENS: $(round(sum(shed))) MWh")
    end

    if filename != ""
        savefig(plt, filename)
    end

    return plt

end

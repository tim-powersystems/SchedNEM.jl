"""
    save_schedule(schedule::SchedData, filename::String)

Saving the SchedData to a file.

"""
function save_schedule(schedule::SchedData, filename::String)

    if isfile(filename)
        @warn "File already exists and will be overwritten: $filename"
    end

    if !isdir(dirname(filename))
        mkpath(dirname(filename))
        @debug "Created directory: $(dirname(filename))"
    end

    if filename[end-2:end] != ".h5"
        filename *= ".h5"
    end

    # Save the schedule to an HDF5 file
    HDF5.h5open(filename, "w") do f

        attrs = HDF5.attributes(f)
        attrs["N"] = get_params(schedule)[1]
        attrs["Ngens"] = get_params(schedule)[2]
        attrs["Nstors"] = get_params(schedule)[3]
        attrs["Ngenstors"] = get_params(schedule)[4]
        attrs["Ndrs"] = get_params(schedule)[5]
        attrs["Nregions"] = get_params(schedule)[6]

        for key in string.(get_keys(schedule))
            val = get_value(schedule, Symbol(key))
            dset = HDF5.create_dataset(f, key, Int, size(val))
            HDF5.write(dset, val)
        end
    end

end

"""
    read_schedule(filename::String)

Reads an hdf5 file, and returns a SchedData object.

"""
function read_schedule(filename::String)
    # Read the schedule from an HDF5 file and return it as a dictionary
    if !isfile(filename)
        error("File not found: $filename")
    end

    sched = HDF5.h5open(filename, "r") do f
        attrs = HDF5.attributes(f)
        # Ensure backward compatibility with files that do not have Nregions attribute (i.e., created before the addition of regional dimension in the SchedData structure)
        if !("Nregions" in keys(attrs))
            sched = SchedData((HDF5.read(attrs["N"]), HDF5.read(attrs["Ngens"]), HDF5.read(attrs["Nstors"]), HDF5.read(attrs["Ngenstors"]), HDF5.read(attrs["Ndrs"]), 12))
            for key in string.(get_keys(sched))
                if key == "shortfall"
                    # For backward compatibility, if shortfall data is not present in the file, initialize it with zeros
                    set_value!(sched, Symbol(key), zeros(Int, 12, get_params(sched)[1]))
                else
                    set_value!(sched, Symbol(key), HDF5.read(f, key))
                end
            end
        else
            # New file format with Nregions attribute
            sched = SchedData((HDF5.read(attrs["N"]), HDF5.read(attrs["Ngens"]), HDF5.read(attrs["Nstors"]), HDF5.read(attrs["Ngenstors"]), HDF5.read(attrs["Ndrs"]), HDF5.read(attrs["Nregions"])))
            for key in string.(get_keys(sched))
                set_value!(sched, Symbol(key), HDF5.read(f, key))
            end
        end

        sched
    end

    return sched
end
# ===========================================================================================================
"""
    save_schedule_change(schedule::SchedChangeData, filename::String)

Saving the SchedChangeData to a file.

"""
function save_schedule_change(scheduleChange::SchedChangeData, filename::String; limit::Tuple=(:all,))

    if isfile(filename)
        @warn "File already exists and will be overwritten: $filename"
    end

    if !isdir(dirname(filename))
        mkpath(dirname(filename))
        @debug "Created directory: $(dirname(filename))"
    end

    if filename[end-3:end] != ".csv"
        filename *= ".csv"
    end
    if limit == (:all,)
        limit = get_keys(scheduleChange)
        all_keys = limit
    else
        all_keys = get_keys(scheduleChange)
    end
    full_table = DataFrames.DataFrame(key=String[], id=Int[], timestep=Int[], sample=Int[], value=Int[])

    for key in intersect(all_keys, limit)
        vals = SchedNEM.get_value(scheduleChange, key)

        # First add the dimension information
        push!(full_table, (string.(key), size(vals,1), size(vals, 2), size(vals, 3), 0))

        coords = findall(vals .!= 0)                # linear indices
        cart = Tuple.(CartesianIndices(vals)[coords])      # vector of (i,j,k)
        for c in cart
            push!(full_table, (string.(key), c[1], c[2], c[3], vals[c...]))
        end
    end

    CSV.write(filename, full_table)
end


function read_sf_from_schedule_change(filename::String)
    if !isfile(filename)
        error("File not found: $filename")
    end
    df = CSV.read(filename, DataFrames.DataFrame)
    sf_df = filter(row -> row.key == "shortfall", df)
    return sf_df
end




function read_schedule_change(filename::String)
    if !isfile(filename)
        error("File not found: $filename")
    end

    df = CSV.read(filename, DataFrames.DataFrame)

    # Extract dimension information
    dim_info = Dict{String, Tuple{Int, Int, Int}}()
    for row in eachrow(df)
        if row.id == 0 && row.timestep == 0 && row.sample == 0
            dim_info[row.key] = (row.value, row.timestep, row.sample)
        end
    end

    # Initialize SchedChangeData with the extracted dimensions
    schedChange = SchedChangeData((dim_info["stor_charging"][1], dim_info["stor_charging"][2], dim_info["stor_charging"][3]))

    # Fill in the values from the DataFrame
    for row in eachrow(df)
        if row.id != 0 || row.timestep != 0 || row.sample != 0
            key_sym = Symbol(row.key)
            if key_sym in get_keys(schedChange)
                vals = get_value(schedChange, key_sym)
                vals[row.id, row.timestep, row.sample] = row.value
                set_value!(schedChange, key_sym, vals)
            else
                @warn "Key $(row.key) in CSV does not match any field in SchedChangeData. Skipping."
            end
        end
    end

    return schedChange
end    

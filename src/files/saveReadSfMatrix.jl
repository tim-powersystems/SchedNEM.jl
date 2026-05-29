"""
    saveSfMatrix(SfMatrix, filename)
Functions to save and read SfMatrix in a sparse format (only non-zero entries are saved).
First entry contains the dimensions of the matrix, followed by the indices and values of the non-zero entries.

"""
function saveSfMatrix(SfMatrix, filename)
    coords = findall(SfMatrix .!= 0)                # linear indices
    if any((SfMatrix .< 0))
        @warn "Matrix contains negative values!! Probably saving a wrong matrix?! Saved to: $filename"
    end
    cart = Tuple.(CartesianIndices(SfMatrix)[coords])      # vector of (i,j,k)
    dims = size(SfMatrix)
    I = [c[1] for c in cart]; J = [c[2] for c in cart]; K = [c[3] for c in cart]
    V = SfMatrix[coords]

    I = vcat(dims[1], I) # Add an entry for the dimensions of the matrix
    J = vcat(dims[2], J)
    K = vcat(dims[3], K)
    V = vcat(0, V) # Add a dummy value for the dimensions entry

    if !ispath(filename)
        mkpath(dirname(filename))
    end

    DataFrames.DataFrame(I=I, J=J, K=K, V=V) |> CSV.write(filename)
end
"""
    readSfMatrix(filename)

Reads a sparse SfMatrix from a CSV file and reconstructs the full matrix. The CSV file should have columns I, J, K, V where I, J, K are the indices and V is the value.
"""
function readSfMatrix(filename)
    df = CSV.read(filename, DataFrames.DataFrame)
    dims = (maximum(df.I), maximum(df.J), maximum(df.K))
    SfMatrixOut = zeros(Float64, dims)
    for row in eachrow(df)
        SfMatrixOut[row.I, row.J, row.K] = row.V
    end
    return SfMatrixOut
end

# ================================================================
# Additional functions to calculate adequacy metrics from the sparse failure matrix file directly, without needing to create the full matrix.
"""
    eensFromSfMatrix(filename)
Calculates the expected energy not supplied (EENS) from a sparse failure matrix CSV file (saved with saveSfMatrix).
"""
function eensFromSfMatrix(filename)
    df = CSV.read(filename, DataFrames.DataFrame)
    return sum(df.V) ./ maximum(df.K)
end
"""
    ensFromSfMatrix(filename)
Calculates the energy not supplied (ENS) for each sample from a sparse failure matrix CSV file (saved with saveSfMatrix). Returns a vector of ENS values for each sample.
"""
function ensFromSfMatrix(filename)
    df = CSV.read(filename, DataFrames.DataFrame)
    ens = zeros(maximum(df.K))
    for group in DataFrames.groupby(df, :K)
        ens[group.K[1]] = sum(group.V)
    end
    return ens
end

"""
    lolhFromSfMatrix(filename)
Calculates the loss of load hours (LOLH) from a sparse failure matrix CSV file (saved with saveSfMatrix). Returns the LOLH value.
"""
function lolhFromSfMatrix(filename)
    df = CSV.read(filename, DataFrames.DataFrame)
    # maximum(df.K) - number of samples
    return sum(df.V .> 0) / maximum(df.K)
end
"""
    eensAreaFromSfMatrix(filename)

Calculates the expected energy not supplied (EENS) for each area from a sparse failure matrix CSV file (saved with saveSfMatrix). 
    Returns a dictionary mapping area to EENS value.

"""
function eensAreaFromSfMatrix(filename)
    df = CSV.read(filename, DataFrames.DataFrame)
    area2reg = PRASNEM.get_region_area_map(;rev=true)
    area_eens = Dict{Int, Float64}()
    for a in keys(area2reg)
        findall(x -> x in area2reg[a], df.I)
        area_eens[a] = sum(df.V[findall(x -> x in area2reg[a], df.I)]) / maximum(df.K)
    end
    return area_eens
end

"""

"""
function eventsFromSfMatrix(filename)
    sf = readSfMatrix(filename)
    return PRASNEM.get_all_event_details(sf)
end

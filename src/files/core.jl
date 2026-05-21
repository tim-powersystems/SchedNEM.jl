
# Functions to parse data from the input files and add it to the PRAS system model
include("addCostData.jl")

# Functions to get UC data from the input files and add to JuMP model
include("getGenOperationData.jl")

# Functions to save/read the schedule
include("dataStructSchedData.jl")
include("dataStructChangeData.jl")
include("saveReadSchedule.jl")
include("saveReadSfMatrix.jl")
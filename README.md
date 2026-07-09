# SchedNEM

[![Build Status](https://github.com/tim-powersystems/SchedNEM.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/tim-powersystems/SchedNEM.jl/actions/workflows/CI.yml?query=branch%3Amain)

The goal of this package is to provide a scheduling module for reliability studies of the Australian National Electricity Market (NEM). It is complementary to [PRASNEM.jl](https://github.com/ARPST-UniMelb/PRASNEM.jl) and operates directly on the PRAS `SystemModel` created there.

SchedNEM.jl builds an economic dispatch unit commitment (ED-UC) optimisation model using JuMP and the [ParametricOptInterface](https://github.com/jump-dev/ParametricOptInterface.jl), so that the model is built only once and only the parameter values are updated between the rolling horizon windows (and between outage samples during reoptimisation). The unit commitment follows the relaxed formulation of Zhang, Capuder and Mancarella (2016), see the [detailed documentation](#documentation) below.

This repository contains:
- The rolling horizon operation model to create a (deterministic) schedule of the system operation
- A reoptimisation module to re-dispatch the system around shortfall events for Monte-Carlo outage samples (with imperfect or perfect foresight of the outages)
- Functions to save/read schedules and shortfall/availability matrices, as well as basic analysis and plotting functions

The implementation for the rolling horizon optimisation is based on the JuMP tutorial by Diego Tejada, see [here](https://jump.dev/JuMP.jl/stable/tutorials/algorithms/rolling_horizon/).

> [!NOTE]
> The default solver is HiGHS, however, we recommend using Gurobi to reduce solving time. The optimiser can be specified as optional parameter in `build_operation_model()`.

> [!NOTE]
> Functions are not exported, i.e. call them fully qualified as `SchedNEM.function_name()`.

## Getting Started

Clone the repository by executing the following function
```sh
git clone "https://github.com/tim-powersystems/SchedNEM.jl"
```

Then start a Julia REPL within the folder and activate and instantiate the local environment:
```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
```

Now you can create a schedule for a PRAS system (created with [PRASNEM.jl](https://github.com/ARPST-UniMelb/PRASNEM.jl), or one of the sample files in this repository):
```julia
using SchedNEM
using PRAS

# Load a PRAS system (alternatively use PRASNEM.create_pras_system)
file_name = "src/sample_data/pras_files/2025-01-07_to_2025-01-13_s2_123456789101112_regions.pras"
sys = SystemModel(file_name)

# Build the operation model and run the rolling horizon optimisation
input_folder = joinpath(pwd(), "src", "sample_data", "nem12")
m = SchedNEM.build_operation_model(sys; input_folder=input_folder)
schedule = SchedNEM.run_operation_model(m, sys)

# Plot the resulting dispatch (empty region list plots all regions)
SchedNEM.plot_timeseries_results(m, sys; region=[])
```

#### Reoptimising around shortfall events

Given a schedule and the outage samples of a PRAS assessment, the reoptimisation re-dispatches the system around the shortfall events of each sample:
```julia
using PRAS, PRASNEM

simspecs = SequentialMonteCarlo(samples=100, seed=1)
sf, genAv, lineAv = assess(sys, simspecs, ShortfallSamples(), GeneratorAvailability(), LineAvailability())

df_events = PRASNEM.get_all_event_details(sf)
load_shedding, shortfall_combined = SchedNEM.reoptimise(df_events, sys, schedule, genAv.available, lineAv.available;
    input_folder=input_folder, min_time_after_event=72)
```

## Optional parameters of SchedNEM.build_operation_model
There are multiple optional parameters that can be adjusted when building the operation model:
| Parameter            | Default       | Description                                                                                                                        |
| -------------------- | ------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| optimisation_window  | 48            | Length of each rolling horizon optimisation window (in time steps / hours).                                                        |
| move_forward         | 24            | Number of time steps the window moves forward between solves (must not exceed optimisation_window).                                |
| input_folder         | ""            | Folder with the PISP input CSVs, used for generator costs and operation data (pmin, ramp rates, min up/down times, start-up costs). |
| optimiser            | `HiGHS.Optimizer()` | Solver to use (e.g. `Gurobi.Optimizer()` to reduce solving time).                                                            |
| DER_parameters       | `PRASNEM.get_DER_parameters()` | Dict with DER flexibility settings (DSP/EV/VPP flexibility, max energy per window, payback options).              |
| genOpDetails         | `(uc=true, ramping=true, binary=false)` | Whether to include unit commitment and ramping. With `binary=false` the UC variables are relaxed to [0, 1] (LP); `binary=true` solves the exact MILP. |
| hydro_parameters     | `PRASNEM.get_hydro_parameters()` | Dict with hydro parameters (discharging cost, categories with final SoC constraint, ...).                       |
| objective_parameters | `(storage_discharging_price=0.1, transmission_flow_penalty=0.1, spillage_penalty=0.8, target_slack_penalty=0.8, dsp_rr_cost=0.95)` | Penalty and cost parameters of the objective function (see [docs/formulation.md](docs/formulation.md)). |

## Overview of SchedNEM.jl functions

The core functions of SchedNEM.jl are ```build_operation_model()```, ```run_operation_model()``` and ```reoptimise()```, as outlined above. Additionally, the following functions are provided in this package.

|      Location       |            Function             |                                                                Details                                                                 |
| :-----------------: | :-----------------------------: | :--------------------------------------------------------------------------------------------------------------------------------------: |
|    ```/model```     | **```build_operation_model```** |               Builds the ED-UC model (variables, objective, constraints) as a parametric model. See optional parameters above.               |
|    ```/model```     |  **```run_operation_model```**  | Runs the rolling horizon optimisation and returns a `SchedData` schedule. Optionally runs a two-pass reserve run (commitments from a reserve-inflated system are kept as lower bounds). |
| ```/reoptimisation``` |      **```reoptimise```**       | Re-dispatches the system around shortfall events for each outage sample (imperfect foresight by default), returning the load shedding per sample and the combined shortfall. |
|   ```/update```     |       ```addReserve!```         |                    Adds the ISP 2024 minimum reserve requirements to the regional loads (distributed by peak load within each area).                    |
|   ```/update```     |  ```update_model_parameters!``` |                 Updates all model parameters (demand, capacities, efficiencies, initial conditions) for a given window without rebuilding the model.                 |
|   ```/update```     | ```updateGenAvailabilityStep!``` / ```...FullHorizon!``` |            Derates the generator capacity parameters with an outage sample (single revealed step or full horizon).             |
|   ```/update```     | ```updateLineAvailabilityStep!``` / ```...FullHorizon!``` |             Derates the line capacities with an outage sample and aggregates them to the interface limit parameters.             |
|   ```/analysis```   |        ```get_results```        |                       Extracts the results of a solved window into (conservatively rounded) integer arrays.                        |
|   ```/analysis```   |  ```plot_timeseries_results```  |                    Plots the dispatch stack (by technology), net/gross demand and load shedding for selected regions.                     |
|    ```/files```     | ```SchedData``` / ```SchedChangeData``` |             Result data structures for the schedule and for the per-sample changes during reoptimisation.              |
|    ```/files```     | ```save_schedule``` / ```read_schedule``` |                                      Saves/reads a `SchedData` schedule to/from HDF5.                                      |
|    ```/files```     | ```saveSfMatrix``` / ```readSfMatrix``` |                             Saves/reads shortfall sample matrices in a sparse CSV format.                              |
|    ```/files```     | ```saveAvMatrix``` / ```readAvMatrix``` |                             Saves/reads boolean availability sample matrices in a sparse HDF5 format.                              |
|    ```/files```     | ```eensFromSfMatrix``` / ```lolhFromSfMatrix``` / ```eventsFromSfMatrix``` / ... |                  Computes adequacy metrics (EENS, LOLH, event details, ...) from saved shortfall matrices.                  |
|    ```/files```     | ```addGenCostData!``` / ```addVollData!``` / ```getGenOperationData``` |          Adds generator cost and VoLL attributes to the PRAS system and reads the generator operation data from the input folder.          |

## Documentation

The detailed mathematical formulation of the model is documented in [docs/formulation.md](docs/formulation.md).

The format of the input data is documented in [src/sample_data/README-data.md](src/sample_data/README-data.md).

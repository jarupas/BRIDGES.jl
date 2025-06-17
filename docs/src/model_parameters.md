# Parameters and Data Imports

## Parameters

The BRIDGES framework uses a centralized parameter management system that loads configuration values from YAML files. This approach allows for flexible configuration without modifying core code. Parameters can be accessed as dictionary key-value pairs after being loaded by this function, allowing for straightforward reference throughout the codebase.

```@autodocs
Modules = [BRIDGES]
Pages = ["parameters.jl"]
```

## Data Imports
```@docs
BRIDGES.load_generators
BRIDGES.load_appliances
BRIDGES.load_p2g
BRIDGES.load_p2h
BRIDGES.load_storage_heat
BRIDGES.load_storage_elec
BRIDGES.load_storage_gas
BRIDGES.load_transmission_electric
BRIDGES.load_transmission_gas
BRIDGES.load_timeseries
BRIDGES.add_costs!
BRIDGES.create_mapping!
BRIDGES.load_data
```

## Clustering Timeseries

```@autodocs
Modules = [BRIDGES]
Pages = ["cluster.jl"]
```

## Helper Functions

```@docs
BRIDGES.compute_crf
BRIDGES.compute_failure_probabilities
BRIDGES.compute_historical_units
BRIDGES.apply_toggle!
BRIDGES.scale_CAPEX!
BRIDGES.get_cost_value
BRIDGES.compute_gas_system_costs
BRIDGES.add_cost_fields!
BRIDGES.compute_biomethane!
```
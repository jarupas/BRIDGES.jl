@doc raw"""
    load_parameters() -> (Dict, Dict)

Loads model parameters and constants from YAML configuration files.

# Returns
- `param`: Dictionary of parameters loaded from `parameters.yaml`
- `cons`: Dictionary of constants loaded from `constants.yaml`
"""
function load_parameters(case)

    current_dir = dirname(@__FILE__)
    param_path = joinpath(current_dir, "parameters_$(case).yaml")
    cons_path = joinpath(current_dir, "constants.yaml")
    
    param = YAML.load_file(param_path)
    cons = YAML.load_file(cons_path)

    param["params"]["current_dir"] = current_dir

    return param["params"], cons["constants"]

end
"""
    types.jl

# Description
Defines all types of the base CVI implementation.
"""

# -----------------------------------------------------------------------------
# STRUCTS
# -----------------------------------------------------------------------------

@with_kw struct CVIOpts
    params::Vector{String} = [
        "n",
        "v",
        "CP",
        "G",
    ]

    CP_alt::Bool = false
end

mutable struct CVIBaseParams
    label_map::LabelMap
    dim::Int
    n_samples::Int
    mu::Vector{Float}               # dim
    n_clusters::Int
    criterion_value::Float
end

const CVIParams = Dict{String, Any}

const CVIRecursionCache = Dict{String, Any}


"""
An object containing all of the information about a single type of CVI parameter.

This includes symbolic pointers to its related functions, the type of the parameter, its shape, and the subsequent element type for expansion.
"""
struct CVIParamConfig
    update::Symbol
    add::Symbol
    expand::Symbol
    type::Type
    shape::Int
    el_type::Type
    to_expand::Bool
end

function get_el_type(shape::Integer, type::Type)
    if shape == 1
        el_type = type
    else
        el_type = Array{type, shape - 1}
    end
    return el_type
end


# """
# A single stage, containing the config for a parameter in a stage.
# """
# const CVIStageOrder = OrderedDict{String, CVIParamConfig}

# """
# The collection of stages, containing ordered configs.
# """
# const CVIConfig = Vector{CVIStageOrder}

const CVIConfig = OrderedDict{String, CVIParamConfig}

function CVIParamConfig(top_config::CVIConfigDict, name::String)
    subconfig = top_config["params"][name]

    param_config = CVIParamConfig(
        Symbol(name * "_update"),
        Symbol(name * "_add"),
        top_config["container"][subconfig["shape"]]["expand"],
        top_config["container"][subconfig["shape"]]["type"]{subconfig["type"]},
        subconfig["shape"],
        get_el_type(subconfig["shape"], subconfig["type"]),
        subconfig["growth"] == "extend",
        # subconfig["to_expand"]
    )
    return param_config
end

function recursive_evalorder!(config::CVIConfig, top_config::CVIConfigDict, name::AbstractString)
    # Iterate over all current dependencies
    for dep in top_config["params"][name]["deps"]
        # Get the stage where the dependency should be
        # i_dep = top_config["params"][name]["stage"]
        # If we don't have the dependency, crawl through its dependency chain
        if !haskey(config, name)
        # if !haskey(config[i_dep], name)
            recursive_evalorder!(config, top_config, dep)
        end
    end
    # If we have all dependencies, build this parameter name's config
    # i_name = top_config["params"][name]["stage"]
    # config[i_name][name] = CVIParamConfig(top_config, name)
    config[name] = CVIParamConfig(top_config, name)
end

# function build_empty_evalorder_priority(top_config::CVIConfigDict, opts::CVIOpts)
#     # Get all of the stages defined in the config
#     stages = [top_config["params"][name]["stage"] for name in keys(top_config["params"])]
#     # Get the maximum value
#     max_stage = maximum(stages)
#     # Create an empty config
#     config = CVIConfig()
#     # Push a stage from 1 to max stage to guarantee that there will be a stage index for each parameter
#     for i = 1:max_stage
#         push!(config, CVIStageOrder())
#     end
#     return config
# end

function build_evalorder(top_config::CVIConfigDict, opts::CVIOpts)::CVIConfig
    # Initialize the strategy
    config = CVIConfig()
    # config = build_empty_evalorder_priority(config, opts)
    # Iterate over every option that we selected
    for param in opts.params
        # Recursively add its dependencies in deepest order
        recursive_evalorder!(config, top_config, param)
    end
    return config
end

mutable struct BaseCVI <: CVI
    opts::CVIOpts
    base::CVIBaseParams
    params::CVIParams
    cache::CVIRecursionCache
    config::CVIConfig
end

# -----------------------------------------------------------------------------
# CONSTRUCTORS
# -----------------------------------------------------------------------------

function CVIBaseParams(dim::Integer=0)
    CVIBaseParams(
        LabelMap(),                 # label_map
        dim,                        # dim
        0,                          # n_samples
        # Vector{Float}(undef, dim),  # mu
        zeros(Float, dim),          # mu
        0,                          # n_clusters
        0.0,                        # criterion_value
    )
end

function BaseCVI(dim::Integer=0, n_clusters::Integer=0)
    opts = CVIOpts()

    config = build_evalorder(CVI_TOP_CONFIG, opts)

    cvi = BaseCVI(
        opts,
        CVIBaseParams(dim),
        CVIParams(),
        CVIRecursionCache(),
        config,
    )

    # Initialize if we know the dimension
    if dim > 0
        init_params!(cvi, dim, n_clusters)
    end

    return cvi
end

# struct CVICacheParams
#     delta_v::Vector{Float}          # dim
#     diff_x_v::Vector{Float}         # dim
# end

# const ALLOWED_CVI_PARAM_TYPES = Union{
#     CVIExpandVector,
#     CVIExpandMatrix,
#     CVIExpandTensor,
# }

# const CVIStrategy = Dict{String, CVIParamConfig}

# function get_cvi_strategy(config::AbstractDict)
#     # Initialize the strategy
#     strategy = CVIStrategy()
#     for (name, subconfig) in config["params"]
#         strategy[name] = CVIParamConfig(
#             Symbol(name * "_update"),
#             Symbol(name * "_add"),
#             config["container"][subconfig["shape"]]["expand"],
#             config["container"][subconfig["shape"]]["type"]{subconfig["type"]},
#             subconfig["shape"],
#             get_el_type(subconfig["shape"], subconfig["type"]),

#         )
#     end
#     return strategy
# end

# const CVI_STRATEGY::CVIStrategy = get_cvi_strategy(CVI_TOP_CONFIG)
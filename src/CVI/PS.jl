"""
    PS.jl

This is a Julia port of a MATLAB implementation of batch and incremental
Partition Separation (PS) Cluster Validity Index.

Authors:
MATLAB implementation: Leonardo Enzo Brito da Silva
Julia port: Sasha Petrenko <sap625@mst.edu>

REFERENCES
[1] Miin-Shen Yang and Kuo-Lung Wu, "A new validity index for fuzzy clustering,"
10th IEEE International Conference on Fuzzy Systems. (Cat. No.01CH37297), Melbourne,
Victoria, Australia, 2001, pp. 89-92, vol.1.
[2] E. Lughofer, "Extensions of vector quantization for incremental clustering," Pattern
Recognit., vol. 41, no. 3, pp. 995–1011, 2008.
"""

using Statistics

"""
    PS

The stateful information of the Partition Separation (PS) CVI.
"""
mutable struct PS <: AbstractCVI
    dim::Integer
    n_samples::Integer
    n::IntegerVector        # dim
    v::RealMatrix           # dim x n_clusters
    D::RealMatrix           # n_clusters x n_clusters
    v_bar::RealVector       # dim
    beta_t::RealFP
    PS_i::RealVector        # n_clusters
    n_clusters::Integer
    criterion_value::RealFP
end # PS <: AbstractCVI

"""
    PS()

Default constructor for the Partition Separation (PS) Cluster Validity Index.
"""
function PS()
    PS(
        0,                              # dim
        0,                              # n_samples
        Array{Integer, 1}(undef, 0),    # n
        Array{RealFP, 2}(undef, 0, 0),  # v
        Array{RealFP, 2}(undef, 0, 0),  # D
        Array{RealFP, 1}(undef, 0),     # v_bar
        0.0,                            # beta_t
        Array{RealFP, 1}(undef, 0),     # PS_i
        0,                              # n_clusters
        0.0                             # criterion_value
    )
end # PS()

"""
    setup!(cvi::PS, sample::Array{T, 1}) where {T<:Real}
"""
function setup!(cvi::PS, sample::Array{T, 1}) where {T<:Real}
    # Get the feature dimension
    cvi.dim = length(sample)
    # Initialize the 2-D arrays with the correct feature dimension
    cvi.v = Array{T, 2}(undef, cvi.dim, 0)
end # setup!(cvi::PS, sample::Array{T, 1}) where {T<:Real}

"""
    param_inc!(cvi::PS, sample::RealVector, label::Integer)

Compute the Partition Separation (PS) CVI incrementally.
"""
function param_inc!(cvi::PS, sample::RealVector, label::Integer)
    n_samples_new = cvi.n_samples + 1
    if isempty(cvi.v)
        setup!(cvi, sample)
    end

    if label > cvi.n_clusters
        n_new = 1
        v_new = sample
        if cvi.n_clusters == 0
            D_new = zeros(1, 1)
        else
            D_new = zeros(cvi.n_clusters + 1, cvi.n_clusters + 1)
            D_new[1:cvi.n_clusters, 1:cvi.n_clusters] = cvi.D
            d_column_new = zeros(cvi.n_clusters + 1)
            for jx = 1:cvi.n_clusters
                d_column_new[jx] = sum((v_new - cvi.v[:, jx]).^2)
            end
            D_new[:, label] = d_column_new
            D_new[label, :] = transpose(d_column_new)
        end
        # Update 1-D parameters with a push
        cvi.n_clusters += 1
        push!(cvi.n, n_new)
        # Update 2-D parameters with appending and reassignment
        cvi.v = [cvi.v v_new]
        cvi.D = D_new
    else
        n_new = cvi.n[label] + 1
        v_new = (1 - 1/n_new) .* cvi.v[:, label] + (1/n_new) .* sample
        d_column_new = zeros(cvi.n_clusters)
        for jx = 1:cvi.n_clusters
            if jx == label
                continue
            end
            d_column_new[jx] = sum((v_new - cvi.v[:, jx]).^2)
        end
        # Update parameters
        cvi.n[label] = n_new
        cvi.v[:, label] = v_new
        cvi.D[:, label] = d_column_new
        cvi.D[label, :] = transpose(d_column_new)
    end
    cvi.n_samples = n_samples_new
end # param_inc!(cvi::PS, sample::RealVector, label::Integer)

"""
    param_batch!(cvi::PS, data::RealMatrix, labels::IntegerVector)

Compute the Partition Separation (PS) CVI in batch.
"""
function param_batch!(cvi::PS, data::RealMatrix, labels::IntegerVector)
    cvi.dim, cvi.n_samples = size(data)
    # Take the average across all samples, but cast to 1-D vector
    u = unique(labels)
    cvi.n_clusters = length(u)
    cvi.n = zeros(Integer, cvi.n_clusters)
    cvi.v = zeros(cvi.dim, cvi.n_clusters)
    cvi.D = zeros(cvi.n_clusters, cvi.n_clusters)
    for ix = 1:cvi.n_clusters
        subset = data[:, findall(x->x==u[ix], labels)]
        cvi.n[ix] = size(subset, 2)
        cvi.v[1:cvi.dim, ix] = mean(subset, dims=2)
    end
    for ix = 1 : (cvi.n_clusters - 1)
        for jx = ix + 1 : cvi.n_clusters
            cvi.D[jx, ix] = sum((cvi.v[:, ix] - cvi.v[:, jx]).^2)
        end
    end
    cvi.D = cvi.D + transpose(cvi.D)
end # param_batch!(cvi::PS, data::RealMatrix, labels::IntegerVector)

"""
    evaluate!(cvi::PS)

Compute the criterion value of the Partition Separation (PS) CVI.
"""
function evaluate!(cvi::PS)
    if cvi.n_clusters > 1
        cvi.v_bar = vec(mean(cvi.v, dims=2))
        cvi.beta_t = 0.0
        cvi.PS_i = zeros(cvi.n_clusters)
        for ix = 1:cvi.n_clusters
            delta_v = cvi.v[:, ix] - cvi.v_bar
            cvi.beta_t = cvi.beta_t + transpose(delta_v) * delta_v
        end
        cvi.beta_t /= cvi.n_clusters
        n_max = maximum(cvi.n)
        for ix = 1:cvi.n_clusters
            d = cvi.D[:, ix]
            deleteat!(d, ix)
            cvi.PS_i[ix] = (cvi.n[ix] / n_max) - exp(-minimum(d) / cvi.beta_t)
        end
        cvi.criterion_value = sum(cvi.PS_i)
    end
end # evaluate(cvi::PS)

"""
    DB.jl

This is a Julia port of a MATLAB implementation of batch and incremental
Davies-Bouldin (DB) Cluster Validity Index.

Authors:
MATLAB implementation: Leonardo Enzo Brito da Silva
Julia port: Sasha Petrenko <sap625@mst.edu>

REFERENCES
[1] D. L. Davies and D. W. Bouldin, "A cluster separation measure,"
IEEE Transaction on Pattern Analysis and Machine Intelligence, vol. 1,
no. 2, pp. 224–227, Feb. 1979.
[2] M. Moshtaghi, J. C. Bezdek, S. M. Erfani, C. Leckie, and J. Bailey,
"Online Cluster Validity Indices for Streaming Data," ArXiv e-prints, 2018,
arXiv:1801.02937v1 [stat.ML]. [Online].
[3] M. Moshtaghi, J. C. Bezdek, S. M. Erfani, C. Leckie, J. Bailey, "Online
cluster validity indices for performance monitoring of streaming data clustering,"
Int. J. Intell. Syst., pp. 1–23, 2018.
"""

using Statistics

"""
    DB

The stateful information of the Davies-Bouldin (DB) CVI.
"""
mutable struct DB <: AbstractCVI
    dim::Integer
    n_samples::Integer
    mu_data::RealVector         # dim
    n::IntegerVector            # dim
    v::RealMatrix               # dim x n_clusters
    CP::RealVector              # dim
    S::RealVector               # dim
    R::RealMatrix               # dim x n_clusters
    G::RealMatrix               # dim x n_clusters
    D::RealMatrix               # n_clusters x n_clusters
    n_clusters::Integer
    criterion_value::RealFP
end # DB <: AbstractCVI

"""
    DB()

Default constructor for the Davies-Bouldin (DB) Cluster Validity Index.
"""
function DB()
    DB(
        0,                              # dim
        0,                              # n_samples
        Array{RealFP, 1}(undef, 0),     # mu_data
        Array{Integer, 1}(undef, 0),    # n
        Array{RealFP, 2}(undef, 0, 0),  # v
        Array{RealFP, 1}(undef, 0),     # CP
        Array{RealFP, 1}(undef, 0),     # S
        Array{RealFP, 2}(undef, 0, 0),  # R
        Array{RealFP, 2}(undef, 0, 0),  # G
        Array{RealFP, 2}(undef, 0, 0),  # D
        0,                              # n_clusters
        0.0                             # criterion_value
    )
end # DB()

"""
    setup!(cvi::DB, sample::Vector{T}) where {T<:RealFP}
"""
function setup!(cvi::DB, sample::Vector{T}) where {T<:RealFP}
    # Get the feature dimension
    cvi.dim = length(sample)
    # Initialize the augmenting 2-D arrays with the correct feature dimension
    # NOTE: R is emptied and calculated in evaluate!, so it is not defined here
    cvi.v = Array{T, 2}(undef, cvi.dim, 0)
    cvi.G = Array{T, 2}(undef, cvi.dim, 0)
end # setup!(cvi::DB, sample::Vector{T}) where {T<:RealFP}

"""
    param_inc!(cvi::DB, sample::RealVector, label::Integer)

Compute the Davies-Bouldin (DB) CVI incrementally.
"""
function param_inc!(cvi::DB, sample::RealVector, label::Integer)
    n_samples_new = cvi.n_samples + 1
    if isempty(cvi.mu_data)
        mu_data_new = sample
        setup!(cvi, sample)
    else
        mu_data_new = (1 - 1/n_samples_new) .* cvi.mu_data + (1/n_samples_new) .* sample
    end

    if label > cvi.n_clusters
        n_new = 1
        v_new = sample
        CP_new = 0.0
        G_new = zeros(cvi.dim)
        S_new = 0.0
        if cvi.n_clusters == 0
            D_new = zeros(1,1)
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
        push!(cvi.CP, CP_new)
        push!(cvi.n, n_new)
        push!(cvi.S, S_new)
        # Update 2-D parameters with appending and reassignment
        cvi.v = [cvi.v v_new]
        cvi.G = [cvi.G G_new]
        cvi.D = D_new
    else
        n_new = cvi.n[label] + 1
        v_new = (1 - 1/n_new) .* cvi.v[:, label] + (1/n_new) .* sample
        delta_v = cvi.v[:, label] - v_new
        diff_x_v = sample .- v_new
        CP_new = cvi.CP[label] + transpose(diff_x_v)*diff_x_v + cvi.n[label]*transpose(delta_v)*delta_v + 2*transpose(delta_v)*cvi.G[:, label]
        G_new = cvi.G[:, label] + diff_x_v + cvi.n[label].*delta_v
        S_new = CP_new / n_new
        d_column_new = zeros(cvi.n_clusters)
        for jx = 1:cvi.n_clusters
            # Skip the current label index
            if jx == label
                continue
            end
            d_column_new[jx] = sum((v_new - cvi.v[:, jx]).^2)
        end
        # Update parameters
        cvi.n[label] = n_new
        cvi.v[:, label] = v_new
        cvi.CP[label] = CP_new
        cvi.G[:, label] = G_new
        cvi.S[label] = S_new
        cvi.D[:, label] = d_column_new
        cvi.D[label, :] = transpose(d_column_new)
    end
    cvi.n_samples = n_samples_new
    cvi.mu_data = mu_data_new
end # param_inc!(cvi::DB, sample::RealVector, label::Integer)

"""
    param_batch!(cvi::DB, data::RealMatrix, labels::IntegerVector)

Compute the Davies-Bouldin (DB) CVI in batch.
"""
function param_batch!(cvi::DB, data::RealMatrix, labels::IntegerVector)
    cvi.dim, cvi.n_samples = size(data)
    # Take the average across all samples, but cast to 1-D vector
    cvi.mu_data = mean(data, dims=2)[:]
    # u = findfirst.(isequal.(unique(labels)), [labels])
    u = unique(labels)
    cvi.n_clusters = length(u)
    cvi.n = zeros(Integer, cvi.n_clusters)
    cvi.v = zeros(cvi.dim, cvi.n_clusters)
    cvi.CP = zeros(cvi.n_clusters)
    cvi.D = zeros(cvi.n_clusters, cvi.n_clusters)
    cvi.S = zeros(cvi.n_clusters)
    for ix = 1:cvi.n_clusters
        subset = data[:, findall(x->x==u[ix], labels)]
        cvi.n[ix] = size(subset, 2)
        cvi.v[1:cvi.dim, ix] = mean(subset, dims=2)
        diff_x_v = subset - cvi.v[:, ix] * ones(1, cvi.n[ix])
        cvi.CP[ix] = sum(diff_x_v.^2)
        cvi.S[ix] = cvi.CP[ix] / cvi.n[ix]
    end
    for ix = 1 : (cvi.n_clusters - 1)
        for jx = ix + 1 : cvi.n_clusters
            cvi.D[jx, ix] = sum((cvi.v[:, ix] - cvi.v[:, jx]).^2)
        end
    end
    cvi.D = cvi.D + transpose(cvi.D)
end # function param_batch!(cvi::DB, data::RealMatrix, labels::IntegerVector)

"""
    evaluate!(cvi::DB)

Compute the criterion value of the Davies-Bouldin (DB) CVI.
"""
function evaluate!(cvi::DB)
    cvi.R = zeros(cvi.n_clusters, cvi.n_clusters)
    for ix = 1:(cvi.n_clusters - 1)
        for jx = ix + 1 : cvi.n_clusters
            cvi.R[ix, jx] = (cvi.S[ix] + cvi.S[jx]) / cvi.D[ix, jx]
        end
    end
    cvi.R = cvi.R + transpose(cvi.R)
    cvi.criterion_value = sum(maximum(cvi.R, dims=2)) / cvi.n_clusters
end # evaluate(cvi::DB)

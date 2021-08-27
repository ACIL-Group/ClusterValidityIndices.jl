"""
    XB.jl

This is a Julia port of a MATLAB implementation of batch and incremental
Xie-Beni (XB) Cluster Validity Index.

Authors:
MATLAB implementation: Leonardo Enzo Brito da Silva
Julia port: Sasha Petrenko <sap625@mst.edu>

REFERENCES
[1] X. L. Xie and G. Beni, "A Validity Measure for Fuzzy Clustering," IEEE
Transactions on Pattern Analysis and Machine Intelligence, vol. 13, no. 8,
pp. 841–847, 1991.
[2] M. Moshtaghi, J. C. Bezdek, S. M. Erfani, C. Leckie, and J. Bailey,
"Online Cluster Validity Indices for Streaming Data," ArXiv e-prints, 2018,
arXiv:1801.02937v1 [stat.ML]. [Online].
[3] M. Moshtaghi, J. C. Bezdek, S. M. Erfani, C. Leckie, J. Bailey, "Online
cluster validity indices for performance monitoring of streaming data clustering,"
Int. J. Intell. Syst., pp. 1–23, 2018.
"""

using Statistics

"""
    XB

The stateful information of the Xie-Beni (XB) CVI.
"""
mutable struct XB <: AbstractCVI
    dim::Integer
    n_samples::Integer
    mu_data::RealVector     # dim
    n::IntegerVector        # dim
    v::RealMatrix           # dim x n_clusters
    CP::RealVector          # dim
    SEP::RealFP
    G::RealMatrix           # dim x n_clusters
    D::RealMatrix           # n_clusters x n_clusters
    WGSS::RealFP
    n_clusters::Integer
    criterion_value::RealFP
end # XB <: AbstractCVI

"""
    XB()

Default constructor for the Xie-Beni (XB) Cluster Validity Index.
"""
function XB()
    XB(
        0,                              # dim
        0,                              # n_samples
        Array{RealFP, 1}(undef, 0),     # mu_data
        Array{Integer, 1}(undef, 0),    # n
        Array{RealFP, 2}(undef, 0, 0),  # v
        Array{RealFP, 1}(undef, 0),     # CP
        0.0,                            # SEP
        Array{RealFP, 2}(undef, 0, 0),  # G
        Array{RealFP, 2}(undef, 0, 0),  # D
        0.0,                            # WGSS
        0,                              # n_clusters
        0.0                             # criterion_value
    )
end # XB()

"""
    setup!(cvi::XB, sample::Vector{T}) where {T<:RealFP}
"""
function setup!(cvi::XB, sample::Vector{T}) where {T<:RealFP}
    # Get the feature dimension
    cvi.dim = length(sample)
    # Initialize the 2-D arrays with the correct feature dimension
    cvi.v = Array{T, 2}(undef, cvi.dim, 0)
    cvi.G = Array{T, 2}(undef, cvi.dim, 0)
end # setup!(cvi::XB, sample::Vector{T}) where {T<:RealFP}

"""
    param_inc!(cvi::XB, sample::RealVector, label::Integer)

Compute the Xie-Beni (XB) CVI incrementally.
"""
function param_inc!(cvi::XB, sample::RealVector, label::Integer)
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
        if cvi.n_clusters == 0
            D_new = zeros(1, 1)
        else
            D_new = zeros(cvi.n_clusters + 1, cvi.n_clusters + 1)
            D_new[1:cvi.n_clusters, 1:cvi.n_clusters] = cvi.D
            d_column_new = zeros(cvi.n_clusters + 1)
            # println(d_column_new)
            for jx = 1:cvi.n_clusters
                # sum((v_new - cvi.v[:, jx]).^2, dims=1)
                d_column_new[jx] = sum((v_new - cvi.v[:, jx]).^2)
            end
            D_new[:, label] = d_column_new
            D_new[label, :] = transpose(d_column_new)
        end
        # Update 1-D parameters with a push
        cvi.n_clusters += 1
        push!(cvi.CP, CP_new)
        push!(cvi.n, n_new)
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
        d_column_new = zeros(cvi.n_clusters)
        for jx = 1:cvi.n_clusters
            if jx == label
                continue
            end
            # sum((v_new - cvi.v[:, jx]).^2, dims=1)
            d_column_new[jx] = sum((v_new - cvi.v[:, jx]).^2)
        end
        # Update parameters
        cvi.n[label] = n_new
        cvi.v[:, label] = v_new
        cvi.CP[label] = CP_new
        cvi.D[:, label] = d_column_new
        cvi.D[label, :] = transpose(d_column_new)
    end
    cvi.n_samples = n_samples_new
    cvi.mu_data = mu_data_new
end # param_inc!(cvi::XB, sample::RealVector, label::Integer)

"""
    param_batch!(cvi::XB, data::RealMatrix, labels::IntegerVector)

Compute the Xie-Beni (XB) CVI in batch.
"""
function param_batch!(cvi::XB, data::RealMatrix, labels::IntegerVector)
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
    for ix = 1:cvi.n_clusters
        subset = data[:, findall(x->x==u[ix], labels)]
        cvi.n[ix] = size(subset, 2)
        cvi.v[1:cvi.dim, ix] = mean(subset, dims=2)
        diff_x_v = subset - cvi.v[:, ix] * ones(1, cvi.n[ix])
        cvi.CP[ix] = sum(diff_x_v.^2)
    end
    for ix = 1 : (cvi.n_clusters - 1)
        for jx = ix + 1 : cvi.n_clusters
            # cvi.D[jx, ix] = sum((cvi.v[:, ix] - cvi.v[:, jx]).^2, dims=1)
            cvi.D[jx, ix] = sum((cvi.v[:, ix] - cvi.v[:, jx]).^2)
        end
    end
    cvi.D = cvi.D + transpose(cvi.D)
end # param_batch!(cvi::XB, data::RealMatrix, labels::IntegerVector)

"""
    evaluate!(cvi::XB)

Compute the criterion value of the Xie-Beni (XB) CVI.
"""
function evaluate!(cvi::XB)
    cvi.WGSS = sum(cvi.CP)
    if cvi.n_clusters > 1
        # Assume a symmetric dimension
        dim = size(cvi.D)[1]
        # Get the values from D as the upper triangular offset from the diagonal
        values = [cvi.D[i,j] for i = 1:dim, j=1:dim if j > i]
        # SEP is the minimum of these unique D values
        cvi.SEP = minimum(values)
        # Criterion value is
        cvi.criterion_value = cvi.WGSS/(cvi.n_samples*cvi.SEP)
    else
        cvi.SEP = 0.0
        cvi.criterion_value = 0.0
    end
end # evaluate(cvi::XB)

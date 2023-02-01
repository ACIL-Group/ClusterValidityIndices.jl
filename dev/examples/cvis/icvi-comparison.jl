using
    ClusterValidityIndices,     # CVI/ICVI
    AdaptiveResonance,          # DDVFA
    MLDatasets,                 # Iris dataset
    DataFrames,                 # DataFrames, necessary for MLDatasets.Iris()
    MLDataUtils,                # Shuffling and splitting
    Printf,                     # Formatted number printing
    Plots                       # Plots frontend
gr()                            # Use the default GR backend explicitly
theme(:dracula)                 # Change the theme for fun

iris = Iris(as_df=false)
features, labels = iris.features, iris.targets

labels = convertlabel(LabelEnc.Indices{Int}, vec(labels))
unique(labels)

# Create a Distributed Dual-Vigilance Fuzzy ART (DDVFA) module with default options
art = DDVFA()
typeof(art)

# Setup the data configuration for the module
data_setup!(art, features)
# Verify that the data is setup
art.config.setup

# Create many ICVI objects
icvis = [
    CH(),
    cSIL(),
    DB(),
    GD43(),
    GD53(),
    PS(),
    rCIP(),
    WB(),
    XB(),
]

# Setup the online/streaming clustering
n_samples = length(labels)          # Number of samples
n_icvi = length(icvis)              # Number of ICVIs being computed
c_labels = zeros(Int, n_samples)    # Clustering labels
criterion_values = zeros(n_icvi, n_samples) # ICVI outputs

# Iterate over all samples
for ix = 1:n_samples
    # Extract one sample
    sample = features[:, ix]
    # Cluster the sample online
    c_labels[ix] = train!(art, sample)
    # Get the new criterion values (ICVI output)
    for jx = 1:n_icvi
        criterion_values[jx, ix] = get_cvi!(icvis[jx], sample, c_labels[ix])
    end
end

# See the matrix of criterion values
criterion_values

criterion_values[:, end]

# Define a simple function for plotting
function plot_cvis(range)
    # Create the plotting object
    p = plot(legend=:topleft)
    # Iterate over the range of ICVI indices provided
    for jx = range
        # Plot the ICVI criterion values versus sample index
        plot!(
            p,                              # Modify the plot object
            1:n_samples,                    # x-axis iteration
            criterion_values[jx, :],        # y-axis criterion value
            linewidth=3,                    # Thicken the lines for visibility
            label=string(typeof(icvis[jx])) # Label is the type of CVI
        )
    end
    # Return the plotting object for IJulia display
    return p
end

# Plot all of the ICVIs tested here
plot_cvis(1:n_icvi)

# Exclude CH and cSIL
plot_cvis(3:n_icvi)

png("assets/icvi-comparision") #hide

# This file was generated using Literate.jl, https://github.com/fredrikekre/Literate.jl


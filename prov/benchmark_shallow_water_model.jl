push!(LOAD_PATH, joinpath(@__DIR__, ".."))

using BenchmarkTools
using CUDA
using Oceananigans
using Oceananigans.Models: ShallowWaterModel

ENV["GKSwstype"] = "nul"
import Plots
Plots.GRBackend()
using Plots
# Benchmark function

include("benchmark/src/Benchmarks.jl")
using Main.Benchmarks


# Benchmark function
function benchmark_shallow_water_model(Arch, FT, N)
    grid = RegularRectilinearGrid(FT, size=(N, N), extent=(1, 1), topology=(Periodic, Periodic, Flat), halo=(3, 3))
    model = ShallowWaterModel(architecture=Arch(), grid=grid, gravitational_acceleration=1.0)
    set!(model, h=1)

    time_step!(model, 1) # warmup

    trial = @benchmark begin
        @sync_gpu time_step!($model, 1)
    end samples=10

    return trial
end

# Benchmark parameters
#
#
Architectures = has_cuda() ? [CPU, GPU] : [CPU]
Float_types = [Float64]
Ns = [32, 64, 128, 256, 512, 1024, 2048, 4096]
# Run and summarize benchmarks

print_system_info()
suite = run_benchmarks(benchmark_shallow_water_model; Architectures, Float_types, Ns)

plot_num = length(Ns)
cpu_times = zeros(Float64, plot_num)
gpu_times = zeros(Float64, plot_num)
plot_keys = collect(keys(suite))
sort!(plot_keys, by = v -> [Symbol(v[1]), v[3]])

for i in 1:plot_num
    cpu_times[i] = mean(suite[plot_keys[i]].times) / 1.0e6
#    gpu_times[i] = mean(suite[plot_keys[i+plot_num]].times) / 1.0e6
end

plt = plot(Ns, cpu_times, lw=4, label="cpu", xaxis=:log, yaxis=:log, legend=:topleft,
          xlabel="Nx", ylabel="Times (ms)", title="Shallow Water Benchmarks: CPU vs GPU")
#plot!(plt, Ns, gpu_times, lw=4, label="gpu")
# display(plt)
savefig(plt, "shallow_water_times.png")


plt2 = plot(Ns, cpu_times./gpu_times, lw=4, xaxis=:log, legend=:none,
            xlabel="Nx", ylabel="Speedup Ratio", title="Shallow Water Benchmarks: CPU/GPU")
display(plt2)
# savefig(plt2, "shallow_water_speedup.png")

df = benchmarks_dataframe(suite)
sort!(df, [:Architectures, :Float_types, :Ns], by=(string, string, identity))
benchmarks_pretty_table(df, title="Shallow water model benchmarks")

if GPU in Architectures
    df_?? = gpu_speedups_suite(suite) |> speedups_dataframe
    sort!(df_??, [:Float_types, :Ns], by=(string, identity))
    benchmarks_pretty_table(df_??, title="Shallow water model CPU to GPU speedup")
end

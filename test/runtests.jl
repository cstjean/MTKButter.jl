using MTKButter
using Test

for (root, dirs, files) in walkdir(@__DIR__)
    for file in files
        if !endswith(file, ".jl")
            continue
        end
        @testset "$file" begin
            include(file)
        end
    end
end

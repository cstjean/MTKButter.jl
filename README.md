# MTKButter

[![Test workflow status](https://github.com/cstjean/MTKButter.jl/actions/workflows/Test.yml/badge.svg?branch=main)](https://github.com/cstjean/MTKButter.jl/actions/workflows/Test.yml?query=branch%3Amain)
[![BestieTemplate](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/JuliaBesties/BestieTemplate.jl/main/docs/src/assets/badge.json)](https://github.com/JuliaBesties/BestieTemplate.jl)

MTKButter.jl introduces `@mtkbmodel`: an alternative implementation of
[ModelingToolkit](https://github.com/SciML/ModelingToolkit.jl)'s `@mtkmodel`,
that enables more flexible component definition / modification.

Demo:

```julia
using MTKButter, DifferentialEquations, Test
using ModelingToolkit: t_nounits as t, D_nounits as D

@mtkbmodel LinearXProducer begin
    @variables begin
        x(t) = 0
    end
    @parameters begin
        rate = 1
    end
    @equations begin
        D(x) ~ rate
    end
end

@mtkbmodel Room begin
    @variables begin
        total_x(t)
    end
    @components begin
        producers = fill(LinearXProducer(), 4)  # @components now supports arbitrary Julia code
    end
    @equations begin
        total_x ~ sum(p.x for p in producers)
    end
end

# Normal usage
@named room1 = Room()  # @mtkcompile also works, but then @set cannot be used afterwards
prob = ODEProblem(mtkcompile(room1), Dict(), (0, 100.0))

# Let's create model variations starting from `room1`, using Accessors.jl.
room2 = @set room1.producers_1.rate = 10     # use Accessors.@set to change a parameter
room2b = @set room1.producers[1].rate = 10   # equivalent; component indexing works correctly
room3 = @set room1.producers = [LinearXProducer()] # replace all the producers with a single one
room3b = Room(producers=[LinearXProducer()])  # equivalent; the constructor can specify components
room4 = @insert room1.producers[5] = LinearXProducer()  # add a fifth producer
#room5 = @set room1.producers.rate = 4   # TODO: change the `rate` of all producers at once

@mtkbmodel ExponentialXProducer begin
    @variables begin
        x(t) = 1
    end
    @equations begin
        D(x) ~ x
    end
end

room5 = @set room1.producers[2] = ExponentialXProducer() # Heterogeneous component vectors also
                                                         # work. No need for an interface.

# Confirm that the results are correct
prob = ODEProblem(mtkcompile(room5), Dict(), (0,5))
sol = solve(prob, Tsit5())
@test sol[room5.total_x][end] ≈ 5 + exp(5) + 5 + 5 rtol=0.01
```

Because 99% of the work is done by the original ModelingToolkit code, everything should mostly work
(our DAE code works the same as before), but beware the
[known issues](https://github.com/cstjean/MTKButter.jl/issues). Let me know if anything fails
that used to work.

Implementation-wise, the
[core differences](https://github.com/cstjean/MTKButter.jl/blob/master/src/bmodel.jl) are:
 - `@mtkbmodel` introduces a new `PreSystem` type, that is convertible to `System`.
 - Instead of storing the equations, `PreSystem` contains a closure-to-build-the-equations.
   That way, the code to replace components is more straight-forward (I think?)
 - MTKButter pirates the Model constructor, `some_model()` works (even without the `name` kwarg).
   Beware that this seems to mess up precompilation.
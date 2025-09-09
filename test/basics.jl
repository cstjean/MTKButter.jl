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
        producers = fill(LinearXProducer(), 4)  # RHS is arbitrary Julia code
    end
    @equations begin
        total_x ~ sum(p.x for p in producers)
    end
end

# Normal usage
@named room1 = Room()  # @mtkcompile also works, but then @set cannot be used afterwards
prob = ODEProblem(mtkcompile(room1), Dict(), (0, 100.0))

room2 = @set room1.producers_1.rate = 10     # use Accessors.@set to change a parameter
room2b = @set room1.producers[1].rate = 10   # equivalent; component indexing works correctly
room3 = @set room1.producers = [LinearXProducer()] # replace all the producers with a single one
room3b = Room(producers=[LinearXProducer()])  # equivalent; the constructor can change components
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

room5 = @set room1.producers[2] = ExponentialXProducer()  # heterogeneous component vectors also work

# Confirm that the results are correct
prob = ODEProblem(mtkcompile(room5), Dict(), (0,5))
sol = solve(prob, Tsit5())
@test sol[room5.total_x][end] ≈ 5 + exp(5) + 5 + 5 rtol=0.01

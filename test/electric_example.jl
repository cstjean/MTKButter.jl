using ModelingToolkit, Plots, OrdinaryDiffEq
using ModelingToolkit: t_nounits as t, D_nounits as D
using MTKButter

@connector Pin begin
    v(t)
    i(t), [connect = Flow]
end

@mtkbmodel Ground begin
    @components begin
        g = Pin()
    end
    @equations begin
        g.v ~ 0
    end
end

@mtkbmodel OnePort begin
    @components begin
        p = Pin()
        n = Pin()
    end
    @variables begin
        v(t)
        i(t)
    end
    @equations begin
        v ~ p.v - n.v
        0 ~ p.i + n.i
        i ~ p.i
    end
end

@mtkbmodel Resistor begin
    @extend OnePort()
    @parameters begin
        R = 1.0 # Sets the default resistance
    end
    @equations begin
        v ~ i * R
    end
end

@mtkbmodel Capacitor begin
    @extend OnePort()
    @parameters begin
        C = 1.0
    end
    @equations begin
        D(v) ~ i / C
    end
end

@mtkbmodel ConstantVoltage begin
    @extend OnePort()
    @parameters begin
        V = 1.0
    end
    @equations begin
        V ~ v
    end
end

@mtkbmodel RCModel begin
    @description "A circuit with a constant voltage source, resistor and capacitor connected in series."
    @components begin
        resistor = Resistor(R = 1.0)
        capacitor = Capacitor(C = 1.0)
        source = ConstantVoltage(V = 1.0)
        ground = Ground()
    end
    @equations begin
        connect(source.p, resistor.p)
        connect(resistor.n, capacitor.p)
        connect(capacitor.n, source.n)
        connect(capacitor.n, ground.g)
    end
end

@mtkcompile rc_model = RCModel()  #(resistor.R = 2.0)
u0 = [
    rc_model.capacitor.v => 0.0
]
prob = ODEProblem(rc_model, u0, (0, 10.0))
sol = solve(prob)
plot(sol)

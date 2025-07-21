@mtkmodel LinearXProducer begin
    @variables begin
        x(t) = 1
    end
    @parameters begin
        rate=1
    end
    @equations begin
        D(x) ~ rate
    end
end

@mtkmodel Room begin
    @components begin
        producers = fill(LinearXProducer(), 4)  # RHS is arbitrary Julia code
    end
end


@mtkmodel ExponentialXProducer begin
    @variables begin
        x(t) = 1
    end
    @equations begin
        D(x) ~ x
    end
end

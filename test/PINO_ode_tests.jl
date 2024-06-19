using Test
using OrdinaryDiffEq, OptimizationOptimisers
using Lux
using Statistics, Random
using NeuralPDE

# dG(u(t, p), t) = f(G,u(t, p))
@testset "Example du = cos(p * t)" begin
    equation = (u, p, t) -> cos(p * t)
    tspan = (0.0f0, 1.0f0)
    u0 = 1.0f0
    prob = ODEProblem(equation, u0, tspan)

    branch = Lux.Chain(
        Lux.Dense(1, 10, Lux.tanh_fast),
        Lux.Dense(10, 10, Lux.tanh_fast),
        Lux.Dense(10, 10))
    trunk = Lux.Chain(
        Lux.Dense(1, 10, Lux.tanh_fast),
        Lux.Dense(10, 10, Lux.tanh_fast),
        Lux.Dense(10, 10, Lux.tanh_fast))

    deeponet = DeepONet(branch, trunk; linear = nothing)
    a = rand(1, 50, 40)
    b = rand(1, 1, 40)
    x = (branch = a, trunk = b)
    θ, st = Lux.setup(Random.default_rng(), deeponet)

    c = deeponet(x, θ, st)[1]
    function_(p, t) = cos(p * t)
    bounds = (0.1f0, pi)
    parametric_function = ParametricFunction(function_, bounds)
    dt = (tspan[2] - tspan[1]) / 40
    strategy = GridTraining(dt)
    opt = OptimizationOptimisers.Adam(0.01)
    alg = PINOODE(deeponet, opt, parametric_function; strategy = strategy)
    sol = solve(prob, alg, verbose = false, maxiters = 5000)
    sol.original
    # TODO intrepretation output another mesh
    # x = (branch = p, trunk = t)
    # phi(sol.original.u)
    # sol.
    ground_analytic = (u0, p, t) -> u0 + sin(p * t) / (p)
    size_of_p = 50
    p_ = range(start = bounds[1], length = size_of_p, stop = bounds[2])
    p = collect(reshape(p_, 1, size(p_)[1], 1))
    ground_solution = ground_analytic.(u0, p, sol.t.trunk)

    @test ground_solution≈sol.u rtol=0.05
end

plot(sol.u[1, :, :], linetype = :contourf)
plot!(ground_solution[1, :, :], linetype = :contourf)

function plot_()
    # Animate
    anim = @animate for (i) in 1:41
        plot(ground_solution[1, i, :], label = "Ground")
        # plot(equation_[1, i, :], label = "equation")
        plot!(sol.u[1, i, :], label = "Predicted")
    end
    gif(anim, "pino.gif", fps = 15)
end

plot_()

@testset "Example du = cos(p * t) + u" begin
    eq_(u, p, t) = cos(p * t) + u
    tspan = (0.0f0, 1.0f0)
    u0 = 1.0f0
    prob = ODEProblem(eq_, u0, tspan)
    branch = Lux.Chain(
        Lux.Dense(1, 10, Lux.tanh_fast),
        Lux.Dense(10, 10, Lux.tanh_fast),
        Lux.Dense(10, 10))
    trunk = Lux.Chain(
        Lux.Dense(1, 10, Lux.tanh_fast),
        Lux.Dense(10, 10, Lux.tanh_fast),
        Lux.Dense(10, 10, Lux.tanh_fast))

    deeponet = DeepONet(branch, trunk)

    parametric_function = Parametric_Function(nothing, bounds)

    dt = (tspan[2] - tspan[1]) / 40
    strategy = GridTraining(dt)

    opt = OptimizationOptimisers.Adam(0.01)
    alg = PINOODE(deeponet, opt, bounds; strategy = strategy)

    sol = solve(prob, alg, verbose = false, maxiters = 10000)

    #if u0 == 1
    ground_analytic_(u0, p, t) = (p * sin(p * t) - cos(p * t) + (p^2 + 2) * exp(t)) /
                                 (p^2 + 1)

    ground_analytic = (u0, p, t) -> u0 + sin(p * t) / (p)
    size_of_p = 50
    p_ = [range(start = b[1], length = size_of_p, stop = b[2]) for b in bounds]
    p = vcat([collect(reshape(p_i, 1, size(p_i)[1], 1)) for p_i in p_]...)
    ground_solution = ground_analytic.(u0, p, sol.t.trunk)

    @test ground_solution≈sol.u rtol=0.05
end





@testset "Example with data du = p*t^2" begin
    equation = (u, p, t) -> p * t^2
    tspan = (0.0f0, 1.0f0)
    u0 = 0.0f0
    prob = ODEProblem(equation, u0, tspan)

    branch = Lux.Chain(
        Lux.Dense(1, 10, Lux.tanh_fast),
        Lux.Dense(10, 10, Lux.tanh_fast),
        Lux.Dense(10, 10, Lux.tanh_fast))
    trunk = Lux.Chain(
        Lux.Dense(1, 10, Lux.tanh_fast),
        Lux.Dense(10, 10, Lux.tanh_fast),
        Lux.Dense(10, 10, Lux.tanh_fast))
    linear = Lux.Chain(Lux.Dense(10, 1))
    deeponet = NeuralPDE.DeepONet(branch, trunk; linear = linear)

    bounds = (p = [0.0f0, 10.0f0],)

    # db = (bounds.p[2] - bounds.p[1]) / 50
    dt = (tspan[2] - tspan[1]) / 40
    strategy = NeuralPDE.GridTraining([db, dt])

    opt = OptimizationOptimisers.Adam(0.03)

    #generate data
    ground_analytic = (u0, p, t) -> u0 + p * t^3 / 3
    function get_trainset(branch_size, trunk_size, bounds, tspan)
        p_ = range(bounds.p[1], stop = bounds.p[2], length = branch_size)
        p = reshape(p_, 1, branch_size, 1)
        t_ = collect(range(tspan[1], stop = tspan[2], length = trunk_size))
        t = reshape(t_, 1, 1, trunk_size)
        (p, t)
    end
    function get_data()
        sol = ground_analytic.(u0, p, t)
        x = equation.(sol, p, t)
        tuple = (branch = x, trunk = t)
        sol, tuple
    end

    branch_size, trunk_size = 50, 40
    p,t = get_trainset(branch_size, trunk_size, bounds, tspan)
    data, tuple = get_data()

    function additional_loss_(phi, θ)
        u = phi(tuple, θ)
        norm = prod(size(u))
        sum(abs2, u .- data) / norm
    end
    alg = NeuralPDE.PINOODE(
        deeponet, opt, bounds; strategy = strategy, additional_loss = additional_loss_)
    sol = solve(prob, alg, verbose = false, maxiters = 2000)

    p_ = bounds.p[1]:strategy.dx[1]:bounds.p[2]
    p = reshape(p_, 1, size(p_)[1], 1)
    ground_solution = ground_analytic.(u0, p, sol.t.trunk)

    @test ground_solution≈sol.u rtol=0.005
end

#vector outputs and multiple parameters
@testset "Example du = cos(p * t)" begin
    function equation1(u, p, t)
        p1, p2 = p[1], p[2]
        cos(p1 * t) + p2
    end

    equation = (u, p, t) -> cos(p * t)
    tspan = (0.0f0, 1.0f0)
    u0 = 1.0f0
    prob = ODEProblem(equation, u0, tspan)

    branch = Lux.Chain(
        Lux.Dense(1, 10, Lux.tanh_fast),
        Lux.Dense(10, 10, Lux.tanh_fast),
        Lux.Dense(10, 10))
    trunk = Lux.Chain(
        Lux.Dense(1, 10, Lux.tanh_fast),
        Lux.Dense(10, 10, Lux.tanh_fast),
        Lux.Dense(10, 10, Lux.tanh_fast))

    deeponet = DeepONet(branch, trunk; linear = nothing)
    # p1 = [0.1f0, pi]; p2 = [0.1f0, 2.0f0]
    # bounds = (p = [p1, p2],)
    #TODO add size_of_p = 50
    bounds = [[0.1f0, pi], [0.1f0, 2.0f0]]
    # db = 0.025f0
    dt = (tspan[2] - tspan[1]) / 40
    strategy = GridTraining(dt)
    opt = OptimizationOptimisers.Adam(0.03)
    alg = PINOODE(deeponet, opt, bounds; strategy = strategy)
    sol = solve(prob, alg, verbose = false, maxiters = 2000)

    ground_analytic = (u0, p, t) -> u0 + sin(p * t) / (p)
    p_ = bounds.p[1]:strategy.dx[1]:bounds.p[2]
    p = reshape(p_, 1, size(p_)[1], 1)
    ground_solution = ground_analytic.(u0, p, sol.t.trunk)

    @test ground_solution≈sol.u rtol=0.01
end
